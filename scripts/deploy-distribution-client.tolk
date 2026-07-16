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

/**
 * Multi-wallet distribution deploy for Phalanx Toolkit clients (Distribution/
 * Enterprise tiers). Mints the supply across up to 12 buckets with optional
 * linear vesting per bucket, then hands minter admin to the client wallet.
 *
 * Env (required):
 *   JETTON_DEPLOYER          — Acton wallet name (pays gas, escrow admin)
 *   JETTON_ADMIN_ADDRESS     — Client wallet (final minter admin)
 *   JETTON_NAME/SYMBOL/DESCRIPTION/IMAGE/DECIMALS — jetton metadata
 *   JETTON_ALLOC_COUNT       — number of buckets (1..12)
 *   JETTON_ALLOC_{i}_ADDRESS — recipient (beneficiary if vesting)
 *   JETTON_ALLOC_{i}_NANO    — amount in nano-jettons
 *   JETTON_ALLOC_{i}_VEST    — "1" to lock via TeamVesting (optional)
 *   JETTON_ALLOC_{i}_VEST_START    — absolute unix start (required if VEST=1)
 *   JETTON_ALLOC_{i}_VEST_DURATION — linear duration in seconds (required if VEST=1)
 *
 * Escrow: deployer is temporary admin during mints, then changes admin to the
 * client (client must claim). Output lines mirror deploy-client-jetton.tolk so
 * toolkit-broadcast.sh can parse minter address + pending-claim flag.
 */
fun processAllocation(
    minter: JettonMinter,
    deployerAddr: address,
    clientAdmin: address,
    addrKey: string,
    nanoKey: string,
    vestKey: string,
    vestStartKey: string,
    vestDurationKey: string,
) {
    val recipient = env<address>(addrKey);
    if (recipient == null) {
        return;
    }
    val nanoOpt = env<coins>(nanoKey);
    if (nanoOpt == null) {
        return;
    }
    val nano = nanoOpt;
    if (nano <= 0) {
        return;
    }

    val vestFlag = env<int>(vestKey) ?? 0;
    if (vestFlag == 1) {
        val startTime = env<int>(vestStartKey)!;
        val duration = env<int>(vestDurationKey)!;
        val vestingConfig: VestingConfig = {
            beneficiary: recipient,
            admin: clientAdmin,
            minterAddress: minter.address,
            totalAmount: nano,
            startTime: startTime,
            duration: duration,
        };
        val vesting = TeamVesting.fromStorage({
            config: vestingConfig.toCell(),
            claimedAmount: 0,
        });
        vesting.sendDeploy(deployerAddr, { value: ton("1") }).waitForFirstTransaction();
        minter
            .sendMint(deployerAddr, vesting.address, nano, ton("0.05"), ton("0.3"))
            .waitForTrace();
        println("TOOLKIT ALLOC_VESTING={} AMOUNT={} BENEFICIARY={}", vesting.address, nano, recipient);
    } else {
        minter
            .sendMint(deployerAddr, recipient, nano, ton("0.05"), ton("0.3"))
            .waitForTrace();
        println("TOOLKIT ALLOC_MINT AMOUNT={} RECIPIENT={}", nano, recipient);
    }
}

fun main() {
    val deployer = promptJettonWallet("JETTON_DEPLOYER", "Toolkit deployer wallet");
    val clientAdmin = promptJettonAddressRequired("JETTON_ADMIN_ADDRESS", "Client admin address");
    val allocCount = env<int>("JETTON_ALLOC_COUNT") ?? 0;
    println("TOOLKIT ALLOC_COUNT={}", allocCount);

    // Deploy minter with deployer as escrow admin (handed to client after mints).
    val storage = promptJettonMinterStorage(deployer.address);
    val minter = JettonMinter.fromStorage(storage);
    val deployRes = minter.sendDeploy(deployer.address, { value: ton("0.1") });
    deployRes.waitForFirstTransaction();
    println("TOOLKIT MINTER_ADDRESS={}", minter.address);
    println("TOOLKIT DEPLOY_TRACE={}", deployRes.waitForTrace());

    // Unrolled up to 12 buckets. Missing slots (null address) are skipped.
    processAllocation(minter, deployer.address, clientAdmin, "JETTON_ALLOC_0_ADDRESS", "JETTON_ALLOC_0_NANO", "JETTON_ALLOC_0_VEST", "JETTON_ALLOC_0_VEST_START", "JETTON_ALLOC_0_VEST_DURATION");
    processAllocation(minter, deployer.address, clientAdmin, "JETTON_ALLOC_1_ADDRESS", "JETTON_ALLOC_1_NANO", "JETTON_ALLOC_1_VEST", "JETTON_ALLOC_1_VEST_START", "JETTON_ALLOC_1_VEST_DURATION");
    processAllocation(minter, deployer.address, clientAdmin, "JETTON_ALLOC_2_ADDRESS", "JETTON_ALLOC_2_NANO", "JETTON_ALLOC_2_VEST", "JETTON_ALLOC_2_VEST_START", "JETTON_ALLOC_2_VEST_DURATION");
    processAllocation(minter, deployer.address, clientAdmin, "JETTON_ALLOC_3_ADDRESS", "JETTON_ALLOC_3_NANO", "JETTON_ALLOC_3_VEST", "JETTON_ALLOC_3_VEST_START", "JETTON_ALLOC_3_VEST_DURATION");
    processAllocation(minter, deployer.address, clientAdmin, "JETTON_ALLOC_4_ADDRESS", "JETTON_ALLOC_4_NANO", "JETTON_ALLOC_4_VEST", "JETTON_ALLOC_4_VEST_START", "JETTON_ALLOC_4_VEST_DURATION");
    processAllocation(minter, deployer.address, clientAdmin, "JETTON_ALLOC_5_ADDRESS", "JETTON_ALLOC_5_NANO", "JETTON_ALLOC_5_VEST", "JETTON_ALLOC_5_VEST_START", "JETTON_ALLOC_5_VEST_DURATION");
    processAllocation(minter, deployer.address, clientAdmin, "JETTON_ALLOC_6_ADDRESS", "JETTON_ALLOC_6_NANO", "JETTON_ALLOC_6_VEST", "JETTON_ALLOC_6_VEST_START", "JETTON_ALLOC_6_VEST_DURATION");
    processAllocation(minter, deployer.address, clientAdmin, "JETTON_ALLOC_7_ADDRESS", "JETTON_ALLOC_7_NANO", "JETTON_ALLOC_7_VEST", "JETTON_ALLOC_7_VEST_START", "JETTON_ALLOC_7_VEST_DURATION");
    processAllocation(minter, deployer.address, clientAdmin, "JETTON_ALLOC_8_ADDRESS", "JETTON_ALLOC_8_NANO", "JETTON_ALLOC_8_VEST", "JETTON_ALLOC_8_VEST_START", "JETTON_ALLOC_8_VEST_DURATION");
    processAllocation(minter, deployer.address, clientAdmin, "JETTON_ALLOC_9_ADDRESS", "JETTON_ALLOC_9_NANO", "JETTON_ALLOC_9_VEST", "JETTON_ALLOC_9_VEST_START", "JETTON_ALLOC_9_VEST_DURATION");
    processAllocation(minter, deployer.address, clientAdmin, "JETTON_ALLOC_10_ADDRESS", "JETTON_ALLOC_10_NANO", "JETTON_ALLOC_10_VEST", "JETTON_ALLOC_10_VEST_START", "JETTON_ALLOC_10_VEST_DURATION");
    processAllocation(minter, deployer.address, clientAdmin, "JETTON_ALLOC_11_ADDRESS", "JETTON_ALLOC_11_NANO", "JETTON_ALLOC_11_VEST", "JETTON_ALLOC_11_VEST_START", "JETTON_ALLOC_11_VEST_DURATION");

    // Escrow: hand minter admin to the client (client claims).
    minter
        .sendChangeMinterAdmin(
            deployer.address,
            0,
            clientAdmin,
            { bounce: false, value: ton("0.05") },
        )
        .waitForTrace();
    println("TOOLKIT PENDING_ADMIN_CLAIM=true");
    println("TOOLKIT FINAL_ADMIN_ADDRESS={}", clientAdmin);

    printJettonMinterInfo(minter, "JETTON");
}
