import "@gen/JettonWallet.code"
import "errors"
import "jetton-utils"
import "messages"

contract PlxStaking {
    author: "Phalanx Foundation"
    version: "2.0.0"
    description: "PLX staking — real jetton escrow, APR accrual per second, min-lock unstake/claim."
    storage: StakingStorage
    incomingMessages: AllowedMessageToStaking
}

@overflow1023_policy("suppress")
struct StakingConfig {
    admin: address
    minterAddress: address
    aprBps: uint32
    minLockSec: uint32
}

@overflow1023_policy("suppress")
struct StakeRecord {
    owner: address
    stakedAmount: coins
    rewardDebt: uint64
    stakedAt: uint32
    lockUntil: uint32
    active: bool
}

@overflow1023_policy("suppress")
struct StakingStorage {
    config: Cell<StakingConfig>
    totalStaked: coins
    rewardPerTokenStored: uint64
    lastUpdateTime: uint32
    rewardPool: coins
    nextStakeId: uint64
    stakes: map<uint64, Cell<StakeRecord>>
}

struct (0x5354414b02) UnstakePlx {
    queryId: uint64
    stakeId: uint64
}

struct (0x5354414b03) ClaimRewards {
    queryId: uint64
    stakeId: uint64
}

struct (0x5354414b04) UpdateApr {
    queryId: uint64
    aprBps: uint32
}

struct (0x5354414b05) SetMinLock {
    queryId: uint64
    minLockSec: uint32
}

type AllowedMessageToStaking =
    | TransferNotificationForRecipient
    | UnstakePlx
    | ClaimRewards
    | UpdateApr
    | SetMinLock
    | TopUpTons

const STAKE_TRANSFER_VALUE = 80000000
const STAKE_FORWARD_DEPOSIT_OP: uint32 = 0x54414b01
const STAKE_FORWARD_REWARD_POOL_OP: uint32 = 0x54414b06
const REWARD_SCALE: uint64 = 1000000000000
const SECONDS_PER_YEAR: int = 31536000

fun StakingStorage.load(): StakingStorage {
    return StakingStorage.fromCell(contract.getData());
}

fun StakingStorage.save(self) {
    contract.setData(self.toCell());
}

fun stakingOwnJettonWallet(minterAddress: address): address {
    val jettonWalletCode = jettonWalletCompiledCode();
    return calcAddressOfJettonWallet(contract.getAddress(), minterAddress, jettonWalletCode);
}

fun parseStakeForwardPayload(payload: ForwardPayloadRemainder): (uint32, bool) {
    var s = payload;
    if (s.remainingBitsCount() == 0 && s.remainingRefsCount() == 0) {
        return (0, false);
    }
    val op = s.loadUint(32);
    if (op == STAKE_FORWARD_REWARD_POOL_OP) {
        return (0, true);
    }
    if (op != STAKE_FORWARD_DEPOSIT_OP) {
        return (0, false);
    }
    val lockSec = s.loadUint(32);
    return (lockSec, false);
}

fun accrueRewards(storage: StakingStorage, config: StakingConfig) {
    val now = blockchain.now();
    if (storage.totalStaked == 0 || now <= storage.lastUpdateTime) {
        storage.lastUpdateTime = now;
        return;
    }
    val elapsed = now - storage.lastUpdateTime;
    val rewardDelta = storage.totalStaked * config.aprBps * elapsed / (10000 * SECONDS_PER_YEAR);
    storage.rewardPerTokenStored += rewardDelta * REWARD_SCALE / storage.totalStaked;
    storage.lastUpdateTime = now;
}

fun pendingReward(stake: StakeRecord, rewardPerTokenStored: uint64): coins {
    val accumulated = stake.stakedAmount * rewardPerTokenStored / REWARD_SCALE;
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

    var storage = lazy StakingStorage.load();
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

    val msg = lazy AllowedMessageToStaking.fromSlice(in.body);

    match (msg) {
        TransferNotificationForRecipient => {
            var storage = lazy StakingStorage.load();
            val config = storage.config.load();
            val ourWallet = stakingOwnJettonWallet(config.minterAddress);
            assert (in.senderAddress == ourWallet) throw Errors.NotValidWallet;

            val incomingAmount = msg.jettonAmount;
            if (incomingAmount == 0) {
                return;
            }

            val (lockSec, isRewardPool) = parseStakeForwardPayload(msg.forwardPayload);
            if (isRewardPool) {
                storage.rewardPool += incomingAmount;
                storage.save();
                return;
            }

            assert (lockSec >= config.minLockSec) throw Errors.InvalidOp;

            accrueRewards(storage, config);

            val now = blockchain.now();
            val stakeId = storage.nextStakeId;
            val rewardDebt = incomingAmount * storage.rewardPerTokenStored / REWARD_SCALE;
            val stake: StakeRecord = {
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

        UnstakePlx => {
            var storage = lazy StakingStorage.load();
            val config = storage.config.load();
            val stakeEntry = storage.stakes.get(msg.stakeId);
            assert (stakeEntry.isFound) throw Errors.InvalidOp;

            var stake = stakeEntry.loadValue().load();
            assert (in.senderAddress == stake.owner) throw Errors.NotOwner;
            assert (stake.active) throw Errors.InvalidOp;
            assert (blockchain.now() >= stake.lockUntil) throw Errors.NothingToClaim;

            accrueRewards(storage, config);
            val pending = pendingReward(stake, storage.rewardPerTokenStored);
            val rewardPay = min(pending, storage.rewardPool);

            stake.active = false;
            storage.stakes.set(msg.stakeId, stake.toCell());
            storage.totalStaked -= stake.stakedAmount;
            storage.rewardPool -= rewardPay;
            storage.save();

            val totalPayout = stake.stakedAmount + rewardPay;
            val transferMsg = createMessage({
                bounce: BounceMode.Only256BitsOfBody,
                dest: stakingOwnJettonWallet(config.minterAddress),
                value: STAKE_TRANSFER_VALUE,
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

        ClaimRewards => {
            var storage = lazy StakingStorage.load();
            val config = storage.config.load();
            val stakeEntry = storage.stakes.get(msg.stakeId);
            assert (stakeEntry.isFound) throw Errors.InvalidOp;

            var stake = stakeEntry.loadValue().load();
            assert (in.senderAddress == stake.owner) throw Errors.NotOwner;
            assert (stake.active) throw Errors.InvalidOp;

            accrueRewards(storage, config);
            val pending = pendingReward(stake, storage.rewardPerTokenStored);
            assert (pending > 0) throw Errors.NothingToClaim;

            val rewardPay = min(pending, storage.rewardPool);
            stake.rewardDebt += rewardPay;
            storage.stakes.set(msg.stakeId, stake.toCell());
            storage.rewardPool -= rewardPay;
            storage.save();

            val transferMsg = createMessage({
                bounce: BounceMode.Only256BitsOfBody,
                dest: stakingOwnJettonWallet(config.minterAddress),
                value: STAKE_TRANSFER_VALUE,
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

        UpdateApr => {
            var storage = lazy StakingStorage.load();
            var config = storage.config.load();
            assert (in.senderAddress == config.admin) throw Errors.NotOwner;
            accrueRewards(storage, config);
            config.aprBps = msg.aprBps;
            storage.config = config.toCell();
            storage.save();
        }

        SetMinLock => {
            var storage = lazy StakingStorage.load();
            var config = storage.config.load();
            assert (in.senderAddress == config.admin) throw Errors.NotOwner;
            config.minLockSec = msg.minLockSec;
            storage.config = config.toCell();
            storage.save();
        }

        TopUpTons => {}
    }
}

get fun get_staking_data(): (coins, uint64, uint32, coins, uint64) {
    val storage = StakingStorage.load();
    return (
        storage.totalStaked,
        storage.rewardPerTokenStored,
        storage.lastUpdateTime,
        storage.rewardPool,
        storage.nextStakeId,
    );
}

get fun get_stake(stakeId: uint64): Cell<StakeRecord>? {
    val storage = StakingStorage.load();
    val entry = storage.stakes.get(stakeId);
    if (!entry.isFound) {
        return null;
    }
    return entry.loadValue();
}

get fun get_apr_bps(): uint32 {
    val storage = StakingStorage.load();
    val config = storage.config.load();
    return config.aprBps;
}
