import "@stdlib/strings"
import "@acton/env"
import "@acton/io"
import "@acton/prompts"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@contracts/MidasHandEscrow"
import "@contracts/storage"
import "@wrappers/JettonMinter.gen"
import "@wrappers/MidasHandEscrow.gen"
import "@wrappers/utils"
import "utils/common"

/**
 * Non-interactive MidasHandEscrow deploy (one instance per deal).
 *
 * Env (required):
 *   DEPLOYER           — Acton wallet name
 *   MH_WHALE           — whale (TON provider) address
 *   MH_OWNER           — owner (jetton provider) address
 *   MH_MINTER          — seed token jetton minter address
 *   MH_ADMIN           — admin multisig address
 *   MH_DEX             — 0 = STON.fi v2.2 (default), 1 = DeDust v2
 *
 * STON.fi env (MH_DEX=0):
 *   MH_ROUTER          — STON.fi v2.2 router address
 *   MH_POOL            — STON.fi v2.2 pool (LP jetton minter) address
 *   MH_PTON_MASTER     — STON.fi pTON v2.1 master address
 *   MH_LP_WALLET_CODE  — LP jetton wallet code (base64 cell, from pool get_jetton_data)
 *   MH_PTON_WALLET_CODE— pTON jetton wallet code (base64 cell)
 *
 * DeDust env (MH_DEX=1), all resolved from the DeDust factory before deploying:
 *   MH_POOL                  — DeDust pool address (LP jetton minter)
 *   MH_DEDUST_NATIVE_VAULT   — factory native vault (TON leg destination)
 *   MH_DEDUST_JETTON_VAULT   — factory jetton vault for the seed jetton
 *   MH_LP_WALLET_CODE        — pool's LP jetton wallet code (base64 cell)
 *   MH_DEDUST_STABLE_POOL    — 1 for a stable pool; only 0 (volatile) is supported
 *
 * The DeDust LiquidityDeposit address is NOT an input: the factory derives it
 * from the depositor (this escrow), and the escrow address is the hash of this
 * config, so it cannot exist before the escrow does. The API binds it right
 * after deploy with BindDedustLiquidityDeposit (0x4d484537); the owner approve
 * refuses a DeDust escrow that is still unbound.
 *
 * The seed jetton wallet code is read from the seed minter get_jetton_data().
 * STON.fi LP add/remove (Fase 2) is wired on-chain: owner approve drives
 * provide_liquidity (2 legs) and settlement drives LP burn + pTON unwrap.
 * DeDust v2 add/remove is wired too: owner approve drives deposit_liquidity on
 * both vaults, settlement comes back as native TON + seed jetton, and a parked
 * leg is recoverable with cancel_deposit after the deposit deadline.
 */
fun main() {
    val deployer = promptJettonWallet("DEPLOYER", "Deployer wallet");
    val whale = promptJettonAddressRequired("MH_WHALE", "Whale address");
    val owner = promptJettonAddressRequired("MH_OWNER", "Owner address");
    val minterAddr = promptJettonAddressRequired("MH_MINTER", "Seed token minter address");
    val admin = promptJettonAddressRequired("MH_ADMIN", "Admin multisig address");
    val dexType: uint8 = (env<int>("MH_DEX") ?? 0) as uint8;
    val proposalTimeoutSec = env<int>("MH_PROPOSAL_TIMEOUT_SEC") ?? 604800;  // 7-day owner confirmation window

    val minter = JettonMinter.fromAddress(minterAddr);
    val seedWalletCode = minter.getJettonData().jettonWalletCode;

    // Exactly one DEX config cell is attached, the other stays null.
    var stonfi: Cell<StonFiConfig>? = null;
    var dedust: Cell<DedustConfig>? = null;

    if (dexType == 1) {
        // DeDust v2: the factory vault addresses come from the API
        // (factory get_vault_address), so this script only validates and
        // serializes them.
        //
        // The LiquidityDeposit address is deliberately NOT a deploy input: the
        // factory derives it from the depositor, which is the escrow itself, and
        // the escrow address is the hash of this very config. It is impossible to
        // know before the escrow exists, so the deploy leaves it null and the
        // admin binds it right after deploy with BindDedustLiquidityDeposit
        // (0x4d484537), keeping the escrow address unchanged.
        val pool = promptJettonAddressRequired("MH_POOL", "DeDust pool address");
        val nativeVault = promptJettonAddressRequired("MH_DEDUST_NATIVE_VAULT", "DeDust native vault");
        val jettonVault = promptJettonAddressRequired("MH_DEDUST_JETTON_VAULT", "DeDust jetton vault");
        val stablePool = (env<int>("MH_DEDUST_STABLE_POOL") ?? 0) != 0;
        val lpWalletCode = env<cell>("MH_LP_WALLET_CODE");
        if (lpWalletCode == null) {
            println("ERROR: MH_LP_WALLET_CODE required (base64/hex BoC of the DeDust pool LP jetton wallet code)");
            throw 1;
        }
        if (stablePool) {
            println("ERROR: only volatile (PoolType 0) DeDust pools are supported");
            throw 1;
        }

        dedust = DedustConfig {
            poolAddress: pool,
            liquidityDeposit: null,
            nativeVault: nativeVault.toCell(),
            jettonVault: jettonVault.toCell(),
            lpWalletCode: lpWalletCode!,
            stablePool,
        }.toCell();

        println("Deploying MidasHandEscrow (DeDust v2)...");
        println("  whale            = {}", whale);
        println("  owner            = {}", owner);
        println("  minter           = {}", minterAddr);
        println("  admin            = {}", admin);
        println("  dex              = 1 (DEDUST)");
        println("  pool             = {}", pool);
        println("  native vault     = {}", nativeVault);
        println("  jetton vault     = {}", jettonVault);
        println("  liquidity deposit= unbound (bind after deploy, op 0x4d484537)");
    } else {
        if (dexType != 0) {
            println("ERROR: MH_DEX must be 0 (STON.fi) or 1 (DeDust)");
            throw 1;
        }
        val router = promptJettonAddressRequired("MH_ROUTER", "STON.fi v2.2 router address");
        val pool = promptJettonAddressRequired("MH_POOL", "STON.fi v2.2 pool address");
        val ptonMaster = promptJettonAddressRequired("MH_PTON_MASTER", "pTON v2.1 master address");

        // The wallet codes are code cells; read from env as base64/hex BoC cells.
        // The deploy script must be run on the Ubuntu host where MH_LP_WALLET_CODE /
        // MH_PTON_WALLET_CODE are exported. We read them via env<cell> which parses
        // base64 or hex encoded BoC strings.
        val lpWalletCode = env<cell>("MH_LP_WALLET_CODE");
        val ptonWalletCode = env<cell>("MH_PTON_WALLET_CODE");
        if (lpWalletCode == null) {
            println("ERROR: MH_LP_WALLET_CODE required (base64/hex BoC of LP jetton wallet code)");
            throw 1;
        }
        if (ptonWalletCode == null) {
            println("ERROR: MH_PTON_WALLET_CODE required (base64/hex BoC of pTON jetton wallet code)");
            throw 1;
        }

        // STON.fi config is nested in its own cell (keeps the main config cell < 1023 bits / 4 refs).
        stonfi = StonFiConfig {
            routerAddress: router,
            poolAddress: pool,
            ptonMaster,
            lpWalletCode: lpWalletCode!,
            ptonWalletCode: ptonWalletCode!,
        }.toCell();

        println("Deploying MidasHandEscrow (STON.fi v2.2)...");
        println("  whale        = {}", whale);
        println("  owner        = {}", owner);
        println("  minter       = {}", minterAddr);
        println("  admin        = {}", admin);
        println("  dex          = 0 (STONFI)");
        println("  router       = {}", router);
        println("  pool         = {}", pool);
        println("  pton master  = {}", ptonMaster);
    }

    val config: MidasEscrowConfig = {
        whaleAddress: whale,
        ownerAddress: owner,
        minterAddress: minterAddr,
        seedWalletCode,
        adminMultisig: admin.toCell(),
        proposalTimeoutSec: proposalTimeoutSec,
        dexType,
        stonfi,
        dedust,
    };

    val escrow = MidasHandEscrow.fromStorage({
        config: config.toCell(),
        status: 0,
        termType: 0,
        whaleTonDeposited: 0,
        ownerJettonDeposited: 0,
        lpHeld: 0,
        lockUntil: 0,
        proposalDeadline: 0,
        settleProgress: 0,
        depositDeadline: 0,
    });

    escrow.deploy(deployer.address, { value: ton("1") });

    println("---");
    println("MidasHandEscrow deployed at: {}", escrow.address);
    println("MIDAS ESCROW_ADDRESS={}", escrow.address);
    println("---");
    println("1. Whale calls DepositTon(termType) with >= 500 TON.");
    println("2. Owner transfers seed jetton with forward op 0x4d484531.");
    println("3. Owner calls ApproveByOwner() — the escrow drives the DEX add-LP (2 legs).");
    println("4. Pool mints LP to escrow — status ACTIVE, lockUntil set when LP received.");
    println("5. After the term, whale/owner call ClaimAfterUnlock() — burn LP and settle both sides.");
    if (dexType == 1) {
        println("6. If a DeDust leg stays parked past depositDeadline, CancelDedustDeposit recovers it.");
    }
}
