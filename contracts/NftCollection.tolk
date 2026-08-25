import "@stdlib/gas-payments"
import "@stdlib/address"
import "errors"
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

fun calculateNftItemAddress(
    index: int,
    nftItemCode: cell,
): address {
    val stateInit = beginCell()
        .storeUint(0, 2)                   // split_depth: absent
        .storeUint(0, 1)                   // special: absent
        .storeUint(1, 1)                   // code: present
        .storeRef(nftItemCode)
        .storeUint(1, 1)                   // data: present
        .storeRef(beginCell()
            .storeInt(1, 1)                // init = true
            .storeInt(index, 64)
            .storeAddress(contract.getAddress())
            .storeAddress(contract.getAddress())       // owner = collection initially
            .storeRef(beginCell().endCell())            // empty individual content
            .endCell())
        .storeUint(0, 1)                   // library: absent
        .endCell();

    return contractAddress(0, stateInit);
}

fun onInternalMessage(in: InMessage) {
    val msg = lazy AllowedCollectionMessage.fromSlice(in.body);

    match (msg) {
        DeployNftItem => {
            var storage = lazy NftCollectionStorage.load();
            assertSenderIsOwner(in.senderAddress, storage.ownerAddress);
            assert (msg.index == storage.nextItemIndex) throw 101; // Wrong index
            assert (msg.owner.getWorkchain() == MY_WORKCHAIN) throw 333;

            val nftAddress = calculateNftItemAddress(msg.index, storage.nftItemCode);

            val nftInitData = beginCell()
                .storeInt(1, 1)               // init = true
                .storeInt(msg.index, 64)
                .storeAddress(contract.getAddress())
                .storeAddress(msg.owner)
                .storeRef(msg.individualContent)
                .endCell();

            val stateInit = beginCell()
                .storeUint(0, 2)              // split_depth: absent
                .storeUint(0, 1)              // special: absent
                .storeUint(1, 1)              // code: present
                .storeRef(storage.nftItemCode)
                .storeUint(1, 1)              // data: present
                .storeRef(nftInitData)
                .storeUint(0, 1)              // library: absent
                .endCell();

            val deployMsg = createMessage({
                bounce: BounceMode.Only256BitsOfBody,
                dest: nftAddress,
                value: ton("0.05"),
                body: beginCell().endCell().asSlice(), // init contract (send empty body)
                stateInit: stateInit,
            });
            deployMsg.send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_BOUNCE_ON_ACTION_FAIL);

            storage.nextItemIndex += 1;
            storage.save();
        }

        BatchDeployNftItem => {
            var storage = lazy NftCollectionStorage.load();
            assertSenderIsOwner(in.senderAddress, storage.ownerAddress);

            // parse batch items â€” each is DeployNftItem
            val itemsCell = msg.items;
            var itemsSlice = itemsCell.beginParse();
            val count = itemsSlice.loadRef();
            var itemSlice = count.beginParse();
            while (!itemSlice.isDataEmpty()) {
                val item = lazy DeployNftItem.fromSlice(itemSlice);
                assert (item.index == storage.nextItemIndex) throw 101;
                assert (item.owner.getWorkchain() == MY_WORKCHAIN) throw 333;

                val nftAddress = calculateNftItemAddress(item.index, storage.nftItemCode);
                val nftInitData = beginCell()
                    .storeInt(1, 1)
                    .storeInt(item.index, 64)
                    .storeAddress(contract.getAddress())
                    .storeAddress(item.owner)
                    .storeRef(item.individualContent)
                    .endCell();

                val stateInit = beginCell()
                    .storeUint(0, 2)
                    .storeUint(0, 1)
                    .storeUint(1, 1)
                    .storeRef(storage.nftItemCode)
                    .storeUint(1, 1)
                    .storeRef(nftInitData)
                    .storeUint(0, 1)
                    .endCell();

                val deployMsg = createMessage({
                    bounce: BounceMode.Only256BitsOfBody,
                    dest: nftAddress,
                    value: ton("0.05"),
                    body: beginCell().endCell().asSlice(),
                    stateInit: stateInit,
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
