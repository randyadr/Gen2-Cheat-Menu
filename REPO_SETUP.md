# Repository setup

Create a public GitHub repository named `Gen2-Cheat-Menu` under `randyadr`, then upload the contents of this repository bundle to its root.

The mod manifest already points to `randyadr/Gen2-Cheat-Menu`.

For the first auto-update-compatible release:

1. Ensure `manifest.json` says version `2.0.0`.
2. Create/push tag `v2.0.0`.
3. `.github/workflows/release.yml` will create a GitHub Release and upload `gen2_cheat_menu_gold-2.0.0.zip`.

For later updates, increment `manifest.json`, commit, then push a matching `v<version>` tag.
