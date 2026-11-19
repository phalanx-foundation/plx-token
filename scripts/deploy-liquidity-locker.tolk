import "@stdlib/strings"
import "@acton/env"
import "@acton/io"
import "@acton/prompts"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@contracts/LiquidityLocker"
import "@wrappers/LiquidityLocker.gen"
import "@wrappers/utils"
import "utils/common"

/**
 * Non-interactive LiquidityLocker deploy.
 *
 * Env (required):
 *   DEPLOYER              — Acton wallet name
 *   LL_ADMIN              — Locker admin address
 *   LL_LP_TOKEN_MINTER    — LP jetton minter address (the DEX pool)
 *   LL_LP_WALLET_CODE     — LP jetton wallet code (base64/hex BoC cell),
 *                           read from the pool's get_jetton_data()
 */
fun main() {
    val deployer = promptJettonWallet("DEPLOYER", "Deployer wallet");
    val admin = promptJettonAddressRequired("LL_ADMIN", "Locker admin address");
    val lpTokenMinter = promptJettonAddressRequired("LL_LP_TOKEN_MINTER", "LP token minter address");
    val lpWalletCode = env<cell>("LL_LP_WALLET_CODE");
    if (lpWalletCode == null) {
        println("ERROR: LL_LP_WALLET_CODE required (base64/hex BoC of the pool LP jetton wallet code)");
        throw 1;
    }

    val cfg: LockerConfig = {
        admin,
        lpTokenMinter,
        lpWalletCode: lpWalletCode!,
    };

    println("Deploying LiquidityLocker...");
    println("  admin          = {}", admin);
    println("  lpTokenMinter  = {}", lpTokenMinter);
    println("  lpWalletCode   = <provided>");

    val locker = LiquidityLocker.fromStorage({
        config: cfg.toCell(),
        nextLockId: 0,
        totalLocked: 0,
        locks: [],
    });

    locker.deploy(deployer, { value: ton("1") });

    println("---");
    println("Locker deployed at: {}", locker.address);
    println("LIQUIDITY_LOCKER CONTRACT_ADDRESS={}", locker.address);
    println("---");
    println("Locked LP tokens can be queried by lockId.");
    println("Users call lockLpTokens() with LP tokens + unlock timestamp.");
    println("Admin can revoke any lock, users can unlock after maturity.");
}
