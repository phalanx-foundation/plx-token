import "@stdlib/strings"
import "@acton/env"
import "@acton/fmt"
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
 *
 * The seed jetton wallet code is read from the seed minter get_jetton_data()
 * so the escrow can verify its own jetton wallet.
 *
 * NOTE: STON.fi LP add/remove (Fase 2) is not wired yet — this Fase 1 escrow is
 * time-locked custody only; principal is returned at settlement.
 */
fun main() {
    val deployer = promptJettonWallet("DEPLOYER", "Deployer wallet");
    val whale = promptJettonAddressRequired("MH_WHALE", "Whale address");
    val owner = promptJettonAddressRequired("MH_OWNER", "Owner address");
    val minterAddr = promptJettonAddressRequired("MH_MINTER", "Seed token minter address");
    val admin = promptJettonAddressRequired("MH_ADMIN", "Admin multisig address");

    val minter = JettonMinter.fromAddress(minterAddr);
    val seedWalletCode = minter.getJettonData().jettonWalletCode;

    val config: MidasEscrowConfig = {
        whaleAddress: whale,
        ownerAddress: owner,
        minterAddress: minterAddr,
        seedWalletCode,
        adminMultisig: admin.toCell(),
        proposalTimeoutSec: 86400,
    };

    println("Deploying MidasHandEscrow...");
    println(fmt("  whale        = {a}", [whale]));
    println(fmt("  owner        = {a}", [owner]));
    println(fmt("  minter       = {a}", [minterAddr]));
    println(fmt("  admin        = {a}", [admin]));

    val escrow = MidasHandEscrow.fromStorage({
        config: config.toCell(),
        status: 0,
        termType: 0,
        whaleTonDeposited: 0,
        ownerJettonDeposited: 0,
        lockUntil: 0,
        proposalDeadline: 0,
    });

    escrow.deploy(deployer, { value: ton("1") });

    println("---");
    println(fmt("MidasHandEscrow deployed at: {a}", [escrow.address]));
    println("---");
    println("1. Whale calls DepositTon(termType) with >= 500 TON.");
    println("2. Owner transfers seed jetton with forward op 0x4d484531.");
    println("3. Owner calls ApproveByOwner() to lock for the term.");
    println("4. After the term, whale/owner call ClaimAfterUnlock().");
}
