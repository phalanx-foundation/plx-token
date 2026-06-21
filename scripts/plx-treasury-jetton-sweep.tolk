import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@wrappers/JettonMinter.gen"
import "@wrappers/JettonWallet.gen"
import "utils/common"

fun sendJetton(
    from: ActonWallet,
    minter: JettonMinter,
    recipient: address,
    amount: coins,
    label: string,
) {
    println("[plx-treasury-sweep] {} -> {} amount {}", label, recipient, amount);
    val senderWallet = JettonWallet { address: minter.getWalletAddress(from.address) };
    val res = senderWallet.sendTransfer(
        from.address,
        ton("0.08"),
        amount,
        recipient,
        from.address,
        null,
        1,
        null,
    );
    println(res.waitForTrace());
}

fun main() {
    val fromName = env<string>("FROM_WALLET") ?? "plx-treasury";
    val from = scripts.wallet(fromName);

    val minter = JettonMinter.fromAddress(env<address>("JETTON_MINTER_ADDRESS")!);

    val lpAddr = env<address>("PLX_LP_ADDRESS")!;
    val marketingAddr = env<address>("PLX_MARKETING_ADDRESS")!;
    val toolkitOpsAddr = env<address>("PLX_TOOLKIT_OPS_ADDRESS")!;

    val lpNano = env<coins>("PLX_SWEEP_LP_NANO")!;
    val marketingNano = env<coins>("PLX_SWEEP_MARKETING_NANO")!;
    val opsNano = env<coins>("PLX_SWEEP_OPS_NANO")!;

    val deploymentId = env<string>("DEPLOYMENT_ID") ?? "unknown";
    println("[plx-treasury-sweep] deployment_id={} signer={}", deploymentId, from.address);
    println(
        "[plx-treasury-sweep] lp={} marketing={} ops={}",
        lpNano,
        marketingNano,
        opsNano,
    );

    if (lpNano > 0) {
        sendJetton(from, minter, lpAddr, lpNano, "lp");
    }
    if (marketingNano > 0) {
        sendJetton(from, minter, marketingAddr, marketingNano, "marketing");
    }
    if (opsNano > 0) {
        sendJetton(from, minter, toolkitOpsAddr, opsNano, "ops");
    }

    println("PLX_SWEEP_DEPLOYMENT_ID={}", deploymentId);
}
