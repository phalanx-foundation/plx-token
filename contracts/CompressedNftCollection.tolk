import "@stdlib/gas-payments"
import "errors"
import "sharding"
import "nft-messages"
import "nft-storage"

contract CompressedNftCollection {
    author: "Phalanx Foundation"
    version: "1.0.0"
    description: "Compressed NFT Collection. TEP #126 compliant (Merkle-proof self-deployment)"
    storage: CompressedNftCollectionStorage
    incomingMessages: AllowedCompressedCollectionMessage
}

type AllowedCompressedCollectionMessage =
    | DeployItemWithProof
    | SetMerkleRoot
    | ChangeCollectionOwner
    | ChangeCollectionContent
    | GetRoyaltyParams
    | TopUpTons

const _TREE_DEPTH: int = 8;

fun hashPair(left: uint256, right: uint256): uint256 {
    // Same idiom as PlxAirdrop: cell.hash() (no @stdlib/hash)
    return beginCell().storeUint(left, 256).storeUint(right, 256).endCell().hash();
}

fun hashLeaf(itemIndex: int, owner: address): uint256 {
    return beginCell().storeUint(itemIndex, 64).storeAddress(owner).endCell().hash();
}

// Verify Merkle proof from a cell containing 8 sibling hashes
fun verifyMerkleProof(
    leafHash: uint256,
    proofCell: cell,
    itemIndex: int,
    root: uint256,
): bool {
    var currentHash = leafHash;
    var index = itemIndex;
    var proofSlice = proofCell.beginParse();
    var depth = 0;

    while (depth < _TREE_DEPTH) {
        val sibling = proofSlice.loadUint(256);
        if ((index & 1) == 0) {
            currentHash = hashPair(currentHash, sibling);
        } else {
            currentHash = hashPair(sibling, currentHash);
        }
        index >>= 1;
        depth += 1;
    }

    return currentHash == root;
}

fun assertSenderIsOwner(senderAddress: address, ownerAddress: address) {
    assert (senderAddress == ownerAddress) throw 73;
}

fun emptyBodySlice(): slice {
    return beginCell().toSlice();
}

// Acton 1.1: createMessage embeds StateInit when dest is AutoDeployAddress
fun calcDeployedNftItem(
    index: int,
    owner: address,
    individualContent: cell,
    nftItemCode: cell,
): AutoDeployAddress {
    val nftInitData = beginCell()
        .storeBool(true)
        .storeUint(index, 64)
        .storeAddress(contract.getAddress())
        .storeAddress(owner)
        .storeRef(individualContent)
        .endCell();

    return {
        workchain: MY_WORKCHAIN,
        stateInit: { code: nftItemCode, data: nftInitData },
    };
}

fun calculateNftItemAddress(
    index: int,
    nftItemCode: cell,
): address {
    return calcDeployedNftItem(
        index,
        contract.getAddress(),
        beginCell().endCell(),
        nftItemCode,
    ).calculateAddress();
}

fun onInternalMessage(in: InMessage) {
    val msg = lazy AllowedCompressedCollectionMessage.fromSlice(in.body);

    match (msg) {
        DeployItemWithProof => {
            var storage = lazy CompressedNftCollectionStorage.load();

            assert (storage.nextItemIndex < storage.maxSupply) throw 103; // Max supply reached

            val proofMsg = msg as DeployItemWithProof;
            val leafHash = hashLeaf(proofMsg.itemIndex, proofMsg.claimant);

            assert (
                verifyMerkleProof(leafHash, proofMsg.proofCell, proofMsg.itemIndex, storage.merkleRoot)
            ) throw 104; // Invalid Merkle proof

            val deployMsg = createMessage({
                bounce: BounceMode.Only256BitsOfBody,
                dest: calcDeployedNftItem(
                    proofMsg.itemIndex,
                    proofMsg.claimant,
                    proofMsg.individualContent,
                    storage.nftItemCode,
                ),
                value: ton("0.05"),
                body: emptyBodySlice(),
            });
            deployMsg.send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_BOUNCE_ON_ACTION_FAIL);

            storage.nextItemIndex += 1;
            storage.save();
        }

        SetMerkleRoot => {
            var storage = lazy CompressedNftCollectionStorage.load();
            assertSenderIsOwner(in.senderAddress, storage.ownerAddress);

            val rootMsg = msg as SetMerkleRoot;
            storage.merkleRoot = rootMsg.newRoot;
            storage.maxSupply = rootMsg.maxSupply;
            storage.save();
        }

        ChangeCollectionOwner => {
            var storage = lazy CompressedNftCollectionStorage.load();
            assertSenderIsOwner(in.senderAddress, storage.ownerAddress);
            storage.ownerAddress = msg.newOwner;
            storage.save();
        }

        ChangeCollectionContent => {
            var storage = lazy CompressedNftCollectionStorage.load();
            assertSenderIsOwner(in.senderAddress, storage.ownerAddress);
            storage.collectionContent = msg.newContent;
            storage.save();
        }

        GetRoyaltyParams => {
            val storage = lazy CompressedNftCollectionStorage.load();

            val responseMsg = createMessage({
                bounce: BounceMode.NoBounce,
                dest: in.senderAddress,
                value: 0,
                body: ReportRoyaltyParams {
                    queryId: msg.queryId,
                    numerator: storage.royaltyFactor,
                    denominator: storage.royaltyBase,
                    destination: storage.royaltyAddress,
                },
            });
            responseMsg.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE | SEND_MODE_IGNORE_ERRORS);
        }

        TopUpTons => {
            // accept tons
        }

        else => throw 0xFFFF,
    }
}

get fun get_collection_data(): CompressedCollectionDataReply {
    val storage = lazy CompressedNftCollectionStorage.load();

    return {
        nextItemIndex: storage.nextItemIndex,
        collectionContent: storage.collectionContent,
        ownerAddress: storage.ownerAddress,
        merkleRoot: storage.merkleRoot,
        maxSupply: storage.maxSupply,
    };
}

get fun get_nft_address_by_index(index: int): address {
    val storage = lazy CompressedNftCollectionStorage.load();
    assert (index < storage.maxSupply) throw 102;

    return calculateNftItemAddress(index, storage.nftItemCode);
}

get fun get_nft_content(index: int, individualContent: cell): cell {
    val storage = lazy CompressedNftCollectionStorage.load();

    return beginCell()
        .storeRef(storage.collectionContent)
        .storeRef(individualContent)
        .endCell();
}

get fun get_merkle_root(): uint256 {
    val storage = lazy CompressedNftCollectionStorage.load();
    return storage.merkleRoot;
}

get fun royalty_params(): RoyaltyParamsReply {
    val storage = lazy CompressedNftCollectionStorage.load();

    return {
        numerator: storage.royaltyFactor,
        denominator: storage.royaltyBase,
        destination: storage.royaltyAddress,
    };
}
