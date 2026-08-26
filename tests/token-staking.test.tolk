import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"

import "@contracts/TokenStaking"
import "@contracts/errors"
import "@contracts/messages"
import "@wrappers/JettonMinter.gen"
import "@wrappers/TokenStaking.gen"
import "@wrappers/utils"

import "test-utils"

const TS_UNIT = 1000000000
const TS_APR_BPS: uint32 = 500
const TS_MIN_LOCK_SEC: uint32 = 2592000
const TS_REWARD_FUND = 100000 * TS_UNIT
const TS_STAKE_AMOUNT = 10000 * TS_UNIT
const TS_DEPOSIT_OP: uint32 = 0x54414b01
const TS_REWARD_POOL_OP: uint32 = 0x54414b06

fun makeStakeDepositPayload(lockSec: uint32): slice {
    return beginCell().storeUint(TS_DEPOSIT_OP, 32).storeUint(lockSec, 32).endCell().beginParse();
}

fun makeRewardPoolPayload(): slice {
    return beginCell().storeUint(TS_REWARD_POOL_OP, 32).endCell().beginParse();
}

fun setupTokenStaking(aprBps: uint32): (JettonMinter, TokenStaking, Treasury, Treasury) {
    val deployer = testing.treasury("ts-deployer");
    val user = testing.treasury("ts-user");
    testing.setNow(1700000000);

    val minter = JettonMinter.fromStorage({
        totalSupply: 0,
        adminAddress: deployer.address,
        nextAdminAddress: null,
        metadata: buildTestMetadata("ts-test-token"),
    });
    expect(minter.sendDeploy(deployer.address, { value: ton("10") })).toHaveSuccessfulDeploy({
        to: minter.address,
    });

    val config: StakingConfig = {
        admin: deployer.address,
        minterAddress: minter.address,
        aprBps,
        minLockSec: TS_MIN_LOCK_SEC,
    };

    val staking = TokenStaking.fromStorage({
        config: config.toCell(),
        totalStaked: 0,
        rewardPerTokenStored: 0,
        lastUpdateTime: 1700000000,
        rewardPool: 0,
        nextStakeId: 0,
        stakes: [],
    });
    expect(staking.sendDeploy(deployer.address, { value: ton("5") })).toHaveSuccessfulDeploy({
        to: staking.address,
    });

    mintTokensTo(deployer, minter, user.address, 200000 * TS_UNIT);
    mintTokensTo(deployer, minter, deployer.address, TS_REWARD_FUND);
    expect(
        transferTokensTo(minter, deployer, staking.address, TS_REWARD_FUND, makeRewardPoolPayload()),
    ).toHaveSuccessfulTx<TransferNotificationForRecipient>({ to: staking.address });

    return (minter, staking, deployer, user);
}

get fun `test token-staking: deploy and fund reward pool`() {
    val (minter, staking, deployer, user) = setupTokenStaking(TS_APR_BPS);
    val (totalStaked, _, lastUpdateTime, rewardPool, nextStakeId) = staking.getStakingData();
    expect(totalStaked).toEqual(0);
    expect(lastUpdateTime).toEqual(1700000000);
    expect(rewardPool).toEqual(TS_REWARD_FUND);
    expect(nextStakeId).toEqual(0);
    expect(minter.address).toEqual(minter.address);
    expect(user.address).toEqual(user.address);
    expect(deployer.address).toEqual(deployer.address);
}

get fun `test token-staking: stake then unstake after lock`() {
    val (minter, staking, deployer, user) = setupTokenStaking(TS_APR_BPS);

    val stakeRes = transferTokensTo(
        minter,
        user,
        staking.address,
        TS_STAKE_AMOUNT,
        makeStakeDepositPayload(TS_MIN_LOCK_SEC),
    );
    expect(stakeRes).toHaveSuccessfulTx<TransferNotificationForRecipient>({ to: staking.address });

    val (totalStaked, _, _, _, nextStakeId) = staking.getStakingData();
    expect(totalStaked).toEqual(TS_STAKE_AMOUNT);
    expect(nextStakeId).toEqual(1);

    testing.setNow(1700000000 + TS_MIN_LOCK_SEC + 1);
    val unstake = staking.sendUnstakeToken(user.address, 0, 0, { bounce: false, value: ton("0.2") });
    expect(unstake).toHaveSuccessfulTx<UnstakeToken>({ from: user.address, to: staking.address });

    val (totalAfter, _, _, _, _) = staking.getStakingData();
    expect(totalAfter).toEqual(0);
}

get fun `test token-staking: early unstake rejected`() {
    val (minter, staking, deployer, user) = setupTokenStaking(TS_APR_BPS);
    transferTokensTo(minter, user, staking.address, TS_STAKE_AMOUNT, makeStakeDepositPayload(TS_MIN_LOCK_SEC));

    val early = staking.sendUnstakeToken(user.address, 0, 0, { bounce: false, value: ton("0.2") });
    expect(early).toHaveFailedTx<UnstakeToken>({
        from: user.address,
        to: staking.address,
        exitCode: Errors.NothingToClaim,
    });
}
