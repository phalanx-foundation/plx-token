import "@stdlib/strings"
import "@acton/env"
import "@acton/fmt"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@wrappers/NftCollection.gen"
import "utils/common"

/**
 * Transfer NFT collection ownership (TEP ChangeCollectionOwner).
 * Caller must be current collection owner.
 *
 * Env:
 *   NFT_COLLECTION_ADDRESS — collection
 *   NFT_NEW_OWNER_ADDRESS  — new owner (defaults to NFT_OWNER_ADDRESS)
 */
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
    val newOwner = promptJettonAddress(
        "NFT_NEW_OWNER_ADDRESS",
        "New collection owner",
        promptJettonAddressRequired("NFT_OWNER_ADDRESS", "Client owner"),
    );

    val collection = NftCollection.fromAddress(collectionAddress);
    val res = collection.sendChangeCollectionOwner(
        deployer.address,
        newOwner,
        { value: ton("0.05") },
    );
    res.waitForFirstTransaction();

    println("TOOLKIT COLLECTION_OWNER={}", newOwner);
    println("TOOLKIT OWNER_CHANGE_TRACE={}", res.waitForTrace());
}
