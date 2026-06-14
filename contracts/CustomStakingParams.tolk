import "@gen/JettonWallet.code"
import "errors"
import "jetton-utils"
import "messages"

contract CustomStakingParams {
    author: "Phalanx Foundation"
    version: "1.0.0"
    description: "Parameterized staking with up to 5 bonus tiers. Effective APR = baseAprBps + max matching bonus tier. Same stake/unstake/claim mechanics as PlxStaking."
    storage: CustomStakingStorage
    incomingMessages: AllowedMessageToCustomStaking
}

@overflow1023_policy("suppress")
struct BonusTier {
    minAmount: coins
    bonusBps: uint32
}

/// Config stores up to 5 bonus tiers. tierCount indicates how many are active.
/// Bonus tiers are evaluated independently; the highest matching bonus is used.
@overflow1023_policy("suppress")
struct CustomStakingConfig {
    admin: address
    minterAddress: address
    baseAprBps: uint32
    minLockSec: uint32
    tierCount: uint8
    tier0: BonusTier
    tier1: BonusTier
    tier2: BonusTier
    tier3: BonusTier
    tier4: BonusTier
}

@overflow1023_policy("suppress")
struct CustomStakeRecord {
    owner: address
    stakedAmount: coins
    rewardDebt: uint64
    stakedAt: uint32
    lockUntil: uint32
    active: bool
}

@overflow1023_policy("suppress")
struct CustomStakingStorage {
    config: Cell<CustomStakingConfig>
    totalStaked: coins
    rewardPerTokenStored: uint64
    lastUpdateTime: uint32
    rewardPool: coins
    nextStakeId: uint64
    stakes: map<uint64, Cell<CustomStakeRecord>>
}

struct (0xC57A0002) CustomUnstake {
    queryId: uint64
    stakeId: uint64
}

struct (0xC57A0003) CustomClaimRewards {
    queryId: uint64
    stakeId: uint64
}

struct (0xC57A0004) CustomSetMinLock {
    queryId: uint64
    minLockSec: uint32
}

/// UpdateBonusTiers: admin sets baseAprBps and up to 5 bonus tiers.
struct (0xC57A0001) UpdateBonusTiers {
    queryId: uint64
    baseAprBps: uint32
    tierCount: uint8
    tier0: BonusTier
    tier1: BonusTier
    tier2: BonusTier
    tier3: BonusTier
    tier4: BonusTier
}

type AllowedMessageToCustomStaking =
    | TransferNotificationForRecipient
    | CustomUnstake
    | CustomClaimRewards
    | CustomSetMinLock
    | UpdateBonusTiers
    | TopUpTons

const CUSTOM_STAKE_TRANSFER_TON_VALUE: coins = 80000000
// Forward payload ops MUST start with bit=0 (so checkIsCorrectTlbEither passes)
const CUSTOM_STAKE_DEPOSIT_OP: uint32 = 0x457A0011
const CUSTOM_STAKE_REWARD_POOL_OP: uint32 = 0x457A0016
const CUSTOM_REWARD_SCALE: uint64 = 1000000000000
const CUSTOM_SECONDS_PER_YEAR: int = 31536000

fun CustomStakingStorage.load(): CustomStakingStorage {
    return CustomStakingStorage.fromCell(contract.getData());
}

fun CustomStakingStorage.save(self) {
    contract.setData(self.toCell());
}

fun customStakingOwnJettonWallet(minterAddress: address): address {
    val walletCode = jettonWalletCompiledCode();
    return calcAddressOfJettonWallet(contract.getAddress(), minterAddress, walletCode);
}

fun parseCustomStakePayload(payload: ForwardPayloadRemainder): (uint32, bool) {
    var s = payload;
    if (s.remainingBitsCount() == 0 && s.remainingRefsCount() == 0) {
        return (0, false);
    }
    val op = s.loadUint(32);
    if (op == CUSTOM_STAKE_REWARD_POOL_OP) {
        return (0, true);
    }
    if (op != CUSTOM_STAKE_DEPOSIT_OP) {
        return (0, false);
    }
    val lockSec = s.loadUint(32);
    return (lockSec, false);
}

/// Return the highest bonus tier bps that applies to stakeAmount.
fun getBonusBps(config: CustomStakingConfig, stakeAmount: coins): uint32 {
    var best: uint32 = 0;
    var i: uint8 = 0;
    while (i < config.tierCount) {
        var tier: BonusTier;
        if (i == 0) { tier = config.tier0; }
        else if (i == 1) { tier = config.tier1; }
        else if (i == 2) { tier = config.tier2; }
        else if (i == 3) { tier = config.tier3; }
        else { tier = config.tier4; }

        if (stakeAmount >= tier.minAmount && tier.bonusBps > best) {
            best = tier.bonusBps;
        }
        i += 1;
    }
    return best;
}

fun getEffectiveAprBps(config: CustomStakingConfig, stakeAmount: coins): uint32 {
    return config.baseAprBps + getBonusBps(config, stakeAmount);
}

fun accrueCustomRewards(storage: CustomStakingStorage, config: CustomStakingConfig) {
    val now = blockchain.now();
    if (storage.totalStaked == 0 || now <= storage.lastUpdateTime) {
        storage.lastUpdateTime = now;
        return;
    }
    val elapsed = now - storage.lastUpdateTime;
    // Use baseAprBps for global accrual (bonus is per-stake at claim time)
    val rewardDelta = storage.totalStaked * config.baseAprBps * elapsed /
        (10000 * CUSTOM_SECONDS_PER_YEAR);
    storage.rewardPerTokenStored += rewardDelta * CUSTOM_REWARD_SCALE / storage.totalStaked;
    storage.lastUpdateTime = now;
}

fun customPendingReward(stake: CustomStakeRecord, rewardPerTokenStored: uint64): coins {
    val accumulated = stake.stakedAmount * rewardPerTokenStored / CUSTOM_REWARD_SCALE;
    if (accumulated < stake.rewardDebt) {
        return 0;
    }
    return accumulated - stake.rewardDebt;
}

fun onBouncedMessage(in: InMessageBounced) {
    in.bouncedBody.skipBouncedPrefix();
    val op = in.bouncedBody.loadUint(32);
    if (op != 0x0f8a7ea5) {
        return;
    }
    in.bouncedBody.loadUint(64);
    val refundedAmount = in.bouncedBody.loadCoins();

    var storage = lazy CustomStakingStorage.load();
    if (storage.rewardPool >= refundedAmount) {
        storage.rewardPool -= refundedAmount;
    } else if (storage.totalStaked >= refundedAmount) {
        storage.totalStaked -= refundedAmount;
    }
    storage.save();
}

fun onInternalMessage(in: InMessage) {
    if (in.body.remainingBitsCount() == 0 && in.body.remainingRefsCount() == 0) {
        return;
    }

    val msg = lazy AllowedMessageToCustomStaking.fromSlice(in.body);

    match (msg) {
        TransferNotificationForRecipient => {
            var storage = lazy CustomStakingStorage.load();
            val config = storage.config.load();
            val ourWallet = customStakingOwnJettonWallet(config.minterAddress);
            assert (in.senderAddress == ourWallet) throw Errors.NotValidWallet;

            val incomingAmount = msg.jettonAmount;
            if (incomingAmount == 0) {
                return;
            }

            val (lockSec, isRewardPool) = parseCustomStakePayload(msg.forwardPayload);
            if (isRewardPool) {
                storage.rewardPool += incomingAmount;
                storage.save();
                return;
            }

            assert (lockSec >= config.minLockSec) throw Errors.InvalidOp;

            accrueCustomRewards(storage, config);

            val now = blockchain.now();
            val stakeId = storage.nextStakeId;
            val rewardDebt = incomingAmount * storage.rewardPerTokenStored / CUSTOM_REWARD_SCALE;
            val stake: CustomStakeRecord = {
                owner: msg.transferInitiator!,
                stakedAmount: incomingAmount,
                rewardDebt,
                stakedAt: now,
                lockUntil: now + lockSec,
                active: true,
            };

            storage.stakes.set(stakeId, stake.toCell());
            storage.nextStakeId += 1;
            storage.totalStaked += incomingAmount;
            storage.save();
        }

        CustomUnstake => {
            var storage = lazy CustomStakingStorage.load();
            val config = storage.config.load();
            val stakeEntry = storage.stakes.get(msg.stakeId);
            assert (stakeEntry.isFound) throw Errors.InvalidOp;

            var stake = stakeEntry.loadValue().load();
            assert (in.senderAddress == stake.owner) throw Errors.NotOwner;
            assert (stake.active) throw Errors.InvalidOp;
            assert (blockchain.now() >= stake.lockUntil) throw Errors.NothingToClaim;

            accrueCustomRewards(storage, config);

            // Apply bonus APR on top of base for this stake's pending reward
            val basePending = customPendingReward(stake, storage.rewardPerTokenStored);
            val effectiveApr = getEffectiveAprBps(config, stake.stakedAmount);
            val bonusPending: coins = config.baseAprBps > 0
                ? (basePending * effectiveApr / config.baseAprBps) as coins
                : basePending;
            val rewardPay = min(bonusPending, storage.rewardPool);

            stake.active = false;
            storage.stakes.set(msg.stakeId, stake.toCell());
            storage.totalStaked -= stake.stakedAmount;
            storage.rewardPool -= rewardPay;
            storage.save();

            val totalPayout = stake.stakedAmount + rewardPay;
            val transferMsg = createMessage({
                bounce: BounceMode.Only256BitsOfBody,
                dest: customStakingOwnJettonWallet(config.minterAddress),
                value: CUSTOM_STAKE_TRANSFER_TON_VALUE,
                body: AskToTransfer {
                    queryId: msg.queryId,
                    jettonAmount: totalPayout,
                    transferRecipient: stake.owner,
                    sendExcessesTo: in.senderAddress,
                    customPayload: null,
                    forwardTonAmount: 0,
                    forwardPayload: jettonEmptyForwardPayload(),
                },
            });
            transferMsg.send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_BOUNCE_ON_ACTION_FAIL);
        }

        CustomClaimRewards => {
            var storage = lazy CustomStakingStorage.load();
            val config = storage.config.load();
            val stakeEntry = storage.stakes.get(msg.stakeId);
            assert (stakeEntry.isFound) throw Errors.InvalidOp;

            var stake = stakeEntry.loadValue().load();
            assert (in.senderAddress == stake.owner) throw Errors.NotOwner;
            assert (stake.active) throw Errors.InvalidOp;

            accrueCustomRewards(storage, config);

            val basePending = customPendingReward(stake, storage.rewardPerTokenStored);
            assert (basePending > 0) throw Errors.NothingToClaim;

            // Scale pending reward by effective APR / base APR
            val effectiveApr = getEffectiveAprBps(config, stake.stakedAmount);
            val scaledPending: coins = config.baseAprBps > 0
                ? (basePending * effectiveApr / config.baseAprBps) as coins
                : basePending;
            val rewardPay = min(scaledPending, storage.rewardPool);

            stake.rewardDebt += basePending;
            storage.stakes.set(msg.stakeId, stake.toCell());
            storage.rewardPool -= rewardPay;
            storage.save();

            val transferMsg = createMessage({
                bounce: BounceMode.Only256BitsOfBody,
                dest: customStakingOwnJettonWallet(config.minterAddress),
                value: CUSTOM_STAKE_TRANSFER_TON_VALUE,
                body: AskToTransfer {
                    queryId: msg.queryId,
                    jettonAmount: rewardPay,
                    transferRecipient: stake.owner,
                    sendExcessesTo: in.senderAddress,
                    customPayload: null,
                    forwardTonAmount: 0,
                    forwardPayload: jettonEmptyForwardPayload(),
                },
            });
            transferMsg.send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_BOUNCE_ON_ACTION_FAIL);
        }

        CustomSetMinLock => {
            var storage = lazy CustomStakingStorage.load();
            var config = storage.config.load();
            assert (in.senderAddress == config.admin) throw Errors.NotOwner;
            config.minLockSec = msg.minLockSec;
            storage.config = config.toCell();
            storage.save();
        }

        UpdateBonusTiers => {
            var storage = lazy CustomStakingStorage.load();
            var config = storage.config.load();
            assert (in.senderAddress == config.admin) throw Errors.NotOwner;
            assert (msg.tierCount <= 5) throw Errors.InvalidOp;

            accrueCustomRewards(storage, config);

            config.baseAprBps = msg.baseAprBps;
            config.tierCount = msg.tierCount;
            config.tier0 = msg.tier0;
            config.tier1 = msg.tier1;
            config.tier2 = msg.tier2;
            config.tier3 = msg.tier3;
            config.tier4 = msg.tier4;
            storage.config = config.toCell();
            storage.save();
        }

        TopUpTons => {}
    }
}

get fun get_staking_data(): (coins, uint64, uint32, coins, uint64) {
    val storage = CustomStakingStorage.load();
    return (
        storage.totalStaked,
        storage.rewardPerTokenStored,
        storage.lastUpdateTime,
        storage.rewardPool,
        storage.nextStakeId,
    );
}

get fun get_custom_stake(stakeId: uint64): Cell<CustomStakeRecord>? {
    val storage = CustomStakingStorage.load();
    val entry = storage.stakes.get(stakeId);
    if (!entry.isFound) {
        return null;
    }
    return entry.loadValue();
}

get fun get_config(): Cell<CustomStakingConfig> {
    return CustomStakingStorage.load().config;
}

get fun get_effective_apr(stakeAmount: coins): uint32 {
    val storage = CustomStakingStorage.load();
    val config = storage.config.load();
    return getEffectiveAprBps(config, stakeAmount);
}
