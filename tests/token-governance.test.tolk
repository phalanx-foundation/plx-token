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
        quorumBps: 5000,
        votingPeriodSec: 604800,
        timelockSec: 86400,
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

get fun `test governance: deploy stores admin config`() {
    val (gov, admin, voter) = setupGovernance();
    val cfg = gov.getConfig().load();
    expect(cfg.admin).toEqual(admin.address);
    expect(cfg.votingPeriodSec).toEqual(604800);
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
        604800,
        86400,
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
