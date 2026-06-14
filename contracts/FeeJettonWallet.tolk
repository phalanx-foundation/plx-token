import "@stdlib/gas-payments"
import "errors"
import "fee-types"
import "fees-management"
import "jetton-utils"
import "messages"
import "sharding"
import "storage"

contract FeeJettonWallet {
    author: "Phalanx Foundation"
    version: "1.0.0"
    description: "Fee Jetton Wallet — charges configurable BPS fee on every transfer. Anti-rug: max 10% (1000 bps) enforced on-chain."
    storage: FeeWalletStorage
    incomingMessages: AllowedMessageToFeeWallet
}

const MAX_FEE_BPS: uint16 = 1000
const FEE_TRANSFER_TON_VALUE: coins = 80000000

type AllowedMessageToFeeWallet =
    | AskToTransfer
    | AskToBurn
    | InternalTransferStep
    | TopUpTons
    | UpdateFeeConfig

type BouncedFeeWalletOp = InternalTransferStep | BurnNotificationForMinter

fun onBouncedMessage(in: InMessageBounced) {
    in.bouncedBody.skipBouncedPrefix();
    val msg = lazy BouncedFeeWalletOp.fromSlice(in.bouncedBody);
    val restoreAmount = match (msg) {
        InternalTransferStep => msg.jettonAmount,
        BurnNotificationForMinter => msg.jettonAmount,
    };
    var storage = lazy FeeWalletStorage.load();
    storage.jettonBalance += restoreAmount;
    storage.save();
}

fun onInternalMessage(in: InMessage) {
    val msg = lazy AllowedMessageToFeeWallet.fromSlice(in.body);

    match (msg) {
        InternalTransferStep => {
            var storage = lazy FeeWalletStorage.load();
            if (in.senderAddress != storage.minterAddress) {
                assert (
                    in.senderAddress == calcAddressOfFeeJettonWallet(
                        msg.transferInitiator!,
                        storage.minterAddress,
                        contract.getCode(),
                        storage.feeBps,
                        storage.feeCollector,
                    )
                ) throw Errors.NotValidWallet;
            }
            storage.jettonBalance += msg.jettonAmount;
            storage.save();

            if (msg.forwardTonAmount != 0) {
                val notifyMsg = createMessage({
                    bounce: BounceMode.NoBounce,
                    dest: storage.ownerAddress,
                    value: msg.forwardTonAmount,
                    body: TransferNotificationForRecipient {
                        queryId: msg.queryId,
                        jettonAmount: msg.jettonAmount,
                        transferInitiator: msg.transferInitiator,
                        forwardPayload: msg.forwardPayload,
                    },
                });
                notifyMsg.send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_BOUNCE_ON_ACTION_FAIL);
            }

            if (msg.sendExcessesTo != null) {
                val toLeaveOnBalance = contract.getOriginalBalance() - in.valueCoins +
                    contract.getStorageDuePayment();
                reserveToncoinsOnBalance(
                    max(toLeaveOnBalance, calculateJettonWalletMinStorageFee()),
                    RESERVE_MODE_AT_MOST,
                );
                val excessesMsg = createMessage({
                    bounce: BounceMode.NoBounce,
                    dest: msg.sendExcessesTo,
                    value: 0,
                    body: ReturnExcessesBack { queryId: msg.queryId },
                });
                excessesMsg.send(SEND_MODE_CARRY_ALL_BALANCE | SEND_MODE_IGNORE_ERRORS);
            }
        }

        AskToTransfer => {
            msg.forwardPayload.checkIsCorrectTlbEither();
            assert (msg.transferRecipient.getWorkchain() == MY_WORKCHAIN) throw Errors.WrongWorkchain;
            checkAmountIsEnoughToTransfer(in.valueCoins, msg.forwardTonAmount, in.originalForwardFee);

            var storage = lazy FeeWalletStorage.load();
            assert (in.senderAddress == storage.ownerAddress) throw Errors.NotOwner;
            assert (storage.jettonBalance >= msg.jettonAmount) throw Errors.BalanceError;

            // Calculate fee (minimum 1 nano-token; skip if calculated fee < 1)
            var feeAmount: coins = 0;
            if (storage.feeBps > 0) {
                val calculated = msg.jettonAmount * storage.feeBps / 10000;
                if (calculated >= 1) {
                    feeAmount = calculated;
                }
            }
            val actualAmount = msg.jettonAmount - feeAmount;

            storage.jettonBalance -= msg.jettonAmount;
            storage.save();

            if (feeAmount > 0) {
                // When a fee applies we need TWO outgoing messages.
                // Using CARRY_ALL_REMAINING (mode=64) for the main transfer AND a separate
                // explicit fee send would try to spend more than the incoming value
                // (action_result_code=37).  Instead: send both with explicit TON values so
                // the total never exceeds what was received.
                val feeMsg = createMessage({
                    bounce: BounceMode.Only256BitsOfBody,
                    dest: calcDeployedFeeJettonWallet(
                        storage.feeCollector,
                        storage.minterAddress,
                        contract.getCode(),
                        storage.feeBps,
                        storage.feeCollector,
                    ),
                    value: FEE_TRANSFER_TON_VALUE,
                    body: InternalTransferStep {
                        queryId: msg.queryId,
                        jettonAmount: feeAmount,
                        transferInitiator: storage.ownerAddress,
                        sendExcessesTo: null,
                        forwardTonAmount: 0,
                        forwardPayload: jettonEmptyForwardPayload(),
                    },
                });
                feeMsg.send(SEND_MODE_BOUNCE_ON_ACTION_FAIL);

                // Main transfer gets the remainder of the incoming TON.
                val deployMsg = createMessage({
                    bounce: BounceMode.Only256BitsOfBody,
                    dest: calcDeployedFeeJettonWallet(
                        msg.transferRecipient,
                        storage.minterAddress,
                        contract.getCode(),
                        storage.feeBps,
                        storage.feeCollector,
                    ),
                    value: in.valueCoins - FEE_TRANSFER_TON_VALUE,
                    body: InternalTransferStep {
                        queryId: msg.queryId,
                        jettonAmount: actualAmount,
                        transferInitiator: storage.ownerAddress,
                        sendExcessesTo: msg.sendExcessesTo,
                        forwardTonAmount: msg.forwardTonAmount,
                        forwardPayload: msg.forwardPayload,
                    },
                });
                deployMsg.send(SEND_MODE_BOUNCE_ON_ACTION_FAIL);
            } else {
                // No fee: carry all remaining value (standard behaviour).
                val deployMsg = createMessage({
                    bounce: BounceMode.Only256BitsOfBody,
                    dest: calcDeployedFeeJettonWallet(
                        msg.transferRecipient,
                        storage.minterAddress,
                        contract.getCode(),
                        storage.feeBps,
                        storage.feeCollector,
                    ),
                    value: 0,
                    body: InternalTransferStep {
                        queryId: msg.queryId,
                        jettonAmount: actualAmount,
                        transferInitiator: storage.ownerAddress,
                        sendExcessesTo: msg.sendExcessesTo,
                        forwardTonAmount: msg.forwardTonAmount,
                        forwardPayload: msg.forwardPayload,
                    },
                });
                deployMsg.send(
                    SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE | SEND_MODE_BOUNCE_ON_ACTION_FAIL,
                );
            }
        }

        AskToBurn => {
            checkAmountIsEnoughToBurn(in.valueCoins);

            var storage = lazy FeeWalletStorage.load();
            assert (in.senderAddress == storage.ownerAddress) throw Errors.NotOwner;
            assert (storage.jettonBalance >= msg.jettonAmount) throw Errors.BalanceError;
            storage.jettonBalance -= msg.jettonAmount;
            storage.save();

            val notifyMinterMsg = createMessage({
                bounce: BounceMode.Only256BitsOfBody,
                dest: storage.minterAddress,
                value: 0,
                body: BurnNotificationForMinter {
                    queryId: msg.queryId,
                    jettonAmount: msg.jettonAmount,
                    burnInitiator: storage.ownerAddress,
                    sendExcessesTo: msg.sendExcessesTo,
                },
            });
            notifyMinterMsg.send(
                SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE | SEND_MODE_BOUNCE_ON_ACTION_FAIL,
            );
        }

        UpdateFeeConfig => {
            // Anti-rug: only minterAddress can update fee config
            var storage = lazy FeeWalletStorage.load();
            assert (in.senderAddress == storage.minterAddress) throw Errors.NotOwner;
            assert (msg.feeBps <= MAX_FEE_BPS) throw Errors.InvalidOp;
            storage.feeBps = msg.feeBps;
            storage.feeCollector = msg.feeCollector;
            storage.save();
        }

        TopUpTons => {}

        else => throw 0xFFFF,
    }
}

get fun get_wallet_data(): JettonWalletDataReply {
    val storage = lazy FeeWalletStorage.load();
    return {
        jettonBalance: storage.jettonBalance,
        ownerAddress: storage.ownerAddress,
        minterAddress: storage.minterAddress,
        jettonWalletCode: contract.getCode(),
    };
}

get fun get_fee_config(): (uint16, address) {
    val storage = lazy FeeWalletStorage.load();
    return (storage.feeBps, storage.feeCollector);
}

get fun get_jetton_balance(): coins {
    return FeeWalletStorage.load().jettonBalance;
}
