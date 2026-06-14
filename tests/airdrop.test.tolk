import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"

import "@contracts/PlxAirdrop"
import "@contracts/errors"
import "@contracts/messages"
import "@contracts/storage"
import "@wrappers/JettonMinter.gen"
import "@wrappers/JettonWallet.gen"
import "@wrappers/PlxAirdrop.gen"
import "@wrappers/utils"

import "test-utils"

const AIRDROP_UNIT = 1000000000
const AIRDROP_AMOUNT = 100 * AIRDROP_UNIT

/// Build a minimal 1-leaf merkle tree (proof is empty, root == leaf hash).
fun buildSingleLeafRoot(claimant: address, amount: coins): uint256 {
    return beginCell().storeAddress(claimant).storeCoins(amount).endCell().hash();
}

/// Build an empty proof cell (for a single-leaf tree).
fun emptyProof(): cell {
    return beginCell().endCell();
}

/// Build a 2-leaf tree and return (root, proof for leaf0).
/// leaf0 = hash(addr0 || amount0), leaf1 = hash(addr1 || amount1)
/// root = hash(min(leaf0, leaf1) || max(leaf0, leaf1))
fun buildTwoLeafTree(addr0: address, amount0: coins, addr1: address, amount1: coins): (uint256, cell) {
    val leaf0 = beginCell().storeAddress(addr0).storeCoins(amount0).endCell().hash();
    val leaf1 = beginCell().storeAddress(addr1).storeCoins(amount1).endCell().hash();
    var root: uint256;
    if (leaf0 <= leaf1) {
        root = beginCell().storeUint(leaf0, 256).storeUint(leaf1, 256).endCell().hash();
    } else {
        root = beginCell().storeUint(leaf1, 256).storeUint(leaf0, 256).endCell().hash();
    }
    // Proof for leaf0 is just leaf1
    val proof = beginCell().storeUint(leaf1, 256).endCell();
    return (root, proof);
}

fun setupAirdrop(merkleRoot: uint256, deadline: uint32 = 0): (JettonMinter, PlxAirdrop, Treasury, Treasury) {
    val deployer = testing.treasury("airdrop-deployer");
    val admin = testing.treasury("airdrop-admin");

    val minter = JettonMinter.fromStorage({
        totalSupply: 0,
        adminAddress: deployer.address,
        nextAdminAddress: null,
        metadata: buildTestMetadata("airdrop-plx-test"),
    });
    expect(minter.sendDeploy(deployer.address, { value: ton("10") })).toHaveSuccessfulDeploy({
        to: minter.address,
    });

    val airdropContract = PlxAirdrop.fromStorage({
        merkleRoot,
        jettonMinter: minter.address,
        admin: admin.address,
        deadline,
        claimedMap: [],
    });
    expect(airdropContract.sendDeploy(admin.address, { value: ton("5") })).toHaveSuccessfulDeploy({
        to: airdropContract.address,
    });

    // Fund the airdrop contract with jettons
    expect(
        minter.sendMint(deployer.address, airdropContract.address, AIRDROP_AMOUNT * 100, ton("0.05"), ton("0.5")),
    ).toHaveSuccessfulTx<MintNewJettons>({ from: deployer.address, to: minter.address });

    return (minter, airdropContract, deployer, admin);
}

get fun `test airdrop: deploy and jetton wallet configured correctly`() {
    val claimant = testing.treasury("airdrop-claimant-check");
    val root = buildSingleLeafRoot(claimant.address, AIRDROP_AMOUNT);
    val (minter, airdrop, _, admin) = setupAirdrop(root);

    val (storedRoot, storedMinter, storedAdmin, storedDeadline) = airdrop.getAirdropData();
    expect(storedRoot).toEqual(root);
    expect(storedMinter).toEqual(minter.address);
    expect(storedAdmin).toEqual(admin.address);
    expect(storedDeadline).toEqual(0);
}

get fun `test airdrop: valid claim with single-leaf tree succeeds`() {
    val claimant = testing.treasury("airdrop-claimant1");
    val root = buildSingleLeafRoot(claimant.address, AIRDROP_AMOUNT);
    val (minter, airdrop, _, _) = setupAirdrop(root);

    expect(airdrop.isClaimed(claimant.address)).toEqual(false);

    val res = airdrop.sendClaim(
        claimant.address, 0, AIRDROP_AMOUNT, emptyProof(), { bounce: false, value: ton("0.3") },
    );
    expect(res).toHaveSuccessfulTx<Claim>({ from: claimant.address, to: airdrop.address });

    expect(airdrop.isClaimed(claimant.address)).toEqual(true);
}

get fun `test airdrop: duplicate claim is rejected`() {
    val claimant = testing.treasury("airdrop-claimant2");
    val root = buildSingleLeafRoot(claimant.address, AIRDROP_AMOUNT);
    val (_, airdrop, _, _) = setupAirdrop(root);

    airdrop.sendClaim(claimant.address, 0, AIRDROP_AMOUNT, emptyProof(), { bounce: false, value: ton("0.3") });

    val res = airdrop.sendClaim(
        claimant.address, 1, AIRDROP_AMOUNT, emptyProof(), { bounce: false, value: ton("0.3") },
    );
    expect(res).toHaveFailedTx<Claim>({
        from: claimant.address,
        to: airdrop.address,
        exitCode: Errors.InvalidOp,
    });
}

get fun `test airdrop: invalid proof is rejected`() {
    val claimant = testing.treasury("airdrop-claimant3");
    val root = buildSingleLeafRoot(claimant.address, AIRDROP_AMOUNT);
    val (_, airdrop, _, _) = setupAirdrop(root);

    // Submit with wrong amount (will produce different leaf hash)
    val wrongAmount = AIRDROP_AMOUNT + 1;
    val res = airdrop.sendClaim(
        claimant.address, 0, wrongAmount, emptyProof(), { bounce: false, value: ton("0.3") },
    );
    expect(res).toHaveFailedTx<Claim>({
        from: claimant.address,
        to: airdrop.address,
        exitCode: Errors.InvalidOp,
    });

    expect(airdrop.isClaimed(claimant.address)).toEqual(false);
}

get fun `test airdrop: claim after deadline is rejected`() {
    val claimant = testing.treasury("airdrop-claimant4");
    val root = buildSingleLeafRoot(claimant.address, AIRDROP_AMOUNT);

    testing.setNow(1700000000);
    val deadline: uint32 = 1700003600;  // 1 hour from now
    val (_, airdrop, _, _) = setupAirdrop(root, deadline);

    // Advance time past deadline
    testing.setNow(1700003601);

    val res = airdrop.sendClaim(
        claimant.address, 0, AIRDROP_AMOUNT, emptyProof(), { bounce: false, value: ton("0.3") },
    );
    expect(res).toHaveFailedTx<Claim>({
        from: claimant.address,
        to: airdrop.address,
        exitCode: Errors.InvalidOp,
    });
}

get fun `test airdrop: valid claim with 2-leaf tree succeeds`() {
    val claimant0 = testing.treasury("airdrop-c0");
    val claimant1 = testing.treasury("airdrop-c1");

    val (root, proof0) = buildTwoLeafTree(
        claimant0.address, AIRDROP_AMOUNT,
        claimant1.address, AIRDROP_AMOUNT,
    );
    val (_, airdrop, _, _) = setupAirdrop(root);

    val res = airdrop.sendClaim(
        claimant0.address, 0, AIRDROP_AMOUNT, proof0, { bounce: false, value: ton("0.3") },
    );
    expect(res).toHaveSuccessfulTx<Claim>({ from: claimant0.address, to: airdrop.address });
    expect(airdrop.isClaimed(claimant0.address)).toEqual(true);
}

get fun `test airdrop: admin can set new merkle root`() {
    val claimant = testing.treasury("airdrop-c-root");
    val root = buildSingleLeafRoot(claimant.address, AIRDROP_AMOUNT);
    val (_, airdrop, _, admin) = setupAirdrop(root);

    val newRoot: uint256 = 0xDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEF;
    val res = airdrop.sendSetMerkleRoot(
        admin.address, 0, newRoot, { bounce: false, value: ton("0.05") },
    );
    expect(res).toHaveSuccessfulTx<SetMerkleRoot>({ from: admin.address, to: airdrop.address });

    val (storedRoot, _, _, _) = airdrop.getAirdropData();
    expect(storedRoot).toEqual(newRoot);
}

get fun `test airdrop: non-admin cannot set merkle root`() {
    val claimant = testing.treasury("airdrop-c-root2");
    val root = buildSingleLeafRoot(claimant.address, AIRDROP_AMOUNT);
    val (_, airdrop, _, _) = setupAirdrop(root);

    val newRoot: uint256 = 0x1234;
    val res = airdrop.sendSetMerkleRoot(
        claimant.address, 0, newRoot, { bounce: false, value: ton("0.05") },
    );
    expect(res).toHaveFailedTx<SetMerkleRoot>({
        from: claimant.address,
        to: airdrop.address,
        exitCode: Errors.NotOwner,
    });
}

get fun `test airdrop: admin can set deadline`() {
    val claimant = testing.treasury("airdrop-deadline");
    val root = buildSingleLeafRoot(claimant.address, AIRDROP_AMOUNT);
    val (_, airdrop, _, admin) = setupAirdrop(root);

    val newDeadline: uint32 = 1800000000;
    val res = airdrop.sendSetDeadline(
        admin.address, 0, newDeadline, { bounce: false, value: ton("0.05") },
    );
    expect(res).toHaveSuccessfulTx<SetDeadline>({ from: admin.address, to: airdrop.address });

    val (_, _, _, storedDeadline) = airdrop.getAirdropData();
    expect(storedDeadline).toEqual(newDeadline);
}

get fun `test airdrop: WithdrawUnclaimed blocked before deadline`() {
    testing.setNow(1700000000);
    val claimant = testing.treasury("airdrop-wd");
    val root = buildSingleLeafRoot(claimant.address, AIRDROP_AMOUNT);
    val (_, airdrop, _, admin) = setupAirdrop(root, 1800000000);

    val res = airdrop.sendWithdrawUnclaimed(
        admin.address, 0, AIRDROP_AMOUNT, { bounce: false, value: ton("0.2") },
    );
    expect(res).toHaveFailedTx<WithdrawUnclaimed>({
        from: admin.address,
        to: airdrop.address,
        exitCode: Errors.NothingToClaim,
    });
}
