import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"

import "@contracts/TokenGovernance"
import "@contracts/errors"
import "@contracts/messages"
import "@wrappers/TokenGovernance.gen"

const GV_UNIT = 1000000000
const GV_START = 1700000000
const GV_VOTING_PERIOD = 604800
const GV_TIMELOCK = 86400

fun setupGovernance(): (TokenGovernance, Treasury, Treasury) {
    val admin = testing.treasury("gv-admin");
    val voter = testing.treasury("gv-voter");
    testing.setNow(GV_START);

    val config: GovernanceConfig = {
        admin: admin.address,
        minterAddress: admin.address,
        proposalThreshold: 1000 * GV_UNIT,
        quorumBps: 5000,
        votingPeriodSec: GV_VOTING_PERIOD,
        timelockSec: GV_TIMELOCK,
    };

    val gov = TokenGovernance.fromStorage({
        config: config.toCell(),
        nextProposalId: 0,
        proposals: [],
        votes: [],
    });
    expect(gov.sendDeploy(admin.address, { value: ton("5") })).toHaveSuccessfulDeploy({
        to: gov.address,
    });

    return (gov, admin, voter);
}

fun governanceDescriptionHash(): bits256 {
    return beginCell().storeUint("governance-test-description".sha256(), 256).endCell().beginParse() as bits256;
}

fun createGovernanceProposal(gov: TokenGovernance, admin: Treasury, target: address): void {
    val result = gov.sendCreateProposal(
        admin.address,
        0,
        governanceDescriptionHash(),
        target,
        beginCell().endCell(),
        { bounce: false, value: ton("0.2") },
    );
    expect(result).toHaveSuccessfulTx<CreateProposal>({ from: admin.address, to: gov.address });
}

get fun `test governance: deploy stores admin config`() {
    val (gov, admin, voter) = setupGovernance();
    val cfg = gov.getConfig().load();
    expect(cfg.admin).toEqual(admin.address);
    expect(cfg.votingPeriodSec).toEqual(GV_VOTING_PERIOD);
    expect(cfg.quorumBps).toEqual(5000);
    expect(voter.address).toEqual(voter.address);
}

get fun `test governance: non-admin cannot update config`() {
    val (gov, admin, voter) = setupGovernance();
    val result = gov.sendUpdateConfig(
        voter.address,
        0,
        1000 * GV_UNIT,
        5000,
        GV_VOTING_PERIOD,
        GV_TIMELOCK,
        { bounce: false, value: ton("0.2") },
    );
    expect(result).toHaveFailedTx<UpdateConfig>({
        from: voter.address,
        to: gov.address,
        exitCode: Errors.NotOwner,
    });
}

get fun `test governance: admin can update config`() {
    val (gov, admin, voter) = setupGovernance();
    val result = gov.sendUpdateConfig(
        admin.address,
        0,
        2000 * GV_UNIT,
        6000,
        1209600,
        172800,
        { bounce: false, value: ton("0.2") },
    );
    expect(result).toHaveSuccessfulTx<UpdateConfig>({ from: admin.address, to: gov.address });

    val cfg = gov.getConfig().load();
    expect(cfg.proposalThreshold).toEqual(2000 * GV_UNIT);
    expect(cfg.quorumBps).toEqual(6000);
    expect(cfg.votingPeriodSec).toEqual(1209600);
    expect(cfg.timelockSec).toEqual(172800);
}

get fun `test governance: admin can create a proposal`() {
    val (gov, admin, voter) = setupGovernance();
    createGovernanceProposal(gov, admin, voter.address);

    val proposal = gov.getProposal(0)!.load();
    expect(proposal.id).toEqual(0);
    expect(proposal.proposer).toEqual(admin.address);
    expect(proposal.targetContract).toEqual(voter.address);
    expect(proposal.descriptionHash).toEqual(governanceDescriptionHash());
    expect(proposal.voteFor).toEqual(0);
    expect(proposal.voteAgainst).toEqual(0);
    expect(proposal.executed).toEqual(false);
    expect(proposal.votingEndsAt).toEqual(GV_START + GV_VOTING_PERIOD);
}

get fun `test governance: non-admin cannot create a proposal`() {
    val (gov, admin, voter) = setupGovernance();
    val result = gov.sendCreateProposal(
        voter.address,
        0,
        governanceDescriptionHash(),
        admin.address,
        beginCell().endCell(),
        { bounce: false, value: ton("0.2") },
    );
    expect(result).toHaveFailedTx<CreateProposal>({
        from: voter.address,
        to: gov.address,
        exitCode: Errors.NotOwner,
    });
    // No proposal was stored after the failed attempt.
    expect(gov.getProposal(0)).toEqual(null);
}

get fun `test governance: voter can vote for a proposal`() {
    val (gov, admin, voter) = setupGovernance();
    createGovernanceProposal(gov, admin, voter.address);

    val result = gov.sendCastVote(
        voter.address,
        0,
        0,
        true,
        { bounce: false, value: ton("0.2") },
    );
    expect(result).toHaveSuccessfulTx<CastVote>({ from: voter.address, to: gov.address });

    val proposal = gov.getProposal(0)!.load();
    expect(proposal.voteFor).toEqual(1);
    expect(proposal.voteAgainst).toEqual(0);
    expect(gov.hasVoted(0, voter.address)).toEqual(true);
}

get fun `test governance: voter can vote against a proposal`() {
    val (gov, admin, voter) = setupGovernance();
    createGovernanceProposal(gov, admin, voter.address);

    val result = gov.sendCastVote(
        voter.address,
        0,
        0,
        false,
        { bounce: false, value: ton("0.2") },
    );
    expect(result).toHaveSuccessfulTx<CastVote>({ from: voter.address, to: gov.address });

    val proposal = gov.getProposal(0)!.load();
    expect(proposal.voteFor).toEqual(0);
    expect(proposal.voteAgainst).toEqual(1);
    expect(gov.hasVoted(0, voter.address)).toEqual(true);
}

get fun `test governance: double vote is rejected`() {
    val (gov, admin, voter) = setupGovernance();
    createGovernanceProposal(gov, admin, voter.address);
    gov.sendCastVote(voter.address, 0, 0, true, { bounce: false, value: ton("0.2") });

    val result = gov.sendCastVote(
        voter.address,
        0,
        0,
        false,
        { bounce: false, value: ton("0.2") },
    );
    expect(result).toHaveFailedTx<CastVote>({
        from: voter.address,
        to: gov.address,
        exitCode: Errors.InvalidOp,
    });

    // Tally must not change after the rejected second vote.
    val proposal = gov.getProposal(0)!.load();
    expect(proposal.voteFor).toEqual(1);
    expect(proposal.voteAgainst).toEqual(0);
}

get fun `test governance: vote after voting period is rejected`() {
    val (gov, admin, voter) = setupGovernance();
    createGovernanceProposal(gov, admin, voter.address);

    testing.setNow(GV_START + GV_VOTING_PERIOD + 1);
    val result = gov.sendCastVote(
        voter.address,
        0,
        0,
        true,
        { bounce: false, value: ton("0.2") },
    );
    expect(result).toHaveFailedTx<CastVote>({
        from: voter.address,
        to: gov.address,
        exitCode: Errors.NothingToClaim,
    });
}

get fun `test governance: execute before voting ends is rejected`() {
    val (gov, admin, voter) = setupGovernance();
    createGovernanceProposal(gov, admin, voter.address);
    gov.sendCastVote(voter.address, 0, 0, true, { bounce: false, value: ton("0.2") });

    val result = gov.sendExecuteProposal(
        voter.address,
        0,
        0,
        { bounce: false, value: ton("0.2") },
    );
    expect(result).toHaveFailedTx<ExecuteProposal>({
        from: voter.address,
        to: gov.address,
        exitCode: Errors.NothingToClaim,
    });
}

get fun `test governance: execute before timelock elapses is rejected`() {
    val (gov, admin, voter) = setupGovernance();
    createGovernanceProposal(gov, admin, voter.address);
    gov.sendCastVote(voter.address, 0, 0, true, { bounce: false, value: ton("0.2") });

    // Voting is over but the timelock has not elapsed yet.
    testing.setNow(GV_START + GV_VOTING_PERIOD + GV_TIMELOCK / 2);
    val result = gov.sendExecuteProposal(
        voter.address,
        0,
        0,
        { bounce: false, value: ton("0.2") },
    );
    expect(result).toHaveFailedTx<ExecuteProposal>({
        from: voter.address,
        to: gov.address,
        exitCode: Errors.NothingToClaim,
    });
}

get fun `test governance: execute a not-passed proposal is rejected`() {
    val (gov, admin, voter) = setupGovernance();
    createGovernanceProposal(gov, admin, voter.address);
    gov.sendCastVote(voter.address, 0, 0, false, { bounce: false, value: ton("0.2") });

    testing.setNow(GV_START + GV_VOTING_PERIOD + GV_TIMELOCK + 1);
    val result = gov.sendExecuteProposal(
        voter.address,
        0,
        0,
        { bounce: false, value: ton("0.2") },
    );
    expect(result).toHaveFailedTx<ExecuteProposal>({
        from: voter.address,
        to: gov.address,
        exitCode: Errors.InvalidOp,
    });

    val proposal = gov.getProposal(0)!.load();
    expect(proposal.executed).toEqual(false);
}

get fun `test governance: passed proposal executes after timelock`() {
    val (gov, admin, voter) = setupGovernance();
    createGovernanceProposal(gov, admin, voter.address);
    gov.sendCastVote(voter.address, 0, 0, true, { bounce: false, value: ton("0.2") });

    testing.setNow(GV_START + GV_VOTING_PERIOD + GV_TIMELOCK + 1);
    val result = gov.sendExecuteProposal(
        voter.address,
        0,
        0,
        { bounce: false, value: ton("0.2") },
    );
    expect(result).toHaveSuccessfulTx<ExecuteProposal>({ from: voter.address, to: gov.address });

    val proposal = gov.getProposal(0)!.load();
    expect(proposal.executed).toEqual(true);
}

get fun `test governance: executed proposal cannot be executed twice`() {
    val (gov, admin, voter) = setupGovernance();
    createGovernanceProposal(gov, admin, voter.address);
    gov.sendCastVote(voter.address, 0, 0, true, { bounce: false, value: ton("0.2") });

    testing.setNow(GV_START + GV_VOTING_PERIOD + GV_TIMELOCK + 1);
    gov.sendExecuteProposal(voter.address, 0, 0, { bounce: false, value: ton("0.2") });

    val result = gov.sendExecuteProposal(
        voter.address,
        0,
        0,
        { bounce: false, value: ton("0.2") },
    );
    expect(result).toHaveFailedTx<ExecuteProposal>({
        from: voter.address,
        to: gov.address,
        exitCode: Errors.InvalidOp,
    });
}

get fun `test governance: has_voted is false before voting`() {
    val (gov, admin, voter) = setupGovernance();
    createGovernanceProposal(gov, admin, voter.address);
    expect(gov.hasVoted(0, voter.address)).toEqual(false);
    expect(gov.hasVoted(0, admin.address)).toEqual(false);
}
