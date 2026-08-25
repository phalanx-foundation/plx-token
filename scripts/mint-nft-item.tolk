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
import "@contracts/sharding"
import "utils/common"

/**
 * Mint one NFT item via DeployNftItem.
 * Caller (JETTON_DEPLOYER / NFT_DEPLOYER) must be the collection owner.
 *
 * Env:
 *   NFT_COLLECTION_ADDRESS — collection address
 *   NFT_ITEM_INDEX         — uint64 index (must equal nextItemIndex)
 *   NFT_ITEM_OWNER         — item owner (defaults to NFT_OWNER_ADDRESS)
 *   NFT_ITEM_NAME / NFT_ITEM_DESCRIPTION / NFT_ITEM_IMAGE_URL — on-chain content
 */
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

fun calcDeployedNftItemAddress(
    collectionAddress: address,
    index: int,
    owner: address,
    individualContent: cell,
): address {
    val nftInitData = beginCell()
        .storeBool(true)
        .storeUint(index, 64)
        .storeAddress(collectionAddress)
        .storeAddress(owner)
        .storeRef(individualContent)
        .endCell();

    return AutoDeployAddress {
        workchain: MY_WORKCHAIN,
        stateInit: { code: nftItemCompiledCode(), data: nftInitData },
    }.calculateAddress();
}

fun main() {
    val deployerNameEnv = env<string>("NFT_DEPLOYER");
    var deployer: ActonWallet;
    if (deployerNameEnv != null) {
        deployer = scripts.wallet(deployerNameEnv);
    } else {
        deployer = promptJettonWallet("JETTON_DEPLOYER", "Toolkit deployer wallet");
    }

    val collectionAddress = promptJettonAddressRequired(
        "NFT_COLLECTION_ADDRESS",
        "NFT collection address",
    );
    val indexRaw = promptJettonString("NFT_ITEM_INDEX", "Item index", "0");
    val index = parseInt(indexRaw) as uint64;

    val itemOwner = promptJettonAddress(
        "NFT_ITEM_OWNER",
        "NFT item owner",
        promptJettonAddressRequired("NFT_OWNER_ADDRESS", "Fallback owner"),
    );

    val content = buildItemContentCell();
    val collection = NftCollection.fromAddress(collectionAddress);

    val mintRes = collection.sendDeployNftItem(
        deployer.address,
        index,
        itemOwner,
        content,
        { value: ton("0.08") },
    );
    mintRes.waitForFirstTransaction();

    val itemAddress = calcDeployedNftItemAddress(
        collectionAddress,
        index as int,
        itemOwner,
        content,
    );

    println("TOOLKIT NFT_ITEM_INDEX={}", index);
    println("TOOLKIT NFT_ITEM_ADDRESS={}", itemAddress);
    println("TOOLKIT NFT_MINT_TRACE={}", mintRes.waitForTrace());
}
