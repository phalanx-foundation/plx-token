import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"

import "@contracts/PaymentSplitter"
import "@contracts/errors"
import "@contracts/messages"
import "@contracts/storage"
import "@wrappers/JettonMinter.gen"
import "@wrappers/PaymentSplitter.gen"
import "@wrappers/utils"

import "test-utils"

const DEPLOY_FEE_PLX = 2500000000
const TINY_AMOUNT = 100000

fun setupSplitter(): (JettonMinter, PaymentSplitter, Treasury, Treasury, Treasury) {
    val deployer = testing.treasury("splitter-deployer");
    val treasury = testing.treasury("splitter-treasury");
    val payer = testing.treasury("splitter-payer");

    val minter = JettonMinter.fromStorage({
        totalSupply: 0,
        adminAddress: deployer.address,
        nextAdminAddress: null,
        metadata: buildTestMetadata("plx-splitter-test"),
    });
    val deployRes = minter.sendDeploy(deployer.address, { value: ton("10") });
    expect(deployRes).toHaveSuccessfulDeploy({ to: minter.address });

    val splitter = PaymentSplitter.fromStorage({
        minterAddress: minter.address,
        treasuryAddress: treasury.address,
        admin: deployer.address,
        burnedTotal: 0,
        forwardedTotal: 0,
        deployCount: 0,
    });
    val splitterDeployRes = splitter.sendDeploy(deployer.address, { value: ton("3") });
    expect(splitterDeployRes).toHaveSuccessfulDeploy({ to: splitter.address });

    val mintRes = minter.sendMint(
        deployer.address,
        payer.address,
        DEPLOY_FEE_PLX * 10,
        ton("0.05"),
        ton("0.5"),
    );
    expect(mintRes).toHaveSuccessfulTx<MintNewJettons>({
        from: deployer.address,
        to: minter.address,
    });

    return (minter, splitter, deployer, treasury, payer);
}

fun payerSendsToSplitter(
    minter: JettonMinter,
    splitter: PaymentSplitter,
    payer: Treasury,
    amount: coins,
    queryId: uint64 = 0,
    forwardTon: coins = 200000000,
    msgValue: coins = 400000000,
): SendResultList {
    val payerWallet = userWallet(minter, payer.address);
    val transferBody = AskToTransfer {
        queryId,
        jettonAmount: amount,
        transferRecipient: splitter.address,
        sendExcessesTo: payer.address,
        customPayload: null,
        forwardTonAmount: forwardTon,
        forwardPayload: makeTinyForwardPayload(),
    };
    return sendRawTransferPayload(payer.address, payerWallet.address, transferBody.toCell(), msgValue);
}

get fun `test splitter: deploy initialises storage with zero counters`() {
    val (_, splitter, _, treasury, _) = setupSplitter();

    val data = splitter.getSplitterData();
    expect(data.treasuryAddress).toEqual(treasury.address);
    expect(data.burnedTotal).toEqual(0);
    expect(data.forwardedTotal).toEqual(0);
    expect(data.deployCount).toEqual(0);
    expect(splitter.getDeployCount()).toEqual(0);
}

get fun `test splitter: jetton wallet address get matches minter`() {
    val (minter, splitter, _, _, _) = setupSplitter();
    val expected = minter.getWalletAddress(splitter.address);
    expect(splitter.getJettonWalletAddress()).toEqual(expected);
}

get fun `test splitter: even amount splits exactly 50/50`() {
    val (minter, splitter, _, treasury, payer) = setupSplitter();

    val supplyBefore = minter.getTotalSupply();
    val res = payerSendsToSplitter(minter, splitter, payer, DEPLOY_FEE_PLX);

    expect(res).toHaveSuccessfulTx<TransferNotificationForRecipient>({
        to: splitter.address,
    });

    val expectedHalf = DEPLOY_FEE_PLX / 2;
    val supplyAfter = minter.getTotalSupply();
    expect(supplyBefore - supplyAfter).toEqual(expectedHalf);

    val treasuryWallet = userWallet(minter, treasury.address);
    expect(treasuryWallet.getJettonBalance()).toEqual(expectedHalf);

    expect(splitter.getBurnedTotal()).toEqual(expectedHalf);
    expect(splitter.getForwardedTotal()).toEqual(expectedHalf);
    expect(splitter.getDeployCount()).toEqual(1);
}

get fun `test splitter: odd amount remainder goes to treasury`() {
    val (minter, splitter, _, treasury, payer) = setupSplitter();

    val odd = DEPLOY_FEE_PLX + 1;
    payerSendsToSplitter(minter, splitter, payer, odd);

    val expectedBurn = odd / 2;
    val expectedForward = odd - expectedBurn;
    expect(expectedForward).toEqual(expectedBurn + 1);

    expect(splitter.getBurnedTotal()).toEqual(expectedBurn);
    expect(splitter.getForwardedTotal()).toEqual(expectedForward);

    val treasuryWallet = userWallet(minter, treasury.address);
    expect(treasuryWallet.getJettonBalance()).toEqual(expectedForward);
}

get fun `test splitter: tiny amount still settles`() {
    val (minter, splitter, _, treasury, payer) = setupSplitter();

    payerSendsToSplitter(minter, splitter, payer, TINY_AMOUNT, 0, 200000000, 500000000);

    val expectedBurn = TINY_AMOUNT / 2;
    val expectedForward = TINY_AMOUNT - expectedBurn;
    expect(splitter.getBurnedTotal()).toEqual(expectedBurn);
    expect(splitter.getForwardedTotal()).toEqual(expectedForward);

    val treasuryWallet = userWallet(minter, treasury.address);
    expect(treasuryWallet.getJettonBalance()).toEqual(expectedForward);
}

get fun `test splitter: counters accumulate across multiple payments`() {
    val (minter, splitter, _, treasury, payer) = setupSplitter();

    payerSendsToSplitter(minter, splitter, payer, DEPLOY_FEE_PLX, 0);
    payerSendsToSplitter(minter, splitter, payer, DEPLOY_FEE_PLX, 1);
    payerSendsToSplitter(minter, splitter, payer, DEPLOY_FEE_PLX, 2);

    val expectedHalf = DEPLOY_FEE_PLX / 2;
    expect(splitter.getBurnedTotal()).toEqual(expectedHalf * 3);
    expect(splitter.getForwardedTotal()).toEqual(expectedHalf * 3);
    expect(splitter.getDeployCount()).toEqual(3);

    val treasuryWallet = userWallet(minter, treasury.address);
    expect(treasuryWallet.getJettonBalance()).toEqual(expectedHalf * 3);
}

get fun `test splitter: notification from non-jetton-wallet is rejected`() {
    val (_, splitter, _, _, payer) = setupSplitter();

    val fakeBody = TransferNotificationForRecipient {
        queryId: 0,
        jettonAmount: DEPLOY_FEE_PLX,
        transferInitiator: payer.address,
        forwardPayload: makeTinyForwardPayload(),
    };

    val outMessage = createMessage({
        bounce: true,
        value: ton("0.4"),
        dest: splitter.address,
        body: fakeBody.toCell(),
    });
    val res = net.send(payer.address, outMessage);

    expect(res).toHaveFailedTx<TransferNotificationForRecipient>({
        from: payer.address,
        to: splitter.address,
        exitCode: Errors.NotValidWallet,
    });
}

get fun `test splitter: zero-amount notification is a no-op`() {
    val (minter, splitter, _, _, payer) = setupSplitter();

    payerSendsToSplitter(minter, splitter, payer, 0, 0, 200000000, 400000000);

    expect(splitter.getBurnedTotal()).toEqual(0);
    expect(splitter.getForwardedTotal()).toEqual(0);
    expect(splitter.getDeployCount()).toEqual(0);
}

get fun `test splitter: admin can withdraw excess TON`() {
    val (_, splitter, deployer, _, _) = setupSplitter();

    val topUpRes = splitter.sendTopUpTons(deployer.address, { bounce: false, value: ton("2") });
    expect(topUpRes).toHaveSuccessfulTx<TopUpTons>({
        from: deployer.address,
        to: splitter.address,
    });

    val res = splitter.sendWithdrawSplitterTons(
        deployer.address,
        0,
        ton("0.5"),
        { bounce: false, value: ton("0.05") },
    );
    expect(res).toHaveSuccessfulTx<WithdrawSplitterTons>({
        from: deployer.address,
        to: splitter.address,
    });
}

get fun `test splitter: non-admin cannot withdraw TON`() {
    val (_, splitter, _, _, payer) = setupSplitter();

    val res = splitter.sendWithdrawSplitterTons(
        payer.address,
        0,
        ton("0.1"),
        { bounce: false, value: ton("0.05") },
    );
    expect(res).toHaveFailedTx<WithdrawSplitterTons>({
        from: payer.address,
        to: splitter.address,
        exitCode: Errors.NotOwner,
    });
}

get fun `test splitter: top-up tons accepted from anyone`() {
    val (_, splitter, _, _, payer) = setupSplitter();

    val res = splitter.sendTopUpTons(payer.address, { bounce: false, value: ton("0.5") });
    expect(res).toHaveSuccessfulTx<TopUpTons>({
        from: payer.address,
        to: splitter.address,
    });
}

get fun `test splitter: total burned + forwarded equals total processed`() {
    val (minter, splitter, _, _, payer) = setupSplitter();

    payerSendsToSplitter(minter, splitter, payer, DEPLOY_FEE_PLX, 0);
    payerSendsToSplitter(minter, splitter, payer, DEPLOY_FEE_PLX + 7, 1);

    val burned = splitter.getBurnedTotal();
    val forwarded = splitter.getForwardedTotal();
    expect(burned + forwarded).toEqual(DEPLOY_FEE_PLX + DEPLOY_FEE_PLX + 7);
}
