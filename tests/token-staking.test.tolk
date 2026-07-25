import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"

import "@contracts/TokenStaking"
import "@contracts/errors"
import "@contracts/messages"
import "@contracts/storage"
import "@wrappers/JettonMinter.gen"
import "@wrappers/TokenStaking.gen"
import "@wrappers/utils"

import "test-utils"

const TS_UNIT = 1000000000
const TS_APR_BPS: uint32 = 500   // 5%
const TS_MIN_LOCK_SEC: uint32 = 2592000  // 30 days
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

fun setupTokenStaking(
    aprBps: uint32,
): (JettonMinter, TokenStaking, Treasury, Treasury) {
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

    // Mint tokens to user + fund reward pool
    mintTokensTo(deployer, minter, user, 200000 * TS_UNIT);
    mintTokensTo(deployer, minter, staking, TS_REWARD_FUND, makeRewardPoolPayload());

    return (minter, staking, deployer, user);
}

fun stakeTokens(
    minter: JettonMinter,
    staking: TokenStaking,
    user: Treasury,
    amount: coins,
    lockSec: uint32,
): SendResultList {
    return transferTokensTo(minter, user, staking, amount, makeStakeDepositPayload(lockSec));
}

// ---- tests ----

fun test_deploy_staking(): void {
    val (minter, staking, deployer, user) = setupTokenStaking(TS_APR_BPS);

    val data = staking.getStakingData();
    expect(data._1).toBe(0);           // totalStaked
    expect(data._3).toBe(1700000000);  // lastUpdateTime
    expect(data._4).toBe(TS_REWARD_FUND); // rewardPool
    expect(data._5).toBe(0);           // nextStakeId
}

fun test_stake_tokens(): void {
    val (minter, staking, deployer, user) = setupTokenStaking(TS_APR_BPS);

    val result = stakeTokens(minter, staking, user, TS_STAKE_AMOUNT, TS_MIN_LOCK_SEC);
    expect(result).toHaveTransactionTo(staking.address);

    val data = staking.getStakingData();
    expect(data._1).toBe(TS_STAKE_AMOUNT); // totalStaked
    expect(data._5).toBe(1);               // nextStakeId = 1

    val stake = staking.getStake(0);
    expect(stake).notToBeNull();
    val s = stake!!.load();
    expect(s.owner).toBe(user.address);
    expect(s.stakedAmount).toBe(TS_STAKE_AMOUNT);
    expect(s.active).toBe(true);
}

fun test_stake_below_min_lock(): void {
    val (minter, staking, deployer, user) = setupTokenStaking(TS_APR_BPS);

    val result = stakeTokens(minter, staking, user, TS_STAKE_AMOUNT, 100); // below minLockSec
    expect(result).toHaveExitCode(Errors.InvalidOp);
}

fun test_unstake_after_lock(): void {
    val (minter, staking, deployer, user) = setupTokenStaking(TS_APR_BPS);

    expect(stakeTokens(minter, staking, user, TS_STAKE_AMOUNT, TS_MIN_LOCK_SEC)).toHaveTransactionTo(staking.address);

    // Fast-forward past lock period
    testing.setNow(1700000000 + TS_MIN_LOCK_SEC + 1);

    val result = staking.sendUnstakeToken(user.address, 0, 0);
    expect(result).toHaveTransactionTo(staking.address);

    val data = staking.getStakingData();
    expect(data._1).toBe(0); // totalStaked = 0

    val stake = staking.getStake(0);
    expect(stake).notToBeNull();
    val s = stake!!.load();
    expect(s.active).toBe(false);
}

fun test_unstake_before_lock_fails(): void {
    val (minter, staking, deployer, user) = setupTokenStaking(TS_APR_BPS);

    expect(stakeTokens(minter, staking, user, TS_STAKE_AMOUNT, TS_MIN_LOCK_SEC)).toHaveTransactionTo(staking.address);

    val result = staking.sendUnstakeToken(user.address, 0, 0);
    expect(result).toHaveExitCode(Errors.NothingToClaim);
}

fun test_only_owner_can_unstake(): void {
    val (minter, staking, deployer, user) = setupTokenStaking(TS_APR_BPS);

    expect(stakeTokens(minter, staking, user, TS_STAKE_AMOUNT, TS_MIN_LOCK_SEC)).toHaveTransactionTo(staking.address);
    testing.setNow(1700000000 + TS_MIN_LOCK_SEC + 1);

    val result = staking.sendUnstakeToken(deployer.address, 0, 0);
    expect(result).toHaveExitCode(Errors.NotOwner);
}

fun test_claim_rewards(): void {
    val (minter, staking, deployer, user) = setupTokenStaking(TS_APR_BPS);

    expect(stakeTokens(minter, staking, user, TS_STAKE_AMOUNT, TS_MIN_LOCK_SEC)).toHaveTransactionTo(staking.address);

    // Fast-forward 90 days to accrue rewards
    testing.setNow(1700000000 + 7776000);

    val dataBefore = staking.getStakingData();

    val result = staking.sendClaimRewards(user.address, 0, 0);
    expect(result).toHaveTransactionTo(staking.address);

    // Reward pool should decrease
    val dataAfter = staking.getStakingData();
    expect(dataAfter._4).toBeLessThan(dataBefore._4);
}

fun test_admin_update_apr(): void {
    val (minter, staking, deployer, user) = setupTokenStaking(TS_APR_BPS);

    val result = staking.sendUpdateApr(deployer.address, 0, 1000); // 10%
    expect(result).toHaveTransactionTo(staking.address);

    val newApr = staking.getAprBps();
    expect(newApr).toBe(1000 as uint32);
}

fun test_non_admin_cannot_update_apr(): void {
    val (minter, staking, deployer, user) = setupTokenStaking(TS_APR_BPS);

    val result = staking.sendUpdateApr(user.address, 0, 1000);
    expect(result).toHaveExitCode(Errors.NotOwner);
}

fun test_zero_stake_rejected(): void {
    val (minter, staking, deployer, user) = setupTokenStaking(TS_APR_BPS);

    val result = stakeTokens(minter, staking, user, 0, TS_MIN_LOCK_SEC);
    expect(result).toHaveTransactionTo(staking.address);

    // zero amount is accepted but ignored — no stake created
    val data = staking.getStakingData();
    expect(data._5).toBe(0);
}
