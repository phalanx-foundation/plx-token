import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"

import "@contracts/PlxStaking"
import "@contracts/errors"
import "@contracts/messages"
import "@contracts/storage"
import "@wrappers/JettonMinter.gen"
import "@wrappers/PlxStaking.gen"
import "@wrappers/utils"

import "test-utils"

const ONE_MONTH_SEC = 2592000
const SECONDS_PER_YEAR = 31536000
const PLX_UNIT = 1000000000
const MIN_LOCK = 25000 * PLX_UNIT
const REWARD_FUND = 500000 * PLX_UNIT

fun makeStakeRewardPoolPayload(): slice {
    return beginCell().storeUint(0x5354414b06, 32).endCell().beginParse();
}

fun setupStaking(): (JettonMinter, PlxStaking, Treasury, Treasury) {
    val deployer = testing.treasury("stake-deployer");
    val user = testing.treasury("stake-user");
    testing.setNow(1700000000);

    val minter = JettonMinter.fromStorage({
        totalSupply: 0,
        adminAddress: deployer.address,
        nextAdminAddress: null,
        metadata: buildTestMetadata("plx-stake-test"),
    });
    expect(minter.sendDeploy(deployer.address, { value: ton("10") })).toHaveSuccessfulDeploy({
        to: minter.address,
    });

    val config: StakingConfig = {
        admin: deployer.address,
        minterAddress: minter.address,
        aprBps: 800,
        minLockSec: ONE_MONTH_SEC,
    };

    val staking = PlxStaking.fromStorage({
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

    expect(
        minter.sendMint(deployer.address, user.address, MIN_LOCK * 100, ton("0.05"), ton("0.5")),
    ).toHaveSuccessfulTx<MintNewJettons>({ from: deployer.address, to: minter.address });

    return (minter, staking, deployer, user);
}

fun makeStakeDepositPayload(lockSec: int): slice {
    return beginCell().storeUint(0x5354414b01, 32).storeUint(lockSec, 32).endCell().beginParse();
}

fun fundStakingRewardPool(
    minter: JettonMinter,
    staking: PlxStaking,
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
        forwardPayload: makeStakeRewardPoolPayload(),
    };
    return sendRawTransferPayload(from.address, wallet.address, body.toCell(), 400000000);
}

fun userStakesToContract(
    minter: JettonMinter,
    staking: PlxStaking,
    user: Treasury,
    amount: coins,
    lockSec: int,
): SendResultList {
    val userWallet = userWallet(minter, user.address);
    val body = AskToTransfer {
        queryId: 0,
        jettonAmount: amount,
        transferRecipient: staking.address,
        sendExcessesTo: user.address,
        customPayload: null,
        forwardTonAmount: 100000000,
        forwardPayload: makeStakeDepositPayload(lockSec),
    };
    return sendRawTransferPayload(user.address, userWallet.address, body.toCell(), 400000000);
}

get fun `test staking: deposit increases totalStaked`() {
    val (minter, staking, deployer, user) = setupStaking();
    fundStakingRewardPool(minter, staking, deployer, REWARD_FUND);

    val res = userStakesToContract(minter, staking, user, MIN_LOCK, ONE_MONTH_SEC);
    expect(res).toHaveSuccessfulTx<TransferNotificationForRecipient>({ to: staking.address });

    val (totalStaked, _, _, _, nextId) = staking.getStakingData();
    expect(totalStaked).toEqual(MIN_LOCK);
    expect(nextId).toEqual(1);
}

get fun `test staking: early unstake rejected`() {
    val (minter, staking, deployer, user) = setupStaking();
    userStakesToContract(minter, staking, user, MIN_LOCK, ONE_MONTH_SEC);

    val res = staking.sendUnstakePlx(user.address, 0, 0, { bounce: false, value: ton("0.2") });
    expect(res).toHaveFailedTx<UnstakePlx>({ from: user.address, to: staking.address });
}

get fun `test staking: unstake after lock period`() {
    val (minter, staking, deployer, user) = setupStaking();
    fundStakingRewardPool(minter, staking, deployer, REWARD_FUND);
    userStakesToContract(minter, staking, user, MIN_LOCK, ONE_MONTH_SEC);

    testing.setNow(1700000000 + ONE_MONTH_SEC + SECONDS_PER_YEAR / 2);
    val res = staking.sendUnstakePlx(user.address, 0, 0, { bounce: false, value: ton("0.2") });
    expect(res).toHaveSuccessfulTx<UnstakePlx>({ from: user.address, to: staking.address });

    val stake = staking.getStake(0)!.load();
    expect(stake.active).toEqual(false);
}
