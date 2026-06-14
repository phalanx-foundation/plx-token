import "@gen/JettonWallet.code"
import "errors"
import "jetton-utils"
import "messages"

contract PlxAirdrop {
    author: "Phalanx Foundation"
    version: "1.0.0"
    description: "Merkle-based airdrop contract. Claimants submit a merkle proof; the contract verifies it, marks the address as claimed, and transfers jettons."
    storage: AirdropStorage
    incomingMessages: AllowedMessageToAirdrop
}

struct AirdropStorage {
    merkleRoot: uint256
    jettonMinter: address
    admin: address
    deadline: uint32
    claimedMap: map<uint256, bool>
}

/// Claim airdrop by providing merkle proof.
/// proof cell: a chain of uint256 hashes (3 per cell, continued in refs).
/// leaf = hash(claimantAddress ++ amount)
struct (0xA1BD0001) Claim {
    queryId: uint64
    amount: coins
    proof: cell
}

/// Admin: update the merkle root (e.g. for a new airdrop round).
struct (0xA1BD0002) SetMerkleRoot {
    queryId: uint64
    merkleRoot: uint256
}

/// Admin: withdraw unclaimed jettons to admin address after deadline.
struct (0xA1BD0003) WithdrawUnclaimed {
    queryId: uint64
    amount: coins
}

/// Admin: set the claim deadline timestamp.
struct (0xA1BD0004) SetDeadline {
    queryId: uint64
    deadline: uint32
}

type AllowedMessageToAirdrop =
    | Claim
    | SetMerkleRoot
    | WithdrawUnclaimed
    | SetDeadline
    | TopUpTons

const AIRDROP_TRANSFER_TON_VALUE: coins = 80000000

fun AirdropStorage.load(): AirdropStorage {
    return AirdropStorage.fromCell(contract.getData());
}

fun AirdropStorage.save(self) {
    contract.setData(self.toCell());
}

fun airdropOwnJettonWallet(jettonMinter: address): address {
    val walletCode = jettonWalletCompiledCode();
    return calcAddressOfJettonWallet(contract.getAddress(), jettonMinter, walletCode);
}

/// Hash two uint256 values together: hash(min(a,b) || max(a,b)).
/// Canonical ordering ensures proof order doesn't matter.
fun hashMerklePair(a: uint256, b: uint256): uint256 {
    if (a <= b) {
        return beginCell().storeUint(a, 256).storeUint(b, 256).endCell().hash();
    }
    return beginCell().storeUint(b, 256).storeUint(a, 256).endCell().hash();
}

/// Compute leaf hash: sha256-equivalent of cell containing (address || amount).
fun computeLeaf(claimant: address, amount: coins): uint256 {
    return beginCell().storeAddress(claimant).storeCoins(amount).endCell().hash();
}

/// Parse and verify a merkle proof against the expected root.
/// Proof encoding: each cell holds up to 3 uint256 values (768 bits),
/// with additional items chained via cell refs.
fun verifyMerkleProof(root: uint256, leaf: uint256, proofCell: cell): bool {
    var current = leaf;
    var s = proofCell.beginParse();

    var continueLoop = true;
    while (continueLoop) {
        // Consume all 256-bit values from current slice
        while (s.remainingBitsCount() >= 256) {
            val sibling = s.loadUint(256);
            current = hashMerklePair(current, sibling);
        }
        // Follow ref chain if available
        if (s.remainingRefsCount() > 0) {
            s = s.loadRef().beginParse();
        } else {
            continueLoop = false;
        }
    }

    return current == root;
}

/// Unique key for the claimed dict: hash of the serialized address.
fun addressToClaimKey(addr: address): uint256 {
    return beginCell().storeAddress(addr).endCell().hash();
}

fun onBouncedMessage(in: InMessageBounced) {
    // No state to restore on bounced jetton transfers
}

fun onInternalMessage(in: InMessage) {
    if (in.body.remainingBitsCount() == 0 && in.body.remainingRefsCount() == 0) {
        return;
    }

    val msg = lazy AllowedMessageToAirdrop.fromSlice(in.body);

    match (msg) {
        Claim => {
            var storage = lazy AirdropStorage.load();

            // Reject after deadline
            assert (storage.deadline == 0 || blockchain.now() <= storage.deadline) throw Errors.InvalidOp;

            val claimant = in.senderAddress;
            val claimKey = addressToClaimKey(claimant);

            // Check not already claimed
            val claimedEntry = storage.claimedMap.get(claimKey);
            assert (!claimedEntry.isFound) throw Errors.InvalidOp;

            // Verify merkle proof
            val leaf = computeLeaf(claimant, msg.amount);
            assert (verifyMerkleProof(storage.merkleRoot, leaf, msg.proof)) throw Errors.InvalidOp;

            // Mark as claimed
            storage.claimedMap.set(claimKey, true);
            storage.save();

            // Transfer jettons to claimant
            val transferMsg = createMessage({
                bounce: BounceMode.Only256BitsOfBody,
                dest: airdropOwnJettonWallet(storage.jettonMinter),
                value: AIRDROP_TRANSFER_TON_VALUE,
                body: AskToTransfer {
                    queryId: msg.queryId,
                    jettonAmount: msg.amount,
                    transferRecipient: claimant,
                    sendExcessesTo: claimant,
                    customPayload: null,
                    forwardTonAmount: 0,
                    forwardPayload: jettonEmptyForwardPayload(),
                },
            });
            transferMsg.send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_BOUNCE_ON_ACTION_FAIL);
        }

        SetMerkleRoot => {
            var storage = lazy AirdropStorage.load();
            assert (in.senderAddress == storage.admin) throw Errors.NotOwner;
            storage.merkleRoot = msg.merkleRoot;
            storage.save();
        }

        WithdrawUnclaimed => {
            val storage = lazy AirdropStorage.load();
            assert (in.senderAddress == storage.admin) throw Errors.NotOwner;
            // Can only withdraw after deadline has passed
            assert (storage.deadline != 0 && blockchain.now() > storage.deadline) throw Errors.NothingToClaim;

            val transferMsg = createMessage({
                bounce: BounceMode.Only256BitsOfBody,
                dest: airdropOwnJettonWallet(storage.jettonMinter),
                value: AIRDROP_TRANSFER_TON_VALUE,
                body: AskToTransfer {
                    queryId: msg.queryId,
                    jettonAmount: msg.amount,
                    transferRecipient: storage.admin,
                    sendExcessesTo: storage.admin,
                    customPayload: null,
                    forwardTonAmount: 0,
                    forwardPayload: jettonEmptyForwardPayload(),
                },
            });
            transferMsg.send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_BOUNCE_ON_ACTION_FAIL);
        }

        SetDeadline => {
            var storage = lazy AirdropStorage.load();
            assert (in.senderAddress == storage.admin) throw Errors.NotOwner;
            storage.deadline = msg.deadline;
            storage.save();
        }

        TopUpTons => {}

        else => throw 0xFFFF,
    }
}

get fun get_airdrop_data(): (uint256, address, address, uint32) {
    val storage = AirdropStorage.load();
    return (storage.merkleRoot, storage.jettonMinter, storage.admin, storage.deadline);
}


get fun is_claimed(claimant: address): bool {
    val storage = AirdropStorage.load();
    val entry = storage.claimedMap.get(addressToClaimKey(claimant));
    return entry.isFound;
}

get fun get_jetton_wallet(): address {
    val storage = AirdropStorage.load();
    return airdropOwnJettonWallet(storage.jettonMinter);
}
