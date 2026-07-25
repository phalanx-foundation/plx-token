import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"

import "@contracts/TokenLockVault"
import "@contracts/errors"
import "@contracts/messages"
import "@contracts/storage"
import "@wrappers/JettonMinter.gen"
import "@wrappers/TokenLockVault.gen"
import "@wrappers/utils"

import "test-utils"

const LV_UNIT = 1000000000
const LV_LOCK_AMOUNT = 10000 * LV_UNIT
const LV_REWARD_FUND = 50000 * LV_UNIT
const LV_TIER_DURATION: uint32 = 7776000  // 90 days
const LV_TIER_BONUS_BPS: uint16 = 500      // 5%

const LV_DEPOSIT_OP: uint32 = 0x4f434b01
const LV_REWARD_POOL_OP: uint32 = 0x4f434b06

fun makeLockDepositPayload(tierIndex: uint8, isSovereign: bool): slice {
    return beginCell()
        .storeUint(LV_DEPOSIT_OP, 32)
        .storeUint(tierIndex, 8)
        .storeUint(if (isSovereign) { 1 } else { 0 }, 1)
        .endCell().beginParse();
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
        tierCount: 2,
        tier0: LockTier { durationSec: LV_TIER_DURATION, bonusBps: LV_TIER_BONUS_BPS },
        tier1: LockTier { durationSec: LV_TIER_DURATION * 2, bonusBps: LV_TIER_BONUS_BPS * 2 },
        tier2: emptyLockTier(),
        tier3: emptyLockTier(),
        eventEndAt: 0,
        minLockAmount: 1000 * LV_UNIT,
        sovereignMinAmount: 50000 * LV_UNIT,
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

    // Fund user + reward pool
    mintTokensTo(deployer, minter, user, 200000 * LV_UNIT);
    mintTokensTo(deployer, minter, vault, LV_REWARD_FUND, makeRewardPoolPayload());

    return (minter, vault, deployer, user);
}

fun lockTokens(
    minter: JettonMinter,
    vault: TokenLockVault,
    user: Treasury,
    amount: coins,
    tierIndex: uint8,
    isSovereign: bool,
): SendResultList {
    return transferTokensTo(minter, user, vault, amount, makeLockDepositPayload(tierIndex, isSovereign));
}

// ---- tests ----

fun test_deploy_lock_vault(): void {
    val (minter, vault, deployer, user) = setupLockVault();

    val data = vault.getLockVaultData();
    expect(data._1).toBe(0);  // nextPositionId
    expect(data._2).toBe(0);  // totalLocked
    expect(data._3).toBe(LV_REWARD_FUND); // rewardPool
}

fun test_lock_tokens(): void {
    val (minter, vault, deployer, user) = setupLockVault();

    val result = lockTokens(minter, vault, user, LV_LOCK_AMOUNT, 0, false);
    expect(result).toHaveTransactionTo(vault.address);

    val data = vault.getLockVaultData();
    expect(data._1).toBe(1);              // nextPositionId = 1
    expect(data._2).toBe(LV_LOCK_AMOUNT); // totalLocked

    val position = vault.getPosition(0);
    expect(position).notToBeNull();
    val p = position!!.load();
    expect(p.owner).toBe(user.address);
    expect(p.amount).toBe(LV_LOCK_AMOUNT);
    expect(p.released).toBe(false);
    expect(p.tierBps).toBe(LV_TIER_BONUS_BPS);
}

fun test_lock_below_min_amount_fails(): void {
    val (minter, vault, deployer, user) = setupLockVault();

    val result = lockTokens(minter, vault, user, 500 * LV_UNIT, 0, false);
    expect(result).toHaveExitCode(Errors.BalanceError);
}

fun test_lock_invalid_tier_fails(): void {
    val (minter, vault, deployer, user) = setupLockVault();

    val result = lockTokens(minter, vault, user, LV_LOCK_AMOUNT, 2, false);
    expect(result).toHaveExitCode(Errors.InvalidOp);
}

fun test_release_after_unlock(): void {
    val (minter, vault, deployer, user) = setupLockVault();

    expect(lockTokens(minter, vault, user, LV_LOCK_AMOUNT, 0, false)).toHaveTransactionTo(vault.address);

    testing.setNow(1700000000 + LV_TIER_DURATION + 1);

    val result = vault.sendReleaseLock(user.address, 0, 0);
    expect(result).toHaveTransactionTo(vault.address);

    val data = vault.getLockVaultData();
    expect(data._2).toBe(0); // totalLocked = 0

    val position = vault.getPosition(0);
    expect(position).notToBeNull();
    val p = position!!.load();
    expect(p.released).toBe(true);
}

fun test_release_before_unlock_fails(): void {
    val (minter, vault, deployer, user) = setupLockVault();

    expect(lockTokens(minter, vault, user, LV_LOCK_AMOUNT, 0, false)).toHaveTransactionTo(vault.address);

    val result = vault.sendReleaseLock(user.address, 0, 0);
    expect(result).toHaveExitCode(Errors.NothingToClaim);
}

fun test_only_owner_can_release(): void {
    val (minter, vault, deployer, user) = setupLockVault();

    expect(lockTokens(minter, vault, user, LV_LOCK_AMOUNT, 0, false)).toHaveTransactionTo(vault.address);
    testing.setNow(1700000000 + LV_TIER_DURATION + 1);

    val result = vault.sendReleaseLock(deployer.address, 0, 0);
    expect(result).toHaveExitCode(Errors.NotOwner);
}

fun test_admin_update_tiers(): void {
    val (minter, vault, deployer, user) = setupLockVault();

    val newTier = LockTier { durationSec: 15552000, bonusBps: 800 };
    val result = vault.sendUpdateTiers(deployer.address, 0, 2, newTier, emptyLockTier(), emptyLockTier(), emptyLockTier());
    expect(result).toHaveTransactionTo(vault.address);
}

fun test_double_release_fails(): void {
    val (minter, vault, deployer, user) = setupLockVault();

    expect(lockTokens(minter, vault, user, LV_LOCK_AMOUNT, 0, false)).toHaveTransactionTo(vault.address);
    testing.setNow(1700000000 + LV_TIER_DURATION + 1);

    expect(vault.sendReleaseLock(user.address, 0, 0)).toHaveTransactionTo(vault.address);

    val result2 = vault.sendReleaseLock(user.address, 0, 0);
    expect(result2).toHaveExitCode(Errors.InvalidOp);
}
