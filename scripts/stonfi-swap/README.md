# Ston.fi swap + LP broadcast (PLX)

On Ubuntu Acton server:

```bash
cd ~/projects/plx-acton/scripts/stonfi-swap
npm install
```

## Swap (`execute.mjs`)

Run via branding script when `STONFI_SWAP_BROADCAST_ENABLED=true`, or manually:

```bash
export TON_OPERATOR_MNEMONIC="..."
export SWAP_SIDE=buy
export SWAP_UNITS=50000000
export STONFI_POOL_ADDRESS=EQAm-5HxQpfQl8_lqyvax4AEPS9LXp6rE8AFr35hcfRPyZTq
node execute.mjs
```

## LP provide (`execute-lp.mjs`) — W5 / v5r1 `plx-lp`

Called by `scripts/stonfi-add-liquidity.py` when `STONFI_LP_AUTO_ENABLED=true` and
`STONFI_LP_BROADCAST_ENABLED=true`. Mnemonic is loaded from `wallets.toml` (`plx-lp`)
unless `TON_OPERATOR_MNEMONIC` is set.

```bash
export LP_TON_NANO=15000000000
export STONFI_POOL_ADDRESS=EQAm-5HxQpfQl8_lqyvax4AEPS9LXp6rE8AFr35hcfRPyZTq
export EXPECTED_WALLET_ADDRESS=EQAiQ41f7R5qzKsoimbujtYdy0bRKW_7Fb0rV5Z4Lw6gr3zH
export DRY_RUN=true   # omit to broadcast
# TON_OPERATOR_MNEMONIC from wallets.toml via Python wrapper is preferred
node execute-lp.mjs
```

Uses Toncenter mainnet RPC. Set `TONCENTER_MAINNET_API_KEY` for higher limits.
