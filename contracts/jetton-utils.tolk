import "sharding"
import "storage"

/// Official TON burn / revoked-admin address (workchain 0 + zero hash).
/// docs.ton.org: revoke by transferring admin here — NOT addr_none/null.
/// Friendly: UQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJKZ
const BURN_ADMIN_ADDRESS: address = address.fromWorkchainAndHash(0, 0)

fun isActiveMinterAdmin(adminAddress: address?): bool {
    return adminAddress != null && adminAddress != BURN_ADMIN_ADDRESS;
}

/// TEP-74 get_jetton_data admin slot must be MsgAddressInt (never empty/none).
fun jettonDataAdminAddress(adminAddress: address?): address {
    return adminAddress != null ? adminAddress! : BURN_ADMIN_ADDRESS;
}

fun calcDeployedJettonWallet(
    ownerAddress: address,
    minterAddress: address,
    jettonWalletCode: cell,
): AutoDeployAddress {
    val emptyWalletStorage: WalletStorage = {
        jettonBalance: 0,
        ownerAddress,
        minterAddress,
    };

    return {
        workchain: MY_WORKCHAIN,
        stateInit: { code: jettonWalletCode, data: emptyWalletStorage.toCell() },
        toShard: { fixedPrefixLength: SHARD_DEPTH, closeTo: ownerAddress },
    };
}

fun calcAddressOfJettonWallet(
    ownerAddress: address,
    minterAddress: address,
    jettonWalletCode: cell,
): address {
    val jwDeployed = calcDeployedJettonWallet(ownerAddress, minterAddress, jettonWalletCode);
    return jwDeployed.calculateAddress();
}

fun jettonEmptyForwardPayload(): slice {
    return beginCell().storeUint(0, 1).toSlice();
}
