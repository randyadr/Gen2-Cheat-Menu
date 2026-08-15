package.path = "./?.lua;./?/init.lua;" .. package.path

local function check(v, msg)
  if not v then error(msg or "check failed", 2) end
end
local function eq(a, b, msg)
  if a ~= b then error((msg or "not equal") .. ": got " .. tostring(a) .. ", want " .. tostring(b), 2) end
end

-- Engine-internal modules are mocked by contract so this test can run without a ROM/cache.
package.preload["src.battle.gen2.Mon"] = function()
  return {
    new = function(data, species, level)
      if not (data and data.pokemon and data.pokemon[species]) then return nil end
      return {
        species = species, name = species, level = level, hp = 20, maxHp = 20,
        stats = { hp = 20 }, moves = { { id = "TACKLE", pp = 1, maxPp = 35 } },
        happiness = 70, dvs = { attack = 1, defense = 1, speed = 1, special = 1 },
      }
    end,
    stampOT = function(save, mon)
      mon.ot = save.player.name
      mon.otId = save.player.id
      return mon
    end,
  }
end

package.preload["src.core.gen2.Boxes"] = function()
  local B = { NUM_BOXES = 14, MONS_PER_BOX = 20, PARTY_SIZE = 6 }
  function B.box(save, index)
    save.boxes = save.boxes or {}
    save.boxes[index] = save.boxes[index] or {}
    return save.boxes[index]
  end
  return B
end

package.preload["src.core.gen2.Evolution"] = function()
  return {
    apply = function(data, mon, evo)
      local into = evo and (evo.into or evo.species)
      if not (into and data.pokemon[into]) then return nil end
      local out = {}
      for k, v in pairs(mon) do out[k] = v end
      out.species = into
      out.name = into
      out.maxHp = 30
      out.hp = 30
      out.stats = { hp = 30 }
      return out
    end,
    markPokedex = function(save, species)
      save.pokedex.seen[species] = true
      save.pokedex.caught[species] = true
      return true
    end,
  }
end

package.preload["src.world.gen2.FieldMoves"] = function()
  return {
    JOHTO_BADGES = { "ZEPHYR", "HIVE", "PLAIN", "FOG", "MINERAL", "STORM", "GLACIER", "RISING" },
    KANTO_BADGES = { "BOULDER", "CASCADE", "THUNDER", "RAINBOW", "SOUL", "MARSH", "VOLCANO", "EARTH" },
    FLYPOINTS = {
      { landmark = "LANDMARK_NEW_BARK_TOWN", spawn = "SPAWN_NEW_BARK" },
      { landmark = "LANDMARK_GOLDENROD_CITY", spawn = "SPAWN_GOLDENROD" },
    },
  }
end

local Registry = {}
Registry.__index = Registry
function Registry.new(data)
  return setmetatable({ data = data or {} }, Registry)
end
function Registry:get(id) return self.data[id] end
function Registry:each()
  local k
  return function()
    k = next(self.data, k)
    if k ~= nil then return k, self.data[k] end
  end
end
function Registry:register(id, value) self.data[id] = value end

local hooks = {}
local screens = Registry.new()
local pushed = {}
local mod = {
  exports = {},
  content = {
    constants = Registry.new({ moneyCap = 999999 }),
    items = Registry.new({
      -- Gold's extracted item table carries metadata beside item records.
      generation = 2,
      source = "ROM:ItemNames + ItemAttributes",
      pockets = { "ITEM", "KEY_ITEM", "BALL", "TM_HM" },
      RARE_CANDY = { id = "RARE_CANDY", name = "RARE CANDY", pocket = "ITEM", index = 0x20 },
      MASTER_BALL = { id = "MASTER_BALL", name = "MASTER BALL", pocket = "BALL", index = 0x01 },
      POKE_BALL = { id = "POKE_BALL", name = "POKE BALL", pocket = "BALL", index = 0x02 },
      SUN_STONE = { id = "SUN_STONE", name = "SUN STONE", pocket = "ITEM", index = 0xA9 },
      TM01 = { id = "TM01", name = "TM01", pocket = "TM_HM", index = 0xBF, tmNumber = 1 },
      HM01 = { id = "HM01", name = "HM01", pocket = "TM_HM", index = 0xF3, tmNumber = 1 },
    }),
    moves = Registry.new({ TACKLE = { pp = 35 } }),
    pokemon = Registry.new({
      CHIKORITA = { name = "CHIKORITA", index = 152, evolutions = { { method = "EVOLVE_LEVEL", level = 16, into = "BAYLEEF" } } },
      BAYLEEF = { name = "BAYLEEF", index = 153, evolutions = {} },
      CYNDAQUIL = { name = "CYNDAQUIL", index = 155, evolutions = {} },
    }),
    screens = screens,
  },
  hooks = {
    wrap = function(_, name, fn, priority) hooks[name] = fn end,
  },
  ui = {
    push = function(game, id, ...)
      pushed[#pushed + 1] = { id = id, args = { ... } }
      return true
    end,
    ListMenu = { new = function(game, title, rows, opts) return { title = title, rows = rows, opts = opts } end },
    QuantityBox = { new = function(game, opts) return { opts = opts } end },
  },
  save = {
    data = {},
    get = function(self, key, default)
      local value = self.data[key]
      if value == nil then return default end
      return value
    end,
    set = function(self, key, value) self.data[key] = value end,
  },
}

local install = assert(loadfile("main.lua"))()
install(mod)

local world = {
  player = { tag = "gold-player" },
  map = { id = "NEW_BARK_TOWN" },
  landmarks = { landmarks = {
    LANDMARK_NEW_BARK_TOWN = { name = "NEW BARK TOWN" },
    LANDMARK_GOLDENROD_CITY = { name = "GOLDENROD CITY" },
  } },
  healWarps = 0,
  flySpawns = {},
  vm = { mem = {} },
  warpToSpawn = function(self) self.healWarps = self.healWarps + 1 end,
  flyTo = function(self, spawn) self.flySpawns[#self.flySpawns + 1] = spawn; return true end,
}
local game = {
  data = { pokemon = mod.content.pokemon.data, moves = mod.content.moves.data, items = mod.content.items.data },
  save = {
    version = "gold", generation = 2,
    player = { name = "GOLD", id = 12345, money = 3000, badges = {}, kantoBadges = {} },
    inventory = {}, pcItems = {}, party = {}, boxes = {}, currentBox = 14,
    pokedex = { seen = {}, caught = {} },
  },
  world = world,
  stack = {
    clear = function(self) self.cleared = true end,
    pop = function(self) self.popped = (self.popped or 0) + 1 end,
  },
}

-- Engine-level save fields.
local ok = mod.exports.maxMoney(game)
check(ok, "max money failed")
eq(game.save.player.money, 999999, "Gold money field")
eq(game.save.money, nil, "must not create Gen1 save.money")

ok = mod.exports.allBadges(game)
check(ok, "all badges failed")
eq(game.save.player.badges.ZEPHYR, true, "Johto badge store")
eq(game.save.player.badges.RISING, true, "Johto final badge")
eq(game.save.player.kantoBadges.BOULDER, true, "Kanto badge store")
eq(game.save.player.kantoBadges.EARTH, true, "Kanto final badge")

ok = mod.exports.completeDex(game)
check(ok, "complete dex failed")
for _, id in ipairs({ "CHIKORITA", "BAYLEEF", "CYNDAQUIL" }) do
  eq(game.save.pokedex.seen[id], true, "seen " .. id)
  eq(game.save.pokedex.caught[id], true, "caught " .. id)
end
eq(game.save.pokedex.owned, nil, "must not create Gen1 pokedex.owned")

ok = mod.exports.setItemCount(game, "RARE_CANDY", 42)
check(ok, "rare candy failed")
eq(game.save.inventory.RARE_CANDY, 42, "Gold live inventory")

-- Regression: Gold item metadata must never be treated as item definitions.
local pickerFactory = screens:get("Gen2CheatItemPicker")
check(type(pickerFactory) == "table" and type(pickerFactory.new) == "function", "item picker screen missing")
local picker = pickerFactory.new(game)
eq(picker.title, "ANY ITEM", "item picker title")
eq(#picker.rows, 6, "item picker filters Gold metadata")
for _, row in ipairs(picker.rows) do
  check(row.value ~= "generation" and row.value ~= "source" and row.value ~= "pockets",
    "metadata leaked into item picker")
end

-- Custom GameShark compatibility: standard 01VVLLHH parsing and live bridges.
local parsed, parseErr = mod.exports.parseGameSharkCode("01 99 73 D5")
check(parsed, parseErr)
eq(parsed.address, 0xD573, "GameShark reversed address")
eq(parsed.value, 0x99, "GameShark value")
local bad = mod.exports.parseGameSharkCode("02AA00C1")
eq(bad, nil, "unsupported GameShark code type rejected")

-- Money is packed BCD across D573-D575.
game.save.player.money = 0
check(mod.exports.applyGameSharkCode(game, "019973D5"), "money byte 1")
check(mod.exports.applyGameSharkCode(game, "019974D5"), "money byte 2")
check(mod.exports.applyGameSharkCode(game, "019975D5"), "money byte 3")
eq(game.save.player.money, 999999, "GameShark live money bridge")

-- Coins are two packed BCD bytes at D57A-D57B.
game.save.player.coins = 0
check(mod.exports.applyGameSharkCode(game, "01997AD5"), "coins byte 1")
check(mod.exports.applyGameSharkCode(game, "01997BD5"), "coins byte 2")
eq(game.save.player.coins, 9999, "GameShark live coins bridge")

-- Badge bytes map bit-for-bit to Gold's real badge stores.
check(mod.exports.applyGameSharkCode(game, "01FF7CD5"), "Johto badge byte")
check(mod.exports.applyGameSharkCode(game, "01FF7DD5"), "Kanto badge byte")
eq(game.save.player.badges.ZEPHYR, true, "GameShark Johto badges")
eq(game.save.player.kantoBadges.EARTH, true, "GameShark Kanto badges")

-- Ball slot/quantity pair: wBalls slot 1 at D5FD/D5FE. Item index 02 = POKE BALL in the test cache.
game.save.inventory.POKE_BALL = nil
game.save.bagOrder = {}
check(mod.exports.applyGameSharkCode(game, "0102FDD5"), "ball slot write")
check(mod.exports.applyGameSharkCode(game, "0163FED5"), "ball quantity write")
eq(game.save.inventory.POKE_BALL, 99, "GameShark live ball bridge")

-- TM01 quantity lives at the first byte of wTMsHMs.
check(mod.exports.applyGameSharkCode(game, "01637ED5"), "TM01 write")
eq(game.save.inventory.TM01, 99, "GameShark TM/HM bridge")

-- Chikorita is dex #152: byte 18, bit 7 => DBF6 value 80.
game.save.pokedex.caught.CHIKORITA = nil
check(mod.exports.applyGameSharkCode(game, "0180F6DB"), "dex caught byte")
eq(game.save.pokedex.caught.CHIKORITA, true, "GameShark dex bridge")

-- Unclaimed WRAM still lands in Gold's sparse VM memory, matching readmem/writemem semantics.
check(mod.exports.applyGameSharkCode(game, "01AA00C1"), "VM WRAM write")
eq(world.vm.mem[0xC100], 0xAA, "GameShark VM memory fallback")

-- Saved code list survives through mod.save and input.step re-applies enabled codes each fixed tick.
mod.save.data.gamesharkCodes = {}
check(mod.exports.addGameSharkCode("01017CD5", true), "add persistent GameShark code")
eq(#mod.exports.listGameSharkCodes(), 1, "GameShark code persisted")
game.save.player.badges.ZEPHYR = false
hooks["input.step"](function() return "tick" end, game, 1 / 60)
eq(game.save.player.badges.ZEPHYR, true, "enabled GameShark code reapplied per tick")
check(mod.exports.setGameSharkEnabled(1, false), "disable GameShark code")
game.save.player.badges.ZEPHYR = false
hooks["input.step"](function() end, game, 1 / 60)
eq(game.save.player.badges.ZEPHYR, false, "disabled GameShark code stays off")
check(mod.exports.deleteGameSharkCode(1), "delete GameShark code")
eq(#mod.exports.listGameSharkCodes(), 0, "GameShark code deleted")

local gsFactory = screens:get("Gen2CheatGameShark")
check(type(gsFactory) == "table" and type(gsFactory.new) == "function", "GameShark manager screen missing")
local gsMenu = gsFactory.new(game)
eq(gsMenu.title, "GAMESHARK CODES", "GameShark manager title")
eq(gsMenu.rows[1].label, "ADD CODE", "GameShark add-code row")

-- Gold Mon builder + OT + party.
local added, where, mon = mod.exports.addPokemonToParty(game, "CHIKORITA", 12)
check(added, "party add failed")
eq(where, "P1", "party destination")
eq(mon.level, 12, "party level")
eq(mon.ot, "GOLD", "OT name")
eq(mon.otId, 12345, "OT id")
eq(game.save.pokedex.caught.CHIKORITA, true, "add marks caught")

-- 14-box support: current box 14 must be a valid direct destination.
added, where, mon = mod.exports.addPokemonToPC(game, "CYNDAQUIL", 7)
check(added, "PC add failed")
eq(where, "BOX 14", "Gold box 14")
eq(game.save.boxes[14][1].species, "CYNDAQUIL", "box 14 mon")

-- Visible FORCE EVOLVE must open Gold's native Gen2EvolutionAnim screen first.
local original = game.save.party[1]
local targetFactory = screens:get("Gen2CheatEvolutionTarget")
check(type(targetFactory) == "table" and type(targetFactory.new) == "function",
  "evolution target screen missing")
local targetMenu = targetFactory.new(game, original)
check(targetMenu.rows[1] ~= nil, "evolution target row missing")
local beforePush = #pushed
targetMenu.opts.onChoose(targetMenu.rows[1])
eq(#pushed, beforePush + 1, "evolution should push one native screen")
local evoPush = pushed[#pushed]
eq(evoPush.id, "Gen2EvolutionAnim", "must push Gold native evolution animation")
local evoOpts = evoPush.args[1]
eq(evoOpts.mon, original, "animation mon")
eq(evoOpts.entry.into, "BAYLEEF", "animation evolution entry")
eq(evoOpts.party, game.save.party, "animation live party container")
eq(evoOpts.index, 1, "animation party index")
eq(evoOpts.save, game.save, "animation save")
eq(evoOpts.force, true, "cheat evolution must be non-cancelable")
eq(original.species, "CHIKORITA", "menu must not evolve before animation commit")
check(type(evoOpts.onDone) == "function", "animation completion callback")

-- PC-box force evolve must give the native animation the exact live box slot.
local pcAdded, pcWhere, pcMon = mod.exports.addPokemonToPC(game, "CHIKORITA", 10)
check(pcAdded, "PC evolution test add failed")
eq(pcWhere, "BOX 14", "PC evolution test destination")
local pcBeforePush = #pushed
ok = mod.exports.startEvolutionAnimation(game, pcMon,
  { method = "EVOLVE_LEVEL", level = 16, into = "BAYLEEF" })
check(ok, "PC evolution animation failed to start")
eq(#pushed, pcBeforePush + 1, "PC evolution should push native screen")
local pcEvoOpts = pushed[#pushed].args[1]
eq(pushed[#pushed].id, "Gen2EvolutionAnim", "PC must push native evolution animation")
eq(pcEvoOpts.party, game.save.boxes[14], "animation live PC box container")
eq(pcEvoOpts.index, 2, "animation PC box index")
eq(pcEvoOpts.mon, pcMon, "animation PC mon")
eq(pcMon.species, "CHIKORITA", "PC mon must wait for animation commit")

-- Headless forceEvolve helper remains available for tests/external callers.
ok = mod.exports.forceEvolve(game, original, { method = "EVOLVE_LEVEL", level = 16, into = "BAYLEEF" })
check(ok, "force evolve failed")
eq(game.save.party[1], original, "evolve keeps live reference")
eq(original.species, "BAYLEEF", "evolved species")
eq(original.maxHp, 30, "evolved engine record")
eq(game.save.pokedex.caught.BAYLEEF, true, "evolution caught flag")

-- Gold world functions, not Gen1 flyWarps/overworld calls.
ok = mod.exports.teleportTo(game, { kind = "heal" })
check(ok, "heal teleport failed")
eq(world.healWarps, 1, "warpToSpawn called")
ok = mod.exports.teleportTo(game, { kind = "fly", spawn = "SPAWN_GOLDENROD" })
check(ok, "fly teleport failed")
eq(world.flySpawns[1], "SPAWN_GOLDENROD", "flyTo called")

-- START hook captures the live Gold game and inserts the menu before MODS.
local menu = hooks["ui.start_menu.items"](function(_, items) return items end, game, {
  { label = "POKéMON" }, { label = "MODS" }, { label = "QUIT" },
})
eq(menu[2].label, "Cheat Menu", "start-menu insertion")

-- Shared runtime hooks really alter engine return values.
mod.exports.toggleNoWild(game)
local encounter = hooks["encounter.roll"](function(def) return def end, { species = "RATTATA" }, {})
eq(encounter, nil, "no-wild hook")

local battlePlayer, battleEnemy = { hp = 100 }, { hp = 77 }
local battle = { player = battlePlayer, enemy = battleEnemy }

mod.exports.toggleAlwaysHit(game)
local hit = hooks["battle.accuracy"](function() return false end, {
  battle = battle, user = battlePlayer, target = battleEnemy,
})
eq(hit, true, "Gold direct-mon always-hit hook")

mod.exports.toggleAlwaysCrit(game)
local crit = hooks["battle.crit"](function() return false end, {
  battle = battle, attacker = battlePlayer,
})
eq(crit, true, "Gold direct-mon crit hook")

mod.exports.toggleOneHitKO(game)
local dmg = hooks["battle.damage"](function() return 5, {} end, {
  battle = battle, user = battlePlayer, target = battleEnemy,
})
eq(dmg, 77, "Gold direct-mon one-hit damage hook")

mod.exports.toggleNoEnemyDamage(game)
dmg = hooks["battle.damage"](function() return 99, {} end, {
  battle = battle, user = battleEnemy, target = battlePlayer,
})
eq(dmg, 0, "Gold direct-mon no-enemy-damage hook")

mod.exports.toggleWalkThroughWalls(game)
local collisionCtx = { mover = world.player, reason = "solid" }
local allowed = hooks["movement.collision"](function(a) return a end, false, collisionCtx)
eq(allowed, true, "Gold world.player wall hook")
eq(collisionCtx.reason, "cheat", "collision reason")

mod.exports.toggleTurboMovement(game)
local frames = hooks["movement.speed"](function(f) return f end, 16, {})
eq(frames, 4, "movement speed hook")

print("gen2_cheat_menu_test: OK")
