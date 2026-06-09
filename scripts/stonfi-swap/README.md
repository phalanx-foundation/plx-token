# Ston.fi swap broadcast (PLX)

On Ubuntu Acton server:

```bash
cd ~/projects/plx-acton/scripts/stonfi-swap
npm install
```

Run via branding script when `STONFI_SWAP_BROADCAST_ENABLED=true`, or manually:

```bash
export TON_OPERATOR_MNEMONIC="..."
export SWAP_SIDE=buy
export SWAP_UNITS=50000000
export STONFI_POOL_ADDRESS=EQAm-5HxQpfQl8_lqyvax4AEPS9LXp6rE8AFr35hcfRPyZTq
node execute.mjs
```

Uses Toncenter mainnet RPC. Set `TONCENTER_MAINNET_API_KEY` for higher limits.
