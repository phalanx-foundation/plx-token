import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@wrappers/JettonMinter.gen"
import "@wrappers/JettonWallet.gen"
import "@wrappers/utils"

fun main() {
    val burnerName = env<string>("PLX_BURNER") ?? "plx-treasury";
    val burner = scripts.wallet(burnerName);

    val minterAddr = env<address>("JETTON_MINTER_ADDRESS")!;
    val minter = JettonMinter.fromAddress(minterAddr);

    val burnAmount = env<coins>("PLX_BURN_AMOUNT")!;

    val burnerJettonWallet = JettonWallet { address: minter.getWalletAddress(burner.address) };
    println(
        "[buyback-burn] burner={} jetton-wallet={} amount={}",
        burner.address,
        burnerJettonWallet.address,
        burnAmount,
    );

    val supplyBefore = minter.getTotalSupply();
    println("[buyback-burn] supply before: {}", supplyBefore);

    val res = burnerJettonWallet.sendAskToBurn(
        burner.address,
        0,
        burnAmount,
        burner.address,
        null,
        { bounce: false, value: ton("0.2") },
    );
    res.waitForTrace();

    val supplyAfter = minter.getTotalSupply();
    println("[buyback-burn] supply after: {}", supplyAfter);
    println("[buyback-burn] burned: {}", supplyBefore - supplyAfter);
}
