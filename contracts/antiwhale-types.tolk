import "sharding"

/// Whale limits held by AntiWhaleJettonMinter.
///
/// Every wallet the minter deploys derives its own limits from this single
/// config. That matters for correctness: a sender wallet computes the address of
/// the recipient wallet from its own limits, and the recipient accepts the
/// internal transfer only when that computed address matches. A minter that let
/// each wallet carry different limits would break every transfer between them.
@overflow1023_policy("suppress")
struct WhaleConfig {
    maxTransferAmount: coins
    maxWalletBalance: coins
}

/// Storage for AntiWhaleJettonMinter: the standard minter fields plus the whale
/// limits that are handed to every wallet at deploy time.
@overflow1023_policy("suppress")
struct AntiWhaleMinterStorage {
    totalSupply: coins
    adminAddress: address?
    nextAdminAddress: address?
    metadata: cell
    whaleConfig: Cell<WhaleConfig>
}

fun AntiWhaleMinterStorage.load(): AntiWhaleMinterStorage {
    return AntiWhaleMinterStorage.fromCell(contract.getData());
}

fun AntiWhaleMinterStorage.save(self) {
    contract.setData(self.toCell());
}

/// Init data used to derive the address of one AntiWhaleJettonWallet.
///
/// This mirrors AntiWhaleWalletStorage in AntiWhaleJettonWallet.tolk field for
/// field, on purpose: the minter and the wallet must agree byte for byte or a
/// transfer would be sent to an address the wallet never accepts. The
/// `anti-whale-minter` tests pin the two together by transferring between two
/// wallets of the same minter and asserting the balance lands on the address the
/// minter reports through `get_wallet_address`.
@overflow1023_policy("suppress")
struct AntiWhaleWalletInitStorage {
    jettonBalance: coins
    ownerAddress: address
    minterAddress: address
    maxTransferAmount: coins
    maxWalletBalance: coins
}

fun calcWhaleWalletDeployAddress(
    ownerAddress: address,
    minterAddress: address,
    walletCode: cell,
    maxTransferAmount: coins,
    maxWalletBalance: coins,
): AutoDeployAddress {
    val initStorage: AntiWhaleWalletInitStorage = {
        jettonBalance: 0,
        ownerAddress,
        minterAddress,
        maxTransferAmount,
        maxWalletBalance,
    };
    return {
        workchain: MY_WORKCHAIN,
        stateInit: { code: walletCode, data: initStorage.toCell() },
        toShard: { fixedPrefixLength: SHARD_DEPTH, closeTo: ownerAddress },
    };
}

fun calcWhaleWalletAddress(
    ownerAddress: address,
    minterAddress: address,
    walletCode: cell,
    maxTransferAmount: coins,
    maxWalletBalance: coins,
): address {
    return calcWhaleWalletDeployAddress(
        ownerAddress, minterAddress, walletCode, maxTransferAmount, maxWalletBalance,
    ).calculateAddress();
}
