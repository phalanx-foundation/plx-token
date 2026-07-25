import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"

import "@contracts/LiquidityLocker"
import "@contracts/errors"
import "@contracts/messages"
import "@contracts/storage"
import "@wrappers/JettonMinter.gen"
import "@wrappers/LiquidityLocker.gen"
import "@wrappers/utils"

import "test-utils"

const LL_UNIT = 1000000000
const LL_LOCK_AMOUNT = 5000 * LL_UNIT
const LL_UNLOCK_DAYS: uint32 = 7776000 // 90 days

const LL_FORWARD_OP: uint32 = 0x4c504b10

fun makeLockPayload(unlockAt: uint32): slice {
    return beginCell().storeUint(LL_FORWARD_OP, 32).storeUint(unlockAt, 32).endCell().beginParse();
}

fun setupLiquidityLocker(): (JettonMinter, LiquidityLocker, Treasury, Treasury) {
    val deployer = testing.treasury("ll-deployer");
    val lpProvider = testing.treasury("ll-provider");
    testing.setNow(1700000000);

    // LP token minter (simulated with JettonMinter)
    val lpMinter = JettonMinter.fromStorage({
        totalSupply: 0,
        adminAddress: deployer.address,
        nextAdminAddress: null,
        metadata: buildTestMetadata("ll-lp-token"),
    });
    expect(lpMinter.sendDeploy(deployer.address, { value: ton("10") })).toHaveSuccessfulDeploy({
        to: lpMinter.address,
    });

    val config: LockerConfig = {
        admin: deployer.address,
        lpTokenMinter: lpMinter.address,
    };

    val locker = LiquidityLocker.fromStorage({
        config: config.toCell(),
        nextLockId: 0,
        totalLocked: 0,
        locks: [],
    });
    expect(locker.sendDeploy(deployer.address, { value: ton("5") })).toHaveSuccessfulDeploy({
        to: locker.address,
    });

    // Fund LP provider with tokens
    mintTokensTo(deployer, lpMinter, lpProvider, 100000 * LL_UNIT);

    return (lpMinter, locker, deployer, lpProvider);
}

fun lockLpTokens(
    lpMinter: JettonMinter,
    locker: LiquidityLocker,
    provider: Treasury,
    amount: coins,
    unlockAt: uint32,
): SendResultList {
    return transferTokensTo(lpMinter, provider, locker, amount, makeLockPayload(unlockAt));
}

// ---- tests ----

fun test_deploy_locker(): void {
    val (lpMinter, locker, deployer, provider) = setupLiquidityLocker();

    val data = locker.getLockerData();
    expect(data._1).toBe(0); // nextLockId
    expect(data._2).toBe(0); // totalLocked
}

fun test_lock_lp_tokens(): void {
    val (lpMinter, locker, deployer, provider) = setupLiquidityLocker();

    val unlockAt = 1700000000 + LL_UNLOCK_DAYS;
    val result = lockLpTokens(lpMinter, locker, provider, LL_LOCK_AMOUNT, unlockAt);
    expect(result).toHaveTransactionTo(locker.address);

    val data = locker.getLockerData();
    expect(data._1).toBe(1);               // nextLockId = 1
    expect(data._2).toBe(LL_LOCK_AMOUNT);  // totalLocked

    val lock = locker.getLock(0);
    expect(lock).notToBeNull();
    val l = lock!!.load();
    expect(l.owner).toBe(provider.address);
    expect(l.lpAmount).toBe(LL_LOCK_AMOUNT);
    expect(l.unlockAt).toBe(unlockAt);
    expect(l.released).toBe(false);
}

fun test_lock_past_timestamp_fails(): void {
    val (lpMinter, locker, deployer, provider) = setupLiquidityLocker();

    val result = lockLpTokens(lpMinter, locker, provider, LL_LOCK_AMOUNT, 1600000000); // past
    // Should be ignored (no valid forward payload match)
    expect(result).toHaveTransactionTo(locker.address);

    val data = locker.getLockerData();
    expect(data._1).toBe(0); // No lock created
}

fun test_unlock_after_lock_period(): void {
    val (lpMinter, locker, deployer, provider) = setupLiquidityLocker();

    val unlockAt = 1700000000 + LL_UNLOCK_DAYS;
    expect(lockLpTokens(lpMinter, locker, provider, LL_LOCK_AMOUNT, unlockAt)).toHaveTransactionTo(locker.address);

    testing.setNow(unlockAt + 1);

    val result = locker.sendUnlockLiquidity(provider.address, 0, 0);
    expect(result).toHaveTransactionTo(locker.address);

    val data = locker.getLockerData();
    expect(data._2).toBe(0); // totalLocked = 0

    val lock = locker.getLock(0);
    val l = lock!!.load();
    expect(l.released).toBe(true);
}

fun test_unlock_before_period_fails(): void {
    val (lpMinter, locker, deployer, provider) = setupLiquidityLocker();

    val unlockAt = 1700000000 + LL_UNLOCK_DAYS;
    expect(lockLpTokens(lpMinter, locker, provider, LL_LOCK_AMOUNT, unlockAt)).toHaveTransactionTo(locker.address);

    val result = locker.sendUnlockLiquidity(provider.address, 0, 0);
    expect(result).toHaveExitCode(Errors.NothingToClaim);
}

fun test_only_owner_can_unlock(): void {
    val (lpMinter, locker, deployer, provider) = setupLiquidityLocker();

    val unlockAt = 1700000000 + LL_UNLOCK_DAYS;
    expect(lockLpTokens(lpMinter, locker, provider, LL_LOCK_AMOUNT, unlockAt)).toHaveTransactionTo(locker.address);
    testing.setNow(unlockAt + 1);

    val result = locker.sendUnlockLiquidity(deployer.address, 0, 0);
    expect(result).toHaveExitCode(Errors.NotOwner);
}

fun test_admin_revoke_lock(): void {
    val (lpMinter, locker, deployer, provider) = setupLiquidityLocker();

    val unlockAt = 1700000000 + LL_UNLOCK_DAYS;
    expect(lockLpTokens(lpMinter, locker, provider, LL_LOCK_AMOUNT, unlockAt)).toHaveTransactionTo(locker.address);

    // Admin revokes before unlock period
    val result = locker.sendRevokeLock(deployer.address, 0, 0);
    expect(result).toHaveTransactionTo(locker.address);

    val data = locker.getLockerData();
    expect(data._2).toBe(0); // totalLocked back to 0

    val lock = locker.getLock(0);
    val l = lock!!.load();
    expect(l.released).toBe(true);
}

fun test_non_admin_cannot_revoke(): void {
    val (lpMinter, locker, deployer, provider) = setupLiquidityLocker();

    val unlockAt = 1700000000 + LL_UNLOCK_DAYS;
    expect(lockLpTokens(lpMinter, locker, provider, LL_LOCK_AMOUNT, unlockAt)).toHaveTransactionTo(locker.address);

    val result = locker.sendRevokeLock(provider.address, 0, 0);
    expect(result).toHaveExitCode(Errors.NotOwner);
}

fun test_double_unlock_fails(): void {
    val (lpMinter, locker, deployer, provider) = setupLiquidityLocker();

    val unlockAt = 1700000000 + LL_UNLOCK_DAYS;
    expect(lockLpTokens(lpMinter, locker, provider, LL_LOCK_AMOUNT, unlockAt)).toHaveTransactionTo(locker.address);
    testing.setNow(unlockAt + 1);

    expect(locker.sendUnlockLiquidity(provider.address, 0, 0)).toHaveTransactionTo(locker.address);

    val result2 = locker.sendUnlockLiquidity(provider.address, 0, 0);
    expect(result2).toHaveExitCode(Errors.InvalidOp);
}
