import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"

import "@contracts/TokenLockVault"
import "@contracts/errors"
import "@contracts/messages"
import "@wrappers/JettonMinter.gen"
import "@wrappers/TokenLockVault.gen"
import "@wrappers/utils"

import "test-utils"

const LV_UNIT = 1000000000
const LV_LOCK_AMOUNT = 10000 * LV_UNIT
const LV_REWARD_FUND = 50000 * LV_UNIT
const LV_TIER_DURATION: uint32 = 7776000
const LV_TIER_BONUS_BPS: uint16 = 500
const LV_DEPOSIT_OP: uint32 = 0x4f434b01
const LV_REWARD_POOL_OP: uint32 = 0x4f434b06

fun makeLockDepositPayload(tierIndex: uint8, isSovereign: bool): slice {
    return beginCell()
        .storeUint(LV_DEPOSIT_OP, 32)
        .storeUint(tierIndex, 8)
        .storeUint(isSovereign ? 1 : 0, 1)
        .endCell()
        .beginParse();
}

fun makeRewardPoolPayload(): slice {
    return beginCell().storeUint(LV_REWARD_POOL_OP, 32).endCell().beginParse();
}

fun emptyLockTier(): LockTier {
    return LockTier { durationSec: 0, bonusBps: 0 };
}

fun setupLockVault(): (JettonMinter, TokenLockVault, Treasury, Treasury) {
    val deployer = testing.treasury("lv-deployer");
    val user = testing.treasury("lv-user");
    testing.setNow(1700000000);

    val minter = JettonMinter.fromStorage({
        totalSupply: 0,
        adminAddress: deployer.address,
        nextAdminAddress: null,
        metadata: buildTestMetadata("lv-test-token"),
    });
    expect(minter.sendDeploy(deployer.address, { value: ton("10") })).toHaveSuccessfulDeploy({
        to: minter.address,
    });

    val config: LockVaultConfig = {
        admin: deployer.address,
        minterAddress: minter.address,
        tierCount: 1,
        tier0: LockTier { durationSec: LV_TIER_DURATION, bonusBps: LV_TIER_BONUS_BPS },
        tier1: emptyLockTier(),
        tier2: emptyLockTier(),
        tier3: emptyLockTier(),
        eventEndAt: 0,
        minLockAmount: 1000 * LV_UNIT,
        sovereignMinAmount: 1000000 * LV_UNIT,
    };

    val vault = TokenLockVault.fromStorage({
        config: config.toCell(),
        nextPositionId: 0,
        totalLocked: 0,
        rewardPool: 0,
        positions: [],
    });
    expect(vault.sendDeploy(deployer.address, { value: ton("5") })).toHaveSuccessfulDeploy({
        to: vault.address,
    });

    mintTokensTo(deployer, minter, user.address, 200000 * LV_UNIT);
    mintTokensTo(deployer, minter, deployer.address, LV_REWARD_FUND);
    expect(
        transferTokensTo(minter, deployer, vault.address, LV_REWARD_FUND, makeRewardPoolPayload()),
    ).toHaveSuccessfulTx<TransferNotificationForRecipient>({ to: vault.address });

    return (minter, vault, deployer, user);
}

get fun `test token-lock-vault: deploy and fund reward pool`() {
    val (minter, vault, deployer, user) = setupLockVault();
    val (nextPositionId, totalLocked, rewardPool, _) = vault.getLockVaultData();
    expect(nextPositionId).toEqual(0);
    expect(totalLocked).toEqual(0);
    expect(rewardPool).toEqual(LV_REWARD_FUND);
    expect(minter.address).toEqual(minter.address);
    expect(user.address).toEqual(user.address);
    expect(deployer.address).toEqual(deployer.address);
}

get fun `test token-lock-vault: lock then release after maturity`() {
    val (minter, vault, deployer, user) = setupLockVault();

    val lockRes = transferTokensTo(
        minter,
        user,
        vault.address,
        LV_LOCK_AMOUNT,
        makeLockDepositPayload(0, false),
    );
    expect(lockRes).toHaveSuccessfulTx<TransferNotificationForRecipient>({ to: vault.address });

    val (nextId, locked, _, _) = vault.getLockVaultData();
    expect(nextId).toEqual(1);
    expect(locked).toEqual(LV_LOCK_AMOUNT);

    testing.setNow(1700000000 + LV_TIER_DURATION + 1);
    val release = vault.sendReleaseLock(user.address, 0, 0, { bounce: false, value: ton("0.2") });
    expect(release).toHaveSuccessfulTx<ReleaseLock>({ from: user.address, to: vault.address });

    val (_, lockedAfter, _, _) = vault.getLockVaultData();
    expect(lockedAfter).toEqual(0);
}

get fun `test token-lock-vault: early release rejected`() {
    val (minter, vault, deployer, user) = setupLockVault();
    transferTokensTo(minter, user, vault.address, LV_LOCK_AMOUNT, makeLockDepositPayload(0, false));

    val early = vault.sendReleaseLock(user.address, 0, 0, { bounce: false, value: ton("0.2") });
    expect(early).toHaveFailedTx<ReleaseLock>({
        from: user.address,
        to: vault.address,
        exitCode: Errors.NothingToClaim,
    });
}
