import "@stdlib/strings"
import "@acton/env"
import "@acton/fmt"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@contracts/storage"
import "@contracts/nft-storage"
import "@gen/NftItem.code"
import "@wrappers/CompressedNftCollection.gen"
import "utils/common"

/**
 * Single-process cNFT deploy + claim (emulation / same network session).
 * Env: same as deploy-cnft-collection + CNFT_PROOF_0..7 + NFT_ITEM_* for claim index 0.
 */
fun buildCollectionContentCell(): cell {
    val name = promptJettonString("COLLECTION_NAME", "Collection name", "Unnamed Collection");
    val description = promptJettonString("COLLECTION_DESCRIPTION", "Collection description", "");
    val image = promptJettonString("COLLECTION_IMAGE_URL", "Collection image URL", "");
    var metadata: OnchainMetadataReply = { contentDict: [] };
    metadata.contentDict.set("name".sha256(), name.prefixWith00());
    metadata.contentDict.set("description".sha256(), description.prefixWith00());
    metadata.contentDict.set("image".sha256(), image.prefixWith00());
    return metadata.toCell();
}

fun buildItemContentCell(): cell {
    val name = promptJettonString("NFT_ITEM_NAME", "Item name", "Item");
    val description = promptJettonString("NFT_ITEM_DESCRIPTION", "Item description", "");
    val image = promptJettonString("NFT_ITEM_IMAGE_URL", "Item image URL", "");
    var metadata: OnchainMetadataReply = { contentDict: [] };
    metadata.contentDict.set("name".sha256(), name.prefixWith00());
    metadata.contentDict.set("description".sha256(), description.prefixWith00());
    metadata.contentDict.set("image".sha256(), image.prefixWith00());
    return metadata.toCell();
}

fun proofSibling(envName: string): uint256 {
    val raw = env<string>(envName);
    if (raw == null) {
        return 0;
    }
    return parseInt(raw) as uint256;
}

fun buildProofCell(): cell {
    val s0 = proofSibling("CNFT_PROOF_0");
    val s1 = proofSibling("CNFT_PROOF_1");
    val s2 = proofSibling("CNFT_PROOF_2");
    val s3 = proofSibling("CNFT_PROOF_3");
    val s4 = proofSibling("CNFT_PROOF_4");
    val s5 = proofSibling("CNFT_PROOF_5");
    val s6 = proofSibling("CNFT_PROOF_6");
    val s7 = proofSibling("CNFT_PROOF_7");
    val cell2 = beginCell().storeUint(s6, 256).storeUint(s7, 256).endCell();
    val cell1 = beginCell()
        .storeUint(s3, 256)
        .storeUint(s4, 256)
        .storeUint(s5, 256)
        .storeRef(cell2)
        .endCell();
    return beginCell()
        .storeUint(s0, 256)
        .storeUint(s1, 256)
        .storeUint(s2, 256)
        .storeRef(cell1)
        .endCell();
}

fun main() {
    val deployer = promptJettonWallet("JETTON_DEPLOYER", "Toolkit deployer wallet");
    val owner = promptJettonAddressRequired("NFT_OWNER_ADDRESS", "cNFT owner");
    val merkleRoot: uint256 = (env<int>("CNFT_MERKLE_ROOT") ?? 0) as uint256;
    val maxSupply = parseInt(promptJettonString("CNFT_MAX_SUPPLY", "Max supply", "256")) as uint64;
    val royaltyFactor = parseInt(promptJettonString("ROYALTY_FACTOR", "Royalty factor", "0")) as uint16;
    val royaltyBase = parseInt(promptJettonString("ROYALTY_BASE", "Royalty base", "10000")) as uint16;

    val storage: CompressedNftCollectionStorage = {
        ownerAddress: owner,
        nextItemIndex: 0,
        collectionContent: buildCollectionContentCell(),
        nftItemCode: nftItemCompiledCode(),
        royaltyFactor: royaltyFactor,
        royaltyBase: royaltyBase,
        royaltyAddress: owner,
        merkleRoot: merkleRoot,
        maxSupply: maxSupply,
    };

    val collection = CompressedNftCollection.fromStorage(storage);
    val deployRes = collection.deploy(deployer.address, { value: ton("0.15") });
    deployRes.waitForFirstTransaction();
    println("TOOLKIT COLLECTION_ADDRESS={}", collection.address);
    println("TOOLKIT MERKLE_ROOT={}", merkleRoot);

    val index = parseInt(promptJettonString("NFT_ITEM_INDEX", "Claim index", "0")) as uint64;
    val claimRes = collection.sendDeployItemWithProof(
        deployer.address,
        index,
        owner,
        buildItemContentCell(),
        buildProofCell(),
        { value: ton("0.12") },
    );
    claimRes.waitForFirstTransaction();
    println("TOOLKIT CNFT_CLAIM_INDEX={}", index);
    println("TOOLKIT CNFT_CLAIM_TRACE={}", claimRes.waitForTrace());
}
