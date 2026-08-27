import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@wrappers/JettonMinter.gen"
import "@wrappers/utils"

fun main() {
    val fromName = env<string>("FROM_WALLET") ?? "plx-marketing";
    val from = scripts.wallet(fromName);
    val minterAddr = env<address>("JETTON_MINTER_ADDRESS")!;
    val minter = JettonMinter.fromAddress(minterAddr);
    // Keep small: ops wallets are low on gas; empty body fails (0xFFFF) — must use TopUpTons.
    val amount = env<coins>("TON_AMOUNT_NANO") ?? ton("0.005");

    println("[topup-minter] {} -> {} amount {}", from.address, minter.address, amount);
    val res = minter.sendTopUpTons(
        from.address,
        { bounce: false, value: amount },
    );
    println(res.waitForTrace());
}
