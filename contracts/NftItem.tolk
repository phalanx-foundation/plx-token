import "@stdlib/gas-payments"
import "nft-messages"
import "nft-storage"

contract NftItem {
    author: "Phalanx Foundation"
    version: "1.0.0"
    description: "NFT Item. TEP-62 compliant"
    storage: NftItemStorage
    incomingMessages: AllowedNftItemMessage
}

type AllowedNftItemMessage =
    | NftTransfer
    | GetStaticData

fun assertOwner(senderAddress: address, ownerAddress: address) {
    assert (senderAddress == ownerAddress) throw 73;
}

fun onInternalMessage(in: InMessage) {
    val msg = lazy AllowedNftItemMessage.fromSlice(in.body);

    match (msg) {
        NftTransfer => {
            var storage = lazy NftItemStorage.load();
            assertOwner(in.senderAddress, storage.ownerAddress);

            storage.ownerAddress = msg.newOwner;
            storage.save();

            val forwardAmount = msg.forwardAmount;
            if (forwardAmount != 0) {
                val notificationBody = beginCell()
                    .storeUint(0x41661e1f, 32)    // ownership_assigned
                    .storeUint(msg.queryId, 64)
                    .storeUint(0, 64)               // prev_owner (zero = not provided)
                    .storeRef(beginCell()
                        .storeAddress(storage.collectionAddress)
                        .storeCoins(0)
                        .storeRef(storage.individualContent)
                        .endCell())
                    .endCell();

                val notifyMsg = createMessage({
                    bounce: BounceMode.NoBounce,
                    dest: msg.newOwner,
                    value: forwardAmount,
                    body: notificationBody.asSlice(),
                });
                notifyMsg.send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_IGNORE_ERRORS);
            }

            if (msg.responseDestination != null) {
                val excessMsg = createMessage({
                    bounce: BounceMode.NoBounce,
                    dest: msg.responseDestination,
                    value: 0,
                    body: NftExcesses { queryId: msg.queryId },
                });
                excessMsg.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE | SEND_MODE_IGNORE_ERRORS);
            }
        }

        GetStaticData => {
            val storage = lazy NftItemStorage.load();

            val responseMsg = createMessage({
                bounce: BounceMode.NoBounce,
                dest: in.senderAddress,
                value: 0,
                body: ReportStaticData {
                    queryId: msg.queryId,
                    index: storage.index,
                    collection: storage.collectionAddress,
                },
            });
            responseMsg.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE | SEND_MODE_IGNORE_ERRORS);
        }

        else => throw 0xFFFF,
    }
}

get fun get_nft_data(): NftDataReply {
    val storage = lazy NftItemStorage.load();

    return {
        init: storage.init,
        index: storage.index,
        collectionAddress: storage.collectionAddress,
        ownerAddress: storage.ownerAddress,
        individualContent: storage.individualContent,
    };
}
