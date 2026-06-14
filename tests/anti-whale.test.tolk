import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"

import "@contracts/AntiWhaleJettonWallet"
import "@contracts/errors"
import "@contracts/messages"
import "@contracts/storage"
import "@wrappers/JettonMinter.gen"
import "@wrappers/AntiWhaleJettonWallet.gen"
import "@wrappers/utils"

import "test-utils"

const AW_UNIT = 1000000000
const AW_MAX_TRANSFER = 1000 * AW_UNIT
const AW_MAX_WALLET = 5000 * AW_UNIT

fun makeAwForwardPayload(): slice {
    return beginCell().storeUint(0, 1).toSlice();
}

/// Deploy an AntiWhaleJettonWallet directly (bypassing minter for simplicity).
/// minterAddress is set to the minterTreasury so we can send UpdateWhaleConfig from it.
fun deployAntiWhaleWallet(
    owner: Treasury,
    minterTreasury: Treasury,
    initialBalance: coins,
    maxTransfer: coins,
    maxWallet: coins,
): AntiWhaleJettonWallet {
    val wallet = AntiWhaleJettonWallet.fromStorage({
        jettonBalance: initialBalance,
        ownerAddress: owner.address,
        minterAddress: minterTreasury.address,
        maxTransferAmount: maxTransfer,
        maxWalletBalance: maxWallet,
    });
    expect(wallet.sendDeploy(owner.address, { value: ton("5") })).toHaveSuccessfulDeploy({
        to: wallet.address,
    });
    return wallet;
}

/// Send InternalTransferStep directly (simulates receiving jettons from minter)
fun injectBalance(
    sender: Treasury,
    wallet: AntiWhaleJettonWallet,
    amount: coins,
): SendResultList {
    val body = InternalTransferStep {
        queryId: 0,
        jettonAmount: amount,
        transferInitiator: null,
        sendExcessesTo: null,
        forwardTonAmount: 0,
        forwardPayload: makeTinyForwardPayload(),
    };
    return sendRawTransferPayload(sender.address, wallet.address, body.toCell(), ton("0.3"));
}

fun sendAntiWhaleTransfer(
    from: Treasury,
    fromWallet: AntiWhaleJettonWallet,
    recipient: address,
    amount: coins,
    value: coins = 400000000,
): SendResultList {
    val body = AskToTransfer {
        queryId: 0,
        jettonAmount: amount,
        transferRecipient: recipient,
        sendExcessesTo: from.address,
        customPayload: null,
        forwardTonAmount: 0,
        forwardPayload: makeAwForwardPayload(),
    };
    return sendRawTransferPayload(from.address, fromWallet.address, body.toCell(), value);
}

get fun `test anti-whale: deploy stores whale config`() {
    val owner = testing.treasury("aw-owner");
    val minter = testing.treasury("aw-minter");

    val wallet = deployAntiWhaleWallet(owner, minter, 0, AW_MAX_TRANSFER, AW_MAX_WALLET);
    val (maxTransfer, maxWallet) = wallet.getWhaleConfig();
    expect(maxTransfer).toEqual(AW_MAX_TRANSFER);
    expect(maxWallet).toEqual(AW_MAX_WALLET);
}

get fun `test anti-whale: transfer within limit succeeds`() {
    val owner = testing.treasury("aw-owner2");
    val minter = testing.treasury("aw-minter2");
    val recipient = testing.treasury("aw-recipient");

    val ownerWallet = deployAntiWhaleWallet(owner, minter, 0, AW_MAX_TRANSFER, AW_MAX_WALLET);

    // Inject balance from minter
    val injectRes = injectBalance(minter, ownerWallet, AW_MAX_TRANSFER * 5);
    expect(injectRes).toHaveSuccessfulTx<InternalTransferStep>({
        from: minter.address, to: ownerWallet.address,
    });
    expect(ownerWallet.getJettonBalance()).toEqual(AW_MAX_TRANSFER * 5);

    val res = sendAntiWhaleTransfer(owner, ownerWallet, recipient.address, AW_MAX_TRANSFER);
    expect(res).toHaveSuccessfulTx<AskToTransfer>({ from: owner.address, to: ownerWallet.address });
}

get fun `test anti-whale: transfer exceeding max transfer rejected with error 200`() {
    val owner = testing.treasury("aw-owner3");
    val minter = testing.treasury("aw-minter3");
    val recipient = testing.treasury("aw-recipient2");

    val ownerWallet = deployAntiWhaleWallet(owner, minter, 0, AW_MAX_TRANSFER, AW_MAX_WALLET);
    // Inject 2x max transfer (within max wallet balance of 5x max transfer)
    injectBalance(minter, ownerWallet, AW_MAX_TRANSFER * 2);

    val tooMuch = AW_MAX_TRANSFER + 1;
    val res = sendAntiWhaleTransfer(owner, ownerWallet, recipient.address, tooMuch);
    expect(res).toHaveFailedTx<AskToTransfer>({
        from: owner.address,
        to: ownerWallet.address,
        exitCode: 200,
    });
}

get fun `test anti-whale: receiving that would exceed max wallet balance rejected with error 201`() {
    val owner = testing.treasury("aw-owner4");
    val minter = testing.treasury("aw-minter4");
    val recipient = testing.treasury("aw-recipient3");

    // Recipient wallet has max balance of AW_MAX_WALLET
    val recipientWallet = deployAntiWhaleWallet(recipient, minter, 0, AW_MAX_TRANSFER, AW_MAX_WALLET);
    val ownerWallet = deployAntiWhaleWallet(owner, minter, 0, AW_MAX_WALLET * 2, 0);

    // Fill recipient up to limit
    injectBalance(minter, recipientWallet, AW_MAX_WALLET - AW_UNIT);

    // Inject lots into owner's wallet (no max limit on sender)
    injectBalance(minter, ownerWallet, AW_MAX_WALLET * 5);

    // Try to transfer 2 units to recipient (which would exceed max_wallet)
    // But wait — the transfer goes through the anti-whale wallet deploy mechanism,
    // and the recipient wallet is already deployed. The deployed recipient wallet
    // is at a different address than what the sender computes (since they have
    // different limits). So let's use minter to inject directly instead.
    //
    // For a direct limit test: just inject balance that exceeds the max.
    val tooMuch = AW_MAX_WALLET + 1;
    val injectRes = injectBalance(minter, recipientWallet, tooMuch);
    expect(injectRes).toHaveFailedTx<InternalTransferStep>({
        from: minter.address,
        to: recipientWallet.address,
        exitCode: 201,
    });
}

get fun `test anti-whale: UpdateWhaleConfig accepted from minterAddress`() {
    val owner = testing.treasury("aw-owner5");
    val minter = testing.treasury("aw-minter5");

    val wallet = deployAntiWhaleWallet(owner, minter, 0, AW_MAX_TRANSFER, AW_MAX_WALLET);

    val newMax = AW_MAX_TRANSFER * 2;
    val newMaxWallet: coins = 0;  // disable
    val res = wallet.sendUpdateWhaleConfig(
        minter.address, 0, newMax, newMaxWallet, { bounce: false, value: ton("0.05") },
    );
    expect(res).toHaveSuccessfulTx<UpdateWhaleConfig>({
        from: minter.address,
        to: wallet.address,
    });

    val (maxTransfer, maxWallet) = wallet.getWhaleConfig();
    expect(maxTransfer).toEqual(newMax);
    expect(maxWallet).toEqual(0);
}

get fun `test anti-whale: UpdateWhaleConfig rejected from non-minter`() {
    val owner = testing.treasury("aw-owner6");
    val minter = testing.treasury("aw-minter6");

    val wallet = deployAntiWhaleWallet(owner, minter, 0, AW_MAX_TRANSFER, AW_MAX_WALLET);

    val res = wallet.sendUpdateWhaleConfig(
        owner.address, 0, AW_MAX_TRANSFER * 2, 0, { bounce: false, value: ton("0.05") },
    );
    expect(res).toHaveFailedTx<UpdateWhaleConfig>({
        from: owner.address,
        to: wallet.address,
        exitCode: Errors.NotOwner,
    });
}

get fun `test anti-whale: max transfer 0 means unlimited`() {
    val owner = testing.treasury("aw-owner7");
    val minter = testing.treasury("aw-minter7");
    val recipient = testing.treasury("aw-recipient4");

    val ownerWallet = deployAntiWhaleWallet(owner, minter, 0, 0, 0);
    injectBalance(minter, ownerWallet, AW_MAX_TRANSFER * 100);

    val res = sendAntiWhaleTransfer(owner, ownerWallet, recipient.address, AW_MAX_TRANSFER * 10);
    expect(res).toHaveSuccessfulTx<AskToTransfer>({ from: owner.address, to: ownerWallet.address });
}
