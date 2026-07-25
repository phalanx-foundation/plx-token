import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"

import "@contracts/TokenGovernance"
import "@contracts/errors"
import "@contracts/messages"
import "@wrappers/TokenGovernance.gen"

const GV_UNIT = 1000000000

fun setupGovernance(): (TokenGovernance, Treasury, Treasury) {
    val admin = testing.treasury("gv-admin");
    val voter = testing.treasury("gv-voter");
    testing.setNow(1700000000);

    val config: GovernanceConfig = {
        admin: admin.address,
        minterAddress: admin.address,
        proposalThreshold: 1000 * GV_UNIT,
        quorumBps: 5000, // 50%
        votingPeriodSec: 604800, // 7 days
        timelockSec: 86400, // 1 day
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

fun dummyPayload(): Cell {
    return beginCell().storeUint(0, 32).endCell();
}

// ---- tests ----

fun test_deploy_governance(): void {
    val (gov, admin, voter) = setupGovernance();

    val cfg = gov.getConfig();
    expect(cfg).notToBeNull();
    val c = cfg!!.load();
    expect(c.admin).toBe(admin.address);
    expect(c.votingPeriodSec).toBe(604800);
}

fun test_create_proposal(): void {
    val (gov, admin, voter) = setupGovernance();

    val result = gov.sendCreateProposal(
        admin.address, 0,
        0xabc1230000000000000000000000000000000000000000000000000000000000 as bits256,
        gov.address,
        dummyPayload(),
    );
    expect(result).toHaveTransactionTo(gov.address);

    val proposal = gov.getProposal(0);
    expect(proposal).notToBeNull();
    val p = proposal!!.load();
    expect(p.executed).toBe(false);
    expect(p.voteFor).toBe(0);
    expect(p.voteAgainst).toBe(0);
}

fun test_non_admin_cannot_create_proposal(): void {
    val (gov, admin, voter) = setupGovernance();

    val result = gov.sendCreateProposal(
        voter.address, 0,
        0xabc1230000000000000000000000000000000000000000000000000000000000 as bits256,
        gov.address,
        dummyPayload(),
    );
    expect(result).toHaveExitCode(Errors.NotOwner);
}

fun test_cast_vote(): void {
    val (gov, admin, voter) = setupGovernance();

    expect(gov.sendCreateProposal(
        admin.address, 0,
        0xabc1230000000000000000000000000000000000000000000000000000000000 as bits256,
        gov.address,
        dummyPayload(),
    )).toHaveTransactionTo(gov.address);

    val result = gov.sendCastVote(voter.address, 0, 0, true);
    expect(result).toHaveTransactionTo(gov.address);

    val proposal = gov.getProposal(0);
    expect(proposal).notToBeNull();
    val p = proposal!!.load();
    expect(p.voteFor).toBe(1);
    expect(p.voteAgainst).toBe(0);

    val voted = gov.hasVoted(0, voter.address);
    expect(voted).toBe(true);
}

fun test_cast_vote_against(): void {
    val (gov, admin, voter) = setupGovernance();

    expect(gov.sendCreateProposal(
        admin.address, 0,
        0xabc1230000000000000000000000000000000000000000000000000000000000 as bits256,
        gov.address,
        dummyPayload(),
    )).toHaveTransactionTo(gov.address);

    expect(gov.sendCastVote(voter.address, 0, 0, false)).toHaveTransactionTo(gov.address);

    val proposal = gov.getProposal(0);
    val p = proposal!!.load();
    expect(p.voteAgainst).toBe(1);
}

fun test_cannot_vote_twice(): void {
    val (gov, admin, voter) = setupGovernance();

    expect(gov.sendCreateProposal(
        admin.address, 0,
        0xabc1230000000000000000000000000000000000000000000000000000000000 as bits256,
        gov.address,
        dummyPayload(),
    )).toHaveTransactionTo(gov.address);

    expect(gov.sendCastVote(voter.address, 0, 0, true)).toHaveTransactionTo(gov.address);

    val result2 = gov.sendCastVote(voter.address, 0, 0, false);
    expect(result2).toHaveExitCode(Errors.InvalidOp);
}

fun test_execute_before_voting_ends_fails(): void {
    val (gov, admin, voter) = setupGovernance();

    expect(gov.sendCreateProposal(
        admin.address, 0,
        0xabc1230000000000000000000000000000000000000000000000000000000000 as bits256,
        gov.address,
        dummyPayload(),
    )).toHaveTransactionTo(gov.address);

    val result = gov.sendExecuteProposal(admin.address, 0, 0);
    expect(result).toHaveExitCode(Errors.NothingToClaim);
}

fun test_execute_after_timelock(): void {
    val (gov, admin, voter) = setupGovernance();

    expect(gov.sendCreateProposal(
        admin.address, 0,
        0xabc1230000000000000000000000000000000000000000000000000000000000 as bits256,
        gov.address,
        dummyPayload(),
    )).toHaveTransactionTo(gov.address);

    // Cast enough votes to pass (quorum = 50% of snapshot)
    val voter2 = testing.treasury("gv-voter2");
    voter2.setBalance(100000 * GV_UNIT);
    expect(gov.sendCastVote(voter.address, 0, 0, true)).toHaveTransactionTo(gov.address);
    expect(gov.sendCastVote(voter2.address, 0, 0, true)).toHaveTransactionTo(gov.address);

    // Fast-forward past voting + timelock
    testing.setNow(1700000000 + 604800 + 86400 + 1);

    val result = gov.sendExecuteProposal(admin.address, 0, 0);
    expect(result).toHaveTransactionTo(gov.address);

    val proposal = gov.getProposal(0);
    val p = proposal!!.load();
    expect(p.executed).toBe(true);
}

fun test_admin_update_config(): void {
    val (gov, admin, voter) = setupGovernance();

    val result = gov.sendUpdateConfig(admin.address, 0, 500 * GV_UNIT, 3000, 1209600, 172800);
    expect(result).toHaveTransactionTo(gov.address);
}
