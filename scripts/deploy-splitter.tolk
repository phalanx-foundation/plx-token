import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@contracts/PaymentSplitter"
import "@wrappers/PaymentSplitter.gen"
import "utils/common"

fun main() {
    val deployer = promptJettonWallet("SPLITTER_DEPLOYER", "Select deployer wallet");

    val minterAddress = promptJettonAddressRequired(
        "JETTON_MINTER_ADDRESS",
        "Enter PLX minter address (testnet or mainnet)",
    );

    val treasuryAddress = promptJettonAddressRequired(
        "TREASURY_ADDRESS",
        "Enter treasury address (where 50% of paid PLX will be forwarded)",
    );

    val adminAddress = promptJettonAddress(
        "SPLITTER_ADMIN_ADDRESS",
        "Enter splitter admin (TON withdraw rights only)",
        deployer.address,
    );

    val splitter = PaymentSplitter.fromStorage({
        minterAddress,
        treasuryAddress,
        admin: adminAddress,
        burnedTotal: 0,
        forwardedTotal: 0,
        deployCount: 0,
    });

    val res = splitter.sendDeploy(deployer.address, { value: ton("0.5") });
    res.waitForFirstTransaction();

    println("SPLITTER_ADDRESS={}", splitter.address);
    println("SPLITTER_MINTER={}", minterAddress);
    println("SPLITTER_TREASURY={}", treasuryAddress);
    println("SPLITTER_ADMIN={}", adminAddress);
    println("SPLITTER_BURNED_TOTAL={}", splitter.getBurnedTotal());
    println("SPLITTER_FORWARDED_TOTAL={}", splitter.getForwardedTotal());
    println("SPLITTER_DEPLOY_COUNT={}", splitter.getDeployCount());
    println("SPLITTER_JETTON_WALLET={}", splitter.getJettonWalletAddress());
}
