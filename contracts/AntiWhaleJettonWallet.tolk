import "@stdlib/gas-payments"
import "errors"
import "fees-management"
import "jetton-utils"
import "messages"
import "sharding"
import "storage"

contract AntiWhaleJettonWallet {
    author: "Phalanx Foundation"
    version: "1.0.0"
    description: "Anti-Whale Jetton Wallet — enforces max transfer amount (error 200) and optional max wallet balance (error 201). Limits stored per-wallet; all wallets from same minter share the same limits."
    storage: AntiWhaleWalletStorage
    incomingMessages: AllowedMessageToAntiWhaleWallet
}

const ANTI_WHALE_ERROR_TRANSFER_LIMIT: int = 200
const ANTI_WHALE_ERROR_WALLET_LIMIT: int = 201

/// Storage for AntiWhaleJettonWallet.
/// maxTransferAmount: maximum jettons allowed in a single transfer (0 = unlimited)
/// maxWalletBalance: maximum jetton balance any wallet may hold (0 = disabled)
@overflow1023_policy("suppress")
struct AntiWhaleWalletStorage {
    jettonBalance: coins
    ownerAddress: address
    minterAddress: address
    maxTransferAmount: coins
    maxWalletBalance: coins
}

/// UpdateWhaleConfig is sent by the minterAddress to adjust limits.
struct (0xAA110001) UpdateWhaleConfig {
    queryId: uint64
    maxTransferAmount: coins
    maxWalletBalance: coins
}

type AllowedMessageToAntiWhaleWallet =
    | AskToTransfer
    | AskToBurn
    | InternalTransferStep
    | TopUpTons
    | UpdateWhaleConfig

type BouncedAntiWhaleWalletOp = InternalTransferStep | BurnNotificationForMinter

fun AntiWhaleWalletStorage.load(): AntiWhaleWalletStorage {
    return AntiWhaleWalletStorage.fromCell(contract.getData());
}

fun AntiWhaleWalletStorage.save(self) {
    contract.setData(self.toCell());
}

fun calcDeployedAntiWhaleJettonWallet(
    ownerAddress: address,
    minterAddress: address,
    walletCode: cell,
    maxTransferAmount: coins,
    maxWalletBalance: coins,
): AutoDeployAddress {
    val initStorage: AntiWhaleWalletStorage = {
        jettonBalance: 0,
        ownerAddress,
        minterAddress,
        maxTransferAmount,
        maxWalletBalance,
    };
    return {
        workchain: MY_WORKCHAIN,
        stateInit: { code: walletCode, data: initStorage.toCell() },
        toShard: { fixedPrefixLength: SHARD_DEPTH, closeTo: ownerAddress },
    };
}

fun calcAddressOfAntiWhaleJettonWallet(
    ownerAddress: address,
    minterAddress: address,
    walletCode: cell,
    maxTransferAmount: coins,
    maxWalletBalance: coins,
): address {
    return calcDeployedAntiWhaleJettonWallet(
        ownerAddress, minterAddress, walletCode, maxTransferAmount, maxWalletBalance,
    ).calculateAddress();
}

fun onBouncedMessage(in: InMessageBounced) {
    in.bouncedBody.skipBouncedPrefix();
    val msg = lazy BouncedAntiWhaleWalletOp.fromSlice(in.bouncedBody);
    val restoreAmount = match (msg) {
        InternalTransferStep => msg.jettonAmount,
        BurnNotificationForMinter => msg.jettonAmount,
    };
    var storage = lazy AntiWhaleWalletStorage.load();
    storage.jettonBalance += restoreAmount;
    storage.save();
}

fun onInternalMessage(in: InMessage) {
    if (in.body.remainingBitsCount() == 0 && in.body.remainingRefsCount() == 0) {
        return;
    }

    val msg = lazy AllowedMessageToAntiWhaleWallet.fromSlice(in.body);

    match (msg) {
        InternalTransferStep => {
            var storage = lazy AntiWhaleWalletStorage.load();
            if (in.senderAddress != storage.minterAddress) {
                assert (
                    in.senderAddress == calcAddressOfAntiWhaleJettonWallet(
                        msg.transferInitiator!,
                        storage.minterAddress,
                        contract.getCode(),
                        storage.maxTransferAmount,
                        storage.maxWalletBalance,
                    )
                ) throw Errors.NotValidWallet;
            }

            // Check max wallet balance limit before crediting
            if (storage.maxWalletBalance > 0) {
                assert (
                    storage.jettonBalance + msg.jettonAmount <= storage.maxWalletBalance
                ) throw ANTI_WHALE_ERROR_WALLET_LIMIT;
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

            var storage = lazy AntiWhaleWalletStorage.load();
            assert (in.senderAddress == storage.ownerAddress) throw Errors.NotOwner;
            assert (storage.jettonBalance >= msg.jettonAmount) throw Errors.BalanceError;

            // Anti-whale: enforce max transfer limit
            if (storage.maxTransferAmount > 0) {
                assert (
                    msg.jettonAmount <= storage.maxTransferAmount
                ) throw ANTI_WHALE_ERROR_TRANSFER_LIMIT;
            }

            storage.jettonBalance -= msg.jettonAmount;
            storage.save();

            val deployMsg = createMessage({
                bounce: BounceMode.Only256BitsOfBody,
                dest: calcDeployedAntiWhaleJettonWallet(
                    msg.transferRecipient,
                    storage.minterAddress,
                    contract.getCode(),
                    storage.maxTransferAmount,
                    storage.maxWalletBalance,
                ),
                value: 0,
                body: InternalTransferStep {
                    queryId: msg.queryId,
                    jettonAmount: msg.jettonAmount,
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

        AskToBurn => {
            checkAmountIsEnoughToBurn(in.valueCoins);

            var storage = lazy AntiWhaleWalletStorage.load();
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

        UpdateWhaleConfig => {
            // Only minterAddress may update whale limits
            var storage = lazy AntiWhaleWalletStorage.load();
            assert (in.senderAddress == storage.minterAddress) throw Errors.NotOwner;
            storage.maxTransferAmount = msg.maxTransferAmount;
            storage.maxWalletBalance = msg.maxWalletBalance;
            storage.save();
        }

        TopUpTons => {}

        else => throw 0xFFFF,
    }
}

get fun get_wallet_data(): JettonWalletDataReply {
    val storage = lazy AntiWhaleWalletStorage.load();
    return {
        jettonBalance: storage.jettonBalance,
        ownerAddress: storage.ownerAddress,
        minterAddress: storage.minterAddress,
        jettonWalletCode: contract.getCode(),
    };
}

get fun get_whale_config(): (coins, coins) {
    val storage = lazy AntiWhaleWalletStorage.load();
    return (storage.maxTransferAmount, storage.maxWalletBalance);
}

get fun get_jetton_balance(): coins {
    return AntiWhaleWalletStorage.load().jettonBalance;
}
