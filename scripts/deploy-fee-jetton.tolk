import "@stdlib/strings"
import "@acton/env"
import "@acton/fmt"
import "@acton/io"
import "@acton/prompts"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@contracts/fee-types"
import "@wrappers/FeeJettonMinter.gen"
import "@wrappers/utils"
import "utils/common"

/**
 * Non-interactive FeeJettonMinter deploy.
 *
 * Env (required):
 *   DEPLOYER              — Acton wallet name (pays gas)
 *   FEE_ADMIN_ADDRESS     — Minter admin address
 *   FEE_COLLECTOR_ADDRESS — Address that collects transfer fees
 *   FEE_BPS               — Fee in basis points as nano-unit (max 1000 = 10%)
 *   JETTON_NAME, JETTON_SYMBOL, JETTON_DESCRIPTION, JETTON_IMAGE, JETTON_DECIMALS
 */
fun main() {
    val deployer = promptJettonWallet("DEPLOYER", "Deployer wallet");
    val admin = promptJettonAddressRequired("FEE_ADMIN_ADDRESS", "Minter admin address");
    val collector = promptJettonAddressRequired("FEE_COLLECTOR_ADDRESS", "Fee collector address");
    val feeBpsRaw: coins = env<coins>("FEE_BPS") ?? 100;
    val feeBps: uint16 = feeBpsRaw as uint16;

    val metadata = promptJettonMetadata(JETTON_DEFAULT_DESCRIPTION);
    val metadataCell = buildJettonMetadataCell(metadata);

    val feeConfig: FeeMinterConfig = { feeBps, feeCollector: collector };
    val storage: FeeMinterStorage = {
        totalSupply: 0,
        adminAddress: admin,
        nextAdminAddress: null,
        metadata: metadataCell,
        feeConfig: feeConfig.toCell(),
    };

    val minter = FeeJettonMinter.fromStorage(storage);
    val res = minter.sendDeploy(deployer.address, { value: ton("0.1") });
    res.waitForFirstTransaction();

    println("FEE_JETTON MINTER_ADDRESS={}", minter.address);
    println("FEE_JETTON ADMIN_ADDRESS={}", admin);
    println("FEE_JETTON COLLECTOR_ADDRESS={}", collector);
    println("FEE_JETTON FEE_BPS={}", feeBps);

    val (actualBps, actualCollector) = minter.getFeeConfig();
    println("FEE_JETTON DEPLOYED_FEE_BPS={}", actualBps);
    println("FEE_JETTON DEPLOYED_COLLECTOR={}", actualCollector);
}
