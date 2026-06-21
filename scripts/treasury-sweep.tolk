import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "utils/common"

fun sendTon(from: ActonWallet, dest: address, amount: coins, label: string) {
    println("[treasury-sweep] {} -> {} amount {}", label, dest, amount);
    val msg = createMessage({
        bounce: false,
        value: amount,
        dest: dest,
    });
    val res = net.send(from.address, msg);
    println(res.waitForTrace());
}

fun main() {
    val fromName = env<string>("FROM_WALLET") ?? "plx-treasury";
    val from = scripts.wallet(fromName);

    val quarter = env<coins>("QUARTER_NANO")!;
    val marketingAddr = env<address>("PLX_MARKETING_ADDRESS")!;
    val toolkitOpsAddr = env<address>("PLX_TOOLKIT_OPS_ADDRESS")!;

    val deploymentId = env<string>("DEPLOYMENT_ID") ?? "unknown";
    println("[treasury-sweep] deployment_id={} signer={}", deploymentId, from.address);
    println("[treasury-sweep] quarter_nano={}", quarter);

    sendTon(from, marketingAddr, quarter, "growth");
    sendTon(from, toolkitOpsAddr, quarter, "ops");
    // LP slice handled by scripts/stonfi-add-liquidity.py (Ston.fi or fallback transfer)

    println("SWEEP_BUYBACK_NANO={}", quarter);
    println("SWEEP_DEPLOYMENT_ID={}", deploymentId);
    println("[treasury-sweep] buyback slice queued (25% retained in treasury until swap+burn)");
}
