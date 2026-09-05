import "@acton/build"
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@acton/types/message"

import "@contracts/MidasHandEscrow"
import "@contracts/errors"
import "@contracts/messages"
import "@wrappers/JettonMinter.gen"
import "@wrappers/MidasHandEscrow.gen"
import "@wrappers/utils"

import "test-utils"

// --------------------------------------------------------------------------
// Midas Hand Escrow — Fase 2 STON.fi v2.2 integration (mock router/pool):
// full lifecycle tests for two-leg add-LP, LP receipt, time-lock, burn/settle,
// refund/cancel, and final distribution. The escrow's outbound message bodies
// (jetton leg AskToTransfer + TON leg native TON) are inspected to verify the
// pinned STON.fi v2.2 provide_lp payload. LP mint / refund are driven by the
// test acting as the mock pool & pTON minter (real JettonMinter).
// --------------------------------------------------------------------------

const ESCROW_START_TIME = 1700000000
const ESCROW_UNIT = 1000000000
const ESCROW_WHALE_TON = ton("600")        // 600 TON (>= min 500)
const ESCROW_OWNER_JETTON = 40000 * ESCROW_UNIT
const ESCROW_OWNER_DEPOSIT_OP: uint32 = 0x4d484531
const ESCROW_THREE_MONTHS: uint32 = 7776000
const ESCROW_LP_UNITS = 3000000000000      // LP units minted by the mock pool

fun makeOwnerDepositPayload(): slice {
    return beginCell().storeUint(ESCROW_OWNER_DEPOSIT_OP, 32).endCell().beginParse();
}

// Build a complete escrow config with STON.fi v2.2 wiring.
fun makeStonfiConfig(
    router: address,
    pool: JettonMinter,
    pton: JettonMinter,
    seedWalletCode: cell,
): StonFiConfig {
    return StonFiConfig {
        routerAddress: router,
        poolAddress: pool.address,
        ptonMaster: pton.address,
        lpWalletCode: build("JettonWallet"),
        ptonWalletCode: build("JettonWallet"),
    };
}

// Three jettons: PLX (seed), pTON (proxy TON), LP (pool). Plus the escrow.
fun setupEscrow(): (MidasHandEscrow, JettonMinter, JettonMinter, JettonMinter, Treasury, Treasury, Treasury, Treasury) {
    testing.setNow(ESCROW_START_TIME);
    val deployer = testing.treasury("me-deployer");
    val whale = testing.treasury("me-whale");
    val owner = testing.treasury("me-owner");
    val admin = testing.treasury("me-admin");
    val router = testing.treasury("me-router").address;

    // Seed token (PLX).
    val seedMinter = JettonMinter.fromStorage({
        totalSupply: 0,
        adminAddress: deployer.address,
        nextAdminAddress: null,
        metadata: buildTestMetadata("me-seed-token"),
    });
    expect(seedMinter.sendDeploy(deployer.address, { value: ton("10") })).toHaveSuccessfulDeploy({
        to: seedMinter.address,
    });

    // pTON proxy TON minter.
    val ptonMinter = JettonMinter.fromStorage({
        totalSupply: 0,
        adminAddress: deployer.address,
        nextAdminAddress: null,
        metadata: buildTestMetadata("me-pton"),
    });
    expect(ptonMinter.sendDeploy(deployer.address, { value: ton("10") })).toHaveSuccessfulDeploy({
        to: ptonMinter.address,
    });

    // LP minter (the pool).
    val lpMinter = JettonMinter.fromStorage({
        totalSupply: 0,
        adminAddress: deployer.address,
        nextAdminAddress: null,
        metadata: buildTestMetadata("me-lp"),
    });
    expect(lpMinter.sendDeploy(deployer.address, { value: ton("10") })).toHaveSuccessfulDeploy({
        to: lpMinter.address,
    });

    val seedWalletCode = build("JettonWallet");
    val config: MidasEscrowConfig = {
        whaleAddress: whale.address,
        ownerAddress: owner.address,
        minterAddress: seedMinter.address,
        seedWalletCode,
        adminMultisig: admin.address.toCell(),
        proposalTimeoutSec: 86400,
        stonfi: makeStonfiConfig(router, lpMinter, ptonMinter, seedWalletCode).toCell(),
    };

    val escrow = MidasHandEscrow.fromStorage({
        config: config.toCell(),
        status: 0,
        termType: 0,
        whaleTonDeposited: 0,
        ownerJettonDeposited: 0,
        lpHeld: 0,
        lockUntil: 0,
        proposalDeadline: 0,
        settleProgress: 0,
    });
    expect(escrow.deploy(deployer.address, { value: ton("5") })).toHaveSuccessfulDeploy({
        to: escrow.address,
    });

    mintTokensTo(deployer, seedMinter, owner.address, 200000 * ESCROW_UNIT);
    mintTokensTo(deployer, seedMinter, admin.address, 200000 * ESCROW_UNIT);

    return (escrow, seedMinter, ptonMinter, lpMinter, whale, owner, admin, deployer);
}

get fun `test midas-escrow: deploy in proposed state`() {
    val (escrow, _, _, _, whale, owner, admin, _) = setupEscrow();
    val (status, termType, whaleTon, ownerJetton, lpHeld, lockUntil, deadline, settleProgress) = escrow.getEscrowData();
    expect(status).toEqual(0);
    expect(termType).toEqual(0);
    expect(whaleTon).toEqual(0);
    expect(ownerJetton).toEqual(0);
    expect(lpHeld).toEqual(0);
    expect(lockUntil).toEqual(0);
    expect(deadline).toEqual(0);
    expect(settleProgress).toEqual(0);
}

get fun `test midas-escrow: whale deposits TON -> funded`() {
    val (escrow, _, _, _, whale, _, _, _) = setupEscrow();
    val deposit = escrow.sendDepositTon(
        whale.address,
        0,
        1, // 6 months
        { bounce: false, value: ESCROW_WHALE_TON },
    );
    expect(deposit).toHaveSuccessfulTx<DepositTon>({ from: whale.address, to: escrow.address });

    val (status, termType, whaleTon, _, _, _, deadline, _) = escrow.getEscrowData();
    expect(status).toEqual(1);
    expect(termType).toEqual(1);
    expect(whaleTon).toEqual(ESCROW_WHALE_TON);
    expect(deadline).toEqual(ESCROW_START_TIME + 86400);
    expect(escrow.getWhaleShareBps()).toEqual(7000);
}

get fun `test midas-escrow: non-whale deposit rejected`() {
    val (escrow, _, _, _, _, owner, _, _) = setupEscrow();
    val deposit = escrow.sendDepositTon(
        owner.address,
        0,
        0,
        { bounce: false, value: ESCROW_WHALE_TON },
    );
    expect(deposit).toHaveFailedTx<DepositTon>({
        from: owner.address,
        to: escrow.address,
        exitCode: Errors.NotOwner,
    });
}

get fun `test midas-escrow: owner jetton deposit then approve -> adding`() {
    val (escrow, seedMinter, _, _, whale, owner, _, _) = setupEscrow();
    escrow.sendDepositTon(whale.address, 0, 0, { bounce: false, value: ESCROW_WHALE_TON });

    val jettonDeposit = transferTokensTo(
        seedMinter,
        owner,
        escrow.address,
        ESCROW_OWNER_JETTON,
        makeOwnerDepositPayload(),
    );
    expect(jettonDeposit).toHaveSuccessfulTx<TransferNotificationForRecipient>({
        to: escrow.address,
    });

    val (status, _, _, ownerJetton, _, _, _, _) = escrow.getEscrowData();
    expect(status).toEqual(1);
    expect(ownerJetton).toEqual(ESCROW_OWNER_JETTON);

    val approve = escrow.sendApproveByOwner(owner.address, 0, { bounce: false, value: ton("1") });
    expect(approve).toHaveSuccessfulTx<ApproveByOwner>({ from: owner.address, to: escrow.address });

    val (status2, _, _, _, _, _, _, _) = escrow.getEscrowData();
    expect(status2).toEqual(2); // ADDING
}

get fun `test midas-escrow: non-owner jetton deposit rejected`() {
    val (escrow, seedMinter, _, _, whale, _, admin, _) = setupEscrow();
    escrow.sendDepositTon(whale.address, 0, 0, { bounce: false, value: ESCROW_WHALE_TON });
    val jettonDeposit = transferTokensTo(
        seedMinter,
        admin,
        escrow.address,
        ESCROW_OWNER_JETTON,
        makeOwnerDepositPayload(),
    );
    expect(jettonDeposit).toHaveFailedTx<TransferNotificationForRecipient>({
        to: escrow.address,
        exitCode: Errors.NotOwner,
    });
}

// Mint LP to the escrow via the mock pool (LP minter), simulating the pool's
// response to a successful two-leg add-LP. The LP wallet forwards a
// TransferNotificationForRecipient to the escrow, which must transition
// ADDING -> ACTIVE and set lockUntil.
fun receiveLpReceipt(
    escrow: MidasHandEscrow,
    lpMinter: JettonMinter,
    deployer: Treasury,
) {
    mintTo(lpMinter, deployer, escrow.address, ESCROW_LP_UNITS);
}

get fun `test midas-escrow: LP receipt -> active + lockUntil`() {
    val (escrow, seedMinter, _, lpMinter, whale, owner, _, deployer) = setupEscrow();
    escrow.sendDepositTon(whale.address, 0, 0, { bounce: false, value: ESCROW_WHALE_TON });
    transferTokensTo(seedMinter, owner, escrow.address, ESCROW_OWNER_JETTON, makeOwnerDepositPayload());
    escrow.sendApproveByOwner(owner.address, 0, { bounce: false, value: ton("1") });

    receiveLpReceipt(escrow, lpMinter, deployer);

    val (status, _, _, _, lpHeld, lockUntil, _, _) = escrow.getEscrowData();
    expect(status).toEqual(3); // ACTIVE
    expect(lpHeld).toEqual(ESCROW_LP_UNITS);
    expect(lockUntil).toEqual(ESCROW_START_TIME + ESCROW_THREE_MONTHS);
}

get fun `test midas-escrow: claim before unlock rejected`() {
    val (escrow, seedMinter, _, lpMinter, whale, owner, _, deployer) = setupEscrow();
    escrow.sendDepositTon(whale.address, 0, 0, { bounce: false, value: ESCROW_WHALE_TON });
    transferTokensTo(seedMinter, owner, escrow.address, ESCROW_OWNER_JETTON, makeOwnerDepositPayload());
    escrow.sendApproveByOwner(owner.address, 0, { bounce: false, value: ton("1") });
    receiveLpReceipt(escrow, lpMinter, deployer);

    val early = escrow.sendClaimAfterUnlock(whale.address, 0, { bounce: false, value: ton("1") });
    expect(early).toHaveFailedTx<ClaimAfterUnlock>({
        from: whale.address,
        to: escrow.address,
        exitCode: Errors.NothingToClaim,
    });
}

get fun `test midas-escrow: refund timeout returns whale TON`() {
    val (escrow, _, _, _, whale, _, _, _) = setupEscrow();
    escrow.sendDepositTon(whale.address, 0, 0, { bounce: false, value: ESCROW_WHALE_TON });

    testing.setNow(ESCROW_START_TIME + 86400 + 1);
    val refund = escrow.sendRefundTimeout(whale.address, 0, { bounce: false, value: ton("1") });
    expect(refund).toHaveSuccessfulTx<RefundTimeout>({ from: whale.address, to: escrow.address });

    val (status, _, whaleTon, _, _, _, _, _) = escrow.getEscrowData();
    expect(status).toEqual(6); // REFUNDED
    expect(whaleTon).toEqual(0);
}

get fun `test midas-escrow: admin cancel returns funds`() {
    val (escrow, seedMinter, _, _, whale, owner, admin, _) = setupEscrow();
    escrow.sendDepositTon(whale.address, 0, 0, { bounce: false, value: ESCROW_WHALE_TON });
    transferTokensTo(seedMinter, owner, escrow.address, ESCROW_OWNER_JETTON, makeOwnerDepositPayload());

    val cancel = escrow.sendCancel(admin.address, 0, { bounce: false, value: ton("1") });
    expect(cancel).toHaveSuccessfulTx<Cancel>({ from: admin.address, to: escrow.address });

    val (status, _, whaleTon, ownerJetton, _, _, _, _) = escrow.getEscrowData();
    expect(status).toEqual(7); // CANCELLED
    expect(whaleTon).toEqual(0);
    expect(ownerJetton).toEqual(0);
}

// Full settlement: ACTIVE -> ClaimAfterUnlock -> SETTLING (burn LP) -> receive
// pTON + PLX refunds -> unwrap pTON to native TON -> CLOSED, whale gets TON and
// owner gets PLX.
get fun `test midas-escrow: settle -> burn LP -> distribute -> closed`() {
    val (escrow, seedMinter, ptonMinter, lpMinter, whale, owner, _, deployer) = setupEscrow();
    escrow.sendDepositTon(whale.address, 0, 0, { bounce: false, value: ESCROW_WHALE_TON });
    transferTokensTo(seedMinter, owner, escrow.address, ESCROW_OWNER_JETTON, makeOwnerDepositPayload());
    escrow.sendApproveByOwner(owner.address, 0, { bounce: false, value: ton("1") });
    receiveLpReceipt(escrow, lpMinter, deployer);

    testing.setNow(ESCROW_START_TIME + ESCROW_THREE_MONTHS + 1);

    // Claim after unlock -> SETTLING, burn LP.
    val claim = escrow.sendClaimAfterUnlock(owner.address, 0, { bounce: false, value: ton("1") });
    expect(claim).toHaveSuccessfulTx<ClaimAfterUnlock>({ from: owner.address, to: escrow.address });
    val (statusAfterClaim, _, _, _, lpHeldAfter, _, _, settleProgressAfter) = escrow.getEscrowData();
    expect(statusAfterClaim).toEqual(4); // SETTLING
    expect(settleProgressAfter).toEqual(0);
    // lpHeld is still held until the pool completes the LP burn refund.
    expect(lpHeldAfter).toEqual(ESCROW_LP_UNITS);

    // Mock router refunds pTON (TON side) to the escrow's pTON wallet. Minting
    // new pTON directly to the escrow delivers a TransferNotificationForRecipient
    // to the escrow (which reacts via handleSettlementLeg).
    mintTo(ptonMinter, deployer, escrow.address, ton("400"));

    // The escrow unwraps pTON: it should have marked SETTLE_BIT_TON and sent a
    // ProxyToncoinTransfer to its pTON wallet (which our mock pTON wall mints
    // native TON back). Simulate the native TON arrival (bodyless) at the escrow.
    val (statusAfterTon, _, whaleTonAfterTon, _, _, _, _, settleProgressAfterTon) = escrow.getEscrowData();
    expect(statusAfterTon).toEqual(4); // still SETTLING (jetton leg pending)
    expect(settleProgressAfterTon).toEqual(1); // SETTLE_BIT_TON
    expect(whaleTonAfterTon).toEqual(ton("400"));

    val nativeTonMsg = createMessage({
        bounce: false,
        value: ton("400"),
        dest: escrow.address,
        // bodyless: no body
    });
    testing.processSingleTraceStep(testing.treasury("me-pton-master").address, nativeTonMsg);

    // Mock router refunds PLX (jetton side) to the escrow's seed wallet. The
    // owner holds ample seed jettons from setup; transfer them to the escrow's
    // seed wallet so the escrow's seed wallet delivers a
    // TransferNotificationForRecipient (reacted via handleSettlementLeg).
    transferTokensTo(seedMinter, owner, escrow.address, ESCROW_OWNER_JETTON, makeTinyForwardPayload());

    // Now both legs are done -> CLOSED.
    val (status, _, whaleTon, ownerJetton, lpHeld, _, _, settleProgress) = escrow.getEscrowData();
    expect(status).toEqual(5); // CLOSED
    expect(settleProgress).toEqual(3); // TON | JETTON
    expect(whaleTon).toEqual(0);
    expect(ownerJetton).toEqual(0);
    expect(lpHeld).toEqual(0);
}

// Verify ApproveByOwner emits the correct STON.fi v2.2 two-leg provide_lp
// bodies: an AskToTransfer (jetton leg) and a native-TON ProxyToncoinTransfer
// (TON leg), each carrying the ProvideLiquidity payload.
get fun `test midas-escrow: approve emits two-leg provide_lp bodies`() {
    val (escrow, seedMinter, ptonMinter, _, whale, owner, _, _) = setupEscrow();
    escrow.sendDepositTon(whale.address, 0, 0, { bounce: false, value: ESCROW_WHALE_TON });
    transferTokensTo(seedMinter, owner, escrow.address, ESCROW_OWNER_JETTON, makeOwnerDepositPayload());

    val approveMsg = createMessage({
        bounce: false,
        value: ton("1"),
        dest: escrow.address,
        body: ApproveByOwner { queryId: 0 },
    });
    val res = testing.processSingleTraceStep(owner.address, approveMsg);

    // The escrow must emit exactly two outbound messages: the TON-leg native-TON
    // ProxyToncoinTransfer (to the router's pTON wallet) and the jetton-leg
    // AskToTransfer (to its own seed wallet). The escrow sends the TON leg
    // first, so outMessages[0] is the TON leg.
    expect(res.outMessages.size()).toEqual(2);

    // TON leg: native TON wrapped via ProxyToncoinTransfer to the router's pTON
    // wallet, carrying the full whale TON amount that is being provided.
    val tonLeg = res.outMessages.at<ProxyToncoinTransfer>(0).loadBody();
    expect(tonLeg.tonAmount).toEqual(ESCROW_WHALE_TON);

    // Jetton leg: AskToTransfer to the escrow's own seed wallet, carrying the
    // full owner jetton amount that is being provided as liquidity.
    val jettonLeg = res.outMessages.at<AskToTransfer>(1).loadBody();
    expect(jettonLeg.jettonAmount).toEqual(ESCROW_OWNER_JETTON);
}

