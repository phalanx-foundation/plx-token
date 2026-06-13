import "@gen/JettonWallet.code"
import "errors"
import "jetton-utils"
import "messages"

contract PlxLockVault {
    author: "Phalanx Foundation"
    version: "2.0.0"
    description: "PLX lock vault — real jetton escrow, per-position tiers, layered locks, campaign end bonus rules."
    storage: LockVaultStorage
    incomingMessages: AllowedMessageToLockVault
}

@overflow1023_policy("suppress")
struct LockTier {
    durationSec: uint32
    bonusBps: uint16
}

@overflow1023_policy("suppress")
struct LockVaultConfig {
    admin: address
    minterAddress: address
    tierCount: uint8
    tier0: LockTier
    tier1: LockTier
    tier2: LockTier
    tier3: LockTier
    eventEndAt: uint32
    minLockAmount: coins
    sovereignMinAmount: coins
}

@overflow1023_policy("suppress")
struct LockPositionOnChain {
    owner: address
    amount: coins
    startAt: uint32
    unlockAt: uint32
    tierBps: uint16
    isSovereign: bool
    released: bool
}

@overflow1023_policy("suppress")
struct LockVaultStorage {
    config: Cell<LockVaultConfig>
    nextPositionId: uint64
    totalLocked: coins
    rewardPool: coins
    positions: map<uint64, Cell<LockPositionOnChain>>
}

struct (0x4c4f434b02) ReleaseLock {
    queryId: uint64
    positionId: uint64
}

struct (0x4c4f434b03) UpdateTiers {
    queryId: uint64
    tierCount: uint8
    tier0: LockTier
    tier1: LockTier
    tier2: LockTier
    tier3: LockTier
}

struct (0x4c4f434b04) SetEventEnd {
    queryId: uint64
    eventEndAt: uint32
}

struct (0x4c4f434b05) SetMinAmounts {
    queryId: uint64
    minLockAmount: coins
    sovereignMinAmount: coins
}

type AllowedMessageToLockVault =
    | TransferNotificationForRecipient
    | ReleaseLock
    | UpdateTiers
    | SetEventEnd
    | SetMinAmounts
    | TopUpTons

const LOCK_TRANSFER_VALUE = 80000000
const LOCK_FORWARD_DEPOSIT_OP: uint32 = 0x4c4f434b01
const LOCK_FORWARD_REWARD_POOL_OP: uint32 = 0x4c4f434b06
const SIX_MONTHS_SEC: uint32 = 15552000

fun LockVaultStorage.load(): LockVaultStorage {
    return LockVaultStorage.fromCell(contract.getData());
}

fun LockVaultStorage.save(self) {
    contract.setData(self.toCell());
}

fun lockVaultOwnJettonWallet(minterAddress: address): address {
    val jettonWalletCode = jettonWalletCompiledCode();
    return calcAddressOfJettonWallet(contract.getAddress(), minterAddress, jettonWalletCode);
}

fun emptyForwardPayload(): slice {
    return beginCell().storeUint(0, 1).toSlice();
}

fun parseLockForwardPayload(payload: ForwardPayloadRemainder): (uint8, bool, bool) {
    var s = payload;
    if (s.remainingBitsCount() == 0 && s.remainingRefsCount() == 0) {
        return (0, false, false);
    }
    val op = s.loadUint(32);
    if (op == LOCK_FORWARD_REWARD_POOL_OP) {
        return (0, false, true);
    }
    if (op != LOCK_FORWARD_DEPOSIT_OP) {
        return (0, false, false);
    }
    val tierIndex = s.loadUint(8);
    val sovereignFlag = s.loadUint(1) != 0;
    return (tierIndex, sovereignFlag, false);
}

fun configTierAt(config: LockVaultConfig, tierIndex: uint8): LockTier {
    if (tierIndex == 0) {
        return config.tier0;
    }
    if (tierIndex == 1) {
        return config.tier1;
    }
    if (tierIndex == 2) {
        return config.tier2;
    }
    return config.tier3;
}

fun bonusEligible(unlockAt: uint32, eventEndAt: uint32): bool {
    if (eventEndAt == 0) {
        return true;
    }
    return unlockAt <= eventEndAt;
}

fun calcBonus(amount: coins, tierBps: uint16): coins {
    return amount * tierBps / 10000;
}

fun onBouncedMessage(in: InMessageBounced) {
    in.bouncedBody.skipBouncedPrefix();
    val op = in.bouncedBody.loadUint(32);
    if (op != 0x0f8a7ea5) {
        return;
    }
    in.bouncedBody.loadUint(64);
    val refundedAmount = in.bouncedBody.loadCoins();

    var storage = lazy LockVaultStorage.load();
    if (storage.rewardPool >= refundedAmount) {
        storage.rewardPool -= refundedAmount;
    } else if (storage.totalLocked >= refundedAmount) {
        storage.totalLocked -= refundedAmount;
    }
    storage.save();
}

fun onInternalMessage(in: InMessage) {
    if (in.body.remainingBitsCount() == 0 && in.body.remainingRefsCount() == 0) {
        return;
    }

    val msg = lazy AllowedMessageToLockVault.fromSlice(in.body);

    match (msg) {
        TransferNotificationForRecipient => {
            var storage = lazy LockVaultStorage.load();
            val config = storage.config.load();
            val ourWallet = lockVaultOwnJettonWallet(config.minterAddress);
            assert (in.senderAddress == ourWallet) throw Errors.NotValidWallet;

            val incomingAmount = msg.jettonAmount;
            if (incomingAmount == 0) {
                return;
            }

            val (tierIndex, isSovereign, isRewardPool) = parseLockForwardPayload(msg.forwardPayload);
            if (isRewardPool) {
                storage.rewardPool += incomingAmount;
                storage.save();
                return;
            }

            assert (tierIndex < config.tierCount) throw Errors.InvalidOp;
            assert (incomingAmount >= config.minLockAmount) throw Errors.BalanceError;

            val tier = configTierAt(config, tierIndex);
            if (isSovereign) {
                assert (incomingAmount >= config.sovereignMinAmount) throw Errors.BalanceError;
                assert (tier.durationSec >= SIX_MONTHS_SEC) throw Errors.InvalidOp;
            }

            val now = contract.getNow();
            val positionId = storage.nextPositionId;
            val position: LockPositionOnChain = {
                owner: msg.transferInitiator!,
                amount: incomingAmount,
                startAt: now,
                unlockAt: now + tier.durationSec,
                tierBps: tier.bonusBps,
                isSovereign,
                released: false,
            };

            storage.positions.set(positionId, position.toCell());
            storage.nextPositionId += 1;
            storage.totalLocked += incomingAmount;
            storage.save();
        }

        ReleaseLock => {
            var storage = lazy LockVaultStorage.load();
            val config = storage.config.load();
            val positionCell = storage.positions.get(msg.positionId);
            assert (positionCell != null) throw Errors.InvalidOp;

            var position = positionCell!.load();
            assert (in.senderAddress == position.owner) throw Errors.NotOwner;
            assert (!position.released) throw Errors.InvalidOp;
            assert (contract.getNow() >= position.unlockAt) throw Errors.NothingToClaim;

            var bonus = 0;
            if (bonusEligible(position.unlockAt, config.eventEndAt)) {
                bonus = calcBonus(position.amount, position.tierBps);
            }
            val bonusPay = min(bonus, storage.rewardPool);

            position.released = true;
            storage.positions.set(msg.positionId, position.toCell());
            storage.totalLocked -= position.amount;
            storage.rewardPool -= bonusPay;
            storage.save();

            val totalPayout = position.amount + bonusPay;
            val transferMsg = createMessage({
                bounce: BounceMode.Only256BitsOfBody,
                dest: lockVaultOwnJettonWallet(config.minterAddress),
                value: LOCK_TRANSFER_VALUE,
                body: AskToTransfer {
                    queryId: msg.queryId,
                    jettonAmount: totalPayout,
                    transferRecipient: position.owner,
                    sendExcessesTo: in.senderAddress,
                    customPayload: null,
                    forwardTonAmount: 0,
                    forwardPayload: emptyForwardPayload(),
                },
            });
            transferMsg.send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_BOUNCE_ON_ACTION_FAIL);
        }

        UpdateTiers => {
            var storage = lazy LockVaultStorage.load();
            val config = storage.config.load();
            assert (in.senderAddress == config.admin) throw Errors.NotOwner;
            assert (msg.tierCount > 0 && msg.tierCount <= 16) throw Errors.InvalidOp;
            config.tierCount = msg.tierCount;
            config.tier0 = msg.tier0;
            config.tier1 = msg.tier1;
            config.tier2 = msg.tier2;
            config.tier3 = msg.tier3;
            storage.config = config.toCell();
            storage.save();
        }

        SetEventEnd => {
            var storage = lazy LockVaultStorage.load();
            val config = storage.config.load();
            assert (in.senderAddress == config.admin) throw Errors.NotOwner;
            config.eventEndAt = msg.eventEndAt;
            storage.config = config.toCell();
            storage.save();
        }

        SetMinAmounts => {
            var storage = lazy LockVaultStorage.load();
            val config = storage.config.load();
            assert (in.senderAddress == config.admin) throw Errors.NotOwner;
            config.minLockAmount = msg.minLockAmount;
            config.sovereignMinAmount = msg.sovereignMinAmount;
            storage.config = config.toCell();
            storage.save();
        }

        TopUpTons => {}
    }
}

get fun getLockVaultData(): (uint64, coins, coins, uint32) {
    val storage = LockVaultStorage.load();
    val config = storage.config.load();
    return (storage.nextPositionId, storage.totalLocked, storage.rewardPool, config.eventEndAt);
}

get fun getPosition(positionId: uint64): Cell<LockPositionOnChain>? {
    val storage = LockVaultStorage.load();
    return storage.positions.get(positionId);
}
