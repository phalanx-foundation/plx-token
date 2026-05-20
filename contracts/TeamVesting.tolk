import "@gen/JettonWallet.code"
import "errors"
import "jetton-utils"
import "messages"

contract TeamVesting {
    author: "Phalanx Foundation"
    version: "1.1.0"
    description: "Linear vesting contract: holds PLX jettons and releases them to beneficiary linearly over duration. Anyone can trigger claim. Admin can revoke unvested portion. v1.1 adds bounce-rollback for failed transfers and admin-controlled excess TON withdrawal."
    storage: VestingStorage
    incomingMessages: AllowedMessageToVesting
}

struct VestingConfig {
    beneficiary: address
    admin: address
    minterAddress: address
    totalAmount: coins
    startTime: uint32
    duration: uint32
}

struct VestingStorage {
    config: Cell<VestingConfig>
    claimedAmount: coins
}

struct (0x77777701) ClaimVested {
    queryId: uint64
}

struct (0x77777702) RevokeVesting {
    queryId: uint64
}

struct (0x77777703) WithdrawTons {
    queryId: uint64
    amount: coins
}

type AllowedMessageToVesting = ClaimVested | RevokeVesting | WithdrawTons | TopUpTons

const VESTING_TRANSFER_VALUE = 80000000

fun VestingStorage.load(): VestingStorage {
    return VestingStorage.fromCell(contract.getData());
}

fun VestingStorage.save(self) {
    contract.setData(self.toCell());
}

fun calculateVestedAmount(
    totalAmount: coins,
    startTime: int,
    duration: int,
    currentTime: int,
): coins {
    if (currentTime <= startTime) {
        return 0;
    }
    val elapsed = currentTime - startTime;
    if (elapsed >= duration) {
        return totalAmount;
    }
    return totalAmount * elapsed / duration;
}

fun ownJettonWalletAddress(minterAddress: address): address {
    val jettonWalletCode = jettonWalletCompiledCode();
    return calcAddressOfJettonWallet(contract.getAddress(), minterAddress, jettonWalletCode);
}

fun emptyForwardPayload(): slice {
    return beginCell().storeUint(0, 1).toSlice();
}

fun onBouncedMessage(in: InMessageBounced) {
    in.bouncedBody.skipBouncedPrefix();

    val op = in.bouncedBody.loadUint(32);
    if (op != 0x0f8a7ea5) {
        return;
    }

    in.bouncedBody.loadUint(64);
    val refundedAmount = in.bouncedBody.loadCoins();

    var storage = lazy VestingStorage.load();
    if (storage.claimedAmount >= refundedAmount) {
        storage.claimedAmount -= refundedAmount;
    } else {
        storage.claimedAmount = 0;
    }
    storage.save();
}

fun onInternalMessage(in: InMessage) {
    val msg = lazy AllowedMessageToVesting.fromSlice(in.body);

    match (msg) {
        ClaimVested => {
            var storage = lazy VestingStorage.load();
            val cfg = storage.config.load();
            val vested = calculateVestedAmount(
                cfg.totalAmount,
                cfg.startTime,
                cfg.duration,
                blockchain.now(),
            );
            val unclaimed = vested - storage.claimedAmount;
            assert (unclaimed > 0) throw Errors.NothingToClaim;
            storage.claimedAmount += unclaimed;
            storage.save();

            val transferMsg = createMessage({
                bounce: BounceMode.Only256BitsOfBody,
                dest: ownJettonWalletAddress(cfg.minterAddress),
                value: VESTING_TRANSFER_VALUE,
                body: AskToTransfer {
                    queryId: msg.queryId,
                    jettonAmount: unclaimed,
                    transferRecipient: cfg.beneficiary,
                    sendExcessesTo: in.senderAddress,
                    customPayload: null,
                    forwardTonAmount: 0,
                    forwardPayload: emptyForwardPayload(),
                },
            });
            transferMsg.send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_BOUNCE_ON_ACTION_FAIL);
        }

        RevokeVesting => {
            var storage = lazy VestingStorage.load();
            val cfg = storage.config.load();
            assert (in.senderAddress == cfg.admin) throw Errors.NotOwner;

            val vested = calculateVestedAmount(
                cfg.totalAmount,
                cfg.startTime,
                cfg.duration,
                blockchain.now(),
            );
            val toBeneficiary = vested - storage.claimedAmount;
            val toAdmin = cfg.totalAmount - vested;

            storage.claimedAmount = cfg.totalAmount;
            storage.save();

            val ownWallet = ownJettonWalletAddress(cfg.minterAddress);

            if (toBeneficiary > 0) {
                val msgB = createMessage({
                    bounce: BounceMode.Only256BitsOfBody,
                    dest: ownWallet,
                    value: VESTING_TRANSFER_VALUE,
                    body: AskToTransfer {
                        queryId: msg.queryId,
                        jettonAmount: toBeneficiary,
                        transferRecipient: cfg.beneficiary,
                        sendExcessesTo: cfg.beneficiary,
                        customPayload: null,
                        forwardTonAmount: 0,
                        forwardPayload: emptyForwardPayload(),
                    },
                });
                msgB.send(SEND_MODE_PAY_FEES_SEPARATELY);
            }

            if (toAdmin > 0) {
                val msgA = createMessage({
                    bounce: BounceMode.Only256BitsOfBody,
                    dest: ownWallet,
                    value: VESTING_TRANSFER_VALUE,
                    body: AskToTransfer {
                        queryId: msg.queryId,
                        jettonAmount: toAdmin,
                        transferRecipient: cfg.admin,
                        sendExcessesTo: cfg.admin,
                        customPayload: null,
                        forwardTonAmount: 0,
                        forwardPayload: emptyForwardPayload(),
                    },
                });
                msgA.send(SEND_MODE_PAY_FEES_SEPARATELY);
            }
        }

        WithdrawTons => {
            val storage = lazy VestingStorage.load();
            val cfg = storage.config.load();
            assert (in.senderAddress == cfg.admin) throw Errors.NotOwner;

            val withdrawMsg = createMessage({
                bounce: BounceMode.NoBounce,
                dest: cfg.admin,
                value: msg.amount,
                body: ReturnExcessesBack { queryId: msg.queryId },
            });
            withdrawMsg.send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_BOUNCE_ON_ACTION_FAIL);
        }

        TopUpTons => {}

        else => throw 0xFFFF,
    }
}

get fun get_vesting_data(): VestingConfig {
    val storage = lazy VestingStorage.load();
    return storage.config.load();
}

get fun get_claimed_amount(): coins {
    val storage = lazy VestingStorage.load();
    return storage.claimedAmount;
}

get fun get_vested_amount(): coins {
    val storage = lazy VestingStorage.load();
    val cfg = storage.config.load();
    return calculateVestedAmount(
        cfg.totalAmount,
        cfg.startTime,
        cfg.duration,
        blockchain.now(),
    );
}

get fun get_claimable_amount(): coins {
    val storage = lazy VestingStorage.load();
    val cfg = storage.config.load();
    val vested = calculateVestedAmount(
        cfg.totalAmount,
        cfg.startTime,
        cfg.duration,
        blockchain.now(),
    );
    return vested - storage.claimedAmount;
}

get fun get_jetton_wallet_address(): address {
    val storage = lazy VestingStorage.load();
    val cfg = storage.config.load();
    return ownJettonWalletAddress(cfg.minterAddress);
}
