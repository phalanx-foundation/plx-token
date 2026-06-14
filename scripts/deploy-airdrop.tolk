import "@stdlib/strings"
import "@acton/env"
import "@acton/fmt"
import "@acton/io"
import "@acton/prompts"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@contracts/PlxAirdrop"
import "@wrappers/PlxAirdrop.gen"
import "@wrappers/utils"
import "utils/common"

/**
 * Non-interactive PlxAirdrop deploy.
 *
 * Env (required):
 *   DEPLOYER              — Acton wallet name (pays gas)
 *   AIRDROP_ADMIN         — Admin address (SetMerkleRoot, WithdrawUnclaimed)
 *   AIRDROP_MINTER        — Jetton minter address
 *   AIRDROP_MERKLE_ROOT   — Initial merkle root (uint256 as decimal string, 0 = placeholder)
 *   AIRDROP_DEADLINE      — Unix timestamp after which claims close (0 = no deadline)
 */
fun main() {
    val deployer = promptJettonWallet("DEPLOYER", "Deployer wallet");
    val admin = promptJettonAddressRequired("AIRDROP_ADMIN", "Airdrop admin address");
    val jettonMinter = promptJettonAddressRequired("AIRDROP_MINTER", "Jetton minter address");
    val merkleRootRaw: int = env<int>("AIRDROP_MERKLE_ROOT") ?? 0;
    val merkleRoot: uint256 = merkleRootRaw as uint256;
    val deadlineRaw: coins = env<coins>("AIRDROP_DEADLINE") ?? 0;
    val deadline: uint32 = deadlineRaw as uint32;

    val storage: AirdropStorage = {
        merkleRoot,
        jettonMinter,
        admin,
        deadline,
        claimedMap: [],
    };

    val airdrop = PlxAirdrop.fromStorage(storage);
    val res = airdrop.sendDeploy(deployer.address, { value: ton("0.1") });
    res.waitForFirstTransaction();

    val jettonWallet = airdrop.getJettonWallet();

    println("AIRDROP CONTRACT_ADDRESS={}", airdrop.address);
    println("AIRDROP ADMIN_ADDRESS={}", admin);
    println("AIRDROP MINTER_ADDRESS={}", jettonMinter);
    println("AIRDROP JETTON_WALLET={}", jettonWallet);
    println("AIRDROP MERKLE_ROOT={}", merkleRoot);
    println("AIRDROP DEADLINE={}", deadline);
    println("AIRDROP DEPLOY_TRACE={}", res.waitForTrace());
}
