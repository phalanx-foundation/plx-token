import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"

import "@contracts/TokenGovernance"
import "@contracts/errors"
import "@contracts/messages"
import "@wrappers/JettonMinter.gen"
import "@wrappers/TokenGovernance.gen"
import "@wrappers/utils"

import "test-utils"

const GV_UNIT = 1000000000
const GV_START = 1700000000
const GV_VOTING_PERIOD = 604800
const GV_TIMELOCK = 86400
const GV_PROPOSAL_THRESHOLD = 1000 * GV_UNIT
const GV_STAKE_OP: uint32 = 0x474f5653

fun makeGovernanceStakePayload(): slice {
    return beginCell().storeUint(GV_STAKE_OP, 32).endCell().beginParse();
}

fun governanceDescriptionHash(): bits256 {
    return beginCell().storeUint("governance-test-description".sha256(), 256).endCell().beginParse() as bits256;
}

fun setupGovernance(): (JettonMinter, TokenGovernance, Treasury, Treasury) {
    val admin = testing.treasury("gv-admin");
    val voter = testing.treasury("gv-voter");
    testing.setNow(GV_START);

    val minter = JettonMinter.fromStorage({
        totalSupply: 0,
        adminAddress: admin.address,
        nextAdminAddress: null,
        metadata: buildTestMetadata("gv-test-token"),
    });
    expect(minter.sendDeploy(admin.address, { value: ton("10") })).toHaveSuccessfulDeploy({
        to: minter.address,
    });

    val config: GovernanceConfig = {
        admin: admin.address,
        minterAddress: minter.address,
        proposalThreshold: GV_PROPOSAL_THRESHOLD,
        quorumBps: 5000,
        votingPeriodSec: GV_VOTING_PERIOD,
        timelockSec: GV_TIMELOCK,
    };

    val gov = TokenGovernance.fromStorage({
        config: config.toCell(),
        nextProposalId: 0,
        proposals: [],
        votes: [],
        stakes: [],
        totalStaked: 0,
    });
    expect(gov.deploy(admin.address, { value: ton("5") })).toHaveSuccessfulDeploy({
        to: gov.address,
    });

    return (minter, gov, admin, voter);
}

fun stakeGovernance(minter: JettonMinter, admin: Treasury, user: Treasury, gov: TokenGovernance, amount: coins): void {
    mintTokensTo(admin, minter, user.address, amount);
    val res = transferTokensTo(minter, user, gov.address, amount, makeGovernanceStakePayload());
    expect(res).toHaveSuccessfulTx<TransferNotificationForRecipient>({ to: gov.address });
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
    val (minter, gov, admin, voter) = setupGovernance();
    val cfg = gov.getConfig().load();
    expect(cfg.admin).toEqual(admin.address);
    expect(cfg.minterAddress).toEqual(minter.address);
    expect(cfg.votingPeriodSec).toEqual(GV_VOTING_PERIOD);
    expect(cfg.quorumBps).toEqual(5000);
    expect(cfg.proposalThreshold).toEqual(GV_PROPOSAL_THRESHOLD);
    expect(gov.getTotalStaked()).toEqual(0);
    expect(voter.address).toEqual(voter.address);
}

get fun `test governance: non-admin cannot update config`() {
    val (minter, gov, admin, voter) = setupGovernance();
    val result = gov.sendUpdateConfig(
        voter.address,
        0,
        GV_PROPOSAL_THRESHOLD,
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
    val (minter, gov, admin, voter) = setupGovernance();
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
    val (minter, gov, admin, voter) = setupGovernance();
    createGovernanceProposal(gov, admin, voter.address);

    val proposal = gov.getProposal(0)!.load();
    expect(proposal.id).toEqual(0);
    expect(proposal.proposer).toEqual(admin.address);
    expect(proposal.targetContract).toEqual(voter.address);
    expect(proposal.descriptionHash).toEqual(governanceDescriptionHash());
    expect(proposal.snapshotBalance).toEqual(0);
    expect(proposal.voteFor).toEqual(0);
    expect(proposal.voteAgainst).toEqual(0);
    expect(proposal.executed).toEqual(false);
    expect(proposal.votingEndsAt).toEqual(GV_START + GV_VOTING_PERIOD);
}

get fun `test governance: non-staked holder cannot create a proposal`() {
    val (minter, gov, admin, voter) = setupGovernance();
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
        exitCode: Errors.NotEnoughVotingPower,
    });
    expect(gov.getProposal(0)).toEqual(null);
}

get fun `test governance: holder below threshold cannot create a proposal`() {
    val (minter, gov, admin, voter) = setupGovernance();
    stakeGovernance(minter, admin, voter, gov, GV_PROPOSAL_THRESHOLD - GV_UNIT);

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
        exitCode: Errors.NotEnoughVotingPower,
    });
    expect(gov.getProposal(0)).toEqual(null);
}

get fun `test governance: staked holder can create a proposal`() {
    val (minter, gov, admin, voter) = setupGovernance();
    stakeGovernance(minter, admin, voter, gov, GV_PROPOSAL_THRESHOLD);

    val result = gov.sendCreateProposal(
        voter.address,
        0,
        governanceDescriptionHash(),
        admin.address,
        beginCell().endCell(),
        { bounce: false, value: ton("0.2") },
    );
    expect(result).toHaveSuccessfulTx<CreateProposal>({ from: voter.address, to: gov.address });

    val proposal = gov.getProposal(0)!.load();
    expect(proposal.proposer).toEqual(voter.address);
    expect(proposal.snapshotBalance).toEqual(GV_PROPOSAL_THRESHOLD);
    expect(gov.getTotalStaked()).toEqual(GV_PROPOSAL_THRESHOLD);
}

get fun `test governance: staked voter can vote for a proposal`() {
    val (minter, gov, admin, voter) = setupGovernance();
    stakeGovernance(minter, admin, voter, gov, 500 * GV_UNIT);
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
    expect(proposal.voteFor).toEqual(500 * GV_UNIT);
    expect(proposal.voteAgainst).toEqual(0);
    expect(gov.hasVoted(0, voter.address)).toEqual(true);
}

get fun `test governance: staked voter can vote against a proposal`() {
    val (minter, gov, admin, voter) = setupGovernance();
    stakeGovernance(minter, admin, voter, gov, 500 * GV_UNIT);
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
    expect(proposal.voteAgainst).toEqual(500 * GV_UNIT);
    expect(gov.hasVoted(0, voter.address)).toEqual(true);
}

get fun `test governance: vote without stake is rejected`() {
    val (minter, gov, admin, voter) = setupGovernance();
    createGovernanceProposal(gov, admin, voter.address);

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
        exitCode: Errors.NotEnoughVotingPower,
    });
}

get fun `test governance: double vote is rejected`() {
    val (minter, gov, admin, voter) = setupGovernance();
    stakeGovernance(minter, admin, voter, gov, 500 * GV_UNIT);
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

    val proposal = gov.getProposal(0)!.load();
    expect(proposal.voteFor).toEqual(500 * GV_UNIT);
    expect(proposal.voteAgainst).toEqual(0);
}

get fun `test governance: vote after voting period is rejected`() {
    val (minter, gov, admin, voter) = setupGovernance();
    stakeGovernance(minter, admin, voter, gov, 500 * GV_UNIT);
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
    val (minter, gov, admin, voter) = setupGovernance();
    stakeGovernance(minter, admin, voter, gov, 500 * GV_UNIT);
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
    val (minter, gov, admin, voter) = setupGovernance();
    stakeGovernance(minter, admin, voter, gov, 500 * GV_UNIT);
    createGovernanceProposal(gov, admin, voter.address);
    gov.sendCastVote(voter.address, 0, 0, true, { bounce: false, value: ton("0.2") });

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
    val (minter, gov, admin, voter) = setupGovernance();
    stakeGovernance(minter, admin, voter, gov, 500 * GV_UNIT);
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
    val (minter, gov, admin, voter) = setupGovernance();
    stakeGovernance(minter, admin, voter, gov, 500 * GV_UNIT);
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
    val (minter, gov, admin, voter) = setupGovernance();
    stakeGovernance(minter, admin, voter, gov, 500 * GV_UNIT);
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
    val (minter, gov, admin, voter) = setupGovernance();
    createGovernanceProposal(gov, admin, voter.address);
    expect(gov.hasVoted(0, voter.address)).toEqual(false);
    expect(gov.hasVoted(0, admin.address)).toEqual(false);
}

get fun `test governance: voting power reflects staked balance`() {
    val (minter, gov, admin, voter) = setupGovernance();
    expect(gov.getVotingPower(voter.address)).toEqual(0);

    stakeGovernance(minter, admin, voter, gov, 3000 * GV_UNIT);
    expect(gov.getVotingPower(voter.address)).toEqual(3000 * GV_UNIT);
    expect(gov.getTotalStaked()).toEqual(3000 * GV_UNIT);
}

get fun `test governance: staked holder cannot unstake while a vote is active`() {
    val (minter, gov, admin, voter) = setupGovernance();
    stakeGovernance(minter, admin, voter, gov, 500 * GV_UNIT);
    createGovernanceProposal(gov, admin, voter.address);
    gov.sendCastVote(voter.address, 0, 0, true, { bounce: false, value: ton("0.2") });

    val result = gov.sendUnstakeVotingPower(
        voter.address,
        0,
        500 * GV_UNIT,
        { bounce: false, value: ton("0.2") },
    );
    expect(result).toHaveFailedTx<UnstakeVotingPower>({
        from: voter.address,
        to: gov.address,
        exitCode: Errors.NothingToClaim,
    });
    expect(gov.getTotalStaked()).toEqual(500 * GV_UNIT);
}

get fun `test governance: staked holder can unstake after voting period`() {
    val (minter, gov, admin, voter) = setupGovernance();
    stakeGovernance(minter, admin, voter, gov, 500 * GV_UNIT);
    createGovernanceProposal(gov, admin, voter.address);
    gov.sendCastVote(voter.address, 0, 0, true, { bounce: false, value: ton("0.2") });

    testing.setNow(GV_START + GV_VOTING_PERIOD + 1);
    val result = gov.sendUnstakeVotingPower(
        voter.address,
        0,
        500 * GV_UNIT,
        { bounce: false, value: ton("0.2") },
    );
    expect(result).toHaveSuccessfulTx<UnstakeVotingPower>({ from: voter.address, to: gov.address });

    expect(gov.getTotalStaked()).toEqual(0);
    expect(gov.getVotingPower(voter.address)).toEqual(0);
}

get fun `test governance: cannot unstake more than staked`() {
    val (minter, gov, admin, voter) = setupGovernance();
    stakeGovernance(minter, admin, voter, gov, 500 * GV_UNIT);

    val result = gov.sendUnstakeVotingPower(
        voter.address,
        0,
        501 * GV_UNIT,
        { bounce: false, value: ton("0.2") },
    );
    expect(result).toHaveFailedTx<UnstakeVotingPower>({
        from: voter.address,
        to: gov.address,
        exitCode: Errors.BalanceError,
    });
    expect(gov.getTotalStaked()).toEqual(500 * GV_UNIT);
}
