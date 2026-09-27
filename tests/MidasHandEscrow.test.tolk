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
        dexType: 0,
        stonfi: makeStonfiConfig(router, lpMinter, ptonMinter, seedWalletCode).toCell(),
        dedust: null,
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
        depositDeadline: 0,
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

// --------------------------------------------------------------------------
// DeDust v2 side: same escrow contract, dexType = DEDUST, native TON leg to the
// native vault and seed jetton leg to the jetton vault. The mock "pool side" is
// a plain treasury for the vault addresses plus a real JettonMinter for the LP.
// --------------------------------------------------------------------------

const ESCROW_DEDUST_NATIVE_VAULT_GAS = 300000000 // 0.3 TON (chain-verified)
const ESCROW_DEDUST_JETTON_FORWARD_GAS = 400000000 // 0.4 TON

fun makeDedustConfig(
    pool: JettonMinter,
    nativeVault: address,
    jettonVault: address,
): DedustConfig {
    return DedustConfig {
        poolAddress: pool.address,
        // Unbound at deploy by design: the factory derives the LiquidityDeposit
        // address from the depositor, which is the escrow itself, and the escrow
        // address is the hash of this config (circular). The admin binds it after
        // deploy with BindDedustLiquidityDeposit.
        liquidityDeposit: null,
        nativeVault: nativeVault.toCell(),
        jettonVault: jettonVault.toCell(),
        lpWalletCode: build("JettonWallet"),
        stablePool: false,
    };
}

fun setupDedustEscrow(bindLiquidityDeposit: bool): (
    MidasHandEscrow,
    JettonMinter,
    JettonMinter,
    Treasury,
    Treasury,
    Treasury,
    address,
    address,
    address,
) {
    testing.setNow(ESCROW_START_TIME);
    val deployer = testing.treasury("me-dd-deployer");
    val whale = testing.treasury("me-dd-whale");
    val owner = testing.treasury("me-dd-owner");
    val admin = testing.treasury("me-dd-admin");
    val nativeVault = testing.treasury("me-dd-native-vault").address;
    val jettonVault = testing.treasury("me-dd-jetton-vault").address;
    val liquidityDeposit = testing.treasury("me-dd-liquidity-deposit").address;

    val seedMinter = JettonMinter.fromStorage({
        totalSupply: 0,
        adminAddress: deployer.address,
        nextAdminAddress: null,
        metadata: buildTestMetadata("me-dd-seed-token"),
    });
    expect(seedMinter.sendDeploy(deployer.address, { value: ton("10") })).toHaveSuccessfulDeploy({
        to: seedMinter.address,
    });

    val lpMinter = JettonMinter.fromStorage({
        totalSupply: 0,
        adminAddress: deployer.address,
        nextAdminAddress: null,
        metadata: buildTestMetadata("me-dd-lp"),
    });
    expect(lpMinter.sendDeploy(deployer.address, { value: ton("10") })).toHaveSuccessfulDeploy({
        to: lpMinter.address,
    });

    val config: MidasEscrowConfig = {
        whaleAddress: whale.address,
        ownerAddress: owner.address,
        minterAddress: seedMinter.address,
        seedWalletCode: build("JettonWallet"),
        adminMultisig: admin.address.toCell(),
        proposalTimeoutSec: 86400,
        dexType: 1, // DEX_DEDUST
        stonfi: null,
        dedust: makeDedustConfig(lpMinter, nativeVault, jettonVault).toCell(),
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
        depositDeadline: 0,
    });
    expect(escrow.deploy(deployer.address, { value: ton("5") })).toHaveSuccessfulDeploy({
        to: escrow.address,
    });

    mintTokensTo(deployer, seedMinter, owner.address, 200000 * ESCROW_UNIT);

    // Production order: deploy -> bind LiquidityDeposit -> fund -> approve. The
    // bind needs the escrow address, so it can only happen after the deploy; the
    // owner approve refuses a DeDust escrow whose resolution path is unbound.
    if (bindLiquidityDeposit) {
        val bind = escrow.sendBindDedustLiquidityDeposit(
            admin.address,
            0,
            liquidityDeposit,
            { bounce: false, value: ton("1") },
        );
        expect(bind).toHaveSuccessfulTx<BindDedustLiquidityDeposit>({
            from: admin.address,
            to: escrow.address,
        });
    }

    return (escrow, seedMinter, lpMinter, whale, owner, admin, nativeVault, jettonVault, liquidityDeposit);
}

get fun `test midas-escrow dedust: approve emits native + jetton deposit legs`() {
    val (escrow, seedMinter, _, whale, owner, _, nativeVault, jettonVault, _) = setupDedustEscrow(true);
    escrow.sendDepositTon(whale.address, 0, 0, { bounce: false, value: ESCROW_WHALE_TON });
    transferTokensTo(seedMinter, owner, escrow.address, ESCROW_OWNER_JETTON, makeOwnerDepositPayload());

    val approveMsg = createMessage({
        bounce: false,
        value: ton("1"),
        dest: escrow.address,
        body: ApproveByOwner { queryId: 0 },
    });
    val res = testing.processSingleTraceStep(owner.address, approveMsg);
    expect(res.outMessages.size()).toEqual(2);

    // [0] Native leg -> native vault, value = amount + 0.3 TON vault gas.
    val native = res.outMessages.at<DedustNativeDepositLiquidity>(0);
    expect(native.info.dest).toEqual(nativeVault);
    expect(native.info.value.grams).toEqual(ESCROW_WHALE_TON + ESCROW_DEDUST_NATIVE_VAULT_GAS);
    val nativeBody = native.loadBody();
    expect(nativeBody.amount).toEqual(ESCROW_WHALE_TON);
    expect(nativeBody.stablePool).toEqual(false);
    expect(nativeBody.asset0Tag).toEqual(0);
    expect(nativeBody.asset1Tag).toEqual(1);
    val (minterWc, minterHash) = seedMinter.address.getWorkchainAndHash();
    expect(nativeBody.jettonWorkchain).toEqual(minterWc);
    expect(nativeBody.jettonHash).toEqual(minterHash);
    val nativeTargets = nativeBody.targets.load();
    expect(nativeTargets.minLpAmount).toEqual(1);
    expect(nativeTargets.asset0TargetBalance).toEqual(ESCROW_WHALE_TON);
    expect(nativeTargets.asset1TargetBalance).toEqual(ESCROW_OWNER_JETTON);

    // [1] Jetton leg -> the escrow's own seed wallet, destination = jetton vault,
    // forward payload = deposit_liquidity with the SAME targets.
    val seedWallet = userWallet(seedMinter, escrow.address).address;
    val jettonLeg = res.outMessages.at<AskToTransfer>(1);
    expect(jettonLeg.info.dest).toEqual(seedWallet);
    val jettonBody = jettonLeg.loadBody();
    expect(jettonBody.jettonAmount).toEqual(ESCROW_OWNER_JETTON);
    expect(jettonBody.transferRecipient).toEqual(jettonVault);
    expect(jettonBody.forwardTonAmount).toEqual(ESCROW_DEDUST_JETTON_FORWARD_GAS);
    var forwardRefSource = jettonBody.forwardPayload;
    val forwardRef = forwardRefSource.loadMaybeRef();
    expect(forwardRef != null).toEqual(true);
    val jettonDeposit = DedustJettonDepositLiquidity.fromSlice(forwardRef!.beginParse());
    expect(jettonDeposit.stablePool).toEqual(false);
    expect(jettonDeposit.jettonWorkchain).toEqual(minterWc);
    expect(jettonDeposit.jettonHash).toEqual(minterHash);
    expect(jettonDeposit.minLpAmount).toEqual(1);
    expect(jettonDeposit.asset0TargetBalance).toEqual(ESCROW_WHALE_TON);
    expect(jettonDeposit.asset1TargetBalance).toEqual(ESCROW_OWNER_JETTON);

    // ADDING, with the recovery deadline stamped one hour ahead.
    val (status, _, _, _, _, _, _, _) = escrow.getEscrowData();
    expect(status).toEqual(2); // ADDING
    expect(escrow.getDexType()).toEqual(1); // DEDUST
    expect(escrow.getDepositDeadline()).toEqual(ESCROW_START_TIME + 3600);
}

get fun `test midas-escrow dedust: LP receipt -> active`() {
    val (escrow, seedMinter, lpMinter, whale, owner, _, _, _, _) = setupDedustEscrow(true);
    escrow.sendDepositTon(whale.address, 0, 0, { bounce: false, value: ESCROW_WHALE_TON });
    transferTokensTo(seedMinter, owner, escrow.address, ESCROW_OWNER_JETTON, makeOwnerDepositPayload());
    escrow.sendApproveByOwner(owner.address, 0, { bounce: false, value: ton("1") });

    receiveLpReceipt(escrow, lpMinter, testing.treasury("me-dd-deployer"));

    val (status, _, _, _, lpHeld, lockUntil, _, _) = escrow.getEscrowData();
    expect(status).toEqual(3); // ACTIVE
    expect(lpHeld).toEqual(ESCROW_LP_UNITS);
    expect(lockUntil).toEqual(ESCROW_START_TIME + ESCROW_THREE_MONTHS);
}

get fun `test midas-escrow dedust: admin cancel blocked during adding`() {
    val (escrow, seedMinter, _, whale, owner, admin, _, _, _) = setupDedustEscrow(true);
    escrow.sendDepositTon(whale.address, 0, 0, { bounce: false, value: ESCROW_WHALE_TON });
    transferTokensTo(seedMinter, owner, escrow.address, ESCROW_OWNER_JETTON, makeOwnerDepositPayload());
    escrow.sendApproveByOwner(owner.address, 0, { bounce: false, value: ton("1") });

    val cancel = escrow.sendCancel(admin.address, 0, { bounce: false, value: ton("1") });
    expect(cancel).toHaveFailedTx<Cancel>({
        from: admin.address,
        to: escrow.address,
        exitCode: Errors.InvalidOp,
    });
}

get fun `test midas-escrow dedust: cancel deposit before deadline rejected`() {
    val (escrow, seedMinter, _, whale, owner, _, _, _, _) = setupDedustEscrow(true);
    escrow.sendDepositTon(whale.address, 0, 0, { bounce: false, value: ESCROW_WHALE_TON });
    transferTokensTo(seedMinter, owner, escrow.address, ESCROW_OWNER_JETTON, makeOwnerDepositPayload());
    escrow.sendApproveByOwner(owner.address, 0, { bounce: false, value: ton("1") });

    val early = escrow.sendCancelDedustDeposit(owner.address, 0, { bounce: false, value: ton("1") });
    expect(early).toHaveFailedTx<CancelDedustDeposit>({
        from: owner.address,
        to: escrow.address,
        exitCode: Errors.NothingToClaim,
    });
}

get fun `test midas-escrow dedust: cancel deposit rejected on stonfi escrow`() {
    val (escrow, seedMinter, _, _, whale, owner, _, _) = setupEscrow();
    escrow.sendDepositTon(whale.address, 0, 0, { bounce: false, value: ESCROW_WHALE_TON });
    transferTokensTo(seedMinter, owner, escrow.address, ESCROW_OWNER_JETTON, makeOwnerDepositPayload());

    val res = escrow.sendCancelDedustDeposit(owner.address, 0, { bounce: false, value: ton("1") });
    expect(res).toHaveFailedTx<CancelDedustDeposit>({
        from: owner.address,
        to: escrow.address,
        exitCode: Errors.InvalidOp,
    });
}

get fun `test midas-escrow dedust: cancel deposit after deadline recovers funds`() {
    val (escrow, seedMinter, _, whale, owner, _, _, _, liquidityDeposit) = setupDedustEscrow(true);
    escrow.sendDepositTon(whale.address, 0, 0, { bounce: false, value: ESCROW_WHALE_TON });
    transferTokensTo(seedMinter, owner, escrow.address, ESCROW_OWNER_JETTON, makeOwnerDepositPayload());
    escrow.sendApproveByOwner(owner.address, 0, { bounce: false, value: ton("1") });

    testing.setNow(ESCROW_START_TIME + 3601);
    val recoverMsg = createMessage({
        bounce: false,
        value: ton("1"),
        dest: escrow.address,
        body: CancelDedustDeposit { queryId: 0 },
    });
    val res = testing.processSingleTraceStep(owner.address, recoverMsg);
    expect(res.outMessages.size()).toEqual(1);
    val cancelMsg = res.outMessages.at<DedustCancelDeposit>(0);
    expect(cancelMsg.info.dest).toEqual(liquidityDeposit);
    expect(cancelMsg.loadBody().queryId).toEqual(0);

    // Back to FUNDED with the guard cleared so the normal refund paths can pay.
    val (status, _, _, _, _, _, _, _) = escrow.getEscrowData();
    expect(status).toEqual(1); // FUNDED
    expect(escrow.getDepositDeadline()).toEqual(0);

    // Second attempt is rejected: the parked deposit can only be claimed once.
    val again = escrow.sendCancelDedustDeposit(owner.address, 0, { bounce: false, value: ton("1") });
    expect(again).toHaveFailedTx<CancelDedustDeposit>({
        from: owner.address,
        to: escrow.address,
        exitCode: Errors.InvalidOp,
    });
}

get fun `test midas-escrow dedust: recovered TON credited then refunded`() {
    val (escrow, seedMinter, _, whale, owner, _, _, _, _) = setupDedustEscrow(true);
    escrow.sendDepositTon(whale.address, 0, 0, { bounce: false, value: ESCROW_WHALE_TON });
    transferTokensTo(seedMinter, owner, escrow.address, ESCROW_OWNER_JETTON, makeOwnerDepositPayload());
    escrow.sendApproveByOwner(owner.address, 0, { bounce: false, value: ton("1") });

    testing.setNow(ESCROW_START_TIME + 3601);
    escrow.sendCancelDedustDeposit(owner.address, 0, { bounce: false, value: ton("1") });

    // The LiquidityDeposit returns the parked TON as a bodyless message. It must
    // be credited so RefundTimeout can pay the whale back in full.
    val nativeBack = createMessage({
        bounce: false,
        value: ton("400"),
        dest: escrow.address,
    });
    testing.processSingleTraceStep(testing.treasury("me-dd-liquidity-deposit").address, nativeBack);

    val (statusAfterCredit, _, whaleTon, _, _, _, _, _) = escrow.getEscrowData();
    expect(statusAfterCredit).toEqual(1); // still FUNDED
    expect(whaleTon).toEqual(ton("400"));

    testing.setNow(ESCROW_START_TIME + 86400 + 1);
    val refund = escrow.sendRefundTimeout(whale.address, 0, { bounce: false, value: ton("1") });
    expect(refund).toHaveSuccessfulTx<RefundTimeout>({ from: whale.address, to: escrow.address });

    val (status, _, whaleTonAfter, ownerJettonAfter, _, _, _, _) = escrow.getEscrowData();
    expect(status).toEqual(6); // REFUNDED
    expect(whaleTonAfter).toEqual(0);
    expect(ownerJettonAfter).toEqual(0);
}

get fun `test midas-escrow dedust: native leg bounce restores whale bucket`() {
    val (escrow, seedMinter, _, whale, owner, _, nativeVault, _, _) = setupDedustEscrow(true);
    escrow.sendDepositTon(whale.address, 0, 0, { bounce: false, value: ESCROW_WHALE_TON });
    transferTokensTo(seedMinter, owner, escrow.address, ESCROW_OWNER_JETTON, makeOwnerDepositPayload());
    escrow.sendApproveByOwner(owner.address, 0, { bounce: false, value: ton("1") });

    val (statusAdding, _, _, _, _, _, _, _) = escrow.getEscrowData();
    expect(statusAdding).toEqual(2); // ADDING

    // A bounced native deposit returns the TON: the whale bucket is restored and
    // the deal steps back to FUNDED so the refund paths can pay it out. The
    // emulator marks a bounce with the 0xFFFFFFFF prefix plus the first 256 bits
    // of the original body.
    val original = beginCell()
        .storeUint(0xD55E4686, 32)
        .storeUint(0, 64)
        .storeCoins(ESCROW_WHALE_TON)
        .endCell();
    val bouncedBody = beginCell()
        .storeUint(0xFFFFFFFF, 32)
        .storeSlice(original.beginParse())
        .endCell();
    val bouncedMsg = createMessage({
        bounce: false,
        value: ESCROW_WHALE_TON,
        dest: escrow.address,
        body: bouncedBody.beginParse(),
    }).bounced();
    testing.processSingleTraceStep(nativeVault, bouncedMsg);

    val (status, _, whaleTon, _, _, _, _, _) = escrow.getEscrowData();
    expect(status).toEqual(1); // FUNDED
    expect(whaleTon).toEqual(ESCROW_WHALE_TON);
}

get fun `test midas-escrow dedust: settle pays native TON and seed jetton`() {
    val (escrow, seedMinter, lpMinter, whale, owner, _, _, _, _) = setupDedustEscrow(true);
    escrow.sendDepositTon(whale.address, 0, 0, { bounce: false, value: ESCROW_WHALE_TON });
    transferTokensTo(seedMinter, owner, escrow.address, ESCROW_OWNER_JETTON, makeOwnerDepositPayload());
    escrow.sendApproveByOwner(owner.address, 0, { bounce: false, value: ton("1") });
    receiveLpReceipt(escrow, lpMinter, testing.treasury("me-dd-deployer"));

    testing.setNow(ESCROW_START_TIME + ESCROW_THREE_MONTHS + 1);
    val claim = escrow.sendClaimAfterUnlock(whale.address, 0, { bounce: false, value: ton("1") });
    expect(claim).toHaveSuccessfulTx<ClaimAfterUnlock>({ from: whale.address, to: escrow.address });

    val (statusAfterClaim, _, _, _, _, _, _, settleProgressAfter) = escrow.getEscrowData();
    expect(statusAfterClaim).toEqual(4); // SETTLING
    expect(settleProgressAfter).toEqual(0);

    // DeDust pays the TON side as native TON (bodyless): the whale is paid and
    // the TON leg is marked, while the deal stays SETTLING for the jetton leg.
    val nativeBack = createMessage({
        bounce: false,
        value: ton("400"),
        dest: escrow.address,
    });
    val nativeRes = testing.processSingleTraceStep(testing.treasury("me-dd-pool").address, nativeBack);
    expect(nativeRes.outMessages.size()).toEqual(1); // payout to the whale
    val payout = (nativeRes.outMessages.atCell(0) as Cell<TlbMessageRelaxedGeneric>).load();
    val (statusAfterTon, _, _, _, _, _, _, settleProgressAfterTon) = escrow.getEscrowData();
    expect(statusAfterTon).toEqual(4); // still SETTLING
    expect(settleProgressAfterTon).toEqual(1); // SETTLE_BIT_TON
    expect(payout.info.dest).toEqual(whale.address);
    expect(payout.info.value.grams).toEqual(ton("400"));
    // Bodyless payout: no opcode. This is the native-TON return DeDust sends as
    // plain TON, forwarded to the whale without any unwrap step (the out-message
    // view of an empty body carries a single inline-either marker bit).
    expect(payout.loadOpcode()).toEqual(null);
    expect(payout.body.remainingBitsCount() < 32).toEqual(true);
    expect(payout.body.remainingRefsCount()).toEqual(0);

    // Seed jetton side comes back from the pool into the escrow's seed wallet.
    transferTokensTo(seedMinter, owner, escrow.address, ESCROW_OWNER_JETTON, makeTinyForwardPayload());

    val (status, _, _, ownerJetton, lpHeld, _, _, settleProgress) = escrow.getEscrowData();
    expect(status).toEqual(5); // CLOSED
    expect(settleProgress).toEqual(3); // TON | JETTON
    expect(ownerJetton).toEqual(0);
    expect(lpHeld).toEqual(0);
}

// The LiquidityDeposit address is derived from the escrow address, so it cannot
// be part of the deploy config. The admin binds it once, right after deploy, and
// only before any deposit leg is in flight.
get fun `test midas-escrow dedust: bind stores the recovery address`() {
    val (escrow, _, _, _, _, _, _, _, liquidityDeposit) = setupDedustEscrow(true);

    val bound = escrow.getDedustLiquidityDeposit();
    expect(bound != null).toEqual(true);
    expect(bound!).toEqual(liquidityDeposit);

    // The bound address reaches the immutable config too, not just the getter.
    val config = escrow.getConfig();
    expect(config.dedust!.load().liquidityDeposit!).toEqual(liquidityDeposit);
}

get fun `test midas-escrow dedust: approve rejected while unbound`() {
    val (escrow, seedMinter, _, whale, owner, _, _, _, _) = setupDedustEscrow(false);
    escrow.sendDepositTon(whale.address, 0, 0, { bounce: false, value: ESCROW_WHALE_TON });
    transferTokensTo(seedMinter, owner, escrow.address, ESCROW_OWNER_JETTON, makeOwnerDepositPayload());

    expect(escrow.getDedustLiquidityDeposit() == null).toEqual(true);

    // Fail closed: without a bound recovery address the parked legs would be
    // unreachable, so the approve is refused instead of moving the money.
    val approve = escrow.sendApproveByOwner(owner.address, 0, { bounce: false, value: ton("1") });
    expect(approve).toHaveFailedTx<ApproveByOwner>({
        from: owner.address,
        to: escrow.address,
        exitCode: Errors.InvalidOp,
    });

    val (status, _, _, _, _, _, _, _) = escrow.getEscrowData();
    expect(status).toEqual(1); // still FUNDED, nothing left the escrow
}

get fun `test midas-escrow dedust: bind rejected from non-admin`() {
    val (escrow, _, _, whale, _, _, _, _, liquidityDeposit) = setupDedustEscrow(false);
    val res = escrow.sendBindDedustLiquidityDeposit(
        whale.address,
        0,
        liquidityDeposit,
        { bounce: false, value: ton("1") },
    );
    expect(res).toHaveFailedTx<BindDedustLiquidityDeposit>({
        from: whale.address,
        to: escrow.address,
        exitCode: Errors.NotOwner,
    });
}

get fun `test midas-escrow dedust: bind frozen once adding`() {
    val (escrow, seedMinter, _, whale, owner, admin, _, _, liquidityDeposit) = setupDedustEscrow(true);
    escrow.sendDepositTon(whale.address, 0, 0, { bounce: false, value: ESCROW_WHALE_TON });
    transferTokensTo(seedMinter, owner, escrow.address, ESCROW_OWNER_JETTON, makeOwnerDepositPayload());
    escrow.sendApproveByOwner(owner.address, 0, { bounce: false, value: ton("1") });

    // A live recovery must not be redirectable, so the address is frozen from
    // ADDING on even for the admin.
    val res = escrow.sendBindDedustLiquidityDeposit(
        admin.address,
        0,
        whale.address,
        { bounce: false, value: ton("1") },
    );
    expect(res).toHaveFailedTx<BindDedustLiquidityDeposit>({
        from: admin.address,
        to: escrow.address,
        exitCode: Errors.InvalidOp,
    });

    val bound = escrow.getDedustLiquidityDeposit();
    expect(bound!).toEqual(liquidityDeposit);
}

get fun `test midas-escrow dedust: bind rejected on stonfi escrow`() {
    val (escrow, seedMinter, _, _, whale, owner, admin, _) = setupEscrow();
    escrow.sendDepositTon(whale.address, 0, 0, { bounce: false, value: ESCROW_WHALE_TON });
    transferTokensTo(seedMinter, owner, escrow.address, ESCROW_OWNER_JETTON, makeOwnerDepositPayload());

    val res = escrow.sendBindDedustLiquidityDeposit(
        admin.address,
        0,
        admin.address,
        { bounce: false, value: ton("1") },
    );
    expect(res).toHaveFailedTx<BindDedustLiquidityDeposit>({
        from: admin.address,
        to: escrow.address,
        exitCode: Errors.InvalidOp,
    });

    expect(escrow.getDedustLiquidityDeposit() == null).toEqual(true);
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

    // The provide_lp body must be carried the TEP-74 `either$1` way (tag bit then
    // ref). A bare ref has zero bits and makes our own JettonWallet throw cell
    // underflow in `checkIsCorrectTlbEither`, which would kill the whole leg.
    var stonfiPayload = jettonLeg.forwardPayload;
    val stonfiRef = stonfiPayload.loadMaybeRef();
    expect(stonfiRef != null).toEqual(true);
    var provideLp = stonfiRef!.beginParse();
    expect(provideLp.loadUint(32)).toEqual(STONFI_PROVIDE_LP_OP);
}

