import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@wrappers/JettonMinter.gen"
import "@wrappers/utils"

fun main() {
    val fromName = env<string>("FROM_WALLET") ?? "plx-deployer-v2";
    val from = scripts.wallet(fromName);
    val minterAddr = env<address>("JETTON_MINTER_ADDRESS")!;
    val minter = JettonMinter.fromAddress(minterAddr);
    val amount = ton("0.05");

    println("[topup-minter] {} -> {} amount {}", from.address, minter.address, amount);
    val res = minter.sendTopUpTons(
        from.address,
        { bounce: false, value: amount },
    );
    println(res.waitForTrace());
}
