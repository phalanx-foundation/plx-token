// === NftItem Storage ===
// Widths match on-chain layout used by NftCollection/CompressedNftCollection deploy:
// init:1 bit, index:64 bits, then addresses + content ref.

struct NftItemStorage {
    init: bool
    index: uint64
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
    nextItemIndex: uint64
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
    nextItemIndex: uint64
    collectionContent: cell
    nftItemCode: cell
    royaltyFactor: uint16
    royaltyBase: uint16
    royaltyAddress: address
    merkleRoot: uint256
    maxSupply: uint64
}

fun CompressedNftCollectionStorage.load(): CompressedNftCollectionStorage {
    return CompressedNftCollectionStorage.fromCell(contract.getData());
}

fun CompressedNftCollectionStorage.save(self) {
    contract.setData(self.toCell());
}

// === Get-Method Reply Types ===

struct NftCollectionDataReply {
    nextItemIndex: uint64
    collectionContent: cell
    ownerAddress: address
}

struct NftDataReply {
    init: bool
    index: uint64
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
    nextItemIndex: uint64
    collectionContent: cell
    ownerAddress: address
    merkleRoot: uint256
    maxSupply: uint64
}
