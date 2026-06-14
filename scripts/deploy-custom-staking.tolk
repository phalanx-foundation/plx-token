import "@stdlib/strings"
import "@acton/env"
import "@acton/fmt"
import "@acton/io"
import "@acton/prompts"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@contracts/CustomStakingParams"
import "@wrappers/CustomStakingParams.gen"
import "@wrappers/utils"
import "utils/common"

/**
 * Non-interactive CustomStakingParams deploy.
 *
 * Env (required):
 *   DEPLOYER              — Acton wallet name
 *   CS_ADMIN              — Staking admin address
 *   CS_MINTER             — Staked jetton minter address
 *   CS_BASE_APR_BPS       — Base APR in basis points (e.g. 500 = 5%)
 *   CS_MIN_LOCK_SEC       — Minimum lock duration in seconds (0 = no min)
 */
fun main() {
    val deployer = promptJettonWallet("DEPLOYER", "Deployer wallet");
    val admin = promptJettonAddressRequired("CS_ADMIN", "Staking admin address");
    val minter = promptJettonAddressRequired("CS_MINTER", "Staked jetton minter address");
    val baseAprBpsRaw: coins = env<coins>("CS_BASE_APR_BPS") ?? 500;
    val baseAprBps: uint32 = baseAprBpsRaw as uint32;
    val minLockSecRaw: coins = env<coins>("CS_MIN_LOCK_SEC") ?? 0;
    val minLockSec: uint32 = minLockSecRaw as uint32;

    val emptyTier: BonusTier = { minAmount: 0, bonusBps: 0 };
    val cfg: CustomStakingConfig = {
        admin,
        minterAddress: minter,
        baseAprBps,
        minLockSec,
        tierCount: 0,
        tier0: emptyTier,
        tier1: emptyTier,
        tier2: emptyTier,
        tier3: emptyTier,
        tier4: emptyTier,
    };

    val storage: CustomStakingStorage = {
        config: cfg.toCell(),
        totalStaked: 0,
        rewardPerTokenStored: 0,
        lastUpdateTime: 0,
        rewardPool: 0,
        nextStakeId: 1,
        stakes: [],
    };

    val staking = CustomStakingParams.fromStorage(storage);
    val res = staking.sendDeploy(deployer.address, { value: ton("0.1") });
    res.waitForFirstTransaction();

    val (totalStaked, nextId, lastUpdate, pool, rewardPerToken) = staking.getStakingData();

    println("CUSTOM_STAKING CONTRACT_ADDRESS={}", staking.address);
    println("CUSTOM_STAKING ADMIN_ADDRESS={}", admin);
    println("CUSTOM_STAKING MINTER_ADDRESS={}", minter);
    println("CUSTOM_STAKING BASE_APR_BPS={}", baseAprBps);
    println("CUSTOM_STAKING MIN_LOCK_SEC={}", minLockSec);
    println("CUSTOM_STAKING TOTAL_STAKED={}", totalStaked);
    println("CUSTOM_STAKING REWARD_POOL={}", pool);
    println("CUSTOM_STAKING DEPLOY_TRACE={}", res.waitForTrace());
}
