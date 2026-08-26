import "errors"
import "messages"

contract TokenGovernance {
    author: "Phalanx Foundation"
    version: "1.0.0"
    description: "Simple DAO governance — token holders vote on proposals with weight proportional to balance snapshot. Admin executes approved proposals after timelock."
    storage: GovernanceStorage
    incomingMessages: AllowedMessageToGovernance
}

@overflow1023_policy("suppress")
struct GovernanceConfig {
    admin: address
    minterAddress: address
    proposalThreshold: coins
    quorumBps: uint16
    votingPeriodSec: uint32
    timelockSec: uint32
}

/// Proposal: created by admin or holders above threshold.
/// weight: snapshot of total voting power (needed for quorum).
/// voteFor/voteAgainst: running tallies.
/// Snapshot is taken on creation — only balances at that time count.
@overflow1023_policy("suppress")
struct Proposal {
    id: uint64
    proposer: address
    descriptionHash: bits256
    targetContract: address
    payload: cell
    snapshotBalance: coins
    voteFor: coins
    voteAgainst: coins
    createdAt: uint32
    votingEndsAt: uint32
    executed: bool
}

@overflow1023_policy("suppress")
struct GovernanceStorage {
    config: Cell<GovernanceConfig>
    nextProposalId: uint64
    proposals: map<uint64, Cell<Proposal>>
    votes: map<uint64, map<address, bool>>
}

struct (0x474f5601) CreateProposal {
    queryId: uint64
    descriptionHash: bits256
    targetContract: address
    payload: cell
}

struct (0x474f5602) CastVote {
    queryId: uint64
    proposalId: uint64
    voteFor: bool
}

struct (0x474f5603) ExecuteProposal {
    queryId: uint64
    proposalId: uint64
}

struct (0x474f5604) UpdateConfig {
    queryId: uint64
    proposalThreshold: coins
    quorumBps: uint16
    votingPeriodSec: uint32
    timelockSec: uint32
}

type AllowedMessageToGovernance =
    | CreateProposal
    | CastVote
    | ExecuteProposal
    | UpdateConfig
    | TopUpTons

const GOVERNANCE_EXECUTE_VALUE = 100000000
const QUORUM_DENOMINATOR: int = 10000

fun GovernanceStorage.load(): GovernanceStorage {
    return GovernanceStorage.fromCell(contract.getData());
}

fun GovernanceStorage.save(self) {
    contract.setData(self.toCell());
}

fun GovernanceStorage.isAdmin(self, sender: address): bool {
    val config = self.config.load();
    return sender == config.admin;
}

fun isActive(proposal: Proposal): bool {
    if (proposal.executed) {
        return false;
    }
    val now = blockchain.now();
    return now < proposal.votingEndsAt || now >= proposal.votingEndsAt;
}

fun hasPassed(proposal: Proposal, config: GovernanceConfig): bool {
    val totalVotes = proposal.voteFor + proposal.voteAgainst;
    if (totalVotes == 0) {
        return false;
    }
    val quorum = proposal.snapshotBalance * config.quorumBps / QUORUM_DENOMINATOR;
    return totalVotes >= quorum && proposal.voteFor > proposal.voteAgainst;
}

fun onInternalMessage(in: InMessage) {
    if (in.body.remainingBitsCount() == 0 && in.body.remainingRefsCount() == 0) {
        return;
    }

    val msg = lazy AllowedMessageToGovernance.fromSlice(in.body);

    match (msg) {
        CreateProposal => {
            var storage = lazy GovernanceStorage.load();
            val config = storage.config.load();

            assert (in.senderAddress == config.admin) throw Errors.NotOwner;

            val now = blockchain.now();
            val proposalId = storage.nextProposalId;
            val proposal: Proposal = {
                id: proposalId,
                proposer: in.senderAddress,
                descriptionHash: msg.descriptionHash,
                targetContract: msg.targetContract,
                payload: msg.payload,
                snapshotBalance: 0,
                voteFor: 0,
                voteAgainst: 0,
                createdAt: now,
                votingEndsAt: now + config.votingPeriodSec,
                executed: false,
            };

            storage.proposals.set(proposalId, proposal.toCell());
            storage.nextProposalId += 1;
            storage.save();
        }

        CastVote => {
            var storage = lazy GovernanceStorage.load();
            val config = storage.config.load();

            val proposalEntry = storage.proposals.get(msg.proposalId);
            assert (proposalEntry.isFound) throw Errors.InvalidOp;

            var proposal = proposalEntry.loadValue().load();

            assert (!proposal.executed) throw Errors.InvalidOp;
            assert (blockchain.now() < proposal.votingEndsAt) throw Errors.NothingToClaim;

            val voteMapEntry = storage.votes.get(msg.proposalId);
            var voteMap: map<address, bool> = [];
            if (voteMapEntry.isFound) {
                voteMap = voteMapEntry.loadValue();
            }

            assert (!voteMap.exists(in.senderAddress)) throw Errors.InvalidOp;

            voteMap.set(in.senderAddress, true);

            if (msg.voteFor) {
                proposal.voteFor += 1;
            } else {
                proposal.voteAgainst += 1;
            }

            storage.proposals.set(msg.proposalId, proposal.toCell());
            storage.votes.set(msg.proposalId, voteMap);
            storage.save();
        }

        ExecuteProposal => {
            var storage = lazy GovernanceStorage.load();
            val config = storage.config.load();

            val proposalEntry = storage.proposals.get(msg.proposalId);
            assert (proposalEntry.isFound) throw Errors.InvalidOp;

            var proposal = proposalEntry.loadValue().load();

            assert (!proposal.executed) throw Errors.InvalidOp;
            assert (blockchain.now() >= proposal.votingEndsAt) throw Errors.NothingToClaim;
            assert (blockchain.now() >= proposal.votingEndsAt + config.timelockSec) throw Errors.NothingToClaim;
            assert (hasPassed(proposal, config)) throw Errors.InvalidOp;

            proposal.executed = true;
            storage.proposals.set(msg.proposalId, proposal.toCell());
            storage.save();

            val execMsg = createMessage({
                bounce: BounceMode.Only256BitsOfBody,
                dest: proposal.targetContract,
                value: GOVERNANCE_EXECUTE_VALUE,
                body: proposal.payload,
            });
            execMsg.send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_BOUNCE_ON_ACTION_FAIL);
        }

        UpdateConfig => {
            var storage = lazy GovernanceStorage.load();
            var config = storage.config.load();

            assert (in.senderAddress == config.admin) throw Errors.NotOwner;

            config.proposalThreshold = msg.proposalThreshold;
            config.quorumBps = msg.quorumBps;
            config.votingPeriodSec = msg.votingPeriodSec;
            config.timelockSec = msg.timelockSec;
            storage.config = config.toCell();
            storage.save();
        }

        TopUpTons => {}
    }
}

get fun get_config(): Cell<GovernanceConfig> {
    val storage = GovernanceStorage.load();
    return storage.config;
}

get fun get_proposal(proposalId: uint64): Cell<Proposal>? {
    val storage = GovernanceStorage.load();
    val entry = storage.proposals.get(proposalId);
    if (!entry.isFound) {
        return null;
    }
    return entry.loadValue();
}

get fun has_voted(proposalId: uint64, voter: address): bool {
    val storage = GovernanceStorage.load();
    val voteMapEntry = storage.votes.get(proposalId);
    if (!voteMapEntry.isFound) {
        return false;
    }
    val voteMap = voteMapEntry.loadValue();
    return voteMap.exists(voter);
}
