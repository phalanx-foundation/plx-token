import "@stdlib/gas-payments"
import "errors"
import "sharding"
import "messages"
import "nft-messages"
import "nft-storage"

contract NftCollection {
    author: "Phalanx Foundation"
    version: "1.0.0"
    description: "NFT Collection. TEP-62 and TEP-66 compliant"
    storage: NftCollectionStorage
    incomingMessages: AllowedCollectionMessage
}

type AllowedCollectionMessage =
    | DeployNftItem
    | BatchDeployNftItem
    | ChangeCollectionOwner
    | ChangeCollectionContent
    | GetRoyaltyParams
    | TopUpTons

fun assertSenderIsOwner(senderAddress: address, ownerAddress: address) {
    assert (senderAddress == ownerAddress) throw 73;
}

fun emptyBodySlice(): slice {
    return beginCell().toSlice();
}

// Acton 1.1: createMessage embeds StateInit when dest is AutoDeployAddress
// (same pattern as calcDeployedJettonWallet) — do not pass stateInit in options.
fun calcDeployedNftItem(
    index: int,
    owner: address,
    individualContent: cell,
    nftItemCode: cell,
): AutoDeployAddress {
    val nftInitData = beginCell()
        .storeBool(true)
        .storeUint(index, 64)
        .storeAddress(contract.getAddress())
        .storeAddress(owner)
        .storeRef(individualContent)
        .endCell();

    return {
        workchain: MY_WORKCHAIN,
        stateInit: { code: nftItemCode, data: nftInitData },
    };
}

fun calculateNftItemAddress(
    index: int,
    nftItemCode: cell,
): address {
    // Getter helper: placeholder owner/content (collection address + empty cell).
    return calcDeployedNftItem(
        index,
        contract.getAddress(),
        beginCell().endCell(),
        nftItemCode,
    ).calculateAddress();
}

fun onInternalMessage(in: InMessage) {
    // Accept deploy / bare top-up with empty body (same pattern as PlxAirdrop et al.)
    if (in.body.remainingBitsCount() == 0 && in.body.remainingRefsCount() == 0) {
        return;
    }

    val msg = lazy AllowedCollectionMessage.fromSlice(in.body);

    match (msg) {
        DeployNftItem => {
            var storage = lazy NftCollectionStorage.load();
            assertSenderIsOwner(in.senderAddress, storage.ownerAddress);
            assert (msg.index == storage.nextItemIndex) throw 101; // Wrong index
            assert (msg.owner.getWorkchain() == MY_WORKCHAIN) throw 333;

            val deployMsg = createMessage({
                bounce: BounceMode.Only256BitsOfBody,
                dest: calcDeployedNftItem(
                    msg.index,
                    msg.owner,
                    msg.individualContent,
                    storage.nftItemCode,
                ),
                value: ton("0.05"),
                body: emptyBodySlice(),
            });
            deployMsg.send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_BOUNCE_ON_ACTION_FAIL);

            storage.nextItemIndex += 1;
            storage.save();
        }

        BatchDeployNftItem => {
            var storage = lazy NftCollectionStorage.load();
            assertSenderIsOwner(in.senderAddress, storage.ownerAddress);

            // parse batch items — each is DeployNftItem
            val itemsCell = msg.items;
            var itemsSlice = itemsCell.beginParse();
            val count = itemsSlice.loadRef();
            var itemSlice = count.beginParse();
            while (itemSlice.remainingBitsCount() > 0 || itemSlice.remainingRefsCount() > 0) {
                val item = lazy DeployNftItem.fromSlice(itemSlice);
                assert (item.index == storage.nextItemIndex) throw 101;
                assert (item.owner.getWorkchain() == MY_WORKCHAIN) throw 333;

                val deployMsg = createMessage({
                    bounce: BounceMode.Only256BitsOfBody,
                    dest: calcDeployedNftItem(
                        item.index,
                        item.owner,
                        item.individualContent,
                        storage.nftItemCode,
                    ),
                    value: ton("0.05"),
                    body: emptyBodySlice(),
                });
                deployMsg.send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_BOUNCE_ON_ACTION_FAIL);

                storage.nextItemIndex += 1;
            }
            storage.save();
        }

        ChangeCollectionOwner => {
            var storage = lazy NftCollectionStorage.load();
            assertSenderIsOwner(in.senderAddress, storage.ownerAddress);
            storage.ownerAddress = msg.newOwner;
            storage.save();
        }

        ChangeCollectionContent => {
            var storage = lazy NftCollectionStorage.load();
            assertSenderIsOwner(in.senderAddress, storage.ownerAddress);
            storage.collectionContent = msg.newContent;
            storage.save();
        }

        GetRoyaltyParams => {
            val storage = lazy NftCollectionStorage.load();

            val responseMsg = createMessage({
                bounce: BounceMode.NoBounce,
                dest: in.senderAddress,
                value: 0,
                body: ReportRoyaltyParams {
                    queryId: msg.queryId,
                    numerator: storage.royaltyFactor,
                    denominator: storage.royaltyBase,
                    destination: storage.royaltyAddress,
                },
            });
            responseMsg.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE | SEND_MODE_IGNORE_ERRORS);
        }

        TopUpTons => {
            // accept tons
        }

        else => throw 0xFFFF,
    }
}

get fun get_collection_data(): NftCollectionDataReply {
    val storage = lazy NftCollectionStorage.load();

    return {
        nextItemIndex: storage.nextItemIndex,
        collectionContent: storage.collectionContent,
        ownerAddress: storage.ownerAddress,
    };
}

get fun get_nft_address_by_index(index: int): address {
    val storage = lazy NftCollectionStorage.load();
    assert (index < storage.nextItemIndex) throw 102; // Index out of bounds

    return calculateNftItemAddress(index, storage.nftItemCode);
}

get fun get_nft_content(index: int, individualContent: cell): cell {
    val storage = lazy NftCollectionStorage.load();

    return beginCell()
        .storeRef(storage.collectionContent)
        .storeRef(individualContent)
        .endCell();
}

get fun royalty_params(): RoyaltyParamsReply {
    val storage = lazy NftCollectionStorage.load();

    return {
        numerator: storage.royaltyFactor,
        denominator: storage.royaltyBase,
        destination: storage.royaltyAddress,
    };
}
