import "@gen/JettonWallet.code"
import "errors"
import "jetton-utils"
import "messages"

contract TokenGovernance {
    author: "Phalanx Foundation"
    version: "2.0.0"
    description: "DAO governance with vote-escrow voting power. Holders stake jettons to earn voting weight; a snapshot of total staked is taken on proposal creation and used as the quorum denominator."
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

/// Proposal: created by admin or any holder whose staked voting power is at or
/// above the threshold.
/// snapshotBalance: total staked at creation time, the quorum denominator.
/// voteFor/voteAgainst: running tallies weighted by each voter's staked amount.
@overflow1023_policy("suppress")
struct Proposal {
    id: uint64
    proposer: address
    descriptionHash: cell
    targetContract: address
    payload: cell
    snapshotBalance: coins
    voteFor: coins
    voteAgainst: coins
    createdAt: uint32
    votingEndsAt: uint32
    executed: bool
}

/// Per-voter escrow: the staked amount (voting power) plus the timestamp until
/// which the stake is locked because the voter voted on an active proposal.
@overflow1023_policy("suppress")
struct VoterStake {
    amount: coins
    lockedUntil: uint32
}

@overflow1023_policy("suppress")
struct GovernanceStorage {
    config: Cell<GovernanceConfig>
    nextProposalId: uint64
    proposals: map<uint64, Cell<Proposal>>
    votes: map<uint64, map<address, bool>>
    stakes: map<address, Cell<VoterStake>>
    totalStaked: coins
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

struct (0x474f5605) UnstakeVotingPower {
    queryId: uint64
    amount: coins
}

type AllowedMessageToGovernance =
    | CreateProposal
    | CastVote
    | ExecuteProposal
    | UpdateConfig
    | UnstakeVotingPower
    | TransferNotificationForRecipient
    | TopUpTons

const GOVERNANCE_EXECUTE_VALUE = 100000000
const QUORUM_DENOMINATOR: int = 10000
const UNSTAKE_TRANSFER_VALUE = 80000000
const STAKE_FORWARD_OP: uint32 = 0x474f5653 // "GOVS"

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

fun ownJettonWallet(minterAddress: address): address {
    val jettonWalletCode = jettonWalletCompiledCode();
    return calcAddressOfJettonWallet(contract.getAddress(), minterAddress, jettonWalletCode);
}

fun votingPower(storage: GovernanceStorage, voter: address): coins {
    val entry = storage.stakes.get(voter);
    if (!entry.isFound) {
        return 0;
    }
    return entry.loadValue().load().amount;
}

fun isStakeForwardPayload(payload: ForwardPayloadRemainder): bool {
    var s = payload;
    if (s.remainingBitsCount() == 0 && s.remainingRefsCount() == 0) {
        return false;
    }
    val op = s.loadUint(32);
    return op == STAKE_FORWARD_OP;
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

            val isAdmin = in.senderAddress == config.admin;
            val power = votingPower(storage, in.senderAddress);
            assert (isAdmin || power >= config.proposalThreshold) throw Errors.NotEnoughVotingPower;

            val now = blockchain.now();
            val proposalId = storage.nextProposalId;
            val proposal: Proposal = {
                id: proposalId,
                proposer: in.senderAddress,
                descriptionHash: beginCell().storeSlice(msg.descriptionHash as slice).endCell(),
                targetContract: msg.targetContract,
                payload: msg.payload,
                snapshotBalance: storage.totalStaked,
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
            val _config = storage.config.load();

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

            val weight = votingPower(storage, in.senderAddress);
            assert (weight > 0) throw Errors.NotEnoughVotingPower;

            voteMap.set(in.senderAddress, true);

            if (msg.voteFor) {
                proposal.voteFor += weight;
            } else {
                proposal.voteAgainst += weight;
            }

            val stakeEntry = storage.stakes.get(in.senderAddress);
            var voterStake = stakeEntry.loadValue().load();
            if (proposal.votingEndsAt > voterStake.lockedUntil) {
                voterStake.lockedUntil = proposal.votingEndsAt;
            }
            storage.stakes.set(in.senderAddress, voterStake.toCell());

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
            assert (
                blockchain.now() >= proposal.votingEndsAt + config.timelockSec
            ) throw Errors.NothingToClaim;
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

        UnstakeVotingPower => {
            var storage = lazy GovernanceStorage.load();
            val config = storage.config.load();

            assert (msg.amount > 0) throw Errors.InvalidOp;
            val current = votingPower(storage, in.senderAddress);
            assert (current >= msg.amount) throw Errors.BalanceError;

            val stakeEntry = storage.stakes.get(in.senderAddress);
            var voterStake = stakeEntry.loadValue().load();
            assert (blockchain.now() >= voterStake.lockedUntil) throw Errors.NothingToClaim;

            if (current == msg.amount) {
                storage.stakes.delete(in.senderAddress);
            } else {
                voterStake.amount = current - msg.amount;
                storage.stakes.set(in.senderAddress, voterStake.toCell());
            }
            storage.totalStaked -= msg.amount;
            storage.save();

            val transferMsg = createMessage({
                bounce: BounceMode.Only256BitsOfBody,
                dest: ownJettonWallet(config.minterAddress),
                value: UNSTAKE_TRANSFER_VALUE,
                body: AskToTransfer {
                    queryId: msg.queryId,
                    jettonAmount: msg.amount,
                    transferRecipient: in.senderAddress,
                    sendExcessesTo: in.senderAddress,
                    customPayload: null,
                    forwardTonAmount: 0,
                    forwardPayload: jettonEmptyForwardPayload(),
                },
            });
            transferMsg.send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_BOUNCE_ON_ACTION_FAIL);
        }

        TransferNotificationForRecipient => {
            var storage = lazy GovernanceStorage.load();
            val config = storage.config.load();
            val ourWallet = ownJettonWallet(config.minterAddress);
            assert (in.senderAddress == ourWallet) throw Errors.NotValidWallet;

            val incomingAmount = msg.jettonAmount;
            if (incomingAmount == 0) {
                return;
            }

            assert (isStakeForwardPayload(msg.forwardPayload)) throw Errors.InvalidOp;

            val voter = msg.transferInitiator!;
            val stakeEntry = storage.stakes.get(voter);
            var voterStake: VoterStake = { amount: 0, lockedUntil: 0 };
            if (stakeEntry.isFound) {
                voterStake = stakeEntry.loadValue().load();
            }
            voterStake.amount = voterStake.amount + incomingAmount;
            storage.stakes.set(voter, voterStake.toCell());
            storage.totalStaked += incomingAmount;
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

get fun get_voting_power(voter: address): coins {
    val storage = GovernanceStorage.load();
    return votingPower(storage, voter);
}

get fun get_total_staked(): coins {
    val storage = GovernanceStorage.load();
    return storage.totalStaked;
}

get fun get_next_proposal_id(): uint64 {
    val storage = GovernanceStorage.load();
    return storage.nextProposalId;
}

get fun get_voter_stake(voter: address): Cell<VoterStake>? {
    val storage = GovernanceStorage.load();
    val entry = storage.stakes.get(voter);
    if (!entry.isFound) {
        return null;
    }
    return entry.loadValue();
}
