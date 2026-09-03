import "errors"
import "jetton-utils"
import "messages"

// Midas Hand non-custodial LP escrow — one instance per deal.
//
// Holds whale TON + owner jetton and releases them only per code rules.
// Security model (per docs.ton.org security best practices):
//   * Authorization ALWAYS by in.senderAddress (never an address in the body).
//   * Jetton custody verified against the escrow's OWN seed-jetton wallet
//     address (computed from the minter + wallet code stored in config), so
//     only real jetton transfers to this contract are credited — and only the
//     configured owner's own deposit counts (transferInitiator check).
//   * Time lock enforced with blockchain.now(); no early release.
//   * Single-flight settlement: every payout path is gated by a terminal
//     status transition, so a claim/refund/cancel can never run twice.
//   * TON payouts are clamped to (balance - gas reserve) to avoid overdrawing.
//
// State machine (Fase 1 — custody + time lock; STON.fi LP add is Fase 2):
//   PROPOSED --DepositTon(whale)--> FUNDED --(owner jetton + ApproveByOwner)--> ACTIVE
//   FUNDED   --RefundTimeout--> REFUNDED
//   PROPOSED/FUNDED --Cancel(admin)--> CANCELLED
//   ACTIVE   --ClaimAfterUnlock--> CLOSED
//
// Cell layout note: the config is stored in its OWN cell (Cell<MidasEscrowConfig>)
// and must stay under the 1023-bit limit. Three addresses + one wallet-code cell
// + one admin cell + a uint32 = 833 bits, comfortably within the limit.
contract MidasHandEscrow {
    author: "Phalanx Foundation"
    version: "1.0.0"
    description: "Midas Hand non-custodial LP escrow — one instance per deal. Holds whale TON + owner jetton; releases only per code rules (time lock, refund timeout, cancel, settlement)."
    storage: MidasEscrowStorage
    incomingMessages: AllowedMessageToMidasEscrow
}

// === status ===
const STATUS_PROPOSED: uint8 = 0
const STATUS_FUNDED: uint8 = 1
const STATUS_ACTIVE: uint8 = 2
const STATUS_CLOSED: uint8 = 3
const STATUS_REFUNDED: uint8 = 4
const STATUS_CANCELLED: uint8 = 5

// === forward-payload op code (owner seed-jetton deposit) ===
const MIDAS_OWNER_DEPOSIT_OP: uint32 = 0x4d484531

// === amounts / durations ===
const MIDAS_MIN_TON_NANO: coins = 500000000000 // 500 TON minimum whale deposit
const MIDAS_GAS_RESERVE: coins = 100000000      // 0.1 TON reserved for fees
const MIDAS_TRANSFER_VALUE: coins = 80000000    // 0.08 TON for jetton transfer ops
const THREE_MONTHS_SEC: uint32 = 7776000
const SIX_MONTHS_SEC: uint32 = 15552000
const TWELVE_MONTHS_SEC: uint32 = 31104000
const DEFAULT_PROPOSAL_TIMEOUT_SEC: uint32 = 86400 // 24h owner response window

@overflow1023_policy("suppress")
struct MidasEscrowConfig {
    whaleAddress: address          // TON provider
    ownerAddress: address          // seed-jetton provider
    minterAddress: address         // seed token jetton minter
    seedWalletCode: cell           // seed token jetton wallet code (own-wallet verify)
    adminMultisig: Cell<address>   // limited admin: cancel (wrapped to keep 1023-bit flat)
    proposalTimeoutSec: uint32     // owner response window
}

@overflow1023_policy("suppress")
struct MidasEscrowStorage {
    config: Cell<MidasEscrowConfig>
    status: uint8
    termType: uint8 // 0 = 3mo, 1 = 6mo, 2 = 12mo (chosen by whale)
    whaleTonDeposited: coins
    ownerJettonDeposited: coins
    lockUntil: uint32
    proposalDeadline: uint32
}

struct (0x4d484530) DepositTon {
    queryId: uint64
    termType: uint8
}

struct (0x4d484532) ApproveByOwner {
    queryId: uint64
}

struct (0x4d484533) ClaimAfterUnlock {
    queryId: uint64
}

struct (0x4d484534) RefundTimeout {
    queryId: uint64
}

struct (0x4d484535) Cancel {
    queryId: uint64
}

type AllowedMessageToMidasEscrow =
    | DepositTon
    | ApproveByOwner
    | ClaimAfterUnlock
    | RefundTimeout
    | Cancel
    | TransferNotificationForRecipient
    | TopUpTons

fun MidasEscrowStorage.load(): MidasEscrowStorage {
    return MidasEscrowStorage.fromCell(contract.getData());
}

fun MidasEscrowStorage.save(self) {
    contract.setData(self.toCell());
}

fun ownSeedWallet(config: MidasEscrowConfig): address {
    return calcAddressOfJettonWallet(contract.getAddress(), config.minterAddress, config.seedWalletCode);
}

fun termDurationFor(termType: uint8): uint32 {
    if (termType == 0) {
        return THREE_MONTHS_SEC;
    }
    if (termType == 1) {
        return SIX_MONTHS_SEC;
    }
    return TWELVE_MONTHS_SEC;
}

// Whale fee share in basis points (per term). Owner share = 10000 - whale share.
fun whaleShareFor(termType: uint8): uint16 {
    if (termType == 0) {
        return 6500;
    }
    if (termType == 1) {
        return 7000;
    }
    return 7500;
}

// Refundable TON = principal, but never more than (balance - gas reserve).
// The guard avoids underflow when the escrow's TON balance is below the reserve.
fun refundableTon(whaleTonDeposited: coins): coins {
    val balance = contract.getOriginalBalance();
    if (balance <= MIDAS_GAS_RESERVE) {
        return 0;
    }
    val available: coins = balance - MIDAS_GAS_RESERVE;
    if (whaleTonDeposited <= available) {
        return whaleTonDeposited;
    }
    return available;
}

fun parseDepositOp(payload: ForwardPayloadRemainder): (uint32, bool) {
    var s = payload;
    if (s.remainingBitsCount() == 0 && s.remainingRefsCount() == 0) {
        return (0, false);
    }
    val op = s.loadUint(32);
    if (op == MIDAS_OWNER_DEPOSIT_OP) {
        return (MIDAS_OWNER_DEPOSIT_OP, true);
    }
    return (0, false);
}

fun sendTonOut(to: address, amount: coins) {
    val msg = createMessage({
        bounce: BounceMode.NoBounce,
        dest: to,
        value: amount,
    });
    msg.send(SEND_MODE_PAY_FEES_SEPARATELY);
}

fun sendJettonOut(
    wallet: address,
    recipient: address,
    amount: coins,
    queryId: uint64,
) {
    val transferMsg = createMessage({
        bounce: BounceMode.Only256BitsOfBody,
        dest: wallet,
        value: MIDAS_TRANSFER_VALUE,
        body: AskToTransfer {
            queryId,
            jettonAmount: amount,
            transferRecipient: recipient,
            sendExcessesTo: contract.getAddress(),
            customPayload: null,
            forwardTonAmount: 0,
            forwardPayload: jettonEmptyForwardPayload(),
        },
    });
    transferMsg.send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_BOUNCE_ON_ACTION_FAIL);
}

// Restore jetton accounting when an outbound jetton transfer bounces
// (receiver wallet missing / action failed). Mirrors TokenLockVault bounce logic.
// In Fase 1 the only jetton we ever send out is the owner's principal back to
// the owner, so it is restored as owner jetton.
fun onBouncedMessage(in: InMessageBounced) {
    in.bouncedBody.skipBouncedPrefix();
    if (in.bouncedBody.remainingBitsCount() < 32) {
        return;
    }
    val op = in.bouncedBody.loadUint(32);
    if (op != 0x0f8a7ea5) {
        return;
    }
    in.bouncedBody.loadUint(64); // queryId
    val bouncedAmount = in.bouncedBody.loadCoins();

    var storage = lazy MidasEscrowStorage.load();
    storage.ownerJettonDeposited += bouncedAmount;
    storage.save();
}

fun onInternalMessage(in: InMessage) {
    if (in.body.remainingBitsCount() == 0 && in.body.remainingRefsCount() == 0) {
        return;
    }

    val msg = lazy AllowedMessageToMidasEscrow.fromSlice(in.body);

    match (msg) {
        DepositTon => {
            var storage = lazy MidasEscrowStorage.load();
            val config = storage.config.load();
            assert (in.senderAddress == config.whaleAddress) throw Errors.NotOwner;
            assert (storage.status == STATUS_PROPOSED) throw Errors.InvalidOp;
            assert (msg.termType <= 2) throw Errors.InvalidOp;
            assert (in.valueCoins >= MIDAS_MIN_TON_NANO) throw Errors.BalanceError;

            storage.termType = msg.termType;
            storage.whaleTonDeposited = in.valueCoins;
            storage.proposalDeadline = blockchain.now() + config.proposalTimeoutSec;
            storage.status = STATUS_FUNDED;
            storage.save();
        }

        ApproveByOwner => {
            var storage = lazy MidasEscrowStorage.load();
            val config = storage.config.load();
            assert (in.senderAddress == config.ownerAddress) throw Errors.NotOwner;
            assert (storage.status == STATUS_FUNDED) throw Errors.InvalidOp;
            assert (storage.ownerJettonDeposited > 0) throw Errors.BalanceError;

            // Fase 2 (STON.fi router) integration point: send whale TON + owner
            // jetton to the router to mint LP back to this escrow, then start the
            // lock once LP tokens are received. Until that is wired, this handler
            // locks the principal in escrow for the term — a safe, honest
            // time-locked custody. Principal is returned at ClaimAfterUnlock.
            storage.status = STATUS_ACTIVE;
            storage.lockUntil = blockchain.now() + termDurationFor(storage.termType);
            storage.save();
        }

        ClaimAfterUnlock => {
            var storage = lazy MidasEscrowStorage.load();
            val config = storage.config.load();
            assert (storage.status == STATUS_ACTIVE) throw Errors.InvalidOp;
            assert (blockchain.now() >= storage.lockUntil) throw Errors.NothingToClaim;
            assert (in.senderAddress == config.whaleAddress || in.senderAddress == config.ownerAddress || in.senderAddress == config.adminMultisig.load()) throw Errors.NotOwner;

            // Settle principal: whale gets TON, owner gets jetton.
            sendTonOut(config.whaleAddress, refundableTon(storage.whaleTonDeposited));
            if (storage.ownerJettonDeposited > 0) {
                sendJettonOut(ownSeedWallet(config), config.ownerAddress, storage.ownerJettonDeposited, msg.queryId);
            }

            storage.status = STATUS_CLOSED;
            storage.whaleTonDeposited = 0;
            storage.ownerJettonDeposited = 0;
            storage.save();
        }

        RefundTimeout => {
            var storage = lazy MidasEscrowStorage.load();
            val config = storage.config.load();
            assert (storage.status == STATUS_FUNDED) throw Errors.InvalidOp;
            assert (blockchain.now() >= storage.proposalDeadline) throw Errors.NothingToClaim;

            sendTonOut(config.whaleAddress, refundableTon(storage.whaleTonDeposited));
            // If the owner already deposited jetton but never approved, return it
            // too — otherwise it would be stranded once the deal is refunded.
            if (storage.ownerJettonDeposited > 0) {
                sendJettonOut(ownSeedWallet(config), config.ownerAddress, storage.ownerJettonDeposited, msg.queryId);
            }

            storage.status = STATUS_REFUNDED;
            storage.whaleTonDeposited = 0;
            storage.ownerJettonDeposited = 0;
            storage.save();
        }

        Cancel => {
            var storage = lazy MidasEscrowStorage.load();
            val config = storage.config.load();
            assert (in.senderAddress == config.adminMultisig.load()) throw Errors.NotOwner;
            assert (storage.status == STATUS_PROPOSED || storage.status == STATUS_FUNDED) throw Errors.InvalidOp;

            sendTonOut(config.whaleAddress, refundableTon(storage.whaleTonDeposited));
            if (storage.ownerJettonDeposited > 0) {
                sendJettonOut(ownSeedWallet(config), config.ownerAddress, storage.ownerJettonDeposited, msg.queryId);
            }

            storage.status = STATUS_CANCELLED;
            storage.whaleTonDeposited = 0;
            storage.ownerJettonDeposited = 0;
            storage.save();
        }

        TransferNotificationForRecipient => {
            var storage = lazy MidasEscrowStorage.load();
            val config = storage.config.load();

            val seedWallet = ownSeedWallet(config);
            val incomingAmount = msg.jettonAmount;
            if (incomingAmount == 0) {
                return;
            }

            // Only transfers from OUR seed-jetton wallet are credited.
            assert (in.senderAddress == seedWallet) throw Errors.NotValidWallet;
            // Owner seed-jetton deposit. Only meaningful while awaiting owner.
            assert (storage.status == STATUS_FUNDED) throw Errors.InvalidOp;
            val (op, isValid) = parseDepositOp(msg.forwardPayload);
            assert (isValid && op == MIDAS_OWNER_DEPOSIT_OP) throw Errors.InvalidOp;
            // Credit only the configured owner's own deposit; a third party must
            // not be able to inflate ownerJettonDeposited on the owner's behalf
            // (which could let a premature ApproveByOwner pass).
            assert (msg.transferInitiator! == config.ownerAddress) throw Errors.NotOwner;
            storage.ownerJettonDeposited += incomingAmount;
            storage.save();
        }

        TopUpTons => {}
    }
}

get fun get_escrow_data(): (uint8, uint8, coins, coins, uint32, uint32) {
    val storage = MidasEscrowStorage.load();
    return (
        storage.status,
        storage.termType,
        storage.whaleTonDeposited,
        storage.ownerJettonDeposited,
        storage.lockUntil,
        storage.proposalDeadline,
    );
}

get fun get_config(): MidasEscrowConfig {
    val storage = MidasEscrowStorage.load();
    return storage.config.load();
}

get fun get_whale_share_bps(): uint16 {
    val storage = MidasEscrowStorage.load();
    return whaleShareFor(storage.termType);
}
