import "sharding"
import "storage"

/// Storage for FeeJettonWallet — extends WalletStorage with fee configuration.
/// feeBps: fee in basis points (100 bps = 1%, max 1000 bps = 10%)
/// feeCollector: address that receives the fee portion of every transfer
@overflow1023_policy("suppress")
struct FeeWalletStorage {
    jettonBalance: coins
    ownerAddress: address
    minterAddress: address
    feeBps: uint16
    feeCollector: address
}

fun FeeWalletStorage.load(): FeeWalletStorage {
    return FeeWalletStorage.fromCell(contract.getData());
}

fun FeeWalletStorage.save(self) {
    contract.setData(self.toCell());
}

/// Config stored in FeeJettonMinter alongside standard minter fields.
@overflow1023_policy("suppress")
struct FeeMinterConfig {
    feeBps: uint16
    feeCollector: address
}

/// Storage for FeeJettonMinter.
@overflow1023_policy("suppress")
struct FeeMinterStorage {
    totalSupply: coins
    adminAddress: address?
    nextAdminAddress: address?
    metadata: cell
    feeConfig: Cell<FeeMinterConfig>
}

fun FeeMinterStorage.load(): FeeMinterStorage {
    return FeeMinterStorage.fromCell(contract.getData());
}

fun FeeMinterStorage.save(self) {
    contract.setData(self.toCell());
}

/// Compute the AutoDeployAddress for a FeeJettonWallet.
/// The wallet address depends on feeBps and feeCollector, so all wallets
/// from the same minter must share the same fee config.
fun calcDeployedFeeJettonWallet(
    ownerAddress: address,
    minterAddress: address,
    walletCode: cell,
    feeBps: uint16,
    feeCollector: address,
): AutoDeployAddress {
    val initStorage: FeeWalletStorage = {
        jettonBalance: 0,
        ownerAddress,
        minterAddress,
        feeBps,
        feeCollector,
    };
    return {
        workchain: MY_WORKCHAIN,
        stateInit: { code: walletCode, data: initStorage.toCell() },
        toShard: { fixedPrefixLength: SHARD_DEPTH, closeTo: ownerAddress },
    };
}

/// UpdateFeeConfig is sent to both FeeJettonWallet (from minter) and FeeJettonMinter (from admin).
/// feeBps must not exceed 1000 (10%).
struct (0xFEE00001) UpdateFeeConfig {
    queryId: uint64
    feeBps: uint16
    feeCollector: address
}

fun calcAddressOfFeeJettonWallet(
    ownerAddress: address,
    minterAddress: address,
    walletCode: cell,
    feeBps: uint16,
    feeCollector: address,
): address {
    return calcDeployedFeeJettonWallet(ownerAddress, minterAddress, walletCode, feeBps, feeCollector)
        .calculateAddress();
}
