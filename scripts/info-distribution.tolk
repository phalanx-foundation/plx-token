import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@wrappers/JettonMinter.gen"
import "@wrappers/TeamVesting.gen"
import "@wrappers/utils"
import "utils/common"

fun main() {
    val minterAddr = env<address>("JETTON_MINTER_ADDRESS")!;
    val minter = JettonMinter.fromAddress(minterAddr);

    println("==== Phalanx PLX — Distribution Status ====");
    printJettonMinterInfo(minter, "PLX");

    val vestingAddr = env<address>("PLX_VESTING_ADDRESS");
    if (vestingAddr != null) {
        val vesting = TeamVesting.fromAddress(vestingAddr);
        val cfg = vesting.getVestingData();
        val vested = vesting.getVestedAmount();
        val claimed = vesting.getClaimedAmount();
        val claimable = vesting.getClaimableAmount();
        println("\n[vesting] address={}", vesting.address);
        println("[vesting] beneficiary={}", cfg.beneficiary);
        println("[vesting] startTime={} duration={}", cfg.startTime, cfg.duration);
        println("[vesting] totalAmount={}", cfg.totalAmount);
        println("[vesting] vested={} (= unlocked so far)", vested);
        println("[vesting] claimed={}", claimed);
        println("[vesting] claimable now={}", claimable);
    }

    val labels = ["lp", "treasury", "community", "marketing"];
    val envKeys = ["PLX_LP", "PLX_TREASURY", "PLX_COMMUNITY", "PLX_MARKETING"];
    var i = 0;
    while (i < 4) {
        val addr = env<address>(envKeys.get(i));
        if (addr != null) {
            printJettonWalletInfo(minter, addr, labels.get(i));
        }
        i += 1;
    }
}
