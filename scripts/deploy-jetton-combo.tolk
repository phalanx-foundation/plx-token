import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@wrappers/JettonMinter.gen"
import "@wrappers/AntiWhaleJettonWallet.gen"
import "@wrappers/PlxAirdrop.gen"
import "@wrappers/TokenStaking.gen"
import "utils/common"

/**
 * Non-interactive multi-template jetton deploy for Phalanx Toolkit.
 *
 * Supports all templates: standard, antiwhale, fee, staking, airdrop.
 * Deploys minter + optional companion contracts in a single transaction chain.
 *
 * Env (required):
 *   JETTON_DEPLOYER          — Acton wallet name (pays gas, escrow admin)
 *   JETTON_ADMIN_ADDRESS     — Client wallet (final minter admin)
 *   JETTON_TEMPLATE          — one of: standard, antiwhale, fee, staking, airdrop
 *   JETTON_NAME, JETTON_SYMBOL, JETTON_SUPPLY, JETTON_DECIMALS
 *   JETTON_DESCRIPTION, JETTON_IMAGE_URL
 *
 * Template-specific env:
 *   antiwhale: JETTON_MAX_TRANSFER, JETTON_MAX_WALLET_BALANCE
 *   fee:       JETTON_FEE_BPS, JETTON_FEE_COLLECTOR
 *   staking:   JETTON_STAKING_APR_BPS, JETTON_STAKING_MIN_LOCK_SEC
 *   airdrop:   JETTON_AIRDROP_MERKLE_ROOT, JETTON_AIRDROP_DEADLINE
 */
fun main() {
    val deployer = promptJettonWallet("JETTON_DEPLOYER", "Toolkit deployer wallet");
    val clientAdmin = promptJettonAddressRequired("JETTON_ADMIN_ADDRESS", "Client admin address");
    val template = env<string>("JETTON_TEMPLATE") ?? "standard";

    val recipient = clientAdmin;
    val storage = promptJettonMinterStorage(clientAdmin);

    // Deploy the jetton minter (same for all templates)
    val minter = JettonMinter.fromStorage(storage);
    val deployRes = minter.sendDeploy(deployer.address, { value: ton("0.08") });
    deployRes.waitForFirstTransaction();
    println("TOOLKIT MINTER_ADDRESS={}", minter.address);
    println("TOOLKIT TEMPLATE={}", template);

    // Template-specific companion contract deploys
    if (template == "antiwhale") {
        deployAntiWhaleFeatures(minter, deployer, clientAdmin);
    }
    if (template == "fee") {
        // Fee features are embedded in the minter/wallet — no separate deploy
        println("TOOLKIT Fee features configured via minter storage. Fee=1");
    }
    if (template == "staking") {
        deployStakingContract(minter, deployer, clientAdmin);
    }
    if (template == "airdrop") {
        deployAirdropContract(minter, deployer, clientAdmin);
    }

    printJettonMinterInfo(minter, "JETTON");
    printJettonWalletInfo(minter, recipient, "JETTON_RECIPIENT");
}

fun deployAntiWhaleFeatures(minter: JettonMinter, deployer: JettonMinter, clientAdmin: address) {
    val maxTransferRaw = env<string>("JETTON_MAX_TRANSFER") ?? "0";
    val maxBalanceRaw = env<string>("JETTON_MAX_WALLET_BALANCE") ?? "0";
    val maxTransfer: coins = maxTransferRaw.toInt() as coins;
    val maxBalance: coins = maxBalanceRaw.toInt() as coins;

    val awStorage: AntiWhaleJettonWalletStorage = {
        jettonBalance: 0,
        ownerAddress: clientAdmin,
        minterAddress: minter.address,
        maxTransferAmount: maxTransfer,
        maxWalletBalance: maxBalance,
    };

    val awWallet = AntiWhaleJettonWallet.fromStorage(awStorage);
    val awRes = awWallet.sendDeploy(deployer.address, { value: ton("0.05") });
    awRes.waitForFirstTransaction();
    println("TOOLKIT ANTI_WHALE_WALLET={}", awWallet.address);
    println("TOOLKIT ANTI_WHALE MAX_TRANSFER={}", maxTransfer);
    println("TOOLKIT ANTI_WHALE MAX_WALLET_BALANCE={}", maxBalance);
}

fun deployStakingContract(minter: JettonMinter, deployer: JettonMinter, clientAdmin: address) {
    val aprBpsRaw = env<string>("JETTON_STAKING_APR_BPS") ?? "500";
    val minLockRaw = env<string>("JETTON_STAKING_MIN_LOCK_SEC") ?? "86400";
    val aprBps: uint32 = aprBpsRaw.toInt() as uint32;
    val minLockSec: uint32 = minLockRaw.toInt() as uint32;

    val stakeConfig: TokenStakingConfig = {
        admin: clientAdmin,
        minterAddress: minter.address,
        aprBps,
        minLockSec,
    };

    val stakingStorage: TokenStakingStakingStorage = {
        config: stakeConfig.toCell(),
        totalStaked: 0,
        rewardPerTokenStored: 0,
        lastUpdateTime: blockchain.now() as uint32,
        rewardPool: 0,
        nextStakeId: 0,
        stakes: emptyMap(),
    };

    val staking = TokenStaking.fromStorage(stakingStorage);
    val stakeRes = staking.sendDeploy(deployer.address, { value: ton("0.1") });
    stakeRes.waitForFirstTransaction();
    println("TOOLKIT STAKING_CONTRACT={}", staking.address);
    println("TOOLKIT STAKING APR_BPS={}", aprBps);
    println("TOOLKIT STAKING MIN_LOCK_SEC={}", minLockSec);
}

fun deployAirdropContract(minter: JettonMinter, deployer: JettonMinter, clientAdmin: address) {
    val merkleRoot = env<string>("JETTON_AIRDROP_MERKLE_ROOT") ?? "";
    val deadlineRaw = env<string>("JETTON_AIRDROP_DEADLINE") ?? "0";
    val deadline: uint32 = deadlineRaw.toInt() as uint32;

    val airdropStorage: PlxAirdropAirdropStorage = {
        merkleRoot: merkleRoot as bits256,
        jettonMinter: minter.address,
        admin: clientAdmin,
        deadline,
        claimedMap: emptyMap(),
    };

    val airdrop = PlxAirdrop.fromStorage(airdropStorage);
    val airRes = airdrop.sendDeploy(deployer.address, { value: ton("0.15") });
    airRes.waitForFirstTransaction();
    println("TOOLKIT AIRDROP_CONTRACT={}", airdrop.address);
    println("TOOLKIT AIRDROP MERKLE_ROOT={}", merkleRoot);
    println("TOOLKIT AIRDROP DEADLINE={}", deadline);
}
