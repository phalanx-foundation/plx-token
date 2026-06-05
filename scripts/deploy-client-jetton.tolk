import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@wrappers/JettonMinter.gen"
import "@wrappers/utils"
import "utils/common"

/**
 * Non-interactive client jetton deploy for Phalanx Toolkit (Batch 8D).
 *
 * Env (required):
 *   JETTON_DEPLOYER          — Acton wallet name (pays gas, escrow admin when minting)
 *   JETTON_ADMIN_ADDRESS     — Client wallet (final minter admin)
 *   JETTON_INITIAL_RECIPIENT — Mint recipient (defaults to admin)
 *   JETTON_NAME, JETTON_SYMBOL, JETTON_DESCRIPTION, JETTON_IMAGE, JETTON_DECIMALS
 *   JETTON_MINT_AMOUNT_NANO  — Initial mint in nano-jettons (0 = deploy-only, client admin)
 *
 * Escrow (mint > 0): deployer admin → mint → change admin to client (client must claim).
 */
fun main() {
    val deployer = promptJettonWallet("JETTON_DEPLOYER", "Toolkit deployer wallet");
    val clientAdmin = promptJettonAddressRequired("JETTON_ADMIN_ADDRESS", "Client admin address");
    val recipient = promptJettonAddress(
        "JETTON_INITIAL_RECIPIENT",
        "Initial mint recipient",
        clientAdmin,
    );
    val mintAmountNano = promptJettonCoins(
        "JETTON_MINT_AMOUNT_NANO",
        "Initial mint amount (nano-jettons)",
        "0",
    );

    val useEscrow = mintAmountNano > 0;
    var adminForDeploy = clientAdmin;
    if (useEscrow) {
        adminForDeploy = deployer.address;
    }

    val storage = promptJettonMinterStorage(adminForDeploy);
    val minter = JettonMinter.fromStorage(storage);
    val deployRes = minter.sendDeploy(deployer.address, { value: ton("0.08") });
    deployRes.waitForFirstTransaction();
    println("TOOLKIT MINTER_ADDRESS={}", minter.address);
    println("TOOLKIT DEPLOY_TRACE={}", deployRes.waitForTrace());

    if (useEscrow) {
        println("TOOLKIT Escrow mint {} nano to {}", mintAmountNano, recipient);
        minter
            .sendMint(deployer.address, recipient, mintAmountNano, ton("0.05"), ton("0.3"))
            .waitForTrace();

        minter
            .sendChangeMinterAdmin(
                deployer.address,
                0,
                clientAdmin,
                { bounce: false, value: ton("0.05") },
            )
            .waitForTrace();
        println("TOOLKIT PENDING_ADMIN_CLAIM=true");
        println("TOOLKIT FINAL_ADMIN_ADDRESS={}", clientAdmin);
    }

    printJettonMinterInfo(minter, "JETTON");
    printJettonWalletInfo(minter, recipient, "JETTON_RECIPIENT");
}
