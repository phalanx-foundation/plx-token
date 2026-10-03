import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"

import "@contracts/AntiWhaleJettonWallet"
import "@contracts/antiwhale-types"
import "@contracts/errors"
import "@contracts/messages"
import "@wrappers/AntiWhaleJettonMinter.gen"
import "@wrappers/AntiWhaleJettonWallet.gen"

import "test-utils"

const AW_MINTER_UNIT = 1000000000
const AW_MINTER_MAX_TRANSFER = 1000 * AW_MINTER_UNIT
const AW_MINTER_MAX_WALLET = 5000 * AW_MINTER_UNIT

/// Deploy an AntiWhaleJettonMinter with the given caps and `admin` in charge.
fun deployWhaleMinter(admin: Treasury, maxTransfer: coins, maxWallet: coins): AntiWhaleJettonMinter {
    val whaleConfig: WhaleConfig = {
        maxTransferAmount: maxTransfer,
        maxWalletBalance: maxWallet,
    };
    val storage: AntiWhaleMinterStorage = {
        totalSupply: 0,
        adminAddress: admin.address,
        nextAdminAddress: null,
        metadata: buildTestMetadata("whale-link"),
        whaleConfig: whaleConfig.toCell(),
    };
    val minter = AntiWhaleJettonMinter.fromStorage(storage);
    expect(minter.deploy(admin.address, { value: ton("5") })).toHaveSuccessfulDeploy({
        to: minter.address,
    });
    return minter;
}

/// The whale wallet address the minter itself reports for `owner`. Every
/// assertion below uses this address on purpose: if the minter's copy of the
/// wallet init data ever drifted from the wallet contract's own copy, transfers
/// would land somewhere else and these tests would fail.
fun whaleWallet(minter: AntiWhaleJettonMinter, owner: address): AntiWhaleJettonWallet {
    return AntiWhaleJettonWallet { address: minter.getWalletAddress(owner) };
}

fun whaleMintBody(amount: coins, sendExcessesTo: address): InternalTransferStep {
    return InternalTransferStep {
        queryId: 0,
        jettonAmount: amount,
        transferInitiator: null,
        sendExcessesTo,
        forwardTonAmount: 0,
        forwardPayload: makeTinyForwardPayload(),
    };
}

fun mintWhaleJettons(
    minter: AntiWhaleJettonMinter,
    admin: Treasury,
    recipient: address,
    amount: coins,
): SendResultList {
    return minter.sendMintNewJettons(
        admin.address,
        0,
        recipient,
        ton("0.05"),
        whaleMintBody(amount, admin.address),
        { value: ton("0.3") },
    );
}

get fun `test anti-whale minter: deploy stores the caps and the minter metadata`() {
    val admin = testing.treasury("awm-admin");
    val minter = deployWhaleMinter(admin, AW_MINTER_MAX_TRANSFER, AW_MINTER_MAX_WALLET);

    val (maxTransfer, maxWallet) = minter.getWhaleConfig();
    expect(maxTransfer).toEqual(AW_MINTER_MAX_TRANSFER);
    expect(maxWallet).toEqual(AW_MINTER_MAX_WALLET);

    val data = minter.getJettonData();
    expect(data.totalSupply).toEqual(0);
    expect(data.mintable).toEqual(true);
    expect(data.adminAddress).toEqual(admin.address);
}

get fun `test anti-whale minter: mint credits the wallet the minter reports`() {
    val admin = testing.treasury("awm-admin2");
    val owner = testing.treasury("awm-owner");
    val minter = deployWhaleMinter(admin, AW_MINTER_MAX_TRANSFER, AW_MINTER_MAX_WALLET);

    val amount = AW_MINTER_MAX_TRANSFER * 2;
    expect(mintWhaleJettons(minter, admin, owner.address, amount)).toHaveSuccessfulTx<MintNewJettons>({
        from: admin.address,
        to: minter.address,
    });

    expect(whaleWallet(minter, owner.address).getJettonBalance()).toEqual(amount);
    expect(minter.getJettonData().totalSupply).toEqual(amount);
}

get fun `test anti-whale minter: mint from a non-admin is rejected`() {
    val admin = testing.treasury("awm-admin3");
    val stranger = testing.treasury("awm-stranger");
    val minter = deployWhaleMinter(admin, AW_MINTER_MAX_TRANSFER, AW_MINTER_MAX_WALLET);

    expect(mintWhaleJettons(minter, stranger, stranger.address, AW_MINTER_MAX_TRANSFER))
        .toHaveFailedTx<MintNewJettons>({
            from: stranger.address,
            to: minter.address,
            exitCode: Errors.NotOwner,
        });
}

get fun `test anti-whale minter: transfer above max transfer is rejected with 200`() {
    val admin = testing.treasury("awm-admin4");
    val owner = testing.treasury("awm-owner2");
    val recipient = testing.treasury("awm-recipient");
    val minter = deployWhaleMinter(admin, AW_MINTER_MAX_TRANSFER, AW_MINTER_MAX_WALLET);

    mintWhaleJettons(minter, admin, owner.address, AW_MINTER_MAX_TRANSFER * 2);
    val ownerWallet = whaleWallet(minter, owner.address);

    val body = buildTransferBody(
        AW_MINTER_MAX_TRANSFER + 1,
        0,
        recipient.address,
        owner.address,
        makeTinyForwardPayload(),
    );
    expect(sendRawTransferPayload(owner.address, ownerWallet.address, body.toCell(), ton("0.4")))
        .toHaveFailedTx<AskToTransfer>({
            from: owner.address,
            to: ownerWallet.address,
            exitCode: 200,
        });

    // The rejected transfer must not move any balance.
    expect(ownerWallet.getJettonBalance()).toEqual(AW_MINTER_MAX_TRANSFER * 2);
}

get fun `test anti-whale minter: credit above max wallet balance is rejected with 201`() {
    val admin = testing.treasury("awm-admin5");
    val owner = testing.treasury("awm-owner3");
    // A generous per-transfer cap lets the credit itself be the failing limit.
    val minter = deployWhaleMinter(admin, AW_MINTER_MAX_WALLET * 4, AW_MINTER_MAX_WALLET);

    val walletAddress = minter.getWalletAddress(owner.address);
    val tooMuch = AW_MINTER_MAX_WALLET + 1;

    // Goes through the real mint path: the minter books the supply, the wallet
    // rejects the credit, and the bounce must restore the supply exactly.
    expect(mintWhaleJettons(minter, admin, owner.address, tooMuch))
        .toHaveFailedTx<InternalTransferStep>({
            from: minter.address,
            to: walletAddress,
            exitCode: 201,
        });

    expect(whaleWallet(minter, owner.address).getJettonBalance()).toEqual(0);
    expect(minter.getJettonData().totalSupply).toEqual(0);
}

get fun `test anti-whale minter: transfer between two of its wallets lands where the minter says`() {
    val admin = testing.treasury("awm-admin6");
    val owner = testing.treasury("awm-owner4");
    val recipient = testing.treasury("awm-recipient2");
    val minter = deployWhaleMinter(admin, AW_MINTER_MAX_TRANSFER, AW_MINTER_MAX_WALLET);

    mintWhaleJettons(minter, admin, owner.address, AW_MINTER_MAX_TRANSFER * 2);

    val ownerWallet = whaleWallet(minter, owner.address);
    val body = buildTransferBody(
        AW_MINTER_MAX_TRANSFER,
        0,
        recipient.address,
        owner.address,
        makeTinyForwardPayload(),
    );
    expect(sendRawTransferPayload(owner.address, ownerWallet.address, body.toCell(), ton("0.4")))
        .toHaveSuccessfulTx<AskToTransfer>({
            from: owner.address,
            to: ownerWallet.address,
        });

    expect(ownerWallet.getJettonBalance()).toEqual(AW_MINTER_MAX_TRANSFER);
    expect(whaleWallet(minter, recipient.address).getJettonBalance()).toEqual(AW_MINTER_MAX_TRANSFER);
}

get fun `test anti-whale minter: zero cap means unlimited`() {
    val admin = testing.treasury("awm-admin7");
    val owner = testing.treasury("awm-owner5");
    val recipient = testing.treasury("awm-recipient3");
    val minter = deployWhaleMinter(admin, 0, 0);

    mintWhaleJettons(minter, admin, owner.address, AW_MINTER_MAX_TRANSFER * 100);

    val ownerWallet = whaleWallet(minter, owner.address);
    val body = buildTransferBody(
        AW_MINTER_MAX_TRANSFER * 10,
        0,
        recipient.address,
        owner.address,
        makeTinyForwardPayload(),
    );
    expect(sendRawTransferPayload(owner.address, ownerWallet.address, body.toCell(), ton("0.4")))
        .toHaveSuccessfulTx<AskToTransfer>({
            from: owner.address,
            to: ownerWallet.address,
        });

    expect(whaleWallet(minter, recipient.address).getJettonBalance())
        .toEqual(AW_MINTER_MAX_TRANSFER * 10);
}

get fun `test anti-whale minter: admin handover waits for the new admin to claim`() {
    val admin = testing.treasury("awm-admin8");
    val client = testing.treasury("awm-client");
    val minter = deployWhaleMinter(admin, AW_MINTER_MAX_TRANSFER, AW_MINTER_MAX_WALLET);

    expect(minter.sendChangeMinterAdmin(admin.address, 0, client.address, { value: ton("0.1") }))
        .toHaveSuccessfulTx<ChangeMinterAdmin>({
            from: admin.address,
            to: minter.address,
        });

    // Still owned by the old admin until the new one claims.
    expect(minter.getJettonData().adminAddress).toEqual(admin.address);
    expect(minter.getNextAdminAddress()).toEqual(client.address);

    expect(minter.sendClaimMinterAdmin(client.address, 0, { value: ton("0.1") }))
        .toHaveSuccessfulTx<ClaimMinterAdmin>({
            from: client.address,
            to: minter.address,
        });

    expect(minter.getJettonData().adminAddress).toEqual(client.address);
    expect(minter.getNextAdminAddress()).toEqual(null);

    // The previous admin is now powerless.
    expect(mintWhaleJettons(minter, admin, admin.address, AW_MINTER_MAX_TRANSFER))
        .toHaveFailedTx<MintNewJettons>({
            from: admin.address,
            to: minter.address,
            exitCode: Errors.NotOwner,
        });
}
