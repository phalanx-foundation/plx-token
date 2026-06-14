import "@gen/FeeJettonWallet.code"
import "errors"
import "fee-types"
import "fees-management"
import "messages"
import "sharding"
import "storage"

contract FeeJettonMinter {
    author: "Phalanx Foundation"
    version: "1.0.0"
    description: "Fee Jetton Minter — deploys FeeJettonWallet instances. Stores and enforces fee config. Admin-only fee updates (max 10%)."
    storage: FeeMinterStorage
    incomingMessages: AllowedMessageToFeeMinter
}

type AllowedMessageToFeeMinter =
    | MintNewJettons
    | BurnNotificationForMinter
    | RequestWalletAddress
    | ChangeMinterAdmin
    | ClaimMinterAdmin
    | DropMinterAdmin
    | ChangeMinterMetadata
    | UpgradeMinterCode
    | UpdateFeeConfig
    | TopUpTons

const MAX_FEE_BPS_MINTER: uint16 = 1000

fun assertSenderIsFeeMinterAdmin(senderAddress: address, adminAddress: address?) {
    assert (senderAddress == adminAddress!) throw Errors.NotOwner;
}

fun feeWalletCode(): cell {
    return feeJettonWalletCompiledCode();
}

fun onBouncedMessage(in: InMessageBounced) {
    in.bouncedBody.skipBouncedPrefix();
    val msg = lazy InternalTransferStep.fromSlice(in.bouncedBody);
    var storage = lazy FeeMinterStorage.load();
    storage.totalSupply -= msg.jettonAmount;
    storage.save();
}

fun onInternalMessage(in: InMessage) {
    val msg = lazy AllowedMessageToFeeMinter.fromSlice(in.body);

    match (msg) {
        BurnNotificationForMinter => {
            var storage = lazy FeeMinterStorage.load();
            val feeConfig = storage.feeConfig.load();
            val walletCode = feeWalletCode();
            assert (
                in.senderAddress == calcAddressOfFeeJettonWallet(
                    msg.burnInitiator,
                    contract.getAddress(),
                    walletCode,
                    feeConfig.feeBps,
                    feeConfig.feeCollector,
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
            excessesMsg.send(
                SEND_MODE_IGNORE_ERRORS | SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE,
            );
        }

        RequestWalletAddress => {
            val storage = lazy FeeMinterStorage.load();
            val feeConfig = storage.feeConfig.load();
            val ownerAddress: Cell<address>? = msg.includeOwnerAddress
                ? msg.ownerAddress.toCell()
                : null;

            var walletAddress: address? = null;
            if (msg.ownerAddress.getWorkchain() == MY_WORKCHAIN) {
                walletAddress = calcAddressOfFeeJettonWallet(
                    msg.ownerAddress,
                    contract.getAddress(),
                    feeWalletCode(),
                    feeConfig.feeBps,
                    feeConfig.feeCollector,
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
            var storage = lazy FeeMinterStorage.load();
            assertSenderIsFeeMinterAdmin(in.senderAddress, storage.adminAddress);
            assert (msg.mintRecipient.getWorkchain() == MY_WORKCHAIN) throw Errors.WrongWorkchain;

            val internalTransferMsg = lazy msg
                .internalTransferMsg
                .load({ throwIfOpcodeDoesNotMatch: Errors.InvalidOp });
            val forwardTonAmount = internalTransferMsg.forwardTonAmount;
            internalTransferMsg.forwardPayload.checkIsCorrectTlbEither();

            checkAmountIsEnoughToTransfer(msg.tonAmount, forwardTonAmount, in.originalForwardFee);

            storage.totalSupply += internalTransferMsg.jettonAmount;
            storage.save();

            reserveToncoinsOnBalance(ton("0.01"), RESERVE_MODE_EXACT_AMOUNT);

            val feeConfig = storage.feeConfig.load();
            val deployMsg = createMessage({
                bounce: BounceMode.Only256BitsOfBody,
                dest: calcDeployedFeeJettonWallet(
                    msg.mintRecipient,
                    contract.getAddress(),
                    feeWalletCode(),
                    feeConfig.feeBps,
                    feeConfig.feeCollector,
                ),
                value: msg.tonAmount,
                body: msg.internalTransferMsg,
            });
            deployMsg.send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_BOUNCE_ON_ACTION_FAIL);
        }

        ChangeMinterAdmin => {
            var storage = lazy FeeMinterStorage.load();
            assertSenderIsFeeMinterAdmin(in.senderAddress, storage.adminAddress);
            storage.nextAdminAddress = msg.newAdminAddress;
            storage.save();
        }

        ClaimMinterAdmin => {
            var storage = lazy FeeMinterStorage.load();
            assertSenderIsFeeMinterAdmin(in.senderAddress, storage.nextAdminAddress);
            storage.adminAddress = storage.nextAdminAddress;
            storage.nextAdminAddress = null;
            storage.save();
        }

        DropMinterAdmin => {
            var storage = lazy FeeMinterStorage.load();
            assertSenderIsFeeMinterAdmin(in.senderAddress, storage.adminAddress);
            storage.adminAddress = null;
            storage.nextAdminAddress = null;
            storage.save();
        }

        ChangeMinterMetadata => {
            var storage = lazy FeeMinterStorage.load();
            assertSenderIsFeeMinterAdmin(in.senderAddress, storage.adminAddress);
            storage.metadata = msg.newMetadata;
            storage.save();
        }

        UpgradeMinterCode => {
            val storage = lazy FeeMinterStorage.load();
            assertSenderIsFeeMinterAdmin(in.senderAddress, storage.adminAddress);
            contract.setCodePostponed(msg.newCode);
            contract.setData(msg.newData);
        }

        UpdateFeeConfig => {
            var storage = lazy FeeMinterStorage.load();
            assertSenderIsFeeMinterAdmin(in.senderAddress, storage.adminAddress);
            // Anti-rug: feeBps cannot exceed 10%
            assert (msg.feeBps <= MAX_FEE_BPS_MINTER) throw Errors.InvalidOp;
            val newConfig: FeeMinterConfig = {
                feeBps: msg.feeBps,
                feeCollector: msg.feeCollector,
            };
            storage.feeConfig = newConfig.toCell();
            storage.save();
        }

        TopUpTons => {}

        else => throw 0xFFFF,
    }
}

get fun get_jetton_data(): JettonDataReply {
    val storage = lazy FeeMinterStorage.load();
    return {
        totalSupply: storage.totalSupply,
        mintable: storage.adminAddress != null,
        adminAddress: storage.adminAddress,
        jettonContent: storage.metadata as Cell<OnchainMetadataReply>,
        jettonWalletCode: feeWalletCode(),
    };
}

get fun get_wallet_address(ownerAddress: address): address {
    val storage = lazy FeeMinterStorage.load();
    val feeConfig = storage.feeConfig.load();
    return calcAddressOfFeeJettonWallet(
        ownerAddress,
        contract.getAddress(),
        feeWalletCode(),
        feeConfig.feeBps,
        feeConfig.feeCollector,
    );
}

get fun get_fee_config(): (uint16, address) {
    val storage = lazy FeeMinterStorage.load();
    val feeConfig = storage.feeConfig.load();
    return (feeConfig.feeBps, feeConfig.feeCollector);
}

get fun get_next_admin_address(): address? {
    val storage = lazy FeeMinterStorage.load();
    return storage.nextAdminAddress;
}

get fun get_total_supply(): coins {
    return FeeMinterStorage.load().totalSupply;
}
