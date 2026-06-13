import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"

import "@contracts/PlxLockVault"
import "@contracts/errors"
import "@contracts/messages"
import "@contracts/storage"
import "@wrappers/JettonMinter.gen"
import "@wrappers/PlxLockVault.gen"
import "@wrappers/utils"

import "test-utils"

const ONE_MONTH_SEC = 2592000
const SECONDS_PER_YEAR = 31536000
const THREE_MONTH_SEC = 7776000
const SIX_MONTH_SEC = 15552000
const PLX_UNIT = 1000000000
const MIN_LOCK = 25000 * PLX_UNIT
const SOVEREIGN_MIN = 1000000 * PLX_UNIT
const REWARD_FUND = 500000 * PLX_UNIT

const TEST_LOCK_FORWARD_DEPOSIT_OP: uint32 = 0x4f434b01
const TEST_LOCK_FORWARD_REWARD_POOL_OP: uint32 = 0x4f434b06

fun makeLockDepositPayload(tierIndex: int, sovereign: bool = false): slice {
    return beginCell()
        .storeUint(TEST_LOCK_FORWARD_DEPOSIT_OP, 32)
        .storeUint(tierIndex, 8)
        .storeUint(sovereign ? 1 : 0, 1)
        .endCell()
        .beginParse();
}

fun makeRewardPoolPayload(): slice {
    return beginCell().storeUint(TEST_LOCK_FORWARD_REWARD_POOL_OP, 32).endCell().beginParse();
}

fun setupLockVault(): (JettonMinter, PlxLockVault, Treasury, Treasury) {
    val deployer = testing.treasury("lock-deployer");
    val user = testing.treasury("lock-user");
    testing.setNow(1700000000);

    val minter = JettonMinter.fromStorage({
        totalSupply: 0,
        adminAddress: deployer.address,
        nextAdminAddress: null,
        metadata: buildTestMetadata("plx-lock-test"),
    });
    expect(minter.sendDeploy(deployer.address, { value: ton("10") })).toHaveSuccessfulDeploy({
        to: minter.address,
    });

    val config: LockVaultConfig = {
        admin: deployer.address,
        minterAddress: minter.address,
        tierCount: 4,
        tier0: LockTier { durationSec: 604800, bonusBps: 50 },
        tier1: LockTier { durationSec: ONE_MONTH_SEC, bonusBps: 200 },
        tier2: LockTier { durationSec: THREE_MONTH_SEC, bonusBps: 800 },
        tier3: LockTier { durationSec: SIX_MONTH_SEC, bonusBps: 2000 },
        eventEndAt: 0,
        minLockAmount: MIN_LOCK,
        sovereignMinAmount: SOVEREIGN_MIN,
    };

    val vault = PlxLockVault.fromStorage({
        config: config.toCell(),
        nextPositionId: 0,
        totalLocked: 0,
        rewardPool: 0,
        positions: [],
    });
    expect(vault.sendDeploy(deployer.address, { value: ton("5") })).toHaveSuccessfulDeploy({
        to: vault.address,
    });

    expect(
        minter.sendMint(deployer.address, deployer.address, REWARD_FUND * 2, ton("0.05"), ton("0.5")),
    ).toHaveSuccessfulTx<MintNewJettons>({ from: deployer.address, to: minter.address });

    expect(
        minter.sendMint(deployer.address, user.address, MIN_LOCK * 100, ton("0.05"), ton("0.5")),
    ).toHaveSuccessfulTx<MintNewJettons>({ from: deployer.address, to: minter.address });

    return (minter, vault, deployer, user);
}

fun userLocksToVault(
    minter: JettonMinter,
    vault: PlxLockVault,
    user: Treasury,
    amount: coins,
    tierIndex: int,
    sovereign: bool = false,
): SendResultList {
    val userWallet = userWallet(minter, user.address);
    val body = AskToTransfer {
        queryId: 0,
        jettonAmount: amount,
        transferRecipient: vault.address,
        sendExcessesTo: user.address,
        customPayload: null,
        forwardTonAmount: 100000000,
        forwardPayload: makeLockDepositPayload(tierIndex, sovereign),
    };
    return sendRawTransferPayload(user.address, userWallet.address, body.toCell(), 400000000);
}

fun fundVaultRewardPool(
    minter: JettonMinter,
    vault: PlxLockVault,
    from: Treasury,
    amount: coins,
): SendResultList {
    val wallet = userWallet(minter, from.address);
    val body = AskToTransfer {
        queryId: 0,
        jettonAmount: amount,
        transferRecipient: vault.address,
        sendExcessesTo: from.address,
        customPayload: null,
        forwardTonAmount: 100000000,
        forwardPayload: makeRewardPoolPayload(),
    };
    return sendRawTransferPayload(from.address, wallet.address, body.toCell(), 400000000);
}

get fun `test lock vault: deploy and lock creates position`() {
    val (minter, vault, deployer, user) = setupLockVault();
    val fundRes = fundVaultRewardPool(minter, vault, deployer, REWARD_FUND);
    expect(fundRes).toHaveSuccessfulTx<TransferNotificationForRecipient>({ to: vault.address });

    val res = userLocksToVault(minter, vault, user, MIN_LOCK, 1);
    expect(res).toHaveSuccessfulTx<TransferNotificationForRecipient>({ to: vault.address });

    val (nextId, totalLocked, rewardPool, _) = vault.getLockVaultData();
    expect(nextId).toEqual(1);
    expect(totalLocked).toEqual(MIN_LOCK);
    expect(rewardPool).toEqual(REWARD_FUND);
}

get fun `test lock vault: layered positions have independent unlock`() {
    val (minter, vault, deployer, user) = setupLockVault();
    val fundRes = fundVaultRewardPool(minter, vault, deployer, REWARD_FUND);
    expect(fundRes).toHaveSuccessfulTx<TransferNotificationForRecipient>({ to: vault.address });

    userLocksToVault(minter, vault, user, MIN_LOCK, 1);
    testing.setNow(1700000000 + ONE_MONTH_SEC / 2);
    userLocksToVault(minter, vault, user, MIN_LOCK * 2, 2);

    val (nextId, totalLocked, _, _) = vault.getLockVaultData();
    expect(nextId).toEqual(2);
    expect(totalLocked).toEqual(MIN_LOCK * 3);

    val pos0 = vault.getPosition(0)!.load();
    val pos1 = vault.getPosition(1)!.load();
    expect(pos0.unlockAt).toEqual(1700000000 + ONE_MONTH_SEC);
    expect(pos1.unlockAt).toEqual(1700000000 + ONE_MONTH_SEC / 2 + THREE_MONTH_SEC);
}

get fun `test lock vault: early claim rejected`() {
    val (minter, vault, deployer, user) = setupLockVault();
    val fundRes = fundVaultRewardPool(minter, vault, deployer, REWARD_FUND);
    expect(fundRes).toHaveSuccessfulTx<TransferNotificationForRecipient>({ to: vault.address });
    userLocksToVault(minter, vault, user, MIN_LOCK, 1);

    val res = vault.sendReleaseLock(user.address, 0, 0, { bounce: false, value: ton("0.2") });
    expect(res).toHaveFailedTx<ReleaseLock>({ from: user.address, to: vault.address, exitCode: 100 });
}

get fun `test lock vault: maturity claim returns principal and bonus`() {
    val (minter, vault, deployer, user) = setupLockVault();
    val fundRes = fundVaultRewardPool(minter, vault, deployer, REWARD_FUND);
    expect(fundRes).toHaveSuccessfulTx<TransferNotificationForRecipient>({ to: vault.address });
    userLocksToVault(minter, vault, user, MIN_LOCK, 1);

    testing.setNow(1700000000 + ONE_MONTH_SEC + 1);
    val res = vault.sendReleaseLock(user.address, 0, 0, { bounce: false, value: ton("0.2") });
    expect(res).toHaveSuccessfulTx<ReleaseLock>({ from: user.address, to: vault.address });

    val pos = vault.getPosition(0)!.load();
    expect(pos.released).toEqual(true);
}

get fun `test lock vault: event end before maturity forfeits bonus`() {
    val (minter, vault, deployer, user) = setupLockVault();
    val fundRes = fundVaultRewardPool(minter, vault, deployer, REWARD_FUND);
    expect(fundRes).toHaveSuccessfulTx<TransferNotificationForRecipient>({ to: vault.address });
    userLocksToVault(minter, vault, user, MIN_LOCK, 2);

    vault.sendSetEventEnd(deployer.address, 0, 1700000000 + ONE_MONTH_SEC, {
        bounce: false,
        value: ton("0.1"),
    });

    testing.setNow(1700000000 + THREE_MONTH_SEC + 1);
    val (_, _, beforePool, _) = vault.getLockVaultData();
    val res = vault.sendReleaseLock(user.address, 0, 0, { bounce: false, value: ton("0.2") });
    expect(res).toHaveSuccessfulTx<ReleaseLock>({ from: user.address, to: vault.address });
    val (_, _, afterPool, _) = vault.getLockVaultData();
    expect(afterPool).toEqual(beforePool);
}

get fun `test lock vault: unauthorized claim rejected`() {
    val (minter, vault, deployer, user) = setupLockVault();
    val fundRes = fundVaultRewardPool(minter, vault, deployer, REWARD_FUND);
    expect(fundRes).toHaveSuccessfulTx<TransferNotificationForRecipient>({ to: vault.address });
    userLocksToVault(minter, vault, user, MIN_LOCK, 1);
    testing.setNow(1700000000 + ONE_MONTH_SEC + 1);

    val res = vault.sendReleaseLock(deployer.address, 0, 0, { bounce: false, value: ton("0.2") });
    expect(res).toHaveFailedTx<ReleaseLock>({ from: deployer.address, to: vault.address, exitCode: 73 });
}

