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
const TOTAL_SUPPLY = 1000000000 * PLX_NANO
const LP_AMOUNT = 400000000 * PLX_NANO
const TREASURY_AMOUNT = 250000000 * PLX_NANO
const COMMUNITY_AMOUNT = 200000000 * PLX_NANO
const MARKETING_AMOUNT = 50000000 * PLX_NANO
const VESTING_AMOUNT = 100000000 * PLX_NANO

// 6 months in seconds (180 days)
const VESTING_DURATION_SECONDS = 15552000

fun main() {
    val deployerName = env<string>("PLX_DEPLOYER") ?? "plx-deployer-v2";
    val deployer = scripts.wallet(deployerName);

    val treasuryAddr = env<address>("PLX_TREASURY") ??
    promptJettonAddressRequired(
        "PLX_TREASURY",
        "Treasury wallet address",
    );
    val lpAddr = env<address>("PLX_LP") ??
    promptJettonAddressRequired(
        "PLX_LP",
        "LP wallet address",
    );
    val communityAddr = env<address>("PLX_COMMUNITY") ??
    promptJettonAddressRequired(
        "PLX_COMMUNITY",
        "Community wallet address",
    );
    val marketingAddr = env<address>("PLX_MARKETING") ??
    promptJettonAddressRequired(
        "PLX_MARKETING",
        "Marketing wallet address",
    );
    val beneficiaryAddr = env<address>("PLX_BENEFICIARY") ??
    promptJettonAddressRequired(
        "PLX_BENEFICIARY",
        "Vesting beneficiary address",
    );

    val vestingStart = env<int>("PLX_VESTING_START")!;

    println("==== Phalanx PLX Distribution Deploy ====");
    println("Deployer: {}", deployer.address);
    println("Treasury:  {}", treasuryAddr);
    println("LP:        {}", lpAddr);
    println("Community: {}", communityAddr);
    println("Marketing: {}", marketingAddr);
    println("Beneficiary (vesting): {}", beneficiaryAddr);
    println("Vesting start (unix): {}", vestingStart);
    println("Vesting duration (sec): {}", VESTING_DURATION_SECONDS);

    // 1) Deploy Jetton Minter
    val metadata: JettonMetadata = {
        name: "Phalanx",
        symbol: "PLX",
        description: JETTON_DEFAULT_DESCRIPTION,
        image: defaultJettonImageUrl(),
        decimals: "9",
    };
    val minter = JettonMinter.fromStorage({
        totalSupply: 0,
        adminAddress: deployer.address,
        nextAdminAddress: null,
        metadata: buildJettonMetadataCell(metadata),
    });
    println("\n[1/7] Deploying minter at {}", minter.address);
    val deployRes = minter.sendDeploy(deployer.address, { value: ton("0.5") });
    deployRes.waitForFirstTransaction();
    println("    OK");

    // 2-5) Mint to 4 wallets
    println("\n[2/7] Minting LP {} nano-PLX to {}", LP_AMOUNT, lpAddr);
    minter.sendMint(deployer.address, lpAddr, LP_AMOUNT, ton("0.05"), ton("0.3")).waitForTrace();

    println("\n[3/7] Minting TREASURY {} nano-PLX to {}", TREASURY_AMOUNT, treasuryAddr);
    minter
        .sendMint(deployer.address, treasuryAddr, TREASURY_AMOUNT, ton("0.05"), ton("0.3"))
        .waitForTrace();

    println("\n[4/7] Minting COMMUNITY {} nano-PLX to {}", COMMUNITY_AMOUNT, communityAddr);
    minter
        .sendMint(deployer.address, communityAddr, COMMUNITY_AMOUNT, ton("0.05"), ton("0.3"))
        .waitForTrace();

    println("\n[5/7] Minting MARKETING {} nano-PLX to {}", MARKETING_AMOUNT, marketingAddr);
    minter
        .sendMint(deployer.address, marketingAddr, MARKETING_AMOUNT, ton("0.05"), ton("0.3"))
        .waitForTrace();

    // 6) Deploy Team Vesting
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

    // 7) Mint VESTING_AMOUNT into vesting contract address
    println("\n[7/7] Minting VESTING {} nano-PLX into vesting contract", VESTING_AMOUNT);
    minter
        .sendMint(deployer.address, vesting.address, VESTING_AMOUNT, ton("0.05"), ton("0.3"))
        .waitForTrace();

    println("\n==== Deploy complete. Summary ====");
    println("PLX_MINTER_ADDRESS={}", minter.address);
    println("PLX_VESTING_ADDRESS={}", vesting.address);
    println("PLX_LP_WALLET={}", minter.getWalletAddress(lpAddr));
    println("PLX_TREASURY_WALLET={}", minter.getWalletAddress(treasuryAddr));
    println("PLX_COMMUNITY_WALLET={}", minter.getWalletAddress(communityAddr));
    println("PLX_MARKETING_WALLET={}", minter.getWalletAddress(marketingAddr));
    println("PLX_VESTING_JETTON_WALLET={}", minter.getWalletAddress(vesting.address));

    printJettonMinterInfo(minter, "PLX");
}
