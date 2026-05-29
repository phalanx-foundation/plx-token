import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@wrappers/JettonMinter.gen"
import "utils/common"

/**
 * Non-interactive metadata refresh for the live PLX testnet minter.
 * Set JETTON_IMAGE (and optional JETTON_* fields) before running.
 *
 * Example:
 *   JETTON_MINTER_ADDRESS=kQAslxaUshiiqy5FrTbYHbBpjBgmcyTHB8vKKCemFKp508xV
 *   JETTON_ADMIN=plx-deployer-v2
 *   JETTON_IMAGE=https://plx.foundation/plx-logo.png
 *   acton run refresh-metadata-testnet
 */
fun main() {
    val admin = promptJettonWallet("JETTON_ADMIN", "Select Jetton Admin ActonWallet");
    val minter = promptJettonMinter("Enter Jetton Minter address");
    val metadata = promptJettonMetadata(JETTON_DEFAULT_DESCRIPTION);

    val res = minter.sendChangeMinterMetadata(
        admin.address,
        0,
        buildJettonMetadataCell(metadata),
        { bounce: false, value: ton("0.05") },
    );
    println(res.waitForTrace());

    printJettonMinterInfo(minter, "JETTON");
}
