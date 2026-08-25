import "@stdlib/strings"
import "@acton/env"
import "@acton/fmt"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@contracts/storage"
import "@wrappers/CompressedNftCollection.gen"
import "utils/common"

/**
 * Claim / deploy one cNFT item with Merkle proof (DeployItemWithProof).
 *
 * Env:
 *   NFT_COLLECTION_ADDRESS
 *   NFT_ITEM_INDEX
 *   NFT_ITEM_OWNER / NFT_OWNER_ADDRESS (claimant)
 *   NFT_ITEM_NAME / NFT_ITEM_DESCRIPTION / NFT_ITEM_IMAGE_URL
 *   CNFT_PROOF_0 .. CNFT_PROOF_7 — sibling hashes as decimal uint256 strings
 *   JETTON_DEPLOYER / NFT_DEPLOYER — pays gas (anyone can claim with valid proof)
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

fun proofSibling(envName: string): uint256 {
    val raw = env<string>(envName);
    if (raw == null) {
        return 0;
    }
    return parseInt(raw) as uint256;
}

/// Pack 8 siblings as 3 + 3 + 2 uint256 cells chained by refs.
fun buildProofCell(): cell {
    val s0 = proofSibling("CNFT_PROOF_0");
    val s1 = proofSibling("CNFT_PROOF_1");
    val s2 = proofSibling("CNFT_PROOF_2");
    val s3 = proofSibling("CNFT_PROOF_3");
    val s4 = proofSibling("CNFT_PROOF_4");
    val s5 = proofSibling("CNFT_PROOF_5");
    val s6 = proofSibling("CNFT_PROOF_6");
    val s7 = proofSibling("CNFT_PROOF_7");

    val cell2 = beginCell()
        .storeUint(s6, 256)
        .storeUint(s7, 256)
        .endCell();
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
    val deployerNameEnv = env<string>("NFT_DEPLOYER");
    var payer: ActonWallet;
    if (deployerNameEnv != null) {
        payer = scripts.wallet(deployerNameEnv);
    } else {
        payer = promptJettonWallet("JETTON_DEPLOYER", "Gas payer wallet");
    }

    val collectionAddress = promptJettonAddressRequired(
        "NFT_COLLECTION_ADDRESS",
        "cNFT collection address",
    );
    val index = parseInt(promptJettonString("NFT_ITEM_INDEX", "Item index", "0")) as uint64;
    val claimant = promptJettonAddress(
        "NFT_ITEM_OWNER",
        "Claimant / item owner",
        promptJettonAddressRequired("NFT_OWNER_ADDRESS", "Claimant"),
    );

    val collection = CompressedNftCollection.fromAddress(collectionAddress);
    val content = buildItemContentCell();
    val proofCell = buildProofCell();

    val res = collection.sendDeployItemWithProof(
        payer.address,
        index,
        claimant,
        content,
        proofCell,
        { value: ton("0.12") },
    );
    res.waitForFirstTransaction();

    println("TOOLKIT CNFT_CLAIM_INDEX={}", index);
    println("TOOLKIT CNFT_CLAIM_TRACE={}", res.waitForTrace());
}
