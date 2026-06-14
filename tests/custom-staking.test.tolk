import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"

import "@contracts/CustomStakingParams"
import "@contracts/errors"
import "@contracts/messages"
import "@contracts/storage"
import "@wrappers/JettonMinter.gen"
import "@wrappers/CustomStakingParams.gen"
import "@wrappers/utils"

import "test-utils"

const CS_UNIT = 1000000000
const CS_BASE_APR: uint32 = 500   // 5%
const CS_MIN_LOCK_SEC: uint32 = 2592000  // 30 days
const CS_REWARD_FUND = 100000 * CS_UNIT
const CS_STAKE_AMOUNT = 10000 * CS_UNIT

const CS_DEPOSIT_OP: uint32 = 0x457A0011
const CS_REWARD_POOL_OP: uint32 = 0x457A0016

fun makeCustomStakeDepositPayload(lockSec: uint32): slice {
    return beginCell().storeUint(CS_DEPOSIT_OP, 32).storeUint(lockSec, 32).endCell().beginParse();
}

fun makeCustomRewardPoolPayload(): slice {
    return beginCell().storeUint(CS_REWARD_POOL_OP, 32).endCell().beginParse();
}

fun emptyBonusTier(): BonusTier {
    return BonusTier { minAmount: 0, bonusBps: 0 };
}

fun setupCustomStaking(
    baseAprBps: uint32,
    tierCount: uint8,
    tier0: BonusTier,
    tier1: BonusTier,
): (JettonMinter, CustomStakingParams, Treasury, Treasury) {
    val deployer = testing.treasury("cs-deployer");
    val user = testing.treasury("cs-user");
    testing.setNow(1700000000);

    val minter = JettonMinter.fromStorage({
        totalSupply: 0,
        adminAddress: deployer.address,
        nextAdminAddress: null,
        metadata: buildTestMetadata("cs-plx-test"),
    });
    expect(minter.sendDeploy(deployer.address, { value: ton("10") })).toHaveSuccessfulDeploy({
        to: minter.address,
    });

    val config: CustomStakingConfig = {
        admin: deployer.address,
        minterAddress: minter.address,
        baseAprBps,
        minLockSec: CS_MIN_LOCK_SEC,
        tierCount,
        tier0,
        tier1,
        tier2: emptyBonusTier(),
        tier3: emptyBonusTier(),
        tier4: emptyBonusTier(),
    };

    val staking = CustomStakingParams.fromStorage({
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

    // Mint tokens for tests
    expect(
        minter.sendMint(deployer.address, deployer.address, CS_REWARD_FUND * 2, ton("0.05"), ton("0.5")),
    ).toHaveSuccessfulTx<MintNewJettons>({ from: deployer.address, to: minter.address });

    expect(
        minter.sendMint(deployer.address, user.address, CS_STAKE_AMOUNT * 100, ton("0.05"), ton("0.5")),
    ).toHaveSuccessfulTx<MintNewJettons>({ from: deployer.address, to: minter.address });

    return (minter, staking, deployer, user);
}

fun fundCustomRewardPool(
    minter: JettonMinter,
    staking: CustomStakingParams,
    from: Treasury,
    amount: coins,
): SendResultList {
    val wallet = userWallet(minter, from.address);
    val body = AskToTransfer {
        queryId: 0,
        jettonAmount: amount,
        transferRecipient: staking.address,
        sendExcessesTo: from.address,
        customPayload: null,
        forwardTonAmount: 100000000,
        forwardPayload: makeCustomRewardPoolPayload(),
    };
    return sendRawTransferPayload(from.address, wallet.address, body.toCell(), 400000000);
}

fun userStakesCustom(
    minter: JettonMinter,
    staking: CustomStakingParams,
    user: Treasury,
    amount: coins,
    lockSec: uint32,
): SendResultList {
    val wallet = userWallet(minter, user.address);
    val body = AskToTransfer {
        queryId: 0,
        jettonAmount: amount,
        transferRecipient: staking.address,
        sendExcessesTo: user.address,
        customPayload: null,
        forwardTonAmount: 100000000,
        forwardPayload: makeCustomStakeDepositPayload(lockSec),
    };
    return sendRawTransferPayload(user.address, wallet.address, body.toCell(), 400000000);
}

get fun `test custom-staking: deposit increases totalStaked`() {
    val t0: BonusTier = { minAmount: 0, bonusBps: 0 };
    val (minter, staking, deployer, user) = setupCustomStaking(CS_BASE_APR, 0, t0, t0);

    fundCustomRewardPool(minter, staking, deployer, CS_REWARD_FUND);
    val res = userStakesCustom(minter, staking, user, CS_STAKE_AMOUNT, CS_MIN_LOCK_SEC);
    expect(res).toHaveSuccessfulTx<TransferNotificationForRecipient>({ to: staking.address });

    val (totalStaked, _, _, _, nextId) = staking.getStakingData();
    expect(totalStaked).toEqual(CS_STAKE_AMOUNT);
    expect(nextId).toEqual(1);
}

get fun `test custom-staking: effective APR with no tiers equals base APR`() {
    val t0: BonusTier = { minAmount: 0, bonusBps: 0 };
    val (_, staking, _, _) = setupCustomStaking(CS_BASE_APR, 0, t0, t0);

    val effectiveApr = staking.getEffectiveApr(CS_STAKE_AMOUNT);
    expect(effectiveApr).toEqual(CS_BASE_APR);
}

get fun `test custom-staking: effective APR with tier bonus applies for qualifying stake`() {
    val tier0: BonusTier = { minAmount: CS_STAKE_AMOUNT, bonusBps: 300 };  // +3% for staking >= CS_STAKE_AMOUNT
    val tier1: BonusTier = { minAmount: 0, bonusBps: 0 };
    val (_, staking, _, _) = setupCustomStaking(CS_BASE_APR, 1, tier0, tier1);

    val effectiveForLarge = staking.getEffectiveApr(CS_STAKE_AMOUNT);
    expect(effectiveForLarge).toEqual(CS_BASE_APR + 300);

    val effectiveForSmall = staking.getEffectiveApr(CS_STAKE_AMOUNT - 1);
    expect(effectiveForSmall).toEqual(CS_BASE_APR);
}

get fun `test custom-staking: higher tier bonus overrides lower for large stake`() {
    val tier0: BonusTier = { minAmount: 1000 * CS_UNIT, bonusBps: 100 };   // +1% for >= 1000
    val tier1: BonusTier = { minAmount: 50000 * CS_UNIT, bonusBps: 500 };  // +5% for >= 50000
    val (_, staking, _, _) = setupCustomStaking(CS_BASE_APR, 2, tier0, tier1);

    val smallStake = 5000 * CS_UNIT;
    val largeStake = 50000 * CS_UNIT;

    // Small stake gets tier0 bonus (100 bps)
    expect(staking.getEffectiveApr(smallStake)).toEqual(CS_BASE_APR + 100);

    // Large stake gets tier1 bonus (500 bps, higher)
    expect(staking.getEffectiveApr(largeStake)).toEqual(CS_BASE_APR + 500);
}

get fun `test custom-staking: early unstake rejected`() {
    val t0: BonusTier = { minAmount: 0, bonusBps: 0 };
    val (minter, staking, deployer, user) = setupCustomStaking(CS_BASE_APR, 0, t0, t0);

    fundCustomRewardPool(minter, staking, deployer, CS_REWARD_FUND);
    userStakesCustom(minter, staking, user, CS_STAKE_AMOUNT, CS_MIN_LOCK_SEC);

    val res = staking.sendCustomUnstake(user.address, 0, 0, { bounce: false, value: ton("0.2") });
    expect(res).toHaveFailedTx<CustomUnstake>({
        from: user.address,
        to: staking.address,
        exitCode: Errors.NothingToClaim,
    });
}

get fun `test custom-staking: unstake after lock period succeeds`() {
    val t0: BonusTier = { minAmount: 0, bonusBps: 0 };
    val (minter, staking, deployer, user) = setupCustomStaking(CS_BASE_APR, 0, t0, t0);

    fundCustomRewardPool(minter, staking, deployer, CS_REWARD_FUND);
    userStakesCustom(minter, staking, user, CS_STAKE_AMOUNT, CS_MIN_LOCK_SEC);

    testing.setNow(1700000000 + CS_MIN_LOCK_SEC + 1);
    val res = staking.sendCustomUnstake(user.address, 0, 0, { bounce: false, value: ton("0.2") });
    expect(res).toHaveSuccessfulTx<CustomUnstake>({ from: user.address, to: staking.address });

    val stake = staking.getCustomStake(0)!.load();
    expect(stake.active).toEqual(false);
}

get fun `test custom-staking: admin can update bonus tiers`() {
    val t0: BonusTier = { minAmount: 0, bonusBps: 0 };
    val (_, staking, deployer, _) = setupCustomStaking(CS_BASE_APR, 0, t0, t0);

    val newTier0: BonusTier = { minAmount: 1000 * CS_UNIT, bonusBps: 250 };
    val res = staking.sendUpdateBonusTiers(
        deployer.address, 0,
        600, 1,
        newTier0, emptyBonusTier(), emptyBonusTier(), emptyBonusTier(), emptyBonusTier(),
        { bounce: false, value: ton("0.1") },
    );
    expect(res).toHaveSuccessfulTx<UpdateBonusTiers>({ from: deployer.address, to: staking.address });

    val effectiveApr = staking.getEffectiveApr(1000 * CS_UNIT);
    expect(effectiveApr).toEqual(600 + 250);
}

get fun `test custom-staking: non-admin cannot update bonus tiers`() {
    val t0: BonusTier = { minAmount: 0, bonusBps: 0 };
    val (_, staking, _, user) = setupCustomStaking(CS_BASE_APR, 0, t0, t0);

    val res = staking.sendUpdateBonusTiers(
        user.address, 0, 999, 0, t0, t0, t0, t0, t0, { bounce: false, value: ton("0.1") },
    );
    expect(res).toHaveFailedTx<UpdateBonusTiers>({
        from: user.address,
        to: staking.address,
        exitCode: Errors.NotOwner,
    });
}

get fun `test custom-staking: reward pool funded via transfer notification`() {
    val t0: BonusTier = { minAmount: 0, bonusBps: 0 };
    val (minter, staking, deployer, _) = setupCustomStaking(CS_BASE_APR, 0, t0, t0);

    val res = fundCustomRewardPool(minter, staking, deployer, CS_REWARD_FUND);
    expect(res).toHaveSuccessfulTx<TransferNotificationForRecipient>({ to: staking.address });

    val (_, _, _, rewardPool, _) = staking.getStakingData();
    expect(rewardPool).toEqual(CS_REWARD_FUND);
}
