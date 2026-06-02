import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@contracts/TeamVesting"
import "@contracts/storage"
import "@wrappers/JettonMinter.gen"
import "@wrappers/TeamVesting.gen"
import "@wrappers/utils"
import "utils/common"

const PLX_NANO = 1000000000
const VESTING_AMOUNT = 100000000 * PLX_NANO
const VESTING_DURATION_SECONDS = 15552000

fun main() {
    val deployerName = env<string>("PLX_DEPLOYER") ?? "plx-deployer-v2";
    val deployer = scripts.wallet(deployerName);

    val minterAddr = env<address>("JETTON_MINTER_ADDRESS")!;
    val minter = JettonMinter.fromAddress(minterAddr);

    val beneficiaryAddr = env<address>("PLX_BENEFICIARY")!;
    val vestingStart = env<int>("PLX_VESTING_START")!;

    println("==== Finish vesting (resume) ====");
    println("Deployer: {}", deployer.address);
    println("Minter:   {}", minter.address);
    println("Beneficiary: {}", beneficiaryAddr);
    println("Vesting start (unix): {}", vestingStart);

    val vestingConfig: VestingConfig = {
        beneficiary: beneficiaryAddr,
        admin: deployer.address,
        minterAddress: minter.address,
        totalAmount: VESTING_AMOUNT,
        startTime: vestingStart,
        duration: VESTING_DURATION_SECONDS,
    };
    val vesting = TeamVesting.fromStorage({
        config: vestingConfig.toCell(),
        claimedAmount: 0,
    });
    println("\n[6/7] Deploying vesting at {}", vesting.address);
    vesting.sendDeploy(deployer.address, { value: ton("1") }).waitForFirstTransaction();
    println("    OK");

    println("\n[7/7] Minting VESTING {} nano-PLX into vesting contract", VESTING_AMOUNT);
    minter
        .sendMint(deployer.address, vesting.address, VESTING_AMOUNT, ton("0.05"), ton("0.3"))
        .waitForTrace();

    println("\n==== Vesting complete ====");
    println("PLX_VESTING_ADDRESS={}", vesting.address);
    println("PLX_VESTING_JETTON_WALLET={}", minter.getWalletAddress(vesting.address));
    printJettonMinterInfo(minter, "PLX");
}
