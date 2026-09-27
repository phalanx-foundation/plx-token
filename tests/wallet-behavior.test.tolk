import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@acton/types/transaction"

import "@contracts/errors"
import "@contracts/messages"
import "@wrappers/JettonWallet.gen"
import "@wrappers/utils"

import "test-utils"

get fun `test wallet: owner can send jettons`() {
    val (minter, deployer, notDeployer) = setupTest();
    val transferAmount = ton("5");
    val senderWallet = mintTo(minter, deployer, deployer.address, ton("20"));
    val receiverWallet = userWallet(minter, notDeployer.address);

    val res = senderWallet.sendTransfer(
        deployer.address,
        DEFAULT_TRANSFER_MSG_VALUE,
        transferAmount,
        notDeployer.address,
        deployer.address,
        null,
        DEFAULT_FORWARD_TON_AMOUNT,
        null,
    );
    expect(res).toHaveSuccessfulTx<AskToTransfer>({
        from: deployer.address,
        to: senderWallet.address,
    });

    expect(senderWallet.getJettonBalance()).toEqual(ton("15"));
    expect(receiverWallet.getJettonBalance()).toEqual(transferAmount);
}

get fun `test wallet: non-owner cannot send jettons`() {
    val (minter, deployer, notDeployer) = setupTest();
    val wallet = mintTo(minter, deployer, deployer.address, ton("7"));
    val balanceBefore = wallet.getJettonBalance();

    val res = wallet.sendTransfer(
        notDeployer.address,
        DEFAULT_TRANSFER_MSG_VALUE,
        ton("3"),
        notDeployer.address,
        deployer.address,
        null,
        DEFAULT_FORWARD_TON_AMOUNT,
        null,
    );
    expect(res).toHaveFailedTx<AskToTransfer>({
        from: notDeployer.address,
        to: wallet.address,
        exitCode: Errors.NotOwner,
    });

    expect(wallet.getJettonBalance()).toEqual(balanceBefore);
}

get fun `test wallet: cannot send more jettons than balance`() {
    val (minter, deployer, notDeployer) = setupTest();
    val wallet = mintTo(minter, deployer, deployer.address, ton("2"));
    val balanceBefore = wallet.getJettonBalance();

    val res = wallet.sendTransfer(
        deployer.address,
        DEFAULT_TRANSFER_MSG_VALUE,
        ton("5"),
        notDeployer.address,
        deployer.address,
        null,
        DEFAULT_FORWARD_TON_AMOUNT,
        null,
    );
    expect(res).toHaveFailedTx<AskToTransfer>({
        from: deployer.address,
        to: wallet.address,
        exitCode: Errors.BalanceError,
    });

    expect(wallet.getJettonBalance()).toEqual(balanceBefore);
}

get fun `test wallet: zero forward ton means no transfer notification`() {
    val (minter, deployer, notDeployer) = setupTest();
    val senderWallet = mintTo(minter, deployer, deployer.address, ton("2"));
    val receiverWallet = userWallet(minter, notDeployer.address);

    val res = senderWallet.sendTransfer(
        deployer.address,
        DEFAULT_TRANSFER_MSG_VALUE,
        ton("1"),
        notDeployer.address,
        deployer.address,
        null,
        0,
        null,
    );
    expect(res).toHaveSuccessfulTx<AskToTransfer>({
        from: deployer.address,
        to: senderWallet.address,
    });
    expect(res).toNotHaveTx<TransferNotificationForRecipient>({
        from: receiverWallet.address,
        to: notDeployer.address,
    });
}

get fun `test wallet: transfer notification should preserve forward payload`() {
    val (minter, deployer, notDeployer) = setupTest();
    val senderWallet = mintTo(minter, deployer, deployer.address, ton("2"));
    val receiverWallet = userWallet(minter, notDeployer.address);
    val sentAmount = ton("0.5");
    val forwardPayload = beginCell().storeUint(0x1234567890abcdef, 128).endCell();

    val res = senderWallet.sendTransfer(
        deployer.address,
        DEFAULT_TRANSFER_MSG_VALUE,
        sentAmount,
        notDeployer.address,
        deployer.address,
        null,
        DEFAULT_FORWARD_TON_AMOUNT,
        forwardPayload,
    );
    expect(res).toHaveSuccessfulTx<AskToTransfer>({
        from: deployer.address,
        to: senderWallet.address,
    });

    val notificationTx = res.findTransaction<TransferNotificationForRecipient>({
        from: receiverWallet.address,
        to: notDeployer.address,
        success: true,
        exitCode: 0,
    });
    expect(notificationTx).toBeNotNull();

    val notification = notificationTx!.loadBody<TransferNotificationForRecipient>();
    var payloadSlice = notification.forwardPayload;
    val payloadRef = payloadSlice.loadMaybeRef();
    expect(payloadRef).toBeNotNull();
    if (payloadRef == null) {
        return;
    }

    var payloadBody = payloadRef.beginParse();
    if (
        payloadBody.remainingBitsCount() == 1 && payloadBody.preloadUint(1) == 1 &&
        payloadBody.remainingRefsCount() == 1
    ) {
        payloadBody.loadUint(1);
        expect(payloadBody.loadRef().hash()).toEqual(forwardPayload.hash());
    } else {
        expect(payloadRef.hash()).toEqual(forwardPayload.hash());
    }
}

get fun `test wallet: bare-ref forward payload is rejected (TEP-74 either required)`() {
    val (minter, deployer, notDeployer) = setupTest();
    val wallet = mintTo(minter, deployer, deployer.address, ton("2"));
    val balanceBefore = wallet.getJettonBalance();

    // A "forward payload in a ref" must be tagged `either$1`: one `1` bit, then
    // the ref (TEP-74, what `storeMaybeRef` writes and what both the DeDust and
    // the STON.fi SDK build). A bare ref carries zero bits, so the wallet's
    // `checkIsCorrectTlbEither` underflows before it can even read the tag.
    // Regressing this turns every two-leg add-LP into a dead leg.
    val bareRefPayload = beginCell().storeRef(makeRichCustomPayload()).endCell().beginParse();
    val body = buildTransferBody(
        ton("1"),
        DEFAULT_FORWARD_TON_AMOUNT,
        notDeployer.address,
        deployer.address,
        bareRefPayload,
    );
    val res = sendRawTransferPayload(deployer.address, wallet.address, body.toCell());

    expect(res).toHaveFailedTx<AskToTransfer>({
        from: deployer.address,
        to: wallet.address,
        exitCode: 9, // cell underflow: the either tag bit is missing
    });
    expect(wallet.getJettonBalance()).toEqual(balanceBefore);

    // The tagged form (`either$1` + ref) is accepted: the leg goes through.
    val taggedPayload = beginCell().storeMaybeRef(makeRichCustomPayload()).endCell().beginParse();
    val okBody = buildTransferBody(
        ton("1"),
        DEFAULT_FORWARD_TON_AMOUNT,
        notDeployer.address,
        deployer.address,
        taggedPayload,
    );
    val okRes = sendRawTransferPayload(deployer.address, wallet.address, okBody.toCell());
    expect(okRes).toHaveSuccessfulTx<AskToTransfer>({
        from: deployer.address,
        to: wallet.address,
    });
}

get fun `test wallet: transfer to undeployed recipient wallet should still work`() {
    val (minter, deployer, _) = setupTest();
    val senderWallet = mintTo(minter, deployer, deployer.address, ton("2"));
    val recipientOwner = randomAddress();
    val recipientWallet = userWallet(minter, recipientOwner);
    val sentAmount = ton("0.5");

    val res = senderWallet.sendTransfer(
        deployer.address,
        DEFAULT_TRANSFER_MSG_VALUE,
        sentAmount,
        recipientOwner,
        deployer.address,
        null,
        0,
        null,
    );

    expect(res).toHaveAllSuccessfulTxs();
    expect(res).toHaveSuccessfulTx<AskToTransfer>({
        from: deployer.address,
        to: senderWallet.address,
    });
    expect(recipientWallet.getJettonBalance()).toEqual(sentAmount);
}

get fun `test wallet: owner can burn jettons`() {
    val (minter, deployer, _) = setupTest();
    val burnAmount = ton("3");
    val wallet = mintTo(minter, deployer, deployer.address, ton("10"));
    val supplyBefore = minter.getTotalSupply();

    val res = wallet.sendAskToBurn(
        deployer.address,
        0,
        burnAmount,
        deployer.address,
        null,
        { bounce: false, value: DEFAULT_BURN_MSG_VALUE },
    );
    expect(res).toHaveSuccessfulTx<AskToBurn>({
        from: deployer.address,
        to: wallet.address,
    });

    expect(wallet.getJettonBalance()).toEqual(ton("7"));
    expect(minter.getTotalSupply()).toEqual(supplyBefore - burnAmount);
}

get fun `test wallet: non-owner cannot burn jettons`() {
    val (minter, deployer, notDeployer) = setupTest();
    val wallet = mintTo(minter, deployer, deployer.address, ton("6"));
    val balanceBefore = wallet.getJettonBalance();
    val supplyBefore = minter.getTotalSupply();

    val res = wallet.sendAskToBurn(
        notDeployer.address,
        0,
        ton("2"),
        deployer.address,
        null,
        { bounce: false, value: DEFAULT_BURN_MSG_VALUE },
    );
    expect(res).toHaveFailedTx<AskToBurn>({
        from: notDeployer.address,
        to: wallet.address,
        exitCode: Errors.NotOwner,
    });

    expect(wallet.getJettonBalance()).toEqual(balanceBefore);
    expect(minter.getTotalSupply()).toEqual(supplyBefore);
}

get fun `test wallet: cannot burn more jettons than balance`() {
    val (minter, deployer, _) = setupTest();
    val wallet = mintTo(minter, deployer, deployer.address, ton("1"));
    val balanceBefore = wallet.getJettonBalance();
    val supplyBefore = minter.getTotalSupply();

    val res = wallet.sendAskToBurn(
        deployer.address,
        0,
        ton("5"),
        deployer.address,
        null,
        { bounce: false, value: DEFAULT_BURN_MSG_VALUE },
    );
    expect(res).toHaveFailedTx<AskToBurn>({
        from: deployer.address,
        to: wallet.address,
        exitCode: Errors.BalanceError,
    });

    expect(wallet.getJettonBalance()).toEqual(balanceBefore);
    expect(minter.getTotalSupply()).toEqual(supplyBefore);
}
