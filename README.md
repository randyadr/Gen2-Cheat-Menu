# Gen2 Gold Cheat Menu

Gold-only port of the uploaded Gen1 cheat menu for `bryanthaboi/gen1recomp`.

This port is intentionally **engine-level**, not a text/UI rename. The menu still uses the mod UI, but every state-changing action is wired to the data structures or engine modules that Pokemon Gold actually runs:

- Money: `save.player.money` (cap 999999)
- Bag: Gold's live flat `save.inventory`; the Gen2 Pack derives ITEM/BALL/KEY/TM-HM pockets from item attributes
- Badges: `save.player.badges` and `save.player.kantoBadges`
- Pokedex: `save.pokedex.seen` and `save.pokedex.caught`
- Pokemon creation: `src.battle.gen2.Mon.new` + `Mon.stampOT`
- PC storage: `src.core.gen2.Boxes` (14 boxes x 20)
- Forced evolution: native `Gen2EvolutionAnim` screen, which commits through `src.core.gen2.Evolution.apply` + `markPokedex`
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

Open the normal START menu and choose **Cheat Menu**. Categories include Pokemon, World, Battle, Player, Items, Pokedex, and **GameShark**.

Major actions include adding any registered Pokemon at levels 1-100 to party or PC, forced evolution through Gold's native evolution animation and evolution record builder, healing party/PC, Gold fly-point teleports, no encounters, walk through walls, 4x movement, guaranteed catch, hit/crit/turn/run/damage cheats, EXP x1-x10, max money, all 16 badges, any registered item quantity, TM/HM groups, all Gold Ball-pocket items, Pokedex seen/caught completion, and user-entered GameShark codes.

## Custom GameShark codes

Open **Cheat Menu -> GAMESHARK -> ADD CODE**. The editor shows eight hexadecimal digits. Use left/right to select a digit, up/down to change it, **A** to save, and **B** to cancel.

This version accepts the standard 8-bit Game Boy / Game Boy Color GameShark write form:

```text
01VVLLHH
```

`VV` is the byte value and `LLHH` is the GameShark's low-byte/high-byte address encoding. For example, a code ending in `73D5` targets Gold address `D573`. Multi-line cheats can be entered as multiple codes; they run in the order shown.

Each saved code has **ENABLED**, **APPLY ONCE**, and **DELETE CODE** controls. Enabled codes are applied every fixed gameplay tick and are stored in the mod's save namespace.

### Engine-level compatibility

Gen1Recomp does not emulate a Game Boy CPU or expose a literal 64 KB cartridge RAM image. It reimplements Pokemon at a higher level. The GameShark manager therefore translates known Pokemon Gold WRAM addresses into the live recomp state. v2.0.3 directly bridges:

- `D573-D575` player money
- `D576-D579` Mom savings / saving flag
- `D57A-D57B` coins
- `D57C-D57D` Johto/Kanto badges
- `D57E-D5B6` TM/HM quantities
- `D5B8-D5E0` normal item slots / quantities
- `D5E2-D5FB` key-item slots
- `D5FD-D615` Ball slots / quantities
- `DBE4-DC03` Pokedex caught bytes
- `DC04-DC23` Pokedex seen bytes

Other WRAM/HRAM writes are mirrored into Gold's sparse script-VM memory where possible. Codes that target hardware state, CPU state, or cartridge variables the recomp does not model cannot be made universally compatible; the code detail screen identifies the target as **VM WRAM** or **UNSUPPORTED** instead of falsely reporting a live engine mapping.


## Removed Gen1-only rows

The old Safari refill and `save.flashLit` dark-cave shortcut are not included. Those fields were Gen1 assumptions and presenting them on Gold would violate the requirement that a visible cheat actually affects the running Gen2 engine.

## Notes

Forced evolution now opens Gold's native `Gen2EvolutionAnim` screen. The animation performs the same flashing/reveal sequence used by normal Gold evolution, commits the resulting Pokemon through `Evolution.apply`, marks the new species seen/caught, and handles evolution-time move learning. Cheat-triggered evolution is forced/non-cancelable.

Session toggles reset when the game is relaunched. Save-table changes persist the next time the game is saved normally.


## Auto updates

This build declares:

```json
"github": "randyadr/Gen2-Cheat-Menu"
```

Gen1Recomp checks GitHub **Releases** for newer semantic versions. Release tags should be `v2.0.3`, `v2.0.4`, etc., and each release must contain a ZIP asset named `gen2_cheat_menu_gold-<version>.zip`.

This repository includes `.github/workflows/release.yml`. After updating `manifest.json` to the new version, commit the change and push a matching tag, for example:

```sh
git tag v2.0.3
git push origin v2.0.3
```

The workflow creates the GitHub Release and uploads the correctly named mod ZIP automatically.
