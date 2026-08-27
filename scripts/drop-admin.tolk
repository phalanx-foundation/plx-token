import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@wrappers/JettonMinter.gen"
import "@wrappers/utils"

fun main() {
    // EMERGENCY: legacy null-drop broke TonAPI catalog (empty admin vs MsgAddressInt).
    // New JettonMinter DropMinterAdmin sets burn address — still irreversible.
    // Dashboard TX is killed; this script stays gated for ops only.
    val adminName = env<string>("PLX_ADMIN") ?? "plx-deployer-v2";
    val admin = scripts.wallet(adminName);

    val minterAddr = env<address>("JETTON_MINTER_ADDRESS")!;
    val minter = JettonMinter.fromAddress(minterAddr);

    val confirm = env<int>("PLX_CONFIRM_DROP_ADMIN") ?? 0;
    if (confirm != 1) {
        println("[drop-admin] ABORT: set PLX_CONFIRM_DROP_ADMIN=1");
        println("[drop-admin] NOTE: revoke sets admin to BURN address (docs.ton.org), not null.");
        println("[drop-admin] Do NOT use against PLX genesis (already revoked). Irreversible.");
        return;
    }

    println("[drop-admin] admin={} minter={}", admin.address, minter.address);
    println("[drop-admin] sending DropMinterAdmin → burn address (PERMANENT fixed supply)");

    val res = minter.sendDropMinterAdmin(
        admin.address,
        0,
        { bounce: false, value: ton("0.05") },
    );
    res.waitForTrace();

    println("[drop-admin] OK. New admin (expect burn): {}", minter.getAdminAddress());
}
