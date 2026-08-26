import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"

import "@contracts/LiquidityLocker"
import "@contracts/errors"
import "@contracts/messages"
import "@wrappers/JettonMinter.gen"
import "@wrappers/LiquidityLocker.gen"
import "@wrappers/utils"

import "test-utils"

const LL_UNIT = 1000000000
const LL_LOCK_AMOUNT = 5000 * LL_UNIT
const LL_UNLOCK_DAYS: uint32 = 7776000
const LL_FORWARD_OP: uint32 = 0x4c504b10

fun makeLockPayload(unlockAt: uint32): slice {
    return beginCell().storeUint(LL_FORWARD_OP, 32).storeUint(unlockAt, 32).endCell().beginParse();
}

fun setupLiquidityLocker(): (JettonMinter, LiquidityLocker, Treasury, Treasury) {
    val deployer = testing.treasury("ll-deployer");
    val lpProvider = testing.treasury("ll-provider");
    testing.setNow(1700000000);

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

    mintTokensTo(deployer, lpMinter, lpProvider.address, 100000 * LL_UNIT);
    return (lpMinter, locker, deployer, lpProvider);
}

get fun `test liquidity-locker: deploy stores empty locker state`() {
    val (lpMinter, locker, deployer, provider) = setupLiquidityLocker();
    val (nextLockId, totalLocked) = locker.getLockerData();
    expect(nextLockId).toEqual(0);
    expect(totalLocked).toEqual(0);
    expect(lpMinter.address).toEqual(lpMinter.address);
    expect(provider.address).toEqual(provider.address);
    expect(deployer.address).toEqual(deployer.address);
}

get fun `test liquidity-locker: lock then unlock after period`() {
    val (lpMinter, locker, deployer, provider) = setupLiquidityLocker();
    val unlockAt = 1700000000 + LL_UNLOCK_DAYS;

    val lockRes = transferTokensTo(
        lpMinter,
        provider,
        locker.address,
        LL_LOCK_AMOUNT,
        makeLockPayload(unlockAt),
    );
    expect(lockRes).toHaveSuccessfulTx<TransferNotificationForRecipient>({ to: locker.address });

    val (nextLockId, totalLocked) = locker.getLockerData();
    expect(nextLockId).toEqual(1);
    expect(totalLocked).toEqual(LL_LOCK_AMOUNT);

    testing.setNow(unlockAt + 1);
    val unlockRes = locker.sendUnlockLiquidity(provider.address, 0, 0, { bounce: false, value: ton("0.2") });
    expect(unlockRes).toHaveSuccessfulTx<UnlockLiquidity>({ from: provider.address, to: locker.address });

    val (_, totalAfter) = locker.getLockerData();
    expect(totalAfter).toEqual(0);
}

get fun `test liquidity-locker: early unlock rejected`() {
    val (lpMinter, locker, deployer, provider) = setupLiquidityLocker();
    val unlockAt = 1700000000 + LL_UNLOCK_DAYS;
    transferTokensTo(lpMinter, provider, locker.address, LL_LOCK_AMOUNT, makeLockPayload(unlockAt));

    val early = locker.sendUnlockLiquidity(provider.address, 0, 0, { bounce: false, value: ton("0.2") });
    expect(early).toHaveFailedTx<UnlockLiquidity>({
        from: provider.address,
        to: locker.address,
        exitCode: Errors.NothingToClaim,
    });
}
