import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@wrappers/JettonMinter.gen"

fun main() {
    val adminName = env<string>("PLX_ADMIN") ?? "plx-deployer";
    val admin = scripts.wallet(adminName);

    val minterAddr = env<address>("JETTON_MINTER_ADDRESS")!;
    val minter = JettonMinter.fromAddress(minterAddr);

    val confirm = env<string>("PLX_CONFIRM_DROP_ADMIN") ?? "";
    if (confirm != "I_UNDERSTAND_THIS_IS_FOREVER") {
        println("[drop-admin] ABORT: set PLX_CONFIRM_DROP_ADMIN=I_UNDERSTAND_THIS_IS_FOREVER");
        return;
    }

    println("[drop-admin] admin={} minter={}", admin.address, minter.address);
    println("[drop-admin] sending DropMinterAdmin (PERMANENT — supply will become fixed)");

    val res = minter.sendDropMinterAdmin(
        admin.address,
        0,
        { bounce: false, value: ton("0.05") },
    );
    res.waitForTrace();

    println("[drop-admin] OK. New admin: {}", minter.getAdminAddress());
}
