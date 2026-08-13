# Changelog

## 2.0.0 - Gold / Gen2 engine port

- Target Pokemon Gold explicitly with `games: ["gold"]`.
- Added `engine_internals` permission for deliberate calls into Gold's live engine modules.
- Replaced Gen1 `save.money` with Gold `save.player.money`.
- Replaced Gen1 badge-item emulation with Johto/Kanto badge stores.
- Replaced `pokedex.owned` with Gold `pokedex.caught`.
- Replaced Gen1 `give_pokemon` command lookup with `src.battle.gen2.Mon.new` and OT stamping.
- Replaced 12-box assumptions with Gold's 14 x 20 `src.core.gen2.Boxes` storage.
- Replaced Gen1 evolution-screen path with Gold `src.core.gen2.Evolution.apply`.
- Replaced Gen1 Fly-warp table/overworld calls with Gold `FieldMoves.FLYPOINTS` and live `game.world` `flyTo`/`warpToSpawn`.
- Updated healing for Gen2 `maxHp` / `maxPp` records.
- ALL BALLS now discovers every Gold item in the BALL pocket.
- Added Sun Stone to the evolution-stone group.
- Updated walk-through-walls to target Gold's persistent `game.world.player`.
- Removed Safari refill and fake `flashLit` shortcut because those Gen1 fields are not Gold engine state.
