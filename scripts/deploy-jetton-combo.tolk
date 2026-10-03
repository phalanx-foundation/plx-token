import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@stdlib/strings"
import "@contracts/antiwhale-types"
import "@contracts/errors"
import "@contracts/fee-types"
import "@contracts/jetton-utils"
import "@contracts/messages"
import "@contracts/PlxAirdrop"
import "@contracts/TokenStaking"
import "@wrappers/AntiWhaleJettonMinter.gen"
import "@wrappers/FeeJettonMinter.gen"
import "@wrappers/JettonMinter.gen"
import "@wrappers/PlxAirdrop.gen"
import "@wrappers/TokenStaking.gen"
import "@wrappers/utils"
import "utils/common"

/**
 * Non-interactive multi-template client deploy for the Phalanx Toolkit.
 *
 * Picked by toolkit-broadcast.sh when JETTON_TEMPLATE is one of the advanced
 * templates, so a buyer who paid for fee / antiwhale / staking / airdrop really
 * gets that contract on chain instead of a plain standard jetton.
 *
 * Env (required):
 *   JETTON_DEPLOYER          — Acton wallet name (pays gas, escrow admin when minting)
 *   JETTON_ADMIN_ADDRESS     — Client wallet (final minter admin)
 *   JETTON_INITIAL_RECIPIENT — Mint recipient (defaults to the client admin)
 *   JETTON_MINT_AMOUNT_NANO  — Initial mint in nano-jettons (0 = deploy-only)
 *   JETTON_TEMPLATE          — fee | antiwhale | staking | airdrop (anything else = standard)
 *   JETTON_NAME, JETTON_SYMBOL, JETTON_DESCRIPTION, JETTON_IMAGE, JETTON_DECIMALS
 *
 * Template env:
 *   fee:       JETTON_FEE_BPS (> 0, <= 1000), JETTON_FEE_COLLECTOR
 *   antiwhale: JETTON_MAX_TRANSFER (> 0), JETTON_MAX_WALLET_BALANCE (0 = disabled)
 *   staking:   JETTON_STAKING_APR_BPS, JETTON_STAKING_MIN_LOCK_SEC
 *   airdrop:   JETTON_AIRDROP_MERKLE_ROOT (required), JETTON_AIRDROP_DEADLINE
 *
 * Escrow: when a supply is minted, the deployer holds minter admin while minting
 * and then hands it to the client, who must claim. Marked with
 * `TOOLKIT PENDING_ADMIN_CLAIM=true` so the API can surface the claim step.
 *
 * stdout markers consumed by toolkit-broadcast.sh:
 *   TOOLKIT MINTER_ADDRESS, TOOLKIT PENDING_ADMIN_CLAIM, TOOLKIT COMPANION_CONTRACT
 */
fun main() {
    val deployer = promptJettonWallet("JETTON_DEPLOYER", "Toolkit deployer wallet");
    val clientAdmin = promptJettonAddressRequired("JETTON_ADMIN_ADDRESS", "Client admin address");
    val template: string = env<string>("JETTON_TEMPLATE") ?? "standard";
    val recipient = promptJettonAddress(
        "JETTON_INITIAL_RECIPIENT",
        "Initial mint recipient",
        clientAdmin,
    );
    val mintAmountNano = promptJettonCoins(
        "JETTON_MINT_AMOUNT_NANO",
        "Initial mint amount (nano-jettons)",
        "0",
    );
    val useEscrow = mintAmountNano > 0;

    println("TOOLKIT TEMPLATE={}", template);
    validateTemplateParams(template, mintAmountNano);

    if (template.equalTo("fee")) {
        deployFeeTemplate(deployer, clientAdmin, recipient, mintAmountNano, useEscrow);
        return;
    }
    if (template.equalTo("antiwhale")) {
        deployAntiWhaleTemplate(deployer, clientAdmin, recipient, mintAmountNano, useEscrow);
        return;
    }
    deployStandardTemplate(clientAdmin, deployer, recipient, mintAmountNano, useEscrow, template);
}

fun failClosed(message: string) {
    // Printed before throwing so the operator sees the reason in the deploy log
    // instead of a bare Acton exit code.
    println("TOOLKIT ERROR={}", message);
    throw Errors.InvalidOp;
}

/**
 * Rejects an unusable template configuration before the first on-chain write,
 * so a misconfigured order never leaves a half-deployed minter behind.
 */
fun validateTemplateParams(template: string, mintAmountNano: coins) {
    if (template.equalTo("fee")) {
        val feeBps: coins = env<coins>("JETTON_FEE_BPS") ?? 0;
        if (feeBps <= 0) {
            failClosed("fee template requires JETTON_FEE_BPS > 0");
        }
        if (feeBps > 1000) {
            failClosed("fee template requires JETTON_FEE_BPS <= 1000");
        }
        return;
    }
    if (template.equalTo("antiwhale")) {
        val maxTransfer: coins = env<coins>("JETTON_MAX_TRANSFER") ?? 0;
        val maxWallet: coins = env<coins>("JETTON_MAX_WALLET_BALANCE") ?? 0;
        if (maxTransfer <= 0) {
            failClosed("antiwhale template requires JETTON_MAX_TRANSFER > 0");
        }
        if (maxWallet > 0 && mintAmountNano > maxWallet) {
            failClosed("antiwhale initial mint exceeds JETTON_MAX_WALLET_BALANCE");
        }
        return;
    }
    if (template.equalTo("staking")) {
        val aprBps: coins = env<coins>("JETTON_STAKING_APR_BPS") ?? 500;
        if (aprBps < 0) {
            failClosed("staking template requires JETTON_STAKING_APR_BPS >= 0");
        }
        return;
    }
    if (template.equalTo("airdrop")) {
        val merkleRoot: int = env<int>("JETTON_AIRDROP_MERKLE_ROOT") ?? 0;
        if (merkleRoot == 0) {
            failClosed("airdrop template requires JETTON_AIRDROP_MERKLE_ROOT");
        }
        return;
    }
}

fun jettonMetadataCell(): cell {
    return buildJettonMetadataCell(promptJettonMetadata(JETTON_DEFAULT_DESCRIPTION));
}

/**
 * Fee-on-transfer template: the minter itself is FeeJettonMinter, which deploys
 * FeeJettonWallet instances that divert `feeBps` of every transfer to the
 * collector. A plain JettonMinter cannot do this, which is why this branch
 * deploys a different minter instead of reusing the standard one.
 */
fun deployFeeTemplate(
    deployer: ActonWallet,
    clientAdmin: address,
    recipient: address,
    mintAmountNano: coins,
    useEscrow: bool,
) {
    val feeBpsRaw: coins = env<coins>("JETTON_FEE_BPS") ?? 0;
    if (feeBpsRaw <= 0) {
        failClosed("fee template requires JETTON_FEE_BPS > 0");
    }
    if (feeBpsRaw > 1000) {
        failClosed("fee template requires JETTON_FEE_BPS <= 1000");
    }
    val feeBps: uint16 = feeBpsRaw as uint16;
    val collector: address = env<address>("JETTON_FEE_COLLECTOR") ?? clientAdmin;

    val adminForDeploy = useEscrow ? deployer.address : clientAdmin;
    val feeConfig: FeeMinterConfig = { feeBps, feeCollector: collector };
    val storage: FeeMinterStorage = {
        totalSupply: 0,
        adminAddress: adminForDeploy,
        nextAdminAddress: null,
        metadata: jettonMetadataCell(),
        feeConfig: feeConfig.toCell(),
    };

    val minter = FeeJettonMinter.fromStorage(storage);
    val deployRes = minter.sendDeploy(deployer.address, { value: ton("0.1") });
    deployRes.waitForFirstTransaction();
    println("TOOLKIT MINTER_ADDRESS={}", minter.address);
    println("TOOLKIT DEPLOY_TRACE={}", deployRes.waitForTrace());
    println("TOOLKIT FEE_BPS={}", feeBps);
    println("TOOLKIT FEE_COLLECTOR={}", collector);

    if (useEscrow) {
        minter
            .sendMint(deployer.address, recipient, mintAmountNano, ton("0.05"), ton("0.3"))
            .waitForTrace();
        // ChangeMinterAdmin is not generated on the legacy fee wrapper, so the
        // body is built by hand from the shared message definition.
        minter
            .sendAny(
                deployer.address,
                ChangeMinterAdmin { queryId: 0, newAdminAddress: clientAdmin }.toCell(),
                { bounce: false, value: ton("0.05") },
            )
            .waitForTrace();
        println("TOOLKIT PENDING_ADMIN_CLAIM=true");
    }

    val (deployedBps, deployedCollector) = minter.getFeeConfig();
    println("TOOLKIT FEE DEPLOYED_BPS={}", deployedBps);
    println("TOOLKIT FEE DEPLOYED_COLLECTOR={}", deployedCollector);
    println("TOOLKIT JETTON_WALLET_ADDRESS={}", minter.getWalletAddress(recipient));
}

/**
 * Anti-whale template: the minter is AntiWhaleJettonMinter, so every wallet it
 * creates enforces the per-transfer and per-wallet caps that the buyer picked.
 */
fun deployAntiWhaleTemplate(
    deployer: ActonWallet,
    clientAdmin: address,
    recipient: address,
    mintAmountNano: coins,
    useEscrow: bool,
) {
    val maxTransfer: coins = env<coins>("JETTON_MAX_TRANSFER") ?? 0;
    if (maxTransfer <= 0) {
        failClosed("antiwhale template requires JETTON_MAX_TRANSFER > 0");
    }
    val maxWallet: coins = env<coins>("JETTON_MAX_WALLET_BALANCE") ?? 0;
    if (maxWallet > 0 && mintAmountNano > maxWallet) {
        failClosed("antiwhale initial mint exceeds JETTON_MAX_WALLET_BALANCE");
    }

    val whaleConfig: WhaleConfig = {
        maxTransferAmount: maxTransfer,
        maxWalletBalance: maxWallet,
    };
    val adminForDeploy = useEscrow ? deployer.address : clientAdmin;
    val storage: AntiWhaleMinterStorage = {
        totalSupply: 0,
        adminAddress: adminForDeploy,
        nextAdminAddress: null,
        metadata: jettonMetadataCell(),
        whaleConfig: whaleConfig.toCell(),
    };

    val minter = AntiWhaleJettonMinter.fromStorage(storage);
    val deployRes = minter.deploy(deployer.address, { value: ton("0.1") });
    deployRes.waitForFirstTransaction();
    println("TOOLKIT MINTER_ADDRESS={}", minter.address);
    println("TOOLKIT DEPLOY_TRACE={}", deployRes.waitForTrace());
    println("TOOLKIT ANTI_WHALE MAX_TRANSFER={}", maxTransfer);
    println("TOOLKIT ANTI_WHALE MAX_WALLET_BALANCE={}", maxWallet);

    if (useEscrow) {
        val transferBody: InternalTransferStep = {
            queryId: 0,
            jettonAmount: mintAmountNano,
            transferInitiator: null,
            sendExcessesTo: deployer.address,
            forwardTonAmount: 0,
            forwardPayload: jettonEmptyForwardPayload(),
        };
        minter
            .sendMintNewJettons(
                deployer.address,
                0,
                recipient,
                ton("0.05"),
                transferBody,
                { value: ton("0.3") },
            )
            .waitForTrace();
        minter
            .sendChangeMinterAdmin(
                deployer.address,
                0,
                clientAdmin,
                { bounce: false, value: ton("0.05") },
            )
            .waitForTrace();
        println("TOOLKIT PENDING_ADMIN_CLAIM=true");
    }

    val whaleWalletAddress = minter.getWalletAddress(recipient);
    println("TOOLKIT ANTI_WHALE WALLET_ADDRESS={}", whaleWalletAddress);
    println("TOOLKIT JETTON_WALLET_ADDRESS={}", whaleWalletAddress);
}

/**
 * Standard minting minter, plus the companion contract a staking or airdrop
 * template needs. Staking is funded later by sending jettons to the vault; the
 * airdrop contract instead receives the initial mint directly, because claims
 * transfer jettons out of its own jetton wallet.
 */
fun deployStandardTemplate(
    clientAdmin: address,
    deployer: ActonWallet,
    recipient: address,
    mintAmountNano: coins,
    useEscrow: bool,
    template: string,
) {
    val adminForDeploy = useEscrow ? deployer.address : clientAdmin;
    val storage = promptJettonMinterStorage(adminForDeploy);
    val minter = JettonMinter.fromStorage(storage);

    // Airdrop claims pay out of the airdrop contract's own jetton wallet, so the
    // initial supply has to land there. Minting to the owner's wallet instead
    // left every claim unfunded until someone topped the contract up by hand.
    val airdropAddress = template.equalTo("airdrop")
        ? PlxAirdrop.fromStorage(buildAirdropStorage(clientAdmin, minter.address)).address
        : null;
    val mintRecipient = airdropAddress ?? recipient;

    val deployRes = minter.sendDeploy(deployer.address, { value: ton("0.1") });
    deployRes.waitForFirstTransaction();
    println("TOOLKIT MINTER_ADDRESS={}", minter.address);
    println("TOOLKIT DEPLOY_TRACE={}", deployRes.waitForTrace());

    if (useEscrow) {
        println("TOOLKIT MINT_RECIPIENT={}", mintRecipient);
        minter
            .sendMint(deployer.address, mintRecipient, mintAmountNano, ton("0.05"), ton("0.3"))
            .waitForTrace();
        minter
            .sendChangeMinterAdmin(
                deployer.address,
                0,
                clientAdmin,
                { bounce: false, value: ton("0.05") },
            )
            .waitForTrace();
        println("TOOLKIT PENDING_ADMIN_CLAIM=true");
    }

    if (template.equalTo("staking")) {
        deployStakingCompanion(deployer, clientAdmin, minter.address);
    }
    if (template.equalTo("airdrop")) {
        deployAirdropCompanion(deployer, clientAdmin, minter.address);
    }

    printJettonMinterInfo(minter, "JETTON");
    printJettonWalletInfo(minter, mintRecipient, "JETTON_RECIPIENT");
}

fun deployStakingCompanion(deployer: ActonWallet, clientAdmin: address, minterAddress: address) {
    val aprBpsRaw: coins = env<coins>("JETTON_STAKING_APR_BPS") ?? 500;
    if (aprBpsRaw < 0) {
        failClosed("staking template requires JETTON_STAKING_APR_BPS >= 0");
    }
    val aprBps: uint32 = aprBpsRaw as uint32;
    val minLockSecRaw: coins = env<coins>("JETTON_STAKING_MIN_LOCK_SEC") ?? 86400;
    val minLockSec: uint32 = minLockSecRaw as uint32;

    val stakingConfig: StakingConfig = {
        admin: clientAdmin,
        minterAddress,
        aprBps,
        minLockSec,
    };
    val stakingStorage: StakingStorage = {
        config: stakingConfig.toCell(),
        totalStaked: 0,
        rewardPerTokenStored: 0,
        lastUpdateTime: 0,
        rewardPool: 0,
        nextStakeId: 1,
        stakes: [],
    };

    val staking = TokenStaking.fromStorage(stakingStorage);
    staking.sendDeploy(deployer.address, { value: ton("0.15") }).waitForFirstTransaction();
    println("TOOLKIT STAKING_CONTRACT={}", staking.address);
    println("TOOLKIT STAKING APR_BPS={}", aprBps);
    println("TOOLKIT STAKING MIN_LOCK_SEC={}", minLockSec);
    println("TOOLKIT COMPANION_CONTRACT={}", staking.address);
}

/**
 * Single source of truth for the airdrop storage, so the address computed for
 * the initial mint is exactly the contract deployed afterwards.
 */
fun buildAirdropStorage(clientAdmin: address, minterAddress: address): AirdropStorage {
    val merkleRootRaw: int = env<int>("JETTON_AIRDROP_MERKLE_ROOT") ?? 0;
    if (merkleRootRaw == 0) {
        failClosed("airdrop template requires JETTON_AIRDROP_MERKLE_ROOT");
    }
    val merkleRoot: uint256 = merkleRootRaw as uint256;
    val deadlineRaw: coins = env<coins>("JETTON_AIRDROP_DEADLINE") ?? 0;
    val deadline: uint32 = deadlineRaw as uint32;

    return {
        merkleRoot,
        jettonMinter: minterAddress,
        admin: clientAdmin,
        deadline,
        claimedMap: [],
    };
}

fun deployAirdropCompanion(deployer: ActonWallet, clientAdmin: address, minterAddress: address) {
    val storage = buildAirdropStorage(clientAdmin, minterAddress);

    val airdrop = PlxAirdrop.fromStorage(storage);
    airdrop.sendDeploy(deployer.address, { value: ton("0.15") }).waitForFirstTransaction();
    println("TOOLKIT AIRDROP_CONTRACT={}", airdrop.address);
    println("TOOLKIT AIRDROP JETTON_WALLET={}", airdrop.getJettonWallet());
    println("TOOLKIT AIRDROP MERKLE_ROOT={}", storage.merkleRoot);
    println("TOOLKIT AIRDROP DEADLINE={}", storage.deadline);
    println("TOOLKIT COMPANION_CONTRACT={}", airdrop.address);
}
