import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"

import "@contracts/FeeJettonMinter"
import "@contracts/FeeJettonWallet"
import "@contracts/fee-types"
import "@contracts/errors"
import "@contracts/messages"
import "@contracts/storage"
import "@wrappers/FeeJettonMinter.gen"
import "@wrappers/FeeJettonWallet.gen"
import "@wrappers/utils"

import "test-utils"

const FEE_PLX_UNIT = 1000000000
const FEE_TEST_SUPPLY = 1000000 * FEE_PLX_UNIT
const TEST_FEE_BPS: uint16 = 500  // 5%

fun makeFeeForwardPayload(): slice {
    return beginCell().storeUint(0, 1).toSlice();
}

fun setupFeeJetton(feeBps: uint16): (FeeJettonMinter, Treasury, Treasury, Treasury) {
    val deployer = testing.treasury("fee-deployer");
    val collector = testing.treasury("fee-collector");
    val user = testing.treasury("fee-user");

    val feeConfig: FeeMinterConfig = {
        feeBps,
        feeCollector: collector.address,
    };

    val minter = FeeJettonMinter.fromStorage({
        totalSupply: 0,
        adminAddress: deployer.address,
        nextAdminAddress: null,
        metadata: buildTestMetadata("fee-plx-test"),
        feeConfig: feeConfig.toCell(),
    });
    expect(minter.sendDeploy(deployer.address, { value: ton("10") })).toHaveSuccessfulDeploy({
        to: minter.address,
    });

    return (minter, deployer, collector, user);
}

fun feeUserWallet(minter: FeeJettonMinter, userAddress: address): FeeJettonWallet {
    val address = minter.getWalletAddress(userAddress);
    return FeeJettonWallet { address };
}

fun mintFeeTokens(
    minter: FeeJettonMinter,
    admin: Treasury,
    recipient: address,
    amount: coins,
): FeeJettonWallet {
    val res = minter.sendMint(admin.address, recipient, amount, ton("0.05"), ton("0.5"));
    expect(res).toHaveSuccessfulTx<MintNewJettons>({ from: admin.address, to: minter.address });
    return feeUserWallet(minter, recipient);
}

fun sendFeeTransfer(
    from: Treasury,
    wallet: FeeJettonWallet,
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
        forwardPayload: makeFeeForwardPayload(),
    };
    return sendRawTransferPayload(from.address, wallet.address, body.toCell(), value);
}

get fun `test fee-jetton: deploy initialises fee config`() {
    val (minter, deployer, collector, _) = setupFeeJetton(TEST_FEE_BPS);

    val (feeBps, feeCollector) = minter.getFeeConfig();
    expect(feeBps).toEqual(TEST_FEE_BPS);
    expect(feeCollector).toEqual(collector.address);
}

get fun `test fee-jetton: mint succeeds and wallet has correct balance`() {
    val (minter, deployer, _, user) = setupFeeJetton(TEST_FEE_BPS);
    val amount = 10000 * FEE_PLX_UNIT;

    val wallet = mintFeeTokens(minter, deployer, user.address, amount);
    expect(wallet.getJettonBalance()).toEqual(amount);
    expect(minter.getTotalSupply()).toEqual(amount);
}

get fun `test fee-jetton: transfer deducts fee from recipient and sends to collector`() {
    val (minter, deployer, collector, user) = setupFeeJetton(TEST_FEE_BPS);
    val transferAmount = 10000 * FEE_PLX_UNIT;
    val recipient = testing.treasury("fee-recipient");

    val userWallet = mintFeeTokens(minter, deployer, user.address, transferAmount * 10);

    val beforeUserBal = userWallet.getJettonBalance();
    val res = sendFeeTransfer(user, userWallet, recipient.address, transferAmount);
    expect(res).toHaveSuccessfulTx<AskToTransfer>({ from: user.address, to: userWallet.address });

    val expectedFee = transferAmount * TEST_FEE_BPS / 10000;
    val expectedActual = transferAmount - expectedFee;

    val afterUserBal = userWallet.getJettonBalance();
    expect(beforeUserBal - afterUserBal).toEqual(transferAmount);

    val recipientWallet = feeUserWallet(minter, recipient.address);
    expect(recipientWallet.getJettonBalance()).toEqual(expectedActual);

    val collectorWallet = feeUserWallet(minter, collector.address);
    expect(collectorWallet.getJettonBalance()).toEqual(expectedFee);
}

get fun `test fee-jetton: zero fee means no fee deduction`() {
    val (minter, deployer, collector, user) = setupFeeJetton(0);
    val transferAmount = 5000 * FEE_PLX_UNIT;
    val recipient = testing.treasury("fee-zero-recipient");

    val userWallet = mintFeeTokens(minter, deployer, user.address, transferAmount * 2);
    sendFeeTransfer(user, userWallet, recipient.address, transferAmount);

    val recipientWallet = feeUserWallet(minter, recipient.address);
    expect(recipientWallet.getJettonBalance()).toEqual(transferAmount);

    // Collector should have zero since feeBps=0
    val collectorWallet = feeUserWallet(minter, collector.address);
    expect(collectorWallet.getJettonBalance()).toEqual(0);
}

get fun `test fee-jetton: UpdateFeeConfig on minter accepted from admin`() {
    val (minter, deployer, _, _) = setupFeeJetton(TEST_FEE_BPS);
    val newCollector = testing.treasury("new-collector");

    val res = minter.sendUpdateFeeConfig(
        deployer.address, 0, 200, newCollector.address, { bounce: false, value: ton("0.1") },
    );
    expect(res).toHaveSuccessfulTx<UpdateFeeConfig>({ from: deployer.address, to: minter.address });

    val (newBps, newColl) = minter.getFeeConfig();
    expect(newBps).toEqual(200);
    expect(newColl).toEqual(newCollector.address);
}

get fun `test fee-jetton: UpdateFeeConfig rejected if fee_bps > 1000`() {
    val (minter, deployer, _, _) = setupFeeJetton(TEST_FEE_BPS);
    val collector = testing.treasury("bad-collector");

    val res = minter.sendUpdateFeeConfig(
        deployer.address, 0, 1001, collector.address, { bounce: false, value: ton("0.1") },
    );
    expect(res).toHaveFailedTx<UpdateFeeConfig>({
        from: deployer.address,
        to: minter.address,
        exitCode: Errors.InvalidOp,
    });
}

get fun `test fee-jetton: UpdateFeeConfig on minter rejected from non-admin`() {
    val (minter, _, _, user) = setupFeeJetton(TEST_FEE_BPS);
    val collector = testing.treasury("bad-collector2");

    val res = minter.sendUpdateFeeConfig(
        user.address, 0, 100, collector.address, { bounce: false, value: ton("0.1") },
    );
    expect(res).toHaveFailedTx<UpdateFeeConfig>({
        from: user.address,
        to: minter.address,
        exitCode: Errors.NotOwner,
    });
}

get fun `test fee-jetton: UpdateFeeConfig on wallet rejected from non-minter`() {
    val (minter, deployer, collector, user) = setupFeeJetton(TEST_FEE_BPS);
    val amount = 1000 * FEE_PLX_UNIT;
    val userWallet = mintFeeTokens(minter, deployer, user.address, amount);

    // Send from user (not minter) — should fail
    val res = userWallet.sendUpdateFeeConfig(
        user.address, 0, 100, collector.address, { bounce: false, value: ton("0.05") },
    );
    expect(res).toHaveFailedTx<UpdateFeeConfig>({
        from: user.address,
        to: userWallet.address,
        exitCode: Errors.NotOwner,
    });
}
