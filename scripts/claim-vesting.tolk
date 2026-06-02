import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@wrappers/TeamVesting.gen"

fun main() {
    val callerName = env<string>("PLX_CALLER") ?? "plx-deployer-v2";
    val caller = scripts.wallet(callerName);

    val vestingAddr = env<address>("PLX_VESTING_ADDRESS")!;
    val vesting = TeamVesting.fromAddress(vestingAddr);

    println("[claim-vesting] caller={} vesting={}", caller.address, vesting.address);
    val claimable = vesting.getClaimableAmount();
    println("[claim-vesting] claimable now: {}", claimable);
    if (claimable == 0) {
        println("[claim-vesting] nothing to claim yet");
        return;
    }

    val res = vesting.sendClaimVested(
        caller.address,
        0,
        { bounce: false, value: ton("0.3") },
    );
    res.waitForTrace();
    println("[claim-vesting] OK; new claimed amount: {}", vesting.getClaimedAmount());
}
