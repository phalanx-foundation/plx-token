/// === NFT Transfer (TEP-62) ===

struct (0x5fcc3d14) NftTransfer {
    queryId: uint64
    newOwner: address
    responseDestination: address?
    customPayload: cell?
    forwardAmount: coins
    forwardPayload: cell?
}

/// === NFT Collection Messages ===

struct (0x1fc1f25e) DeployNftItem {
    index: int
    owner: address
    individualContent: cell
}

struct (0x810273dc) BatchDeployNftItem {
    items: cell  /// ref to list of DeployNftItem
}

struct (0x4edc4880) ChangeCollectionOwner {
    newOwner: address
}

struct (0x1a0b861e) ChangeCollectionContent {
    newContent: cell
}

/// === Royalty Messages (TEP-66) ===

struct (0x693d3950) GetRoyaltyParams {
    queryId: uint64
}

struct (0xa8cb00ad) ReportRoyaltyParams {
    queryId: uint64
    numerator: uint16
    denominator: uint16
    destination: address
}

/// === Get Static Data ===

struct (0x2fcb26a2) GetStaticData {
    queryId: uint64
}

struct (0x8b771735) ReportStaticData {
    queryId: uint64
    index: int
    collection: address
}

/// === Compressed NFT Messages (TEP #126) ===

struct (0x9f5c8a3b) DeployItemWithProof {
    itemIndex: int
    claimant: address
    individualContent: cell
    proofCell: cell         /// cell containing sibling hashes as uint256 chain
}

struct (0x1a4e7c2d) SetMerkleRoot {
    newRoot: uint256
    maxSupply: int
}

/// === Excess Messages ===

struct (0xd53276db) NftExcesses {
    queryId: uint64
}
