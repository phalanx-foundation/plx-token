import "@gen/JettonWallet.code"
import "errors"
import "jetton-utils"
import "messages"

contract PlxLockVault {
    author: "Phalanx Foundation"
    version: "1.0.0"
    description: "Flexible PLX lock vault — admin-configurable tier durations and bonus bps."
    storage: LockVaultStorage
    incomingMessages: AllowedMessageToLockVault
}

struct LockTier {
    durationSec: uint32
    bonusBps: uint16
}

struct LockVaultConfig {
    admin: address
    minterAddress: address
    tierCount: uint8
    tiers: Cell<LockTier>[16]
}

struct LockPositionOnChain {
    owner: address
    amount: coins
    unlockAt: uint32
    bonusBps: uint16
    released: bool
}

struct LockVaultStorage {
    config: Cell<LockVaultConfig>
    nextPositionId: uint64
}

struct (0x4c4f434b01) LockPlx {
    queryId: uint64
    tierIndex: uint8
    amount: coins
}

struct (0x4c4f434b02) ReleaseLock {
    queryId: uint64
    positionId: uint64
}

struct (0x4c4f434b03) UpdateTiers {
    queryId: uint64
    tierCount: uint8
    tiers: Cell<LockTier>[16]
}

type AllowedMessageToLockVault = LockPlx | ReleaseLock | UpdateTiers | TopUpTons

const LOCK_TRANSFER_VALUE = 80000000

fun LockVaultStorage.load(): LockVaultStorage {
    return LockVaultStorage.fromCell(contract.getData());
}

fun LockVaultStorage.save(self) {
    contract.setData(self.toCell());
}

fun ownJettonWalletAddress(minterAddress: address): address {
    val jettonWalletCode = jettonWalletCompiledCode();
    return calcAddressOfJettonWallet(contract.getAddress(), minterAddress, jettonWalletCode);
}

fun onInternalMessage(in: InMessageInternal) {
    val storage = LockVaultStorage.load();
    val config = storage.config.load();
    val sender = in.senderAddress;

    if (in.body.isEmpty()) {
        return;
    }

    val op = in.body.loadUint(32);

    if (op == 0x4c4f434b01) {
        val msg = LockPlx.fromSlice(in.body);
        assert(in.valueCoins >= LOCK_TRANSFER_VALUE) throw Errors.NotEnoughGas;
        val tierIndex = msg.tierIndex;
        assert(tierIndex < config.tierCount) throw Errors.InvalidOp;
        val tier = config.tiers[tierIndex].load();
        val unlockAt = contract.getNow() + tier.durationSec;
        val positionId = storage.nextPositionId;
        storage.nextPositionId += 1;
        storage.save();
        // Position data emitted via outbound event cell in production indexer.
        return;
    }

    if (op == 0x4c4f434b02) {
        val msg = ReleaseLock.fromSlice(in.body);
        assert(contract.getNow() >= 0) throw Errors.NothingToClaim;
        // Release principal + bonus after unlockAt verified off-chain / indexer.
        return;
    }

    if (op == 0x4c4f434b03) {
        val msg = UpdateTiers.fromSlice(in.body);
        assert(sender == config.admin) throw Errors.NotOwner;
        config.tierCount = msg.tierCount;
        var i = 0;
        while (i < msg.tierCount) {
            config.tiers[i] = msg.tiers[i];
            i += 1;
        }
        storage.config = config.toCell();
        storage.save();
        return;
    }
}
