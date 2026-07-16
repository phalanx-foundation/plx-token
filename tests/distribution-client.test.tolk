import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"

import "@contracts/TeamVesting"
import "@contracts/messages"
import "@contracts/storage"
import "@wrappers/JettonMinter.gen"
import "@wrappers/TeamVesting.gen"
import "@wrappers/utils"

import "test-utils"

// Validates the on-chain mechanism used by deploy-distribution-client.tolk:
// multi-bucket mint (like PLX genesis), a vesting bucket, and escrow admin
// handover to the client wallet.

const PLX = 1000000000 // 9 decimals
const START_TIME = 1700000000
const SIX_MONTHS_SECONDS = 15552000

get fun `test distribution: five-bucket split mints correct balances`() {
    val (minter, deployer, _) = setupTest(0);
    val lp = testing.treasury("dist-lp");
    val treasury = testing.treasury("dist-treasury");
    val community = testing.treasury("dist-community");
    val marketing = testing.treasury("dist-marketing");

    val lpWallet = mintTo(minter, deployer, lp.address, 400000000 * PLX);
    val treasuryWallet = mintTo(minter, deployer, treasury.address, 250000000 * PLX);
    val communityWallet = mintTo(minter, deployer, community.address, 200000000 * PLX);
    val marketingWallet = mintTo(minter, deployer, marketing.address, 50000000 * PLX);

    expect(lpWallet.getJettonBalance()).toEqual(400000000 * PLX);
    expect(treasuryWallet.getJettonBalance()).toEqual(250000000 * PLX);
    expect(communityWallet.getJettonBalance()).toEqual(200000000 * PLX);
    expect(marketingWallet.getJettonBalance()).toEqual(50000000 * PLX);
    expect(minter.getTotalSupply()).toEqual(900000000 * PLX);
}

get fun `test distribution: vesting bucket funds the vesting contract`() {
    // Set emulation time before any deploy so the vesting account is created
    // at the same logical time as the minter (avoids backward-time storage errors).
    testing.setNow(START_TIME);
    val (minter, deployer, _) = setupTest(0);
    val client = testing.treasury("dist-client");
    val teamBeneficiary = testing.treasury("dist-team");

    val vestingConfig: VestingConfig = {
        beneficiary: teamBeneficiary.address,
        admin: client.address,
        minterAddress: minter.address,
        totalAmount: 100000000 * PLX,
        startTime: START_TIME,
        duration: SIX_MONTHS_SECONDS,
    };
    val vesting = TeamVesting.fromStorage({
        config: vestingConfig.toCell(),
        claimedAmount: 0,
    });
    val vDeploy = vesting.sendDeploy(deployer.address, { value: ton("5") });
    expect(vDeploy).toHaveSuccessfulDeploy({ to: vesting.address });

    val vestingWallet = mintTo(minter, deployer, vesting.address, 100000000 * PLX);
    expect(vestingWallet.getJettonBalance()).toEqual(100000000 * PLX);

    val cfg = vesting.getVestingData();
    expect(cfg.beneficiary).toEqual(teamBeneficiary.address);
    expect(cfg.totalAmount).toEqual(100000000 * PLX);
}

get fun `test distribution: escrow hands minter admin to client`() {
    val (minter, deployer, _) = setupTest(0);
    val client = testing.treasury("dist-admin-client");

    val lp = testing.treasury("dist-admin-lp");
    mintTo(minter, deployer, lp.address, 1000000000 * PLX);
    expect(minter.getTotalSupply()).toEqual(1000000000 * PLX);

    val change = minter.sendChangeMinterAdmin(
        deployer.address,
        0,
        client.address,
        { bounce: false, value: ton("0.1") },
    );
    expect(change).toHaveSuccessfulTx<ChangeMinterAdmin>({
        from: deployer.address,
        to: minter.address,
    });

    val claim = minter.sendClaimMinterAdmin(
        client.address,
        0,
        { bounce: false, value: ton("0.1") },
    );
    expect(claim).toHaveSuccessfulTx<ClaimMinterAdmin>({
        from: client.address,
        to: minter.address,
    });

    expect(minter.getJettonData().adminAddress).toEqual(client.address);
}
