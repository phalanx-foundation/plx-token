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
 * Non-interactive Compressed NFT collection deploy (TEP #126).
 *
 * Env:
 *   JETTON_DEPLOYER / NFT_DEPLOYER
 *   NFT_OWNER_ADDRESS
 *   COLLECTION_NAME, COLLECTION_DESCRIPTION, COLLECTION_IMAGE_URL
 *   ROYALTY_FACTOR, ROYALTY_BASE
 *   CNFT_MERKLE_ROOT — decimal uint256 (0 = placeholder until SetMerkleRoot)
 *   CNFT_MAX_SUPPLY  — uint64 (default 256)
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

fun promptRoyaltyFactor(): uint16 {
    val fromEnv = env<string>("ROYALTY_FACTOR");
    if (fromEnv != null) {
        return parseInt(fromEnv) as uint16;
    }
    val percent = promptJettonString("ROYALTY_PERCENT", "Royalty percent", "0");
    return (parseInt(percent) * 100) as uint16;
}

fun promptRoyaltyBase(): uint16 {
    val fromEnv = env<string>("ROYALTY_BASE");
    if (fromEnv != null) {
        return parseInt(fromEnv) as uint16;
    }
    return 10000;
}

fun main() {
    val deployerNameEnv = env<string>("NFT_DEPLOYER");
    var deployer: ActonWallet;
    if (deployerNameEnv != null) {
        deployer = scripts.wallet(deployerNameEnv);
    } else {
        deployer = promptJettonWallet("JETTON_DEPLOYER", "Toolkit deployer wallet");
    }

    val owner = promptJettonAddressRequired("NFT_OWNER_ADDRESS", "cNFT collection owner");
    val royaltyFactor = promptRoyaltyFactor();
    val royaltyBase = promptRoyaltyBase();

    val merkleRootRaw: int = env<int>("CNFT_MERKLE_ROOT") ?? 0;
    val merkleRoot: uint256 = merkleRootRaw as uint256;
    val maxSupplyRaw = promptJettonString("CNFT_MAX_SUPPLY", "Max supply", "256");
    val maxSupply = parseInt(maxSupplyRaw) as uint64;

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
    println("TOOLKIT MAX_SUPPLY={}", maxSupply);
    println("TOOLKIT DEPLOY_TRACE={}", deployRes.waitForTrace());
}
