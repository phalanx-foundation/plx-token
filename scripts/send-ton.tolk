import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "utils/common"

fun main() {
    val fromName = env<string>("FROM_WALLET") ?? "plx-treasury";
    val toAddr = env<address>("TO_ADDRESS")!;
    // TON_AMOUNT_NANO = nanotons (e.g. 3000000000 for 3 TON). Bare TON_AMOUNT via env<coins> is nanotons too.
    val amount = env<coins>("TON_AMOUNT_NANO") ?? env<coins>("TON_AMOUNT") ?? ton("0.03");
    val from = scripts.wallet(fromName);
    println("send-ton: {} -> {} amount {}", from.address, toAddr, amount);
    val msg = createMessage({
        bounce: false,
        value: amount,
        dest: toAddr,
    });
    val res = net.send(from.address, msg);
    println(res.waitForTrace());
}
