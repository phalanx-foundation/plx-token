import "errors"
import "jetton-utils"
import "messages"

// Midas Hand non-custodial LP escrow — one instance per deal.
//
// Holds whale TON + owner seed jetton, then (on owner approve) drives STON.fi
// v2.2 balanced add-liquidity fully on-chain, holds the minted LP, time-locks,
// and on settlement burns the LP, receives back pTON (the TON side, a jetton)
// + PLX, unwraps the pTON to native TON, and redistributes principal.
//
// === Security model (per docs.ton.org best practices) ===
//   * Authorization ALWAYS by in.senderAddress (never an address in the body).
//   * Jetton custody verified against the escrow's OWN jetton wallet address
//     (computed from minter + wallet code stored in config), so only real
//     jetton transfers are credited — and only the configured owner's own seed
//     deposit counts (transferInitiator check), so a third party cannot inflate
//     the owner's deposit bucket.
//   * Time lock enforced with blockchain.now(); no early release.
//   * Single-flight settlement: every payout path is gated by a terminal status
//     transition (CLOSED/REFUNDED/CANCELLED). Settlement is guarded by a
//     "settle progress" bitmask so the two refund legs (TON and jetton) can each
//     settle exactly once and the escrow closes only when both are received.
//
// === State machine (Fase 2 — full on-chain STON.fi v2.2 add/remove LP) ===
//   PROPOSED --DepositTon(whale)--> FUNDED
//   FUNDED --(owner jetton)---- ApproveByOwner --> ADDING (2-leg add-LP in flight)
//   ADDING --(LP via own LP wallet)--------------> ACTIVE (locked)
//   ACTIVE --lock<=now --ClaimAfterUnlock--------> SETTLING (burn LP in flight)
//   SETTLING --(pTON unwrapped + PLX sent)--------> CLOSED
//   FUNDED   --RefundTimeout---------------------> REFUNDED
//   PROPOSED/FUNDED/ADDING --Cancel(admin)-------> CANCELLED
//
// lockUntil is computed when LP is received (not at approve), so the release
// window cannot be predicted or gamed from outside. Settlement is inherent in
// the status; a rebounced LP burn returns to ACTIVE so a claim can retry.
//
// === STON.fi v2.2 add/remove LP semantics (pinned from @ston-fi/sdk 2.7) ===
// Balanced two-leg provide_lp:
//   * Jetton leg: AskToTransfer(seed jetton) from the escrow's own seed wallet
//     to the ROUTER, forwardPayload = ProvideLiquidity{ otherTokenWallet =
//     router's pTON wallet (the TON side of the pair) }.
//   * TON leg: native TON -> the router's pTON wallet, body = ProxyToncoinTransfer
//     { tonAmount, refund, forwardPayload = ProvideLiquidity{ otherTokenWallet =
//     router's PLX wallet (the jetton side of the pair) } }.
//   * The pool mints LP to receiverAddress (the escrow's LP wallet).
// Removal (ClaimAfterUnlock):
//   * AskToBurn(LP) from the escrow's own LP wallet. The pool's burn_notification
//     routes the router pay_to so that pTON (TON side) lands at the escrow's
//     pTON wallet and PLX (jetton side) lands at the escrow's seed wallet.
//   * pTON -> unwrap to native TON (ProxyToncoinTransfer to the escrow's own
//     pTON wallet -> pTON master -> native TON back to escrow) -> forward to
//     whale. PLX -> forward to owner. When both legs settle the escrow closes.
//
// Config cell must stay < 1023 bits. Dynamic addresses are wrapped in
// Cell<address>; the two code cells + wrapped addresses fit comfortably.

contract MidasHandEscrow {
    author: "Phalanx Foundation"
    version: "1.2.0"
    description: "Midas Hand non-custodial LP escrow — one instance per deal. Holds whale TON + owner jetton, drives STON.fi v2.2 add-LP on-chain, time-locks, and settles (burn LP + return pTON/PLX) per code rules."
    storage: MidasEscrowStorage
    incomingMessages: AllowedMessageToMidasEscrow
}

// === status ===
const STATUS_PROPOSED: uint8 = 0
const STATUS_FUNDED: uint8 = 1
const STATUS_ADDING: uint8 = 2   // LP mint in flight (owner approved)
const STATUS_ACTIVE: uint8 = 3   // LP received, locked
const STATUS_SETTLING: uint8 = 4 // LP burn in flight
const STATUS_CLOSED: uint8 = 5
const STATUS_REFUNDED: uint8 = 6
const STATUS_CANCELLED: uint8 = 7

// === settle-progress bitmask (single-flight per refund leg) ===
const SETTLE_BIT_TON: uint8 = 1    // TON leg refunded to whale
const SETTLE_BIT_JETTON: uint8 = 2 // jetton leg refunded to owner

// === forward-payload op code (owner seed-jetton deposit) ===
const MIDAS_OWNER_DEPOSIT_OP: uint32 = 0x4d484531

// === STON.fi v2.2 op codes (pinned from @ston-fi/sdk@2.7.0 + STON.fi docs) ===
const STONFI_PROVIDE_LP_OP: uint32 = 0x37C096DF  // 935368415 provide_liquidity
const PTON_TON_TRANSFER_OP: uint32 = 0x01F3835D // 32736093 pTON v2.1 ProxyToncoinTransfer (unwrap pTON -> native TON)
const STONFI_TX_DEADLINE_SEC: uint32 = 900       // 15 min SDK default

// === amounts / durations ===
const MIDAS_MIN_TON_NANO: coins = 500000000000 // 500 TON minimum whale deposit
const MIDAS_GAS_RESERVE: coins = 100000000      // 0.1 TON reserved for fees
const MIDAS_TRANSFER_VALUE: coins = 80000000    // 0.08 TON for jetton transfer ops
const THREE_MONTHS_SEC: uint32 = 7776000
const SIX_MONTHS_SEC: uint32 = 15552000
const TWELVE_MONTHS_SEC: uint32 = 31104000
const DEFAULT_PROPOSAL_TIMEOUT_SEC: uint32 = 86400 // 24h owner response window

// Gas budget for the two-leg add-LP (TON leg + jetton leg). Bounded so a
// malicious config can't drain the entire balance; split across both legs.
const MIDAS_ADD_LP_TON_LEG_NANO: coins = 600000000    // 0.6 TON for the TON (native TON) leg
const MIDAS_ADD_LP_JETTON_LEG_NANO: coins = 600000000 // 0.6 TON for the jetton leg
const MIDAS_PTON_UNWRAP_VALUE: coins = 100000000      // 0.1 TON for pTON unwrap ProxyToncoinTransfer

@overflow1023_policy("suppress")
struct MidasEscrowConfig {
    whaleAddress: address          // TON provider
    ownerAddress: address          // seed-jetton provider
    minterAddress: address         // seed token jetton minter (PLX)
    seedWalletCode: cell           // seed token jetton wallet code (own-wallet verify)
    adminMultisig: Cell<address>   // limited admin: cancel
    proposalTimeoutSec: uint32     // owner response window
    // STON.fi v2.2 (Fase 2) is nested in its own cell so the main config stays
    // under both the 1023-bit and 4-ref limits.
    stonfi: Cell<StonFiConfig>
}

@overflow1023_policy("suppress")
struct StonFiConfig {
    routerAddress: address         // v2.2 router (route add-LP / burn refund)
    poolAddress: address           // LP jetton minter = pool (PLX/TON pool)
    ptonMaster: address            // pTON v2.1 master (TON side wrap/unwrap)
    lpWalletCode: cell             // LP jetton wallet code (own LP-wallet verify)
    ptonWalletCode: cell           // pTON jetton wallet code (own pTON-wallet verify)
}

@overflow1023_policy("suppress")
struct MidasEscrowStorage {
    config: Cell<MidasEscrowConfig>
    status: uint8
    termType: uint8 // 0 = 3mo, 1 = 6mo, 2 = 12mo (chosen by whale)
    whaleTonDeposited: coins
    ownerJettonDeposited: coins
    lpHeld: coins
    lockUntil: uint32
    proposalDeadline: uint32
    settleProgress: uint8 // SETTLE_BIT_* bitmask; 0 outside settlement
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

// pTON v2.1 ProxyToncoinTransfer body (0x01f3835d). Sent to a pTON wallet to
// wrap native TON into pTON, or sent to the escrow's own pTON wallet to unwrap
// pTON back into native TON (the pTON master then mints native TON to refund).
struct (0x01F3835D) ProxyToncoinTransfer {
    queryId: uint64
    tonAmount: coins
    refundAddress: address
    forwardPayload: cell?
}

fun MidasEscrowStorage.load(): MidasEscrowStorage {
    return MidasEscrowStorage.fromCell(contract.getData());
}

fun MidasEscrowStorage.save(self) {
    contract.setData(self.toCell());
}

fun ownSeedWallet(config: MidasEscrowConfig): address {
    return calcAddressOfJettonWallet(contract.getAddress(), config.minterAddress, config.seedWalletCode);
}

fun ownLpWallet(config: MidasEscrowConfig): address {
    val sc = config.stonfi.load();
    return calcAddressOfJettonWallet(contract.getAddress(), sc.poolAddress, sc.lpWalletCode);
}

fun ownPtonWallet(config: MidasEscrowConfig): address {
    val sc = config.stonfi.load();
    return calcAddressOfJettonWallet(contract.getAddress(), sc.ptonMaster, sc.ptonWalletCode);
}

fun loadStonfiConfig(config: MidasEscrowConfig): StonFiConfig {
    return config.stonfi.load();
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

// Build the STON.fi v2.2 provide-liquidity *forward payload* attached (as a
// ref) to both the jetton transfer and the TON leg. Matches
// `RouterV2_2.createProvideLiquidityBody()`:
//   { op=PROVIDE_LP, otherTokenWallet, refund, excess, deadline,
//     ref[minLpOut, receiver, bothPositive, fwdGas, customPayload] }
// For the jetton leg, otherTokenWallet = router's pTON wallet (TON side).
// For the TON leg,       otherTokenWallet = router's PLX wallet (jetton side).
fun makeProvideLpForwardPayload(
    otherTokenWallet: address,
    refundAddress: address,
    excessesAddress: address,
    receiver: address,
    minLpOut: coins,
): cell {
    return beginCell()
        .storeUint(STONFI_PROVIDE_LP_OP, 32)
        .storeAddress(otherTokenWallet)
        .storeAddress(refundAddress)
        .storeAddress(excessesAddress)
        .storeUint(blockchain.now() + STONFI_TX_DEADLINE_SEC, 64)
        .storeRef(
            beginCell()
                .storeCoins(minLpOut)
                .storeAddress(receiver)
                .storeUint(1, 1)          // bothPositive (balanced)
                .storeCoins(0)            // dexCustomPayloadForwardGasAmount
                .storeMaybeRef(null)      // dexCustomPayload
                .endCell(),
        )
        .endCell();
}

// Restore jetton accounting when an outbound jetton transfer/burn bounces.
// If the LP burn bounces (e.g. minter transiently not writable) during
// settlement, restore lpHeld and return to ACTIVE so a claim can retry. Any
// other bounced outbound transfer/burn restores the owner seed jetton.
fun onBouncedMessage(in: InMessageBounced) {
    in.bouncedBody.skipBouncedPrefix();
    // A bounced JettonTransfer (0x0f8a7ea5) or AskToBurn (0x595f07bc). The
    // bounced body mirrors the original: op(32) queryId(64) amount(coins).
    if (in.bouncedBody.remainingBitsCount() < 32) {
        return;
    }
    val op = in.bouncedBody.loadUint(32);
    val isTransfer = op == 0x0f8a7ea5;
    val isBurn = op == 0x595f07bc;
    if (!isTransfer && !isBurn) {
        return;
    }
    in.bouncedBody.loadUint(64); // queryId
    val bouncedAmount = in.bouncedBody.loadCoins();

    var storage = lazy MidasEscrowStorage.load();
    if (storage.status == STATUS_SETTLING) {
        storage.lpHeld += bouncedAmount;
        storage.status = STATUS_ACTIVE;
        storage.settleProgress = 0;
    } else {
        storage.ownerJettonDeposited += bouncedAmount;
    }
    storage.save();
}

fun onInternalMessage(in: InMessage) {
    // A bodyless TON message during settlement = native TON arrived back from
    // the pTON master after unwrap. Forward the whale's principal and close.
    if (in.body.remainingBitsCount() == 0 && in.body.remainingRefsCount() == 0) {
        var storage = lazy MidasEscrowStorage.load();
        if (storage.status == STATUS_SETTLING && (storage.settleProgress & SETTLE_BIT_TON) != 0) {
            val config = storage.config.load();
            sendTonOut(config.whaleAddress, refundableTon(storage.whaleTonDeposited));
            storage.whaleTonDeposited = 0;
            storage.save();
            maybeClose(storage);
        }
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

            // Drive STON.fi v2.2 balanced add-LP as TWO legs:
            //   1. TON leg: send native TON from the escrow balance to the
            //      router's pTON wallet; the ProxyToncoinTransfer wraps it and
            //      routes the provide_lp body to the router.
            //   2. Jetton leg: AskToTransfer the owner seed jetton from the
            //      escrow's seed wallet to the router (forwardPayload = provide_lp body).
            // The pool mints LP back to the escrow's LP wallet (received via
            // TransferNotificationForRecipient), which transitions ADDING->ACTIVE.
            storage.status = STATUS_ADDING;
            storage.settleProgress = 0;
            storage.save();

            val router = loadStonfiConfig(config).routerAddress;
            val receiver = contract.getAddress();
            val refund = contract.getAddress();
            val excess = contract.getAddress();
            val minLpOut: coins = 1; // conservative; pool mints > 1000 liquid units

            // TON leg: native TON -> router's pTON wallet (wraps + routes).
            val sc = loadStonfiConfig(config);
            val routerPtonWallet = calcAddressOfJettonWallet(
                router, sc.ptonMaster, sc.ptonWalletCode,
            );
            val routerSeedWallet = calcAddressOfJettonWallet(
                router, config.minterAddress, config.seedWalletCode,
            );
            val tonForward = makeProvideLpForwardPayload(
                routerSeedWallet, // otherTokenWallet = PLX (jetton side)
                refund, excess, receiver, minLpOut,
            );
            sendTonProvideLeg(
                routerPtonWallet,
                storage.whaleTonDeposited,
                tonForward,
            );

            // Jetton leg: seed jetton -> router (forwardPayload provides PLX).
            val seedWallet = ownSeedWallet(config);
            val jettonForward = makeProvideLpForwardPayload(
                routerPtonWallet, // otherTokenWallet = pTON (TON side)
                refund, excess, receiver, minLpOut,
            );
            sendJettonProvideLeg(seedWallet, router, storage.ownerJettonDeposited, jettonForward);
        }

        ClaimAfterUnlock => {
            var storage = lazy MidasEscrowStorage.load();
            val config = storage.config.load();
            assert (storage.status == STATUS_ACTIVE) throw Errors.InvalidOp;
            assert (blockchain.now() >= storage.lockUntil) throw Errors.NothingToClaim;
            assert (
                in.senderAddress == config.whaleAddress ||
                in.senderAddress == config.ownerAddress ||
                in.senderAddress == config.adminMultisig.load()
            ) throw Errors.NotOwner;

            // Burn LP to release the underlying pTON + PLX. The LP jetton wallet
            // burns and notifies the pool; the pool routes the router pay_to so
            // the refund lands at the escrow's pTON & seed wallets. Each refund
            // TransferNotificationForRecipient in STATUS_SETTLING completes one
            // leg (see handleSettlementLeg).
            storage.status = STATUS_SETTLING;
            storage.settleProgress = 0;
            storage.save();
            burnLp(ownLpWallet(config), storage.lpHeld, msg.queryId);
        }

        RefundTimeout => {
            var storage = lazy MidasEscrowStorage.load();
            val config = storage.config.load();
            assert (storage.status == STATUS_FUNDED) throw Errors.InvalidOp;
            assert (blockchain.now() >= storage.proposalDeadline) throw Errors.NothingToClaim;

            sendTonOut(config.whaleAddress, refundableTon(storage.whaleTonDeposited));
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
            assert (
                storage.status == STATUS_PROPOSED ||
                storage.status == STATUS_FUNDED ||
                storage.status == STATUS_ADDING
            ) throw Errors.InvalidOp;

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

            val incomingAmount = msg.jettonAmount;
            if (incomingAmount == 0) {
                return;
            }

            val seedWallet = ownSeedWallet(config);
            val lpWallet = ownLpWallet(config);
            val ptonWallet = ownPtonWallet(config);

            // Branch 1: LP received from our own LP jetton wallet (add-LP mint).
            if (in.senderAddress == lpWallet) {
                assert (storage.status == STATUS_ADDING) throw Errors.InvalidOp;
                storage.lpHeld += incomingAmount;
                storage.status = STATUS_ACTIVE;
                storage.lockUntil = blockchain.now() + termDurationFor(storage.termType);
                storage.save();
                return;
            }

            // Branch 2: settlement callback from the router after LP burn. The
            // router pays pTON (TON side) to our pTON wallet and PLX (jetton side)
            // to our seed wallet.
            if (storage.status == STATUS_SETTLING) {
                handleSettlementLeg(storage, config, in.senderAddress, incomingAmount);
                return;
            }

            // Branch 3: owner seed-jetton deposit (from our own seed wallet).
            assert (in.senderAddress == seedWallet) throw Errors.NotValidWallet;
            assert (storage.status == STATUS_FUNDED) throw Errors.InvalidOp;
            val (op, isValid) = parseDepositOp(msg.forwardPayload);
            assert (isValid && op == MIDAS_OWNER_DEPOSIT_OP) throw Errors.InvalidOp;
            assert (msg.transferInitiator! == config.ownerAddress) throw Errors.NotOwner;
            storage.ownerJettonDeposited += incomingAmount;
            storage.save();
        }

        TopUpTons => {}
    }
}

// Handle a settlement refund leg received from the router after LP burn.
//   - pTON from the escrow's pTON wallet -> unwrap to native TON, send to whale.
//   - PLX from the escrow's seed wallet    -> send to owner.
// Each leg is single-flight (settleProgress bitmask). When both legs are done,
// the escrow closes. This is the only path that can set STATUS_CLOSED.
fun handleSettlementLeg(
    storage: MidasEscrowStorage,
    config: MidasEscrowConfig,
    sender: address,
    incomingAmount: coins,
) {
    val seedWallet = ownSeedWallet(config);
    val ptonWallet = ownPtonWallet(config);

    if (sender == ptonWallet) {
        // TON side returned as pTON. Unwrap: send a ProxyToncoinTransfer to the
        // escrow's own pTON wallet, which routes to the pTON master and mints the
        // native TON back to this escrow (arrives as a bodyless TON message).
        // Mark the TON leg settled; the actual native-TON refund to the whale
        // happens when that native TON arrives (handled at the top of
        // onInternalMessage).
        assert ((storage.settleProgress & SETTLE_BIT_TON) == 0) throw Errors.InvalidOp;
        storage.settleProgress = storage.settleProgress | SETTLE_BIT_TON;
        storage.whaleTonDeposited = incomingAmount;
        storage.save();
        unwrapPton(ptonWallet, storage.whaleTonDeposited, 0);
        return;
    }

    if (sender == seedWallet) {
        // Jetton side returned as PLX. Send it to the owner; mark leg settled.
        assert ((storage.settleProgress & SETTLE_BIT_JETTON) == 0) throw Errors.InvalidOp;
        storage.settleProgress = storage.settleProgress | SETTLE_BIT_JETTON;
        storage.save();
        sendJettonOut(seedWallet, config.ownerAddress, incomingAmount, 0);
        maybeClose(storage);
        return;
    }

    throw Errors.NotValidWallet;
}

// If both settlement legs are marked done, set STATUS_CLOSED and zero balances.
fun maybeClose(storage: MidasEscrowStorage) {
    if (storage.settleProgress == (SETTLE_BIT_TON | SETTLE_BIT_JETTON)) {
        storage.status = STATUS_CLOSED;
        storage.lpHeld = 0;
        storage.ownerJettonDeposited = 0;
        storage.whaleTonDeposited = 0;
        storage.save();
    }
}

// Send the TON provide-liquidity leg: native TON -> the router's pTON wallet.
// The ProxyToncoinTransfer wraps the TON into pTON and forwards the provide_lp
// body to the router. The router routes to the pool; LP is minted to receiver.
fun sendTonProvideLeg(
    routerPtonWallet: address,
    tonAmount: coins,
    forwardPayload: cell,
) {
    val outMsg = createMessage({
        bounce: BounceMode.NoBounce,
        dest: routerPtonWallet,
        value: MIDAS_ADD_LP_TON_LEG_NANO + tonAmount,
        body: ProxyToncoinTransfer {
            queryId: 0,
            tonAmount,
            refundAddress: contract.getAddress(),
            forwardPayload,
        },
    });
    outMsg.send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_BOUNCE_ON_ACTION_FAIL);
}

// Send one jetton provide-liquidity leg: AskToTransfer from the escrow's own
// jetton wallet with the v2.2 provide_lp body as forwardPayload.
fun sendJettonProvideLeg(
    jettonWallet: address,
    router: address,
    amount: coins,
    forwardPayload: cell,
) {
    val outMsg = createMessage({
        bounce: BounceMode.Only256BitsOfBody,
        dest: jettonWallet,
        value: MIDAS_ADD_LP_JETTON_LEG_NANO,
        body: AskToTransfer {
            queryId: 0,
            jettonAmount: amount,
            transferRecipient: router,
            sendExcessesTo: contract.getAddress(),
            customPayload: null,
            forwardTonAmount: MIDAS_ADD_LP_JETTON_LEG_NANO - MIDAS_TRANSFER_VALUE,
            forwardPayload: beginCell().storeRef(forwardPayload).endCell().beginParse(),
        },
    });
    outMsg.send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_BOUNCE_ON_ACTION_FAIL);
}

// Send the STON.fi v2.2 burn request to the escrow's LP wallet. The LP jetton
// wallet burns (AskToBurn) and notifies the pool; the pool routes the router
// pay_to to return pTON + PLX to the escrow's pTON and seed wallets.
fun burnLp(
    lpWallet: address,
    amount: coins,
    queryId: uint64,
) {
    val outMsg = createMessage({
        bounce: BounceMode.Only256BitsOfBody,
        dest: lpWallet,
        value: MIDAS_TRANSFER_VALUE,
        body: AskToBurn {
            queryId,
            jettonAmount: amount,
            sendExcessesTo: contract.getAddress(),
            customPayload: null,
        },
    });
    outMsg.send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_BOUNCE_ON_ACTION_FAIL);
}

// Unwrap pTON back to native TON. We hold pTON in our own pTON wallet after the
// LP-burn refund; send a ProxyToncoinTransfer to that wallet, which routes to
// the pTON master and mints native TON back to refundAddress (the escrow). The
// resulting native TON arrives as a bodyless TON message (handled at the top of
// onInternalMessage) and is forwarded to the whale.
fun unwrapPton(
    ptonWallet: address,
    amount: coins,
    queryId: uint64,
) {
    val outMsg = createMessage({
        bounce: BounceMode.NoBounce,
        dest: ptonWallet,
        value: MIDAS_PTON_UNWRAP_VALUE,
        body: ProxyToncoinTransfer {
            queryId,
            tonAmount: amount,
            refundAddress: contract.getAddress(),
            forwardPayload: null,
        },
    });
    outMsg.send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_BOUNCE_ON_ACTION_FAIL);
}

get fun get_escrow_data(): (uint8, uint8, coins, coins, coins, uint32, uint32, uint8) {
    val storage = MidasEscrowStorage.load();
    return (
        storage.status,
        storage.termType,
        storage.whaleTonDeposited,
        storage.ownerJettonDeposited,
        storage.lpHeld,
        storage.lockUntil,
        storage.proposalDeadline,
        storage.settleProgress,
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
