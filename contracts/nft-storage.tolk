// === NftItem Storage ===

struct NftItemStorage {
    init: int
    index: int
    collectionAddress: address
    ownerAddress: address
    individualContent: cell
}

fun NftItemStorage.load(): NftItemStorage {
    return NftItemStorage.fromCell(contract.getData());
}

fun NftItemStorage.save(self) {
    contract.setData(self.toCell());
}

// === NftCollection Storage ===

struct NftCollectionStorage {
    ownerAddress: address
    nextItemIndex: int
    collectionContent: cell
    nftItemCode: cell
    royaltyFactor: uint16
    royaltyBase: uint16
    royaltyAddress: address
}

fun NftCollectionStorage.load(): NftCollectionStorage {
    return NftCollectionStorage.fromCell(contract.getData());
}

fun NftCollectionStorage.save(self) {
    contract.setData(self.toCell());
}

// === Compressed Nft Collection Storage ===

struct CompressedNftCollectionStorage {
    ownerAddress: address
    nextItemIndex: int
    collectionContent: cell
    nftItemCode: cell
    royaltyFactor: uint16
    royaltyBase: uint16
    royaltyAddress: address
    merkleRoot: uint256
    maxSupply: int
}

fun CompressedNftCollectionStorage.load(): CompressedNftCollectionStorage {
    return CompressedNftCollectionStorage.fromCell(contract.getData());
}

fun CompressedNftCollectionStorage.save(self) {
    contract.setData(self.toCell());
}

// === Get-Method Reply Types ===

struct NftCollectionDataReply {
    nextItemIndex: int
    collectionContent: cell
    ownerAddress: address
}

struct NftDataReply {
    init: int
    index: int
    collectionAddress: address
    ownerAddress: address
    individualContent: cell
}

struct RoyaltyParamsReply {
    numerator: uint16
    denominator: uint16
    destination: address
}

struct CompressedCollectionDataReply {
    nextItemIndex: int
    collectionContent: cell
    ownerAddress: address
    merkleRoot: uint256
    maxSupply: int
}
