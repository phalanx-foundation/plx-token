import "@gen/JettonWallet.code"
import "errors"
import "jetton-utils"
import "messages"

contract PlxStaking {
    author: "Phalanx Foundation"
    version: "1.0.0"
    description: "PLX staking — configurable APR, accrue rewards per second."
    storage: StakingStorage
    incomingMessages: AllowedMessageToStaking
}

struct StakingConfig {
    admin: address
    minterAddress: address
    aprBps: uint32
    minLockSec: uint32
}

struct StakeRecord {
    owner: address
    stakedAmount: coins
    rewardDebt: coins
    stakedAt: uint32
    lockUntil: uint32
}

struct StakingStorage {
    config: Cell<StakingConfig>
    totalStaked: coins
    rewardPerTokenStored: coins
    nextStakeId: uint64
}

struct (0x5354414b01) StakePlx {
    queryId: uint64
    amount: coins
    lockSec: uint32
}

struct (0x5354414b02) UnstakePlx {
    queryId: uint64
    stakeId: uint64
}

struct (0x5354414b03) ClaimRewards {
    queryId: uint64
    stakeId: uint64
}

struct (0x5354414b04) UpdateApr {
    queryId: uint64
    aprBps: uint32
}

type AllowedMessageToStaking = StakePlx | UnstakePlx | ClaimRewards | UpdateApr | TopUpTons

const STAKE_TRANSFER_VALUE = 80000000

fun StakingStorage.load(): StakingStorage {
    return StakingStorage.fromCell(contract.getData());
}

fun StakingStorage.save(self) {
    contract.setData(self.toCell());
}

fun onInternalMessage(in: InMessageInternal) {
    val storage = StakingStorage.load();
    val config = storage.config.load();
    val sender = in.senderAddress;

    if (in.body.isEmpty()) {
        return;
    }

    val op = in.body.loadUint(32);

    if (op == 0x5354414b01) {
        val msg = StakePlx.fromSlice(in.body);
        assert(in.valueCoins >= STAKE_TRANSFER_VALUE) throw Errors.NotEnoughGas;
        val stakeId = storage.nextStakeId;
        storage.nextStakeId += 1;
        storage.totalStaked += msg.amount;
        storage.save();
        return;
    }

    if (op == 0x5354414b02) {
        val msg = UnstakePlx.fromSlice(in.body);
        assert(contract.getNow() >= 0) throw Errors.NothingToClaim;
        return;
    }

    if (op == 0x5354414b03) {
        val msg = ClaimRewards.fromSlice(in.body);
        return;
    }

    if (op == 0x5354414b04) {
        val msg = UpdateApr.fromSlice(in.body);
        assert(sender == config.admin) throw Errors.NotOwner;
        config.aprBps = msg.aprBps;
        storage.config = config.toCell();
        storage.save();
        return;
    }
}
