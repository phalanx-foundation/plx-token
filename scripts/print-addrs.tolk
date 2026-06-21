import "@acton/io"
import "@acton/emulation/scripts"
import "utils/common"

fun printWallet(name: string) {
    val w = scripts.wallet(name);
    println("{} -> {}", name, w.address);
}

fun main() {
    printWallet("plx-deployer-v2");
    printWallet("plx-treasury");
    printWallet("plx-lp");
    printWallet("plx-community");
    printWallet("plx-marketing");
    printWallet("plx-vesting-beneficiary");
}
