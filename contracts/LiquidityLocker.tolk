import "errors"
import "messages"

contract LiquidityLocker {
    author: "Phalanx Foundation"
    version: "1.0.0"
    description: "LP token locker — lock DEX liquidity pool tokens for a configurable period. On-chain proof of locked liquidity to prevent rug pulls."
    storage: LockerStorage
    incomingMessages: AllowedMessageToLocker
}

@overflow1023_policy("suppress")
struct LockerConfig {
    admin: address
    lpTokenMinter: address
}

/// LockRecord: one locked position.
/// lpAmount: nano-units of LP tokens locked
/// unlockAt: block time when lock expires
/// released: true after owner has withdrawn
@overflow1023_policy("suppress")
struct LockRecord {
    id: uint64
    owner: address
    lpAmount: coins
    lockedAt: uint32
    unlockAt: uint32
    released: bool
}

@overflow1023_policy("suppress")
struct LockerStorage {
    config: Cell<LockerConfig>
    nextLockId: uint64
    totalLocked: coins
    locks: map<uint64, Cell<LockRecord>>
}

struct (0x4c504b01) LockLiquidity {
    queryId: uint64
    lpTokenMinter: address
    lpAmount: coins
    unlockAt: uint32
}

struct (0x4c504b02) UnlockLiquidity {
    queryId: uint64
    lockId: uint64
}

struct (0x4c504b03) RevokeLock {
    queryId: uint64
    lockId: uint64
}

type AllowedMessageToLocker =
    | TransferNotificationForRecipient
    | UnlockLiquidity
    | RevokeLock
    | TopUpTons

const LP_TRANSFER_VALUE = 80000000
const LP_LOCK_FORWARD_OP: uint32 = 0x4c504b10

fun LockerStorage.load(): LockerStorage {
    return LockerStorage.fromCell(contract.getData());
}

fun LockerStorage.save(self) {
    contract.setData(self.toCell());
}

fun parseLockPayload(payload: ForwardPayloadRemainder): (uint32, bool) {
    var s = payload;
    if (s.remainingBitsCount() == 0 && s.remainingRefsCount() == 0) {
        return (0, false);
    }
    val op = s.loadUint(32);
    if (op != LP_LOCK_FORWARD_OP) {
        return (0, false);
    }
    val unlockAt = s.loadUint(32);
    return (unlockAt, true);
}

fun onInternalMessage(in: InMessage) {
    if (in.body.remainingBitsCount() == 0 && in.body.remainingRefsCount() == 0) {
        return;
    }

    val msg = lazy AllowedMessageToLocker.fromSlice(in.body);

    match (msg) {
        TransferNotificationForRecipient => {
            var storage = lazy LockerStorage.load();
            val config = storage.config.load();

            val incomingAmount = msg.jettonAmount;
            if (incomingAmount == 0) {
                return;
            }

            val (unlockAt, isValid) = parseLockPayload(msg.forwardPayload);
            if (!isValid || unlockAt <= blockchain.now()) {
                return;
            }

            val lockId = storage.nextLockId;
            val record: LockRecord = {
                id: lockId,
                owner: msg.transferInitiator!,
                lpAmount: incomingAmount,
                lockedAt: blockchain.now(),
                unlockAt,
                released: false,
            };

            storage.locks.set(lockId, record.toCell());
            storage.nextLockId += 1;
            storage.totalLocked += incomingAmount;
            storage.save();
        }

        UnlockLiquidity => {
            var storage = lazy LockerStorage.load();

            val lockEntry = storage.locks.get(msg.lockId);
            assert (lockEntry.isFound) throw Errors.InvalidOp;

            var record = lockEntry.loadValue().load();

            assert (in.senderAddress == record.owner) throw Errors.NotOwner;
            assert (!record.released) throw Errors.InvalidOp;
            assert (blockchain.now() >= record.unlockAt) throw Errors.NothingToClaim;

            record.released = true;
            storage.locks.set(msg.lockId, record.toCell());
            storage.totalLocked -= record.lpAmount;
            storage.save();

            val transferMsg = createMessage({
                bounce: BounceMode.Only256BitsOfBody,
                dest: in.senderAddress,
                value: LP_TRANSFER_VALUE,
                body: JettonTransferNotification {
                    queryId: msg.queryId,
                    jettonAmount: record.lpAmount,
                    sender: contract.getAddress(),
                    forwardPayload: jettonEmptyForwardPayload(),
                },
            });
            transferMsg.send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_BOUNCE_ON_ACTION_FAIL);
        }

        RevokeLock => {
            var storage = lazy LockerStorage.load();
            val config = storage.config.load();

            assert (in.senderAddress == config.admin) throw Errors.NotOwner;

            val lockEntry = storage.locks.get(msg.lockId);
            assert (lockEntry.isFound) throw Errors.InvalidOp;

            var record = lockEntry.loadValue().load();
            assert (!record.released) throw Errors.InvalidOp;

            record.released = true;
            storage.locks.set(msg.lockId, record.toCell());
            storage.totalLocked -= record.lpAmount;
            storage.save();
        }

        TopUpTons => {}
    }
}

get fun get_locker_data(): (uint64, coins) {
    val storage = LockerStorage.load();
    return (storage.nextLockId, storage.totalLocked);
}

get fun get_lock(lockId: uint64): Cell<LockRecord>? {
    val storage = LockerStorage.load();
    val entry = storage.locks.get(lockId);
    if (!entry.isFound) {
        return null;
    }
    return entry.loadValue();
}
