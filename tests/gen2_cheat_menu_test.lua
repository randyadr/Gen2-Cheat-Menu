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
      RARE_CANDY = { name = "RARE CANDY", pocket = "ITEM" },
      MASTER_BALL = { name = "MASTER BALL", pocket = "BALL" },
      POKE_BALL = { name = "POKE BALL", pocket = "BALL" },
      SUN_STONE = { name = "SUN STONE", pocket = "ITEM" },
    }),
    moves = Registry.new({ TACKLE = { pp = 35 } }),
    pokemon = Registry.new({
      CHIKORITA = { name = "CHIKORITA", evolutions = { { method = "EVOLVE_LEVEL", level = 16, into = "BAYLEEF" } } },
      BAYLEEF = { name = "BAYLEEF", evolutions = {} },
      CYNDAQUIL = { name = "CYNDAQUIL", evolutions = {} },
    }),
    screens = screens,
  },
  hooks = {
    wrap = function(_, name, fn, priority) hooks[name] = fn end,
  },
  ui = {
    push = function(game, id, ...) pushed[#pushed + 1] = id; return true end,
    ListMenu = { new = function(game, title, rows, opts) return { title = title, rows = rows, opts = opts } end },
    QuantityBox = { new = function(game, opts) return { opts = opts } end },
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
  warpToSpawn = function(self) self.healWarps = self.healWarps + 1 end,
  flyTo = function(self, spawn) self.flySpawns[#self.flySpawns + 1] = spawn; return true end,
}
local game = {
  data = { pokemon = mod.content.pokemon.data, moves = mod.content.moves.data },
  save = {
    version = "gold", generation = 2,
    player = { name = "GOLD", id = 12345, money = 3000, badges = {}, kantoBadges = {} },
    inventory = {}, pcItems = {}, party = {}, boxes = {}, currentBox = 14,
    pokedex = { seen = {}, caught = {} },
  },
  world = world,
  stack = { clear = function(self) self.cleared = true end },
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

-- Instant force evolve still goes through the Gen2 Evolution module and mutates live record.
local original = game.save.party[1]
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
