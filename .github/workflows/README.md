# GitHub Actions Workflows

| Workflow | Trigger | Purpose |
|---|---|---|
| `contracts.yml` | push/PR to `master` | Lint + build + run all 60 tolk tests on Ubuntu |

CI runs automatically on every push and PR. The badge in the main `README.md`
turns green ✅ when CI passes and red ❌ when something breaks. Maintainers
should never merge a red PR.

## Local re-run

You can run the same checks locally before pushing:

```bash
acton check
acton fmt --check
acton build
acton test
```

If all four pass locally, CI will pass too (barring environment-specific issues).
