import "@acton/build"
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"

import "@contracts/MidasHandEscrow"
import "@contracts/errors"
import "@contracts/messages"
import "@wrappers/JettonMinter.gen"
import "@wrappers/MidasHandEscrow.gen"
import "@wrappers/utils"

import "test-utils"

const ESCROW_START_TIME = 1700000000
const ESCROW_UNIT = 1000000000
const ESCROW_WHALE_TON = ton("600")        // 600 TON
const ESCROW_OWNER_JETTON = 40000 * ESCROW_UNIT
const ESCROW_OWNER_DEPOSIT_OP: uint32 = 0x4d484531
const ESCROW_THREE_MONTHS: uint32 = 7776000

fun makeOwnerDepositPayload(): slice {
    return beginCell().storeUint(ESCROW_OWNER_DEPOSIT_OP, 32).endCell().beginParse();
}

fun setupEscrow(): (MidasHandEscrow, JettonMinter, Treasury, Treasury, Treasury) {
    testing.setNow(ESCROW_START_TIME);
    val deployer = testing.treasury("me-deployer");
    val whale = testing.treasury("me-whale");
    val owner = testing.treasury("me-owner");
    val admin = testing.treasury("me-admin");

    val minter = JettonMinter.fromStorage({
        totalSupply: 0,
        adminAddress: deployer.address,
        nextAdminAddress: null,
        metadata: buildTestMetadata("me-seed-token"),
    });
    expect(minter.sendDeploy(deployer.address, { value: ton("10") })).toHaveSuccessfulDeploy({
        to: minter.address,
    });

    val walletCode = build("JettonWallet");
    val config: MidasEscrowConfig = {
        whaleAddress: whale.address,
        ownerAddress: owner.address,
        minterAddress: minter.address,
        seedWalletCode: walletCode,
        adminMultisig: admin.address.toCell(),
        proposalTimeoutSec: 86400,
    };

    val escrow = MidasHandEscrow.fromStorage({
        config: config.toCell(),
        status: 0,
        termType: 0,
        whaleTonDeposited: 0,
        ownerJettonDeposited: 0,
        lockUntil: 0,
        proposalDeadline: 0,
    });
    expect(escrow.deploy(deployer.address, { value: ton("5") })).toHaveSuccessfulDeploy({
        to: escrow.address,
    });

    mintTokensTo(deployer, minter, owner.address, 200000 * ESCROW_UNIT);
    mintTokensTo(deployer, minter, admin.address, 200000 * ESCROW_UNIT);

    return (escrow, minter, whale, owner, admin);
}

get fun `test midas-escrow: deploy in proposed state`() {
    val (escrow, _, whale, owner, admin) = setupEscrow();
    val (status, termType, whaleTon, ownerJetton, lockUntil, deadline) = escrow.getEscrowData();
    expect(status).toEqual(0);
    expect(termType).toEqual(0);
    expect(whaleTon).toEqual(0);
    expect(ownerJetton).toEqual(0);
    expect(lockUntil).toEqual(0);
    expect(deadline).toEqual(0);
    expect(whale.address).toEqual(whale.address);
    expect(owner.address).toEqual(owner.address);
    expect(admin.address).toEqual(admin.address);
}

get fun `test midas-escrow: whale deposits TON -> funded`() {
    val (escrow, _, whale, _, _) = setupEscrow();

    val deposit = escrow.sendDepositTon(
        whale.address,
        0,
        1, // 6 months
        { bounce: false, value: ESCROW_WHALE_TON },
    );
    expect(deposit).toHaveSuccessfulTx<DepositTon>({ from: whale.address, to: escrow.address });

    val (status, termType, whaleTon, _, _, deadline) = escrow.getEscrowData();
    expect(status).toEqual(1);
    expect(termType).toEqual(1);
    expect(whaleTon).toEqual(ESCROW_WHALE_TON);
    expect(deadline).toEqual(ESCROW_START_TIME + 86400);
    expect(escrow.getWhaleShareBps()).toEqual(7000);
}

get fun `test midas-escrow: non-whale deposit rejected`() {
    val (escrow, _, _, owner, _) = setupEscrow();

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

get fun `test midas-escrow: owner jetton deposit then approve -> active`() {
    val (escrow, minter, whale, owner, _) = setupEscrow();
    escrow.sendDepositTon(whale.address, 0, 0, { bounce: false, value: ESCROW_WHALE_TON });

    val jettonDeposit = transferTokensTo(
        minter,
        owner,
        escrow.address,
        ESCROW_OWNER_JETTON,
        makeOwnerDepositPayload(),
    );
    expect(jettonDeposit).toHaveSuccessfulTx<TransferNotificationForRecipient>({
        to: escrow.address,
    });

    val (status, _, _, ownerJetton, _, _) = escrow.getEscrowData();
    expect(status).toEqual(1);
    expect(ownerJetton).toEqual(ESCROW_OWNER_JETTON);

    val approve = escrow.sendApproveByOwner(owner.address, 0, { bounce: false, value: ton("0.2") });
    expect(approve).toHaveSuccessfulTx<ApproveByOwner>({ from: owner.address, to: escrow.address });

    val (status2, _, _, _, lockUntil, _) = escrow.getEscrowData();
    expect(status2).toEqual(2);
    expect(lockUntil).toEqual(ESCROW_START_TIME + ESCROW_THREE_MONTHS);
}

get fun `test midas-escrow: non-owner jetton deposit rejected`() {
    val (escrow, minter, whale, _, admin) = setupEscrow();
    escrow.sendDepositTon(whale.address, 0, 0, { bounce: false, value: ESCROW_WHALE_TON });

    // A third party (admin treasury, not the configured owner) tries to deposit
    // jetton with the owner-deposit op. The escrow must reject it.
    val jettonDeposit = transferTokensTo(
        minter,
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

get fun `test midas-escrow: claim before unlock rejected`() {
    val (escrow, minter, whale, owner, _) = setupEscrow();
    escrow.sendDepositTon(whale.address, 0, 0, { bounce: false, value: ESCROW_WHALE_TON });
    transferTokensTo(minter, owner, escrow.address, ESCROW_OWNER_JETTON, makeOwnerDepositPayload());
    escrow.sendApproveByOwner(owner.address, 0, { bounce: false, value: ton("0.2") });

    val early = escrow.sendClaimAfterUnlock(whale.address, 0, { bounce: false, value: ton("0.2") });
    expect(early).toHaveFailedTx<ClaimAfterUnlock>({
        from: whale.address,
        to: escrow.address,
        exitCode: Errors.NothingToClaim,
    });
}

get fun `test midas-escrow: claim after unlock settles principal`() {
    val (escrow, minter, whale, owner, _) = setupEscrow();
    escrow.sendDepositTon(whale.address, 0, 0, { bounce: false, value: ESCROW_WHALE_TON });
    transferTokensTo(minter, owner, escrow.address, ESCROW_OWNER_JETTON, makeOwnerDepositPayload());
    escrow.sendApproveByOwner(owner.address, 0, { bounce: false, value: ton("0.2") });

    testing.setNow(ESCROW_START_TIME + ESCROW_THREE_MONTHS + 1);
    val claim = escrow.sendClaimAfterUnlock(owner.address, 0, { bounce: false, value: ton("0.2") });
    expect(claim).toHaveSuccessfulTx<ClaimAfterUnlock>({ from: owner.address, to: escrow.address });

    val (status, _, whaleTon, ownerJetton, _, _) = escrow.getEscrowData();
    expect(status).toEqual(3);
    expect(whaleTon).toEqual(0);
    expect(ownerJetton).toEqual(0);
}

get fun `test midas-escrow: refund timeout returns whale TON`() {
    val (escrow, _, whale, _, _) = setupEscrow();
    escrow.sendDepositTon(whale.address, 0, 0, { bounce: false, value: ESCROW_WHALE_TON });

    testing.setNow(ESCROW_START_TIME + 86400 + 1);
    val refund = escrow.sendRefundTimeout(whale.address, 0, { bounce: false, value: ton("0.2") });
    expect(refund).toHaveSuccessfulTx<RefundTimeout>({ from: whale.address, to: escrow.address });

    val (status, _, whaleTon, _, _, _) = escrow.getEscrowData();
    expect(status).toEqual(4);
    expect(whaleTon).toEqual(0);
}

get fun `test midas-escrow: admin cancel returns funds`() {
    val (escrow, minter, whale, owner, admin) = setupEscrow();
    escrow.sendDepositTon(whale.address, 0, 0, { bounce: false, value: ESCROW_WHALE_TON });
    transferTokensTo(minter, owner, escrow.address, ESCROW_OWNER_JETTON, makeOwnerDepositPayload());

    val cancel = escrow.sendCancel(admin.address, 0, { bounce: false, value: ton("0.2") });
    expect(cancel).toHaveSuccessfulTx<Cancel>({ from: admin.address, to: escrow.address });

    val (status, _, whaleTon, ownerJetton, _, _) = escrow.getEscrowData();
    expect(status).toEqual(5);
    expect(whaleTon).toEqual(0);
    expect(ownerJetton).toEqual(0);
}
