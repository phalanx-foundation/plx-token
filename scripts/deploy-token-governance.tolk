import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@contracts/TokenGovernance"
import "@wrappers/TokenGovernance.gen"
import "utils/common"

/**
 * Non-interactive TokenGovernance deploy (vote-escrow DAO governance).
 *
 * Holders stake the governance jetton to earn voting power. Creating a proposal
 * requires the admin or a holder with staked balance >= GV_PROPOSAL_THRESHOLD.
 * Quorum is measured against the snapshot of total staked at proposal creation.
 * Votes are weighted by staked balance, and a voter's stake is locked until the
 * proposal's voting period ends.
 *
 * Env (required):
 *   DEPLOYER              — Acton wallet name
 *   GV_ADMIN              — Governance admin address
 *   GV_MINTER             — Governance (staked) jetton minter address
 * Env (optional):
 *   GV_PROPOSAL_THRESHOLD — Minimum staked balance to create a proposal (nano, default 1_000_000_000_000 = 1000 tokens @ 9 decimals)
 *   GV_QUORUM_BPS         — Quorum in basis points (default 5000 = 50%)
 *   GV_VOTING_PERIOD_SEC  — Voting period in seconds (default 604800 = 7 days)
 *   GV_TIMELOCK_SEC       — Timelock in seconds (default 86400 = 1 day)
 */
fun main() {
    val deployer = promptJettonWallet("DEPLOYER", "Deployer wallet");
    val admin = promptJettonAddressRequired("GV_ADMIN", "Governance admin address");
    val minter = promptJettonAddressRequired(
        "GV_MINTER",
        "Governance (staked) jetton minter address",
    );

    val proposalThresholdRaw = env<int>("GV_PROPOSAL_THRESHOLD") ?? 1000000000000;
    val proposalThreshold: coins = proposalThresholdRaw;
    val quorumBpsRaw = env<int>("GV_QUORUM_BPS") ?? 5000;
    val quorumBps: uint16 = quorumBpsRaw as uint16;
    val votingPeriodSecRaw = env<int>("GV_VOTING_PERIOD_SEC") ?? 604800;
    val votingPeriodSec: uint32 = votingPeriodSecRaw as uint32;
    val timelockSecRaw = env<int>("GV_TIMELOCK_SEC") ?? 86400;
    val timelockSec: uint32 = timelockSecRaw as uint32;

    val config: GovernanceConfig = {
        admin,
        minterAddress: minter,
        proposalThreshold,
        quorumBps,
        votingPeriodSec,
        timelockSec,
    };

    println("Deploying TokenGovernance (vote-escrow DAO)...");
    println("  admin             = {}", admin);
    println("  minter            = {}", minter);
    println("  proposalThreshold = {}", proposalThreshold);
    println("  quorumBps         = {}", quorumBps);
    println("  votingPeriodSec   = {}", votingPeriodSec);
    println("  timelockSec       = {}", timelockSec);

    val gov = TokenGovernance.fromStorage({
        config: config.toCell(),
        nextProposalId: 0,
        proposals: [],
        votes: [],
        stakes: [],
        totalStaked: 0,
    });

    gov.deploy(deployer.address, { value: ton("0.1") });

    println("---");
    println("TokenGovernance deployed at: {}", gov.address);
    println("TOKEN_GOVERNANCE CONTRACT_ADDRESS={}", gov.address);
    println("TOKEN_GOVERNANCE ADMIN_ADDRESS={}", admin);
    println("TOKEN_GOVERNANCE MINTER_ADDRESS={}", minter);
    println("TOKEN_GOVERNANCE PROPOSAL_THRESHOLD={}", proposalThreshold);
    println("TOKEN_GOVERNANCE QUORUM_BPS={}", quorumBps);
    println("TOKEN_GOVERNANCE VOTING_PERIOD_SEC={}", votingPeriodSec);
    println("TOKEN_GOVERNANCE TIMELOCK_SEC={}", timelockSec);
    println("TOKEN_GOVERNANCE TOTAL_STAKED={}", gov.getTotalStaked());
    println("---");
    println("1. Holders stake jettons (forward op 0x474f5653) to earn voting power.");
    println("2. The admin, or a staked holder above the threshold, creates a proposal.");
    println("3. Voters cast weighted votes; stake is locked until the voting period ends.");
    println("4. Any caller executes a passed proposal after the voting period + timelock.");
}
