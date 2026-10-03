import "@gen/AntiWhaleJettonWallet.code"
import "antiwhale-types"
import "errors"
import "fees-management"
import "jetton-utils"
import "messages"
import "sharding"
import "storage"

contract AntiWhaleJettonMinter {
    author: "Phalanx Foundation"
    version: "1.0.0"
    description: "Anti-Whale Jetton Minter: deploys AntiWhaleJettonWallet instances that reject a single transfer above maxTransferAmount (error 200) and a credit above maxWalletBalance (error 201). Limits live in minter storage so every wallet it deploys shares the same caps."
    storage: AntiWhaleMinterStorage
    incomingMessages: AllowedMessageToAntiWhaleMinter
}

type AllowedMessageToAntiWhaleMinter =
    | MintNewJettons
    | BurnNotificationForMinter
    | RequestWalletAddress
    | ChangeMinterAdmin
    | ClaimMinterAdmin
    | DropMinterAdmin
    | ChangeMinterMetadata
    | UpgradeMinterCode
    | TopUpTons

fun antiWhaleWalletCode(): cell {
    return antiWhaleJettonWalletCompiledCode();
}

fun onBouncedMessage(in: InMessageBounced) {
    in.bouncedBody.skipBouncedPrefix();
    val msg = lazy InternalTransferStep.fromSlice(in.bouncedBody);

    var storage = lazy AntiWhaleMinterStorage.load();
    storage.totalSupply -= msg.jettonAmount;
    storage.save();
}

fun assertSenderIsWhaleAdmin(senderAddress: address, adminAddress: address?) {
    assert (senderAddress == adminAddress!) throw Errors.NotOwner;
}

fun onInternalMessage(in: InMessage) {
    // Accept deploy / bare top-up with empty body. The generated wrapper's
    // deploy() sends no body, and plain TON top-ups to a minter are harmless.
    if (in.body.remainingBitsCount() == 0 && in.body.remainingRefsCount() == 0) {
        return;
    }

    val msg = lazy AllowedMessageToAntiWhaleMinter.fromSlice(in.body);

    match (msg) {
        BurnNotificationForMinter => {
            var storage = lazy AntiWhaleMinterStorage.load();
            val limits = storage.whaleConfig.load();
            assert (
                in.senderAddress ==
                calcWhaleWalletAddress(
                    msg.burnInitiator,
                    contract.getAddress(),
                    antiWhaleWalletCode(),
                    limits.maxTransferAmount,
                    limits.maxWalletBalance,
                )
            ) throw Errors.NotValidWallet;
            storage.totalSupply -= msg.jettonAmount;
            storage.save();

            if (msg.sendExcessesTo == null) {
                return;
            }

            val excessesMsg = createMessage({
                bounce: BounceMode.NoBounce,
                dest: msg.sendExcessesTo,
                value: 0,
                body: ReturnExcessesBack { queryId: msg.queryId },
            });
            excessesMsg.send(SEND_MODE_IGNORE_ERRORS | SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
        }

        RequestWalletAddress => {
            val ownerAddress: Cell<address>? = msg.includeOwnerAddress
                ? msg.ownerAddress.toCell()
                : null;

            var walletAddress: address? = null;
            if (msg.ownerAddress.getWorkchain() == MY_WORKCHAIN) {
                val limits = AntiWhaleMinterStorage.load().whaleConfig.load();
                walletAddress = calcWhaleWalletAddress(
                    msg.ownerAddress,
                    contract.getAddress(),
                    antiWhaleWalletCode(),
                    limits.maxTransferAmount,
                    limits.maxWalletBalance,
                );
            }

            val respondMsg = createMessage({
                bounce: BounceMode.NoBounce,
                dest: in.senderAddress,
                value: 0,
                body: ResponseWalletAddress {
                    queryId: msg.queryId,
                    jettonWalletAddress: walletAddress,
                    ownerAddress,
                },
            });
            respondMsg.send(
                SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE | SEND_MODE_BOUNCE_ON_ACTION_FAIL,
            );
        }

        MintNewJettons => {
            var storage = lazy AntiWhaleMinterStorage.load();
            assertSenderIsWhaleAdmin(in.senderAddress, storage.adminAddress);
            assert (msg.mintRecipient.getWorkchain() == MY_WORKCHAIN) throw Errors.WrongWorkchain;

            val internalTransferMsg = lazy msg
                .internalTransferMsg
                .load({ throwIfOpcodeDoesNotMatch: Errors.InvalidOp });
            val forwardTonAmount = internalTransferMsg.forwardTonAmount;
            internalTransferMsg.forwardPayload.checkIsCorrectTlbEither();

            checkAmountIsEnoughToTransfer(msg.tonAmount, forwardTonAmount, in.originalForwardFee);

            storage.totalSupply += internalTransferMsg.jettonAmount;
            storage.save();

            reserveToncoinsOnBalance(
                ton("0.01"),
                RESERVE_MODE_EXACT_AMOUNT,
            );

            val limits = storage.whaleConfig.load();
            val deployMsg = createMessage({
                bounce: BounceMode.Only256BitsOfBody,
                dest: calcWhaleWalletDeployAddress(
                    msg.mintRecipient,
                    contract.getAddress(),
                    antiWhaleWalletCode(),
                    limits.maxTransferAmount,
                    limits.maxWalletBalance,
                ),
                value: msg.tonAmount,
                body: msg.internalTransferMsg,
            });
            deployMsg.send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_BOUNCE_ON_ACTION_FAIL);
        }

        ChangeMinterAdmin => {
            var storage = lazy AntiWhaleMinterStorage.load();
            assertSenderIsWhaleAdmin(in.senderAddress, storage.adminAddress);
            storage.nextAdminAddress = msg.newAdminAddress;
            storage.save();
        }

        ClaimMinterAdmin => {
            var storage = lazy AntiWhaleMinterStorage.load();
            assertSenderIsWhaleAdmin(in.senderAddress, storage.nextAdminAddress);
            storage.adminAddress = storage.nextAdminAddress;
            storage.nextAdminAddress = null;
            storage.save();
        }

        DropMinterAdmin => {
            // Official revoke: set admin to burn MsgAddressInt (docs.ton.org),
            // NOT null/addr_none: empty admin breaks TonAPI jetton catalog indexing.
            var storage = lazy AntiWhaleMinterStorage.load();
            assertSenderIsWhaleAdmin(in.senderAddress, storage.adminAddress);
            storage.adminAddress = burnAdminAddress();
            storage.nextAdminAddress = null;
            storage.save();
        }

        ChangeMinterMetadata => {
            var storage = lazy AntiWhaleMinterStorage.load();
            assertSenderIsWhaleAdmin(in.senderAddress, storage.adminAddress);
            storage.metadata = msg.newMetadata;
            storage.save();
        }

        UpgradeMinterCode => {
            val storage = lazy AntiWhaleMinterStorage.load();
            assertSenderIsWhaleAdmin(in.senderAddress, storage.adminAddress);
            contract.setCodePostponed(msg.newCode);
            contract.setData(msg.newData);
        }

        TopUpTons => {
            // just accept tons
        }

        else => throw 0xFFFF,
    }
}

get fun get_jetton_data(): JettonDataReply {
    val storage = lazy AntiWhaleMinterStorage.load();

    return {
        totalSupply: storage.totalSupply,
        mintable: isActiveMinterAdmin(storage.adminAddress),
        adminAddress: jettonDataAdminAddress(storage.adminAddress),
        jettonContent: storage.metadata as Cell<OnchainMetadataReply>,
        jettonWalletCode: antiWhaleWalletCode(),
    };
}

get fun get_wallet_address(ownerAddress: address): address {
    val limits = AntiWhaleMinterStorage.load().whaleConfig.load();
    return calcWhaleWalletAddress(
        ownerAddress,
        contract.getAddress(),
        antiWhaleWalletCode(),
        limits.maxTransferAmount,
        limits.maxWalletBalance,
    );
}

get fun get_whale_config(): (coins, coins) {
    val limits = AntiWhaleMinterStorage.load().whaleConfig.load();
    return (limits.maxTransferAmount, limits.maxWalletBalance);
}

get fun get_next_admin_address(): address? {
    return AntiWhaleMinterStorage.load().nextAdminAddress;
}
