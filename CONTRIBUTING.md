# Contributing to Phalanx (PLX)

Thanks for your interest in improving Phalanx (PLX). Contributions of any kind
are welcome: bug reports, security disclosures, documentation fixes, test
additions, gas optimizations, or new operational scripts.

## Ground Rules

1. **Smart contract source is the source of truth.** When proposing changes
   to `contracts/`, please update related `tests/`, `wrappers/`, and `scripts/`
   in the same PR.
2. **Never commit secrets.** `wallets.toml`, mnemonics, real `.env` files, and
   any production keys must stay outside the repository. The `.gitignore` is
   already strict about this — please don't relax it without strong reason.
3. **Cell-size discipline.** TON cells are limited to 1023 bits and 4 refs.
   When modifying storage layouts (`contracts/storage.tolk`), keep mutable
   fields inline and immutable config in cell references where appropriate.
4. **Don't break the API.** Public opcodes and message structs in
   `contracts/messages.tolk` are part of the contract ABI. Adding fields or
   opcodes is OK; renaming or removing them is a breaking change and requires
   a migration plan.

## Local Setup

```bash
git clone https://github.com/phalanx-foundation/plx-token.git
cd plx-token

# Install Acton CLI
curl -LsSf https://github.com/ton-blockchain/acton/releases/latest/download/acton-installer.sh | sh

acton doctor       # verify toolchain
acton build        # compile every contract
acton test         # 60+ tests should pass
```

## Pull Request Checklist

Before opening a PR:

- [ ] `acton build` passes for every contract
- [ ] `acton test` shows all tests passing (no skipped except documented)
- [ ] New tests added for new behavior (`tests/*.test.tolk`)
- [ ] `acton check --fix` produces a clean working tree
- [ ] No new secrets, mnemonics, or production keys introduced anywhere

## Reporting Security Issues

Please do **not** open a public GitHub issue for vulnerabilities that could
result in fund loss. Instead, see [SECURITY.md](SECURITY.md) for the
responsible-disclosure process.

For everything else (bugs, doc fixes, gas regressions, UX improvements), open a
regular GitHub issue or PR.

## Style

- Tolk follows the conventions in `contracts/` already (Pascal case for
  contracts and structs, lower-camel for functions, opcodes prefixed with
  intent like `AskTo*` / `Mint*`).
- Markdown docs aim for short paragraphs, tables for comparable items, and
  fenced code blocks with explicit shell prompts.

## License

By contributing, you agree your contributions are licensed under the same
[MIT License](LICENSE) as the rest of the project.
