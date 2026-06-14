import "@stdlib/strings"
import "@acton/env"
import "@acton/fmt"
import "@acton/io"
import "@acton/prompts"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@contracts/AntiWhaleJettonWallet"
import "@wrappers/AntiWhaleJettonWallet.gen"
import "@wrappers/utils"
import "utils/common"

/**
 * Non-interactive AntiWhaleJettonWallet deploy (standalone wallet for testing/admin).
 *
 * Env (required):
 *   DEPLOYER              — Acton wallet name
 *   AW_OWNER              — Wallet owner address
 *   AW_MINTER             — Jetton minter address
 *   AW_MAX_TRANSFER       — Max transfer amount in nano-tokens (0 = no limit)
 *   AW_MAX_WALLET         — Max wallet balance in nano-tokens (0 = disabled)
 */
fun main() {
    val deployer = promptJettonWallet("DEPLOYER", "Deployer wallet");
    val owner = promptJettonAddressRequired("AW_OWNER", "Wallet owner address");
    val minter = promptJettonAddressRequired("AW_MINTER", "Jetton minter address");
    val maxTransfer: coins = env<coins>("AW_MAX_TRANSFER") ?? 1000000000000;  // default 1000 tokens
    val maxWallet: coins = env<coins>("AW_MAX_WALLET") ?? 0;  // default: disabled

    val storage: AntiWhaleWalletStorage = {
        jettonBalance: 0,
        ownerAddress: owner,
        minterAddress: minter,
        maxTransferAmount: maxTransfer,
        maxWalletBalance: maxWallet,
    };

    val wallet = AntiWhaleJettonWallet.fromStorage(storage);
    val res = wallet.sendDeploy(deployer.address, { value: ton("0.05") });
    res.waitForFirstTransaction();

    val (walletMaxTransfer, walletMaxBalance) = wallet.getWhaleConfig();

    println("ANTI_WHALE WALLET_ADDRESS={}", wallet.address);
    println("ANTI_WHALE OWNER_ADDRESS={}", owner);
    println("ANTI_WHALE MINTER_ADDRESS={}", minter);
    println("ANTI_WHALE MAX_TRANSFER={}", walletMaxTransfer);
    println("ANTI_WHALE MAX_WALLET_BALANCE={}", walletMaxBalance);
    println("ANTI_WHALE DEPLOY_TRACE={}", res.waitForTrace());
}
