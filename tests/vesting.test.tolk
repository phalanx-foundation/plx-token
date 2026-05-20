import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"

import "@contracts/TeamVesting"
import "@contracts/errors"
import "@contracts/messages"
import "@contracts/storage"
import "@wrappers/JettonMinter.gen"
import "@wrappers/TeamVesting.gen"
import "@wrappers/utils"

import "test-utils"

const SIX_MONTHS_SECONDS = 15768000
const VESTING_TOTAL = 100000000000000000 // 100M PLX with 9 decimals
const START_TIME = 1700000000

// Helper: setup fresh minter + vesting contract + fund vesting
fun setupVesting(): (JettonMinter, TeamVesting, Treasury, Treasury) {
    val deployer = testing.treasury("vesting-deployer");
    val beneficiary = testing.treasury("vesting-beneficiary");

    // Set blockchain time to known START_TIME
    testing.setNow(START_TIME);

    // Deploy minter
    val minter = JettonMinter.fromStorage({
        totalSupply: 0,
        adminAddress: deployer.address,
        nextAdminAddress: null,
        metadata: buildTestMetadata("plx-test"),
    });
    val deployRes = minter.sendDeploy(deployer.address, { value: ton("10") });
    expect(deployRes).toHaveSuccessfulDeploy({ to: minter.address });

    // Build vesting contract
    val vestingConfig: VestingConfig = {
        beneficiary: beneficiary.address,
        admin: deployer.address,
        minterAddress: minter.address,
        totalAmount: VESTING_TOTAL,
        startTime: START_TIME,
        duration: SIX_MONTHS_SECONDS,
    };
    val vesting = TeamVesting.fromStorage({
        config: vestingConfig.toCell(),
        claimedAmount: 0,
    });

    // Deploy vesting (fund with extra TON for claim gas)
    val vestingDeployRes = vesting.sendDeploy(deployer.address, { value: ton("5") });
    expect(vestingDeployRes).toHaveSuccessfulDeploy({ to: vesting.address });

    // Mint VESTING_TOTAL PLX to the vesting contract address (creates its jetton wallet)
    val mintRes = minter.sendMint(
        deployer.address,
        vesting.address,
        VESTING_TOTAL,
        ton("0.05"),
        ton("0.5"),
    );
    expect(mintRes).toHaveSuccessfulTx<MintNewJettons>({
        from: deployer.address,
        to: minter.address,
    });

    return (minter, vesting, deployer, beneficiary);
}

get fun `test vesting: deploy populates config correctly`() {
    val (_, vesting, _, beneficiary) = setupVesting();

    val cfg = vesting.getVestingData();
    expect(cfg.beneficiary).toEqual(beneficiary.address);
    expect(cfg.totalAmount).toEqual(VESTING_TOTAL);
    expect(cfg.startTime).toEqual(START_TIME);
    expect(cfg.duration).toEqual(SIX_MONTHS_SECONDS);
}

get fun `test vesting: at t=start nothing is claimable`() {
    val (_, vesting, _, _) = setupVesting();
    testing.setNow(START_TIME);

    expect(vesting.getVestedAmount()).toEqual(0);
    expect(vesting.getClaimableAmount()).toEqual(0);
}

get fun `test vesting: claim before unlock should fail`() {
    val (_, vesting, _, beneficiary) = setupVesting();
    testing.setNow(START_TIME);

    val res = vesting.sendClaimVested(
        beneficiary.address,
        0,
        { bounce: false, value: ton("0.2") },
    );
    expect(res).toHaveFailedTx<ClaimVested>({
        from: beneficiary.address,
        to: vesting.address,
        exitCode: 100,
    });
}

get fun `test vesting: half-time linear release`() {
    val (_, vesting, _, _) = setupVesting();
    testing.setNow(START_TIME + SIX_MONTHS_SECONDS / 2);

    val vested = vesting.getVestedAmount();
    expect(vested).toEqual(VESTING_TOTAL / 2);

    val claimable = vesting.getClaimableAmount();
    expect(claimable).toEqual(VESTING_TOTAL / 2);
}

get fun `test vesting: claim half-time sends jettons to beneficiary`() {
    val (minter, vesting, _, beneficiary) = setupVesting();
    testing.setNow(START_TIME + SIX_MONTHS_SECONDS / 2);

    val beneficiaryWallet = userWallet(minter, beneficiary.address);
    val balanceBefore = beneficiaryWallet.getJettonBalance();

    val res = vesting.sendClaimVested(
        beneficiary.address,
        0,
        { bounce: false, value: ton("0.3") },
    );
    expect(res).toHaveSuccessfulTx<ClaimVested>({
        from: beneficiary.address,
        to: vesting.address,
    });

    val balanceAfter = beneficiaryWallet.getJettonBalance();
    expect(balanceAfter - balanceBefore).toEqual(VESTING_TOTAL / 2);
    expect(vesting.getClaimedAmount()).toEqual(VESTING_TOTAL / 2);
}

get fun `test vesting: claim then claim again later releases more`() {
    val (minter, vesting, _, beneficiary) = setupVesting();

    testing.setNow(START_TIME + SIX_MONTHS_SECONDS / 2);
    vesting.sendClaimVested(beneficiary.address, 0, { bounce: false, value: ton("0.3") });

    testing.setNow(START_TIME + SIX_MONTHS_SECONDS);
    val res2 = vesting.sendClaimVested(
        beneficiary.address,
        1,
        { bounce: false, value: ton("0.3") },
    );
    expect(res2).toHaveSuccessfulTx<ClaimVested>({
        from: beneficiary.address,
        to: vesting.address,
    });

    val beneficiaryWallet = userWallet(minter, beneficiary.address);
    expect(beneficiaryWallet.getJettonBalance()).toEqual(VESTING_TOTAL);
    expect(vesting.getClaimedAmount()).toEqual(VESTING_TOTAL);
}

get fun `test vesting: full duration releases all`() {
    val (minter, vesting, _, beneficiary) = setupVesting();
    testing.setNow(START_TIME + SIX_MONTHS_SECONDS);

    expect(vesting.getVestedAmount()).toEqual(VESTING_TOTAL);
    expect(vesting.getClaimableAmount()).toEqual(VESTING_TOTAL);

    val res = vesting.sendClaimVested(
        beneficiary.address,
        0,
        { bounce: false, value: ton("0.3") },
    );
    expect(res).toHaveSuccessfulTx<ClaimVested>({
        from: beneficiary.address,
        to: vesting.address,
    });

    val beneficiaryWallet = userWallet(minter, beneficiary.address);
    expect(beneficiaryWallet.getJettonBalance()).toEqual(VESTING_TOTAL);
}

get fun `test vesting: time after duration caps at total`() {
    val (_, vesting, _, _) = setupVesting();
    testing.setNow(START_TIME + SIX_MONTHS_SECONDS * 5);

    expect(vesting.getVestedAmount()).toEqual(VESTING_TOTAL);
}

get fun `test vesting: claim twice at same time second should fail`() {
    val (_, vesting, _, beneficiary) = setupVesting();
    testing.setNow(START_TIME + SIX_MONTHS_SECONDS / 2);

    vesting.sendClaimVested(beneficiary.address, 0, { bounce: false, value: ton("0.3") });

    val res2 = vesting.sendClaimVested(
        beneficiary.address,
        1,
        { bounce: false, value: ton("0.3") },
    );
    expect(res2).toHaveFailedTx<ClaimVested>({
        from: beneficiary.address,
        to: vesting.address,
        exitCode: 100,
    });
}

get fun `test vesting: revoke by admin sends vested to beneficiary and rest to admin`() {
    val (minter, vesting, deployer, beneficiary) = setupVesting();
    testing.setNow(START_TIME + SIX_MONTHS_SECONDS / 4);

    val res = vesting.sendRevokeVesting(
        deployer.address,
        0,
        { bounce: false, value: ton("0.4") },
    );
    expect(res).toHaveSuccessfulTx<RevokeVesting>({
        from: deployer.address,
        to: vesting.address,
    });

    val beneficiaryWallet = userWallet(minter, beneficiary.address);
    val adminWallet = userWallet(minter, deployer.address);

    expect(beneficiaryWallet.getJettonBalance()).toEqual(VESTING_TOTAL / 4);
    expect(adminWallet.getJettonBalance()).toEqual(VESTING_TOTAL - VESTING_TOTAL / 4);
}

get fun `test vesting: non-admin cannot revoke`() {
    val (_, vesting, _, beneficiary) = setupVesting();
    testing.setNow(START_TIME + SIX_MONTHS_SECONDS / 4);

    val res = vesting.sendRevokeVesting(
        beneficiary.address,
        0,
        { bounce: false, value: ton("0.4") },
    );
    expect(res).toHaveFailedTx<RevokeVesting>({
        from: beneficiary.address,
        to: vesting.address,
        exitCode: Errors.NotOwner,
    });
}

get fun `test vesting: jetton wallet address get matches expected`() {
    val (minter, vesting, _, _) = setupVesting();
    val expected = minter.getWalletAddress(vesting.address);
    expect(vesting.getJettonWalletAddress()).toEqual(expected);
}
