import "errors"
import "jetton-utils"
import "messages"

// Midas Hand non-custodial LP escrow — one instance per deal.
//
// Holds whale TON + owner seed jetton, then (on owner approve) drives a balanced
// add-liquidity fully on-chain on ONE of two DEXes (chosen at deploy time by
// `config.dexType`), holds the minted LP, time-locks, and on settlement burns
// the LP and redistributes principal.
//
//   * STON.fi v2.2 — TON side is the pTON jetton, so settlement receives pTON
//     and unwraps it to native TON before paying the whale.
//   * DeDust v2    — TON side is native TON held by the native vault, so the
//     payout arrives as a bodyless TON message: no unwrap step exists.
//
// DeDust layout is pinned from mainnet chain data, not from documentation: the
// docs page and @dedust/sdk@0.8.7 disagree about `deposit_liquidity`, and the
// chain shows the SDK is right (target balances live in a ref). See
// toolkit-staging/docs/DEDUST-V2-LP-LAYOUT.md.
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
// === State machine (STON.fi v2.2 and DeDust v2) ===
//   PROPOSED --DepositTon(whale)--> FUNDED
//   FUNDED --(owner jetton)---- ApproveByOwner --> ADDING (2-leg add-LP in flight)
//   ADDING --(LP via own LP wallet)--------------> ACTIVE (locked)
//   ACTIVE --lock<=now --ClaimAfterUnlock--------> SETTLING (burn LP in flight)
//   SETTLING --(TON side + jetton side refunded)--> CLOSED
//   ADDING/ACTIVE --CancelDedustDeposit (DeDust)-> FUNDED (parked deposit recovered)
//   FUNDED   --RefundTimeout---------------------> REFUNDED
//   PROPOSED/FUNDED --Cancel(admin)--------------> CANCELLED
//
// ADDING is deliberately NOT cancellable by the admin on DeDust: a lone leg sits
// in a LiquidityDeposit contract, so paying the whale from the escrow balance
// first would refund money that is not there yet. The admin must run
// CancelDedustDeposit after the deadline and only then cancel. On STON.fi the
// admin cancel remains immediate, as before. A cancel_deposit refund can also
// arrive after the deal went ACTIVE (partial fill), and is then credited to the
// whale TON / owner jetton bucket so the final distribution stays whole.
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
// === DeDust v2 add/remove LP semantics (pinned from chain data + sdk 0.8.7) ===
// Balanced two-leg deposit (both legs must carry identical target balances):
//   * Native leg: deposit_liquidity#d55e4686 to the native vault. `amount` is
//     the TON being provided and `asset0_target_balance` equals that same
//     amount; min_lp_amount and both target balances sit in ONE ref; two
//     trailing Maybe bits are the fulfill/reject payloads (both null).
//   * Jetton leg: a standard jetton transfer to the jetton vault whose forward
//     payload is deposit_liquidity#40e108d6 with pool_params inline (native
//     asset first, seed jetton second) and no query id.
// The vault parks a lone leg in a LiquidityDeposit contract until both legs
// arrive, so a failed leg MUST be recovered with cancel_deposit#166cedee.
// Removal is a plain LP jetton burn: the pool pays the assets back to its owner
// (native TON bodyless, seed jetton to the escrow's seed wallet).
//
// Config cell must stay under 1023 bits and 4 refs. Dynamic addresses are
// wrapped in Cell<address>; the seed wallet code, the admin multisig and the
// single active DEX config (the other one is null, costing zero refs) fit.

contract MidasHandEscrow {
    author: "Phalanx Foundation"
    version: "1.3.0"
    description: "Midas Hand non-custodial LP escrow — one instance per deal. Holds whale TON + owner jetton, drives balanced add-LP on-chain on STON.fi v2.2 or DeDust v2, time-locks, and settles per code rules."
    storage: MidasEscrowStorage
    incomingMessages: AllowedMessageToMidasEscrow
}

// === DEX selector ===
const DEX_STONFI: uint8 = 0
const DEX_DEDUST: uint8 = 1

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

// === DeDust v2 op codes and gas (pinned from chain data + @dedust/sdk@0.8.7) ===
const DEDUST_DEPOSIT_NATIVE_OP: uint32 = 0xD55E4686     // native vault deposit_liquidity
const DEDUST_DEPOSIT_JETTON_OP: uint32 = 0x40E108D6     // jetton vault deposit_liquidity forward payload
const DEDUST_CANCEL_DEPOSIT_OP: uint32 = 0x166CEDEE     // LiquidityDeposit.cancel_deposit
const DEDUST_NATIVE_TAG: uint4 = 0b0000                 // Asset = native
const DEDUST_JETTON_TAG: uint4 = 0b0001                 // Asset = jetton$0001 wc hash
// Chain-verified: the native vault leg carries amount + 0.3 TON, and the
// LiquidityDeposit cancel costs 0.5 TON. Both fit the 0.6 TON per-leg budget.
const DEDUST_NATIVE_VAULT_GAS: coins = 300000000        // 0.3 TON
const DEDUST_CANCEL_GAS: coins = 500000000              // 0.5 TON
const DEDUST_JETTON_FORWARD_GAS: coins = 400000000      // 0.4 TON forward to the jetton vault
// A DeDust deposit parks in LiquidityDeposit until both legs land. If the
// second leg never lands, anyone allowed may recover the parked funds after
// this window, then refund through the normal FUNDED paths.
const DEDUST_DEPOSIT_DEADLINE_SEC: uint32 = 3600        // 1 hour

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
    dexType: uint8                 // DEX_STONFI | DEX_DEDUST — exactly one deal, one DEX
    // Exactly one of the two DEX configs is set. The other stays null, so it
    // costs one bit instead of a ref and the main config keeps 3 refs total.
    stonfi: Cell<StonFiConfig>?
    dedust: Cell<DedustConfig>?
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
struct DedustConfig {
    poolAddress: address            // LP jetton minter = the DeDust pool
    // The LiquidityDeposit account that parks this escrow's deposit legs. Its
    // address is derived from the depositor, which is this escrow, so it CANNOT
    // be part of the deploy config: the escrow address is the hash of that very
    // config (circular, proven in .verify/dedust-ld-address-probe.cjs). The
    // deploy script therefore leaves it null and the admin binds it once, right
    // after deploy, from the DeDust factory get-method
    // `get_liquidity_deposit_address(escrow, poolType, assets)`.
    liquidityDeposit: address?
    nativeVault: Cell<address>      // factory native vault (TON leg destination)
    jettonVault: Cell<address>      // factory jetton vault for the seed jetton
    lpWalletCode: cell              // pool's LP jetton wallet code (own LP-wallet verify)
    stablePool: bool                // PoolType: false = volatile (the only supported pool)
}

// DeDust deposit target balances. Chain data shows the native vault reads these
// from ONE ref, never inline, which is what @dedust/sdk@0.8.7 writes.
@overflow1023_policy("suppress")
struct DedustTargets {
    minLpAmount: coins
    asset0TargetBalance: coins
    asset1TargetBalance: coins
}

// DeDust native vault `deposit_liquidity#d55e4686`.
// Pool params are pinned to the chain-verified canonical order for a TON/jetton
// volatile pool: asset0 = native TON, asset1 = the seed jetton. A pool whose
// factory order differs is rejected at config time by the API rather than
// risking a deposit into a pool address that does not exist.
@overflow1023_policy("suppress")
struct (0xD55E4686) DedustNativeDepositLiquidity {
    queryId: uint64
    amount: coins
    stablePool: bool                    // PoolType (1 bit)
    asset0Tag: uint4                    // DEDUST_NATIVE_TAG
    asset1Tag: uint4                    // DEDUST_JETTON_TAG
    jettonWorkchain: int8
    jettonHash: uint256
    targets: Cell<DedustTargets>
    fulfillPayload: cell?
    rejectPayload: cell?
}

// DeDust jetton vault `deposit_liquidity#40e108d6`, attached as the forward
// payload of an AskToTransfer to the jetton vault. No query id: it lives in the
// wrapping jetton transfer. Pool params are inline, as both the DeDust TL-B docs
// and the SDK agree for this side.
@overflow1023_policy("suppress")
struct (0x40E108D6) DedustJettonDepositLiquidity {
    stablePool: bool                    // PoolType (1 bit)
    asset0Tag: uint4                    // DEDUST_NATIVE_TAG
    asset1Tag: uint4                    // DEDUST_JETTON_TAG
    jettonWorkchain: int8
    jettonHash: uint256
    minLpAmount: coins
    asset0TargetBalance: coins
    asset1TargetBalance: coins
    fulfillPayload: cell?
    rejectPayload: cell?
}

// LiquidityDeposit.cancel_deposit#166cedee — the only way to recover a deposit
// leg that was parked because the matching leg never arrived.
struct (0x166CEDEE) DedustCancelDeposit {
    queryId: uint64
    payload: cell?
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
    depositDeadline: uint32 // DeDust only: when a parked deposit may be recovered
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

// Bind the DeDust LiquidityDeposit address once, right after deploy, from the
// factory get-method. The escrow address is the hash of its config and the
// LiquidityDeposit address is derived from the escrow address, so the value
// cannot be known before the escrow exists. Admin-only, and frozen as soon as a
// deposit leg is in flight (see the handler), so a compromised admin cannot
// redirect a live recovery.
struct (0x4d484537) BindDedustLiquidityDeposit {
    queryId: uint64
    liquidityDeposit: address
}

// Recover a DeDust deposit leg parked in the pool's LiquidityDeposit contract
// because the matching leg never arrived. Allowed only after depositDeadline.
struct (0x4d484536) CancelDedustDeposit {
    queryId: uint64
}

type AllowedMessageToMidasEscrow =
    | DepositTon
    | ApproveByOwner
    | ClaimAfterUnlock
    | RefundTimeout
    | Cancel
    | CancelDedustDeposit
    | BindDedustLiquidityDeposit
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

fun isDedust(config: MidasEscrowConfig): bool {
    return config.dexType == DEX_DEDUST;
}

// The active DEX wallet set. LP custody is verified against the escrow's OWN LP
// wallet on both DEXes; only the minter (pool) and the wallet code differ.
fun ownLpWallet(config: MidasEscrowConfig): address {
    if (isDedust(config)) {
        val dc = config.dedust!.load();
        return calcAddressOfJettonWallet(contract.getAddress(), dc.poolAddress, dc.lpWalletCode);
    }
    val sc = config.stonfi!.load();
    return calcAddressOfJettonWallet(contract.getAddress(), sc.poolAddress, sc.lpWalletCode);
}

// pTON only exists on the STON.fi rail. Never call this on a DeDust escrow.
fun ownPtonWallet(config: MidasEscrowConfig): address {
    val sc = config.stonfi!.load();
    return calcAddressOfJettonWallet(contract.getAddress(), sc.ptonMaster, sc.ptonWalletCode);
}

fun loadStonfiConfig(config: MidasEscrowConfig): StonFiConfig {
    return config.stonfi!.load();
}

fun loadDedustConfig(config: MidasEscrowConfig): DedustConfig {
    return config.dedust!.load();
}

// Rebuild the DeDust config with a bound LiquidityDeposit address, keeping every
// other field of the escrow config untouched. Used once per DeDust deal by
// BindDedustLiquidityDeposit, before any deposit leg is dispatched.
fun withDedustLiquidityDeposit(
    config: MidasEscrowConfig,
    liquidityDeposit: address,
): MidasEscrowConfig {
    val dc = loadDedustConfig(config);
    val updated: DedustConfig = {
        poolAddress: dc.poolAddress,
        liquidityDeposit,
        nativeVault: dc.nativeVault,
        jettonVault: dc.jettonVault,
        lpWalletCode: dc.lpWalletCode,
        stablePool: dc.stablePool,
    };
    return MidasEscrowConfig {
        whaleAddress: config.whaleAddress,
        ownerAddress: config.ownerAddress,
        minterAddress: config.minterAddress,
        seedWalletCode: config.seedWalletCode,
        adminMultisig: config.adminMultisig,
        proposalTimeoutSec: config.proposalTimeoutSec,
        dexType: config.dexType,
        stonfi: config.stonfi,
        dedust: updated.toCell(),
    };
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
// A bounced DeDust native-vault leg returns the TON and steps ADDING back to
// FUNDED so the normal refund paths can pay it out.
fun onBouncedMessage(in: InMessageBounced) {
    in.bouncedBody.skipBouncedPrefix();
    if (in.bouncedBody.remainingBitsCount() < 32) {
        return;
    }
    val op = in.bouncedBody.loadUint(32);

    if (op == DEDUST_DEPOSIT_NATIVE_OP) {
        var storage = lazy MidasEscrowStorage.load();
        if (storage.status == STATUS_ADDING) {
            storage.status = STATUS_FUNDED;
        }
        storage.whaleTonDeposited += in.valueCoins;
        storage.save();
        return;
    }

    // A bounced JettonTransfer (0x0f8a7ea5) or AskToBurn (0x595f07bc). The
    // bounced body mirrors the original: op(32) queryId(64) amount(coins).
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
    // A bodyless TON message is never a protocol command. Three cases matter:
    //   * DeDust settlement: the pool pays the TON side as native TON, so this
    //     message IS the whale refund, with no unwrap step in between.
    //   * STON.fi settlement: it is the native TON minted by the pTON master
    //     after the escrow's own unwrap request, so the TON leg is already
    //     marked settled and the whale is paid now.
    //   * DeDust recovery: a cancel_deposit refund returns the parked TON, which
    //     is credited back so the normal refund paths can pay it out.
    if (in.body.remainingBitsCount() == 0 && in.body.remainingRefsCount() == 0) {
        var storage = lazy MidasEscrowStorage.load();
        val config = storage.config.load();
        if (storage.status == STATUS_SETTLING) {
            if (isDedust(config)) {
                // The DeDust pool pays the TON side back as native TON. Any TON
                // credited earlier (a parked leftover returned by cancel_deposit)
                // is added on top so the whale receives everything in one payout.
                if ((storage.settleProgress & SETTLE_BIT_TON) == 0) {
                    storage.settleProgress = storage.settleProgress | SETTLE_BIT_TON;
                    storage.whaleTonDeposited += in.valueCoins;
                    storage.save();
                    sendTonOut(config.whaleAddress, refundableTon(storage.whaleTonDeposited));
                    storage.whaleTonDeposited = 0;
                    storage.save();
                    maybeClose(storage);
                }
            } else if ((storage.settleProgress & SETTLE_BIT_TON) != 0) {
                sendTonOut(config.whaleAddress, refundableTon(storage.whaleTonDeposited));
                storage.whaleTonDeposited = 0;
                storage.save();
                maybeClose(storage);
            }
            return;
        }
        // DeDust only: credit refunded native TON (cancel_deposit recovery, or a
        // stray transfer) into the whale bucket while the deal is not settling.
        if (
            isDedust(config) &&
            (storage.status == STATUS_FUNDED ||
                storage.status == STATUS_ADDING ||
                storage.status == STATUS_ACTIVE)
        ) {
            storage.whaleTonDeposited += in.valueCoins;
            storage.save();
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

            storage.status = STATUS_ADDING;
            storage.settleProgress = 0;
            if (isDedust(config)) {
                // Fail closed: a DeDust deposit parks a lone leg in the pool's
                // LiquidityDeposit account, and that account is only reachable
                // through the address bound right after deploy. Approving before
                // the bind would let the whale's TON park with no way back, so
                // the approve itself requires the recovery path to exist.
                assert (loadDedustConfig(config).liquidityDeposit != null) throw Errors.InvalidOp;
                // DeDust parks a lone leg in a LiquidityDeposit contract until the
                // matching leg arrives, so stamp the recovery deadline now: after
                // it passes, CancelDedustDeposit may pull the parked funds back.
                storage.depositDeadline = blockchain.now() + DEDUST_DEPOSIT_DEADLINE_SEC;
                // Both principals physically leave the escrow with the two deposit
                // legs, so the buckets are zeroed here and every leg that comes
                // back is credited with the amount that actually arrives: a bounced
                // native leg, a cancel_deposit recovery (bodyless TON here plus the
                // seed jetton in the notification branch), and the settlement
                // payout each add to their own bucket. Keeping the principals
                // recorded while the legs are out would double-count them against
                // the pool payout (or against a recovered parked leg).
                val tonLegAmount = storage.whaleTonDeposited;
                val jettonLegAmount = storage.ownerJettonDeposited;
                storage.whaleTonDeposited = 0;
                storage.ownerJettonDeposited = 0;
                storage.save();
                startDedustAddLiquidity(storage, config, tonLegAmount, jettonLegAmount);
            } else {
                storage.depositDeadline = 0;
                storage.save();
                startStonfiAddLiquidity(storage, config);
            }
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

            // Burn LP to release the underlying assets. On STON.fi the LP jetton
            // wallet burns and the pool routes the router pay_to so pTON (TON
            // side) lands at the escrow's pTON wallet and PLX at the seed wallet,
            // then the pTON is unwrapped to native TON. On DeDust the pool pays
            // native TON straight back (bodyless) plus the seed jetton. Each
            // refund completes one leg (see handleSettlementLeg).
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
            // On DeDust, a lone leg sits in a LiquidityDeposit contract, so paying
            // the whale from the escrow balance during ADDING would refund money
            // that is not there yet. The admin must run CancelDedustDeposit after
            // the deposit deadline first, then cancel.
            assert (!(isDedust(config) && storage.status == STATUS_ADDING)) throw Errors.InvalidOp;
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

        BindDedustLiquidityDeposit => {
            var storage = lazy MidasEscrowStorage.load();
            val config = storage.config.load();
            assert (isDedust(config)) throw Errors.InvalidOp;
            assert (in.senderAddress == config.adminMultisig.load()) throw Errors.NotOwner;
            // Only the window in which no deposit leg is in flight: PROPOSED
            // (deployed, not funded yet) and FUNDED (funded, owner has not
            // approved). From ADDING on, the address is frozen so a compromised
            // admin cannot point a live recovery at some other account.
            assert (
                storage.status == STATUS_PROPOSED ||
                storage.status == STATUS_FUNDED
            ) throw Errors.InvalidOp;

            storage.config = withDedustLiquidityDeposit(config, msg.liquidityDeposit).toCell();
            storage.save();
        }

        CancelDedustDeposit => {
            var storage = lazy MidasEscrowStorage.load();
            val config = storage.config.load();
            assert (isDedust(config)) throw Errors.InvalidOp;
            val dc = loadDedustConfig(config);
            // The approve gate already refused an unbound config, so a missing
            // address here means the state is inconsistent; refuse rather than
            // send cancel_deposit into the void.
            assert (dc.liquidityDeposit != null) throw Errors.InvalidOp;
            assert (
                in.senderAddress == config.whaleAddress ||
                in.senderAddress == config.ownerAddress ||
                in.senderAddress == config.adminMultisig.load()
            ) throw Errors.NotOwner;
            assert (
                storage.status == STATUS_ADDING ||
                storage.status == STATUS_FUNDED ||
                storage.status == STATUS_ACTIVE
            ) throw Errors.InvalidOp;
            // depositDeadline doubles as the "recovery not requested yet" guard:
            // it is zero before approve and is zeroed when the cancel is sent, so
            // the parked deposit can never be claimed twice.
            assert (storage.depositDeadline != 0) throw Errors.InvalidOp;
            assert (blockchain.now() >= storage.depositDeadline) throw Errors.NothingToClaim;

            // Back to FUNDED so the refund paths can pay out once the vault
            // returns the parked assets. If the deposit was only partly matched,
            // the LP still arrives and flips the deal to ACTIVE (branch 1 accepts
            // DeDust FUNDED too).
            if (storage.status == STATUS_ADDING) {
                storage.status = STATUS_FUNDED;
            }
            storage.depositDeadline = 0;
            storage.save();
            sendDedustCancelDeposit(dc.liquidityDeposit!, msg.queryId);
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

            // Branch 1: LP received from our own LP jetton wallet (add-LP mint).
            if (in.senderAddress == lpWallet) {
                // DeDust recovery can step ADDING back to FUNDED while the pool is
                // still matching a partly filled deposit, so accept both statuses.
                assert (
                    storage.status == STATUS_ADDING ||
                    (isDedust(config) && storage.status == STATUS_FUNDED)
                ) throw Errors.InvalidOp;
                storage.lpHeld += incomingAmount;
                storage.status = STATUS_ACTIVE;
                storage.lockUntil = blockchain.now() + termDurationFor(storage.termType);
                storage.save();
                return;
            }

            // Branch 2: settlement callback from the DEX after LP burn. On
            // STON.fi the router pays pTON (TON side) to our pTON wallet and PLX
            // (jetton side) to our seed wallet; on DeDust only the seed jetton
            // arrives here (native TON comes as a bodyless message).
            if (storage.status == STATUS_SETTLING) {
                handleSettlementLeg(storage, config, in.senderAddress, incomingAmount);
                return;
            }

            // Branch 3: seed-jetton arrival from our own seed wallet.
            assert (in.senderAddress == seedWallet) throw Errors.NotValidWallet;
            if (isDedust(config)) {
                // DeDust returns the jetton leg of a cancelled/parked deposit
                // straight to the escrow's seed wallet. Credit it so the owner is
                // made whole at settlement or refund.
                storage.ownerJettonDeposited += incomingAmount;
                storage.save();
                return;
            }
            // STON.fi owner seed-jetton deposit: only the configured owner, with
            // the MIDAS forward op, and only while FUNDED.
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

// Handle a settlement refund leg received from the DEX after LP burn.
//   * STON.fi: pTON from the escrow's pTON wallet -> unwrap to native TON, then
//     send to the whale; PLX from the escrow's seed wallet -> send to the owner.
//   * DeDust:  native TON arrives as a bodyless message (handled at the top of
//     onInternalMessage); only the seed-jetton leg lands here.
// Each leg is single-flight (settleProgress bitmask). When both legs are done,
// the escrow closes. This is the only path that can set STATUS_CLOSED.
fun handleSettlementLeg(
    storage: MidasEscrowStorage,
    config: MidasEscrowConfig,
    sender: address,
    incomingAmount: coins,
) {
    val seedWallet = ownSeedWallet(config);

    if (isDedust(config)) {
        // DeDust has no pTON: only the seed-jetton leg can arrive here.
        assert (sender == seedWallet) throw Errors.NotValidWallet;
        assert ((storage.settleProgress & SETTLE_BIT_JETTON) == 0) throw Errors.InvalidOp;
        storage.settleProgress = storage.settleProgress | SETTLE_BIT_JETTON;
        storage.save();
        sendJettonOut(seedWallet, config.ownerAddress, incomingAmount, 0);
        maybeClose(storage);
        return;
    }

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

// Drive STON.fi v2.2 balanced add-LP as TWO legs:
//   1. TON leg: send native TON from the escrow balance to the router's pTON
//      wallet; the ProxyToncoinTransfer wraps it and routes the provide_lp body
//      to the router.
//   2. Jetton leg: AskToTransfer the owner seed jetton from the escrow's seed
//      wallet to the router (forwardPayload = provide_lp body).
// The pool mints LP back to the escrow's LP wallet (received via
// TransferNotificationForRecipient), which transitions ADDING -> ACTIVE.
fun startStonfiAddLiquidity(storage: MidasEscrowStorage, config: MidasEscrowConfig) {
    val sc = loadStonfiConfig(config);
    val router = sc.routerAddress;
    val receiver = contract.getAddress();
    val refund = contract.getAddress();
    val excess = contract.getAddress();
    val minLpOut: coins = 1; // conservative; pool mints > 1000 liquid units

    // TON leg: native TON -> router's pTON wallet (wraps + routes).
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
    val jettonForward = makeProvideLpForwardPayload(
        routerPtonWallet, // otherTokenWallet = pTON (TON side)
        refund, excess, receiver, minLpOut,
    );
    sendJettonProvideLeg(
        ownSeedWallet(config),
        router,
        storage.ownerJettonDeposited,
        jettonForward,
    );
}

// Drive DeDust v2 balanced add-LP as TWO legs, both declaring the SAME targets:
//   1. Native leg: native TON to the factory's native vault.
//   2. Jetton leg: seed jetton transfer to the factory's jetton vault with the
//      deposit_liquidity forward payload.
// The vault parks a lone leg until the matching leg lands, then the pool mints
// LP to the escrow's LP wallet (ADDING -> ACTIVE).
fun startDedustAddLiquidity(
    storage: MidasEscrowStorage,
    config: MidasEscrowConfig,
    tonAmount: coins,
    jettonAmount: coins,
) {
    val dc = loadDedustConfig(config);
    val (minterWorkchain, minterHash) = config.minterAddress.getWorkchainAndHash();
    val targets = makeDedustTargets(
        1,
        tonAmount,
        jettonAmount,
    );
    sendDedustNativeProvideLeg(
        dc,
        tonAmount,
        targets,
        minterWorkchain,
        minterHash,
    );
    sendDedustJettonProvideLeg(
        ownSeedWallet(config),
        dc.jettonVault.load(),
        jettonAmount,
        dc.stablePool,
        minterWorkchain,
        minterHash,
        targets,
    );
}

// Build the shared DeDust target-balance ref. Both legs of one balanced deposit
// MUST carry identical targets. Chain data shows real clients declare
// `target_i == the amount they are providing`, NOT `reserve_i + amount`: a second
// deposit of 0.1 TON into the same pool minutes after a 199.9 TON deposit still
// declared exactly 0.1 TON (proof: .verify/dedust-target-probe.cjs).
fun makeDedustTargets(
    minLpAmount: coins,
    tonAmount: coins,
    jettonAmount: coins,
): Cell<DedustTargets> {
    val targets: DedustTargets = {
        minLpAmount,
        asset0TargetBalance: tonAmount,
        asset1TargetBalance: jettonAmount,
    };
    return targets.toCell();
}

// STON.fi TON leg: native TON -> the router's pTON wallet. The
// ProxyToncoinTransfer wraps the TON into pTON and forwards the provide_lp
// body to the router; the router routes to the pool and LP is minted.
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

// DeDust native-vault leg. Value must be the provided amount plus 0.3 TON of
// vault gas (chain-verified), so the escrow balance must exceed the principal.
fun sendDedustNativeProvideLeg(
    dc: DedustConfig,
    tonAmount: coins,
    targets: Cell<DedustTargets>,
    jettonWorkchain: int8,
    jettonHash: uint256,
) {
    val outMsg = createMessage({
        bounce: BounceMode.Only256BitsOfBody,
        dest: dc.nativeVault.load(),
        value: DEDUST_NATIVE_VAULT_GAS + tonAmount,
        body: DedustNativeDepositLiquidity {
            queryId: 0,
            amount: tonAmount,
            stablePool: dc.stablePool,
            asset0Tag: DEDUST_NATIVE_TAG,
            asset1Tag: DEDUST_JETTON_TAG,
            jettonWorkchain,
            jettonHash,
            targets,
            fulfillPayload: null,
            rejectPayload: null,
        },
    });
    outMsg.send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_BOUNCE_ON_ACTION_FAIL);
}

// DeDust jetton-vault leg: transfer the seed jetton to the jetton vault with
// deposit_liquidity#40e108d6 as the forward payload (pool params inline, no
// query id in the payload, and the forward payload always sits in a ref).
//
// The ref MUST be tagged the TEP-74 way, `either$1` = one `1` bit then the ref.
// Both the DeDust and the STON.fi SDK build it with `storeMaybeRef` (see
// @dedust/sdk JettonWallet.sendTransfer and @ston-fi/sdk
// createJettonTransferMessage), and our own JettonWallet enforces the same shape
// in `checkIsCorrectTlbEither`: a bare ref with zero bits throws cell underflow
// (exit 9) before the leg is ever delivered, so a tag-less ref is a dead leg.
fun sendDedustJettonProvideLeg(
    jettonWallet: address,
    jettonVault: address,
    amount: coins,
    stablePool: bool,
    jettonWorkchain: int8,
    jettonHash: uint256,
    targets: Cell<DedustTargets>,
) {
    val t = targets.load();
    val payload = DedustJettonDepositLiquidity {
        stablePool,
        asset0Tag: DEDUST_NATIVE_TAG,
        asset1Tag: DEDUST_JETTON_TAG,
        jettonWorkchain,
        jettonHash,
        minLpAmount: t.minLpAmount,
        asset0TargetBalance: t.asset0TargetBalance,
        asset1TargetBalance: t.asset1TargetBalance,
        fulfillPayload: null,
        rejectPayload: null,
    };
    val outMsg = createMessage({
        bounce: BounceMode.Only256BitsOfBody,
        dest: jettonWallet,
        value: MIDAS_ADD_LP_JETTON_LEG_NANO,
        body: AskToTransfer {
            queryId: 0,
            jettonAmount: amount,
            transferRecipient: jettonVault,
            sendExcessesTo: contract.getAddress(),
            customPayload: null,
            forwardTonAmount: DEDUST_JETTON_FORWARD_GAS,
            forwardPayload: beginCell().storeMaybeRef(payload.toCell()).toSlice(),
        },
    });
    outMsg.send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_BOUNCE_ON_ACTION_FAIL);
}

// Recover a DeDust deposit leg parked in the pool's LiquidityDeposit account.
// The contract refunds both parked assets to the escrow (native TON bodyless,
// jetton to the escrow's seed wallet).
fun sendDedustCancelDeposit(liquidityDeposit: address, queryId: uint64) {
    val outMsg = createMessage({
        bounce: BounceMode.Only256BitsOfBody,
        dest: liquidityDeposit,
        value: DEDUST_CANCEL_GAS,
        body: DedustCancelDeposit {
            queryId,
            payload: null,
        },
    });
    outMsg.send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_BOUNCE_ON_ACTION_FAIL);
}

// STON.fi jetton leg: AskToTransfer from the escrow's own jetton wallet with the
// v2.2 provide_lp body as forwardPayload. Same TEP-74 `either$1` tag rule as the
// DeDust leg above: `storeMaybeRef` (a bare ref makes our own JettonWallet throw
// cell underflow on `checkIsCorrectTlbEither`).
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
            forwardPayload: beginCell().storeMaybeRef(forwardPayload).toSlice(),
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

// DeDust recovery window: when a parked deposit may be pulled back. Zero means
// either "no DeDust deal" or "recovery already requested".
get fun get_deposit_deadline(): uint32 {
    val storage = MidasEscrowStorage.load();
    return storage.depositDeadline;
}

// Active DEX selector: 0 = STON.fi v2.2, 1 = DeDust v2.
get fun get_dex_type(): uint8 {
    val storage = MidasEscrowStorage.load();
    return storage.config.load().dexType;
}

// DeDust LiquidityDeposit bound to this escrow, or null before the admin binds
// it right after deploy. The API reads this to confirm the recovery path exists
// before the whale is asked to approve.
get fun get_dedust_liquidity_deposit(): address? {
    val storage = MidasEscrowStorage.load();
    if (!isDedust(storage.config.load())) {
        return null;
    }
    return loadDedustConfig(storage.config.load()).liquidityDeposit;
}

get fun get_config(): MidasEscrowConfig {
    val storage = MidasEscrowStorage.load();
    return storage.config.load();
}

get fun get_whale_share_bps(): uint16 {
    val storage = MidasEscrowStorage.load();
    return whaleShareFor(storage.termType);
}
