/**
 * Broadcast Ston.fi swap on mainnet using operator mnemonic.
 *
 * Env:
 *   TON_OPERATOR_MNEMONIC — 12/24 words
 *   SWAP_SIDE — buy | sell (buy = TON→PLX)
 *   SWAP_UNITS — nano units (TON for buy, PLX for sell)
 *   STONFI_POOL_ADDRESS, PLX_JETTON_MINTER_MAINNET
 *   TONCENTER_MAINNET_API_KEY (optional)
 */

import { StonApiClient } from "@ston-fi/api";
import { dexFactory, Client as StonClient } from "@ston-fi/sdk";
import { mnemonicToPrivateKey } from "@ton/crypto";
import { Address, TonClient, WalletContractV4 } from "@ton/ton";

const TON_NATIVE = "EQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAM9c";
const pool =
  process.env.STONFI_POOL_ADDRESS ||
  "EQAm-5HxQpfQl8_lqyvax4AEPS9LXp6rE8AFr35hcfRPyZTq";
const plxMinter =
  process.env.PLX_JETTON_MINTER_MAINNET ||
  process.env.JETTON_MINTER_ADDRESS ||
  "EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS";
const side = (process.env.SWAP_SIDE || "buy").toLowerCase();
const units = process.env.SWAP_UNITS || "50000000";
const slippage = process.env.STONFI_SLIPPAGE || "0.03";
const mnemonic = (process.env.TON_OPERATOR_MNEMONIC || "").trim();

if (!mnemonic) {
  console.error("TON_OPERATOR_MNEMONIC required");
  process.exit(1);
}

const apiKey = process.env.TONCENTER_MAINNET_API_KEY || "";
const endpoint = apiKey
  ? `https://toncenter.com/api/v2/jsonRPC?api_key=${apiKey}`
  : "https://toncenter.com/api/v2/jsonRPC";

const tonClient = new TonClient({ endpoint });
const stonClient = new StonClient({ endpoint });
const apiClient = new StonApiClient();

const keyPair = await mnemonicToPrivateKey(mnemonic.split(/\s+/));
const wallet = WalletContractV4.create({
  workchain: 0,
  publicKey: keyPair.publicKey,
});
const walletContract = tonClient.open(wallet);
const userWalletAddress = wallet.address.toString();

let simulation;
if (side === "buy") {
  simulation = await apiClient.simulateSwap({
    offerAddress: TON_NATIVE,
    askAddress: plxMinter,
    offerUnits: units,
    poolAddress: pool,
    slippageTolerance: slippage,
  });
} else {
  simulation = await apiClient.simulateReverseSwap({
    offerAddress: plxMinter,
    askAddress: TON_NATIVE,
    offerUnits: units,
    poolAddress: pool,
    slippageTolerance: slippage,
  });
}

const { router: routerInfo } = simulation;
const dexContracts = dexFactory(routerInfo);
const router = stonClient.open(dexContracts.Router.create(routerInfo.address));
const proxyTon = dexContracts.pTON.create(routerInfo.ptonMasterAddress);

let txParams;
if (side === "buy") {
  txParams = await router.getSwapTonToJettonTxParams({
    userWalletAddress,
    offerAmount: simulation.offerUnits,
    minAskAmount: simulation.minAskUnits,
    askJettonAddress: simulation.askAddress,
    proxyTon,
    queryId: Date.now(),
  });
} else {
  txParams = await router.getSwapJettonToTonTxParams({
    userWalletAddress,
    offerJettonAddress: simulation.offerAddress,
    offerAmount: simulation.offerUnits,
    minAskAmount: simulation.minAskUnits,
    proxyTon,
    queryId: Date.now(),
  });
}

const seqno = await walletContract.getSeqno();
await walletContract.sendTransfer({
  seqno,
  secretKey: keyPair.secretKey,
  messages: [
    {
      to: Address.parse(txParams.to),
      value: BigInt(txParams.value),
      body: txParams.body,
    },
  ],
});

console.log(
  JSON.stringify({
    ok: true,
    side,
    units,
    wallet: userWalletAddress,
    to: txParams.to,
    value: txParams.value,
  }),
);
