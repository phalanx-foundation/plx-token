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
 *   MH_ROUTER          — STON.fi v2.2 router address
 *   MH_POOL            — STON.fi v2.2 pool (LP jetton minter) address
 *   MH_PTON_MASTER     — STON.fi pTON v2.1 master address
 *   MH_LP_WALLET_CODE  — LP jetton wallet code (base64 cell, from pool get_jetton_data)
 *   MH_PTON_WALLET_CODE— pTON jetton wallet code (base64 cell)
 *
 * The seed jetton wallet code is read from the seed minter get_jetton_data().
 * STON.fi LP add/remove (Fase 2) is wired on-chain: owner approve drives
 * provide_liquidity (2 legs) and settlement drives LP burn + pTON unwrap.
 */
fun main() {
    val deployer = promptJettonWallet("DEPLOYER", "Deployer wallet");
    val whale = promptJettonAddressRequired("MH_WHALE", "Whale address");
    val owner = promptJettonAddressRequired("MH_OWNER", "Owner address");
    val minterAddr = promptJettonAddressRequired("MH_MINTER", "Seed token minter address");
    val admin = promptJettonAddressRequired("MH_ADMIN", "Admin multisig address");
    val router = promptJettonAddressRequired("MH_ROUTER", "STON.fi v2.2 router address");
    val pool = promptJettonAddressRequired("MH_POOL", "STON.fi v2.2 pool address");
    val ptonMaster = promptJettonAddressRequired("MH_PTON_MASTER", "pTON v2.1 master address");

    val minter = JettonMinter.fromAddress(minterAddr);
    val seedWalletCode = minter.getJettonData().jettonWalletCode;

    // The wallet codes are code cells; read from env as base64/hex BoC cells.
    // The deploy script must be run on the Ubuntu host where MH_LP_WALLET_CODE /
    // MH_PTON_WALLET_CODE are exported. We read them via env<cell> which parses
    // base64 or hex encoded BoC strings.
    val lpWalletCode = env<cell>("MH_LP_WALLET_CODE");
    val ptonWalletCode = env<cell>("MH_PTON_WALLET_CODE");
    val proposalTimeoutSec = env<int>("MH_PROPOSAL_TIMEOUT_SEC") ?? 604800;  // 7-day owner confirmation window
    if (lpWalletCode == null) {
        println("ERROR: MH_LP_WALLET_CODE required (base64/hex BoC of LP jetton wallet code)");
        throw 1;
    }
    if (ptonWalletCode == null) {
        println("ERROR: MH_PTON_WALLET_CODE required (base64/hex BoC of pTON jetton wallet code)");
        throw 1;
    }

    // STON.fi config is nested in its own cell (keeps the main config cell < 1023 bits / 4 refs).
    val stonfi: StonFiConfig = {
        routerAddress: router,
        poolAddress: pool,
        ptonMaster,
        lpWalletCode: lpWalletCode!,
        ptonWalletCode: ptonWalletCode!,
    };

    val config: MidasEscrowConfig = {
        whaleAddress: whale,
        ownerAddress: owner,
        minterAddress: minterAddr,
        seedWalletCode,
        adminMultisig: admin.toCell(),
        proposalTimeoutSec: proposalTimeoutSec,
        stonfi: stonfi.toCell(),
    };

    println("Deploying MidasHandEscrow...");
    println("  whale        = {}", whale);
    println("  owner        = {}", owner);
    println("  minter       = {}", minterAddr);
    println("  admin        = {}", admin);
    println("  router       = {}", router);
    println("  pool         = {}", pool);
    println("  pton master  = {}", ptonMaster);

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
    });

    escrow.deploy(deployer.address, { value: ton("1") });

    println("---");
    println("MidasHandEscrow deployed at: {}", escrow.address);
    println("MIDAS ESCROW_ADDRESS={}", escrow.address);
    println("---");
    println("1. Whale calls DepositTon(termType) with >= 500 TON.");
    println("2. Owner transfers seed jetton with forward op 0x4d484531.");
    println("3. Owner calls ApproveByOwner() — escrow drives STON.fi v2.2 add-LP (2 legs).");
    println("4. Pool mints LP to escrow — status ACTIVE, lockUntil set when LP received.");
    println("5. After the term, whale/owner call ClaimAfterUnlock() — burn LP + pTON/PLX redistributed.");
}
