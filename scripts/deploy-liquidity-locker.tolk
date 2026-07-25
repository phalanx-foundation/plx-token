import "@stdlib/strings"
import "@acton/env"
import "@acton/fmt"
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
 *   LL_LP_TOKEN_MINTER    — LP jetton minter address
 */
fun main() {
    val deployer = promptJettonWallet("DEPLOYER", "Deployer wallet");
    val admin = promptJettonAddressRequired("LL_ADMIN", "Locker admin address");
    val lpTokenMinter = promptJettonAddressRequired("LL_LP_TOKEN_MINTER", "LP token minter address");

    val cfg: LockerConfig = {
        admin,
        lpTokenMinter,
    };

    println("Deploying LiquidityLocker...");
    println(fmt("  admin          = {a}", [admin]));
    println(fmt("  lpTokenMinter  = {a}", [lpTokenMinter]));

    val locker = LiquidityLocker.fromStorage({
        config: cfg.toCell(),
        nextLockId: 0,
        totalLocked: 0,
        locks: [],
    });

    locker.deploy(deployer, { value: ton("1") });

    println("---");
    println(fmt("Locker deployed at: {a}", [locker.address]));
    println("---");
    println("Locked LP tokens can be queried by lockId.");
    println("Users call lockLpTokens() with LP tokens + unlock timestamp.");
    println("Admin can revoke any lock, users can unlock after maturity.");
}
