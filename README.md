# Gen2 Gold Cheat Menu

Gold-only port of the uploaded Gen1 cheat menu for `bryanthaboi/gen1recomp`.

This port is intentionally **engine-level**, not a text/UI rename. The menu still uses the mod UI, but every state-changing action is wired to the data structures or engine modules that Pokemon Gold actually runs:

- Money: `save.player.money` (cap 999999)
- Bag: Gold's live flat `save.inventory`; the Gen2 Pack derives ITEM/BALL/KEY/TM-HM pockets from item attributes
- Badges: `save.player.badges` and `save.player.kantoBadges`
- Pokedex: `save.pokedex.seen` and `save.pokedex.caught`
- Pokemon creation: `src.battle.gen2.Mon.new` + `Mon.stampOT`
- PC storage: `src.core.gen2.Boxes` (14 boxes x 20)
- Forced evolution: `src.core.gen2.Evolution.apply` + `markPokedex`
- Teleport: live `game.world:warpToSpawn()` / `game.world:flyTo()` using `FieldMoves.FLYPOINTS`
- Battle/movement cheats: runtime hooks (`encounter.roll`, `catch.rate`, `battle.*`, `exp.gain`, `movement.*`)

## Install

Extract the folder into the engine's normal `mods/` directory so the final layout is:

```text
mods/
  gen2_cheat_menu_gold/
    manifest.json
    main.lua
    mod.card
    README.md
```

The manifest declares `"games": ["gold"]` and requests `engine_internals`, because the Pokemon creation, box, evolution, and fly helpers deliberately call Gold's own engine modules.

## Menu

Open the normal START menu and choose **Cheat Menu**. Categories include Pokemon, World, Battle, Player, Items, and Pokedex.

Major actions include adding any registered Pokemon at levels 1-100 to party or PC, instant forced evolution through Gold's evolution record builder, healing party/PC, Gold fly-point teleports, no encounters, walk through walls, 4x movement, guaranteed catch, hit/crit/turn/run/damage cheats, EXP x1-x10, max money, all 16 badges, any registered item quantity, TM/HM groups, all Gold Ball-pocket items, and Pokedex seen/caught completion.

## Removed Gen1-only rows

The old Safari refill and `save.flashLit` dark-cave shortcut are not included. Those fields were Gen1 assumptions and presenting them on Gold would violate the requirement that a visible cheat actually affects the running Gen2 engine.

## Notes

Forced evolution is instant rather than opening the Gen1 `EvolutionState` screen. The resulting Pokemon still comes from Gold's `Evolution.apply`, including recalculated Gen2 stats and the correct evolved species record, and the new species is marked seen/caught.

Session toggles reset when the game is relaunched. Save-table changes persist the next time the game is saved normally.


## Auto updates

This build declares:

```json
"github": "randyadr/Gen2-Cheat-Menu"
```

Gen1Recomp checks GitHub **Releases** for newer semantic versions. Release tags should be `v2.0.1`, `v2.0.2`, etc., and each release must contain a ZIP asset named `gen2_cheat_menu_gold-<version>.zip`.

This repository includes `.github/workflows/release.yml`. After updating `manifest.json` to the new version, commit the change and push a matching tag, for example:

```sh
git tag v2.0.1
git push origin v2.0.1
```

The workflow creates the GitHub Release and uploads the correctly named mod ZIP automatically.
