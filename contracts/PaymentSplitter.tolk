import "@gen/JettonWallet.code"
import "errors"
import "jetton-utils"
import "messages"

contract PaymentSplitter {
    author: "Phalanx Foundation"
    version: "1.0.0"
    description: "Hybrid 50/50 jetton splitter. On every incoming jetton transfer notification it burns 50% and forwards 50% to a fixed treasury address. Used by Phalanx Toolkit deploy fee rail when a client pays in PLX. Treasury and minter addresses are immutable once deployed; redeploy a new splitter to change them."
    storage: SplitterStorage
    incomingMessages: AllowedMessageToSplitter
}

@overflow1023_policy("suppress")
struct SplitterStorage {
    minterAddress: address
    treasuryAddress: address
    admin: address
    burnedTotal: coins
    forwardedTotal: coins
    deployCount: uint64
}

struct (0x88888801) WithdrawSplitterTons {
    queryId: uint64
    amount: coins
}

type AllowedMessageToSplitter =
    | TransferNotificationForRecipient
    | WithdrawSplitterTons
    | TopUpTons

const SPLIT_OP_VALUE: coins = 80000000

fun SplitterStorage.load(): SplitterStorage {
    return SplitterStorage.fromCell(contract.getData());
}

fun SplitterStorage.save(self) {
    contract.setData(self.toCell());
}

fun splitterOwnJettonWalletAddress(minterAddress: address): address {
    val jettonWalletCode = jettonWalletCompiledCode();
    return calcAddressOfJettonWallet(contract.getAddress(), minterAddress, jettonWalletCode);
}

fun splitterEmptyForwardPayload(): slice {
    return beginCell().storeUint(0, 1).toSlice();
}

fun onBouncedMessage(in: InMessageBounced) {
    in.bouncedBody.skipBouncedPrefix();

    val op = in.bouncedBody.loadUint(32);
    in.bouncedBody.loadUint(64);

    var storage = lazy SplitterStorage.load();

    if (op == 0x595f07bc) {
        val refundedAmount = in.bouncedBody.loadCoins();
        if (storage.burnedTotal >= refundedAmount) {
            storage.burnedTotal -= refundedAmount;
        } else {
            storage.burnedTotal = 0;
        }
        storage.save();
    } else if (op == 0x0f8a7ea5) {
        val refundedAmount = in.bouncedBody.loadCoins();
        if (storage.forwardedTotal >= refundedAmount) {
            storage.forwardedTotal -= refundedAmount;
        } else {
            storage.forwardedTotal = 0;
        }
        storage.save();
    }
}

fun onInternalMessage(in: InMessage) {
    if (in.body.remainingBitsCount() == 0 && in.body.remainingRefsCount() == 0) {
        return;
    }

    val msg = lazy AllowedMessageToSplitter.fromSlice(in.body);

    match (msg) {
        TransferNotificationForRecipient => {
            var storage = lazy SplitterStorage.load();
            val ourWallet = splitterOwnJettonWalletAddress(storage.minterAddress);
            assert (in.senderAddress == ourWallet) throw Errors.NotValidWallet;

            val incomingAmount = msg.jettonAmount;
            if (incomingAmount == 0) {
                return;
            }

            val burnAmount = incomingAmount / 2;
            val forwardAmount = incomingAmount - burnAmount;

            storage.burnedTotal += burnAmount;
            storage.forwardedTotal += forwardAmount;
            storage.deployCount += 1;
            storage.save();

            if (burnAmount > 0) {
                val burnMsg = createMessage({
                    bounce: BounceMode.Only256BitsOfBody,
                    dest: ourWallet,
                    value: SPLIT_OP_VALUE,
                    body: AskToBurn {
                        queryId: msg.queryId,
                        jettonAmount: burnAmount,
                        sendExcessesTo: contract.getAddress(),
                        customPayload: null,
                    },
                });
                burnMsg.send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_BOUNCE_ON_ACTION_FAIL);
            }

            if (forwardAmount > 0) {
                val transferMsg = createMessage({
                    bounce: BounceMode.Only256BitsOfBody,
                    dest: ourWallet,
                    value: SPLIT_OP_VALUE,
                    body: AskToTransfer {
                        queryId: msg.queryId,
                        jettonAmount: forwardAmount,
                        transferRecipient: storage.treasuryAddress,
                        sendExcessesTo: contract.getAddress(),
                        customPayload: null,
                        forwardTonAmount: 0,
                        forwardPayload: splitterEmptyForwardPayload(),
                    },
                });
                transferMsg.send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_BOUNCE_ON_ACTION_FAIL);
            }
        }

        WithdrawSplitterTons => {
            val storage = lazy SplitterStorage.load();
            assert (in.senderAddress == storage.admin) throw Errors.NotOwner;

            val withdrawMsg = createMessage({
                bounce: BounceMode.NoBounce,
                dest: storage.admin,
                value: msg.amount,
                body: ReturnExcessesBack { queryId: msg.queryId },
            });
            withdrawMsg.send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_BOUNCE_ON_ACTION_FAIL);
        }

        TopUpTons => {}

        else => throw 0xFFFF,
    }
}

get fun get_splitter_data(): SplitterStorage {
    return SplitterStorage.load();
}

get fun get_burned_total(): coins {
    return SplitterStorage.load().burnedTotal;
}

get fun get_forwarded_total(): coins {
    return SplitterStorage.load().forwardedTotal;
}

get fun get_deploy_count(): uint64 {
    return SplitterStorage.load().deployCount;
}

get fun get_jetton_wallet_address(): address {
    val storage = lazy SplitterStorage.load();
    return splitterOwnJettonWalletAddress(storage.minterAddress);
}
