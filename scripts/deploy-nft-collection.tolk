import "@stdlib/strings"
import "@acton/env"
import "@acton/fmt"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@contracts/storage"
import "@contracts/nft-storage"
import "@gen/NftItem.code"
import "@wrappers/NftCollection.gen"
import "utils/common"

/**
 * Non-interactive NFT collection deploy for Phalanx Toolkit.
 *
 * Env (required):
 *   JETTON_DEPLOYER / NFT_DEPLOYER — Acton wallet name (pays gas)
 *   NFT_OWNER_ADDRESS              — collection owner (royalty destination default)
 *   COLLECTION_NAME, COLLECTION_DESCRIPTION, COLLECTION_IMAGE_URL
 *   ROYALTY_FACTOR, ROYALTY_BASE    — TEP-66 (shell derives from ROYALTY_PERCENT)
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

    val owner = promptJettonAddressRequired("NFT_OWNER_ADDRESS", "NFT collection owner");
    val royaltyFactor = promptRoyaltyFactor();
    val royaltyBase = promptRoyaltyBase();

    val storage: NftCollectionStorage = {
        ownerAddress: owner,
        nextItemIndex: 0,
        collectionContent: buildCollectionContentCell(),
        nftItemCode: nftItemCompiledCode(),
        royaltyFactor: royaltyFactor,
        royaltyBase: royaltyBase,
        royaltyAddress: owner,
    };

    val collection = NftCollection.fromStorage(storage);
    val deployRes = collection.deploy(deployer.address, { value: ton("0.15") });
    deployRes.waitForFirstTransaction();

    println("TOOLKIT COLLECTION_ADDRESS={}", collection.address);
    println("TOOLKIT DEPLOY_TRACE={}", deployRes.waitForTrace());
}
