-- Gen2 Gold Cheat Menu
-- API v2 Gold/Gen2 mod for bryanthaboi/gen1recomp.
--
-- UI is built through the public mod API, while state-changing cheats bind to
-- Gold's live engine modules/save shape. This is intentional: Gen2 has its own
-- Game2/World/Battle/save implementation, so Gen1 command/save shims are not
-- used for engine-level mutations.

local SCREEN = "Gen2CheatMenu"
local SCREEN_POKEMON = "Gen2CheatPokemonPicker"
local SCREEN_LEVEL = "Gen2CheatPokemonLevel"
local SCREEN_DEST = "Gen2CheatPokemonDestination"
local SCREEN_EVOLVE_SOURCE = "Gen2CheatEvolutionSource"
local SCREEN_EVOLVE_PARTY = "Gen2CheatEvolutionParty"
local SCREEN_EVOLVE_PC = "Gen2CheatEvolutionPC"
local SCREEN_EVOLVE_TARGET = "Gen2CheatEvolutionTarget"
local SCREEN_TELEPORT = "Gen2CheatTeleport"
local SCREEN_POKEMON_TOOLS = "Gen2CheatPokemonTools"
local SCREEN_WORLD_TOOLS = "Gen2CheatWorldTools"
local SCREEN_PLAYER_TOOLS = "Gen2CheatPlayerTools"
local SCREEN_ITEM_TOOLS = "Gen2CheatItemTools"
local SCREEN_POKEDEX_TOOLS = "Gen2CheatPokedexTools"
local SCREEN_BATTLE_TOOLS = "Gen2CheatBattleTools"
local SCREEN_QUANTITY = "Gen2CheatQuantity"
local SCREEN_ITEM_PICKER = "Gen2CheatItemPicker"

return function(mod)
  -- Gold engine modules. The manifest requests engine_internals so these are
  -- the same implementations Game2 uses, not text/UI stand-ins.
  local Gen2Mon = require("src.battle.gen2.Mon")
  local Gen2Boxes = require("src.core.gen2.Boxes")
  local Gen2Evolution = require("src.core.gen2.Evolution")
  local Gen2FieldMoves = require("src.world.gen2.FieldMoves")

  local BOX_COUNT = Gen2Boxes.NUM_BOXES or 14
  local BOX_CAPACITY = Gen2Boxes.MONS_PER_BOX or 20

  local function worldOf(game)
    return game and (game.world or game.overworld) or nil
  end

  -- Shared battle hooks keep Gen1 names, but Gold's user/target/attacker
  -- values are the party-mon tables themselves rather than Gen1 battler
  -- wrappers. Resolve either shape so the toggle is genuinely active in Gold.
  local function playerSide(ctx, battler)
    if type(battler) ~= "table" then return nil end
    if battler.isPlayer ~= nil then return battler.isPlayer and true or false end
    local battle = ctx and ctx.battle
    if battle then
      if battler == battle.player then return true end
      if battler == battle.enemy then return false end
    end
    return nil
  end

  -- Session-only toggles intentionally reset to OFF on a fresh launch.
  local session = {
    noWild = false,
    guaranteedCatch = false,
    alwaysHit = false,
    alwaysCrit = false,
    alwaysEscape = false,
    alwaysFirst = false,
    oneHitKO = false,
    noEnemyDamage = false,
    walkThroughWalls = false,
    turboMovement = false,
    expMultiplier = 1,
  }
  local liveGame = nil
  -- ---------- small public-data helpers

  local function registryGet(registry, id)
    if type(registry) ~= "table" or type(registry.get) ~= "function" then
      return nil
    end
    local ok, value = pcall(registry.get, registry, id)
    if ok then return value end
    return nil
  end

  local function ensureSave(game)
    if not (game and type(game.save) == "table") then return nil end
    local save = game.save
    save.player = type(save.player) == "table" and save.player or {}
    save.player.badges = type(save.player.badges) == "table" and save.player.badges or {}
    save.player.kantoBadges = type(save.player.kantoBadges) == "table" and save.player.kantoBadges or {}
    save.inventory = type(save.inventory) == "table" and save.inventory or {}
    save.pcItems = type(save.pcItems) == "table" and save.pcItems or {}
    save.party = type(save.party) == "table" and save.party or {}
    save.boxes = type(save.boxes) == "table" and save.boxes or {}
    save.currentBox = math.max(1, math.min(BOX_COUNT, tonumber(save.currentBox) or 1))
    save.pokedex = type(save.pokedex) == "table" and save.pokedex or {}
    save.pokedex.seen = type(save.pokedex.seen) == "table" and save.pokedex.seen or {}
    save.pokedex.caught = type(save.pokedex.caught) == "table" and save.pokedex.caught or {}
    return save
  end

  local function ensureBoxes(save)
    if not save then return {} end
    save.boxes = type(save.boxes) == "table" and save.boxes or {}
    for i = 1, BOX_COUNT do
      if type(save.boxes[i]) ~= "table" then save.boxes[i] = {} end
    end
    save.currentBox = math.max(1, math.min(BOX_COUNT, tonumber(save.currentBox) or 1))
    return save.boxes
  end

  local function findFreeBox(save)
    local boxes = ensureBoxes(save)
    for off = 0, BOX_COUNT - 1 do
      local i = ((save.currentBox - 1 + off) % BOX_COUNT) + 1
      if #boxes[i] < BOX_CAPACITY then return i end
    end
    return nil
  end

  local function depositExactBox(save, boxNum, mon)
    if not (save and boxNum and mon) then return false end
    local box = Gen2Boxes.box(save, boxNum)
    if type(box) ~= "table" or #box >= BOX_CAPACITY then return false end
    box[#box + 1] = mon
    return true
  end

  local function isBadge(id)
    return type(id) == "string" and id:find("BADGE", 1, true) ~= nil
  end

  local function bagCapacity()
    local configured = registryGet(mod.content.constants, "bagSize")
    if type(configured) == "number" and configured >= 1 then
      return math.floor(configured)
    end
    return 20
  end

  local function bagSlots(save)
    local n = 0
    for id in pairs(save.inventory or {}) do
      if not isBadge(id) then n = n + 1 end
    end
    return n
  end

  local function ensureBagOrder(save)
    if type(save.bagOrder) == "table" then return save.bagOrder end
    local order = {}
    for id in pairs(save.inventory or {}) do
      if not isBadge(id) then order[#order + 1] = id end
    end
    table.sort(order)
    save.bagOrder = order
    return order
  end

  local function appendBagOrder(save, id)
    local order = ensureBagOrder(save)
    for _, existing in ipairs(order) do
      if existing == id then return end
    end
    order[#order + 1] = id
  end

  local function setItemCount(game, id, count)
    local save = ensureSave(game)
    if not save then return false, "NO SAVE" end
    if registryGet(mod.content.items, id) == nil then return false, "N/A" end
    count = math.max(1, math.min(99, math.floor(tonumber(count) or 1)))
    -- Gold keeps one live id->count inventory. PackMenu derives ITEM/BALL/KEY/TM
    -- pockets from the item's extracted attributes when it draws.
    save.inventory[id] = count
    return true, tostring(count)
  end

  local function setItem99(game, id)
    return setItemCount(game, id, 99)
  end

  local function setGroupCount(game, ids, count)
    local changed = 0
    for _, id in ipairs(ids) do
      local ok = setItemCount(game, id, count)
      if ok then changed = changed + 1 end
    end
    if changed == 0 then return false, "N/A" end
    return true, tostring(math.max(1, math.min(99, math.floor(tonumber(count) or 1))))
  end

  -- Kept as a public/backward-compatible helper for mods that used v1.x exports.
  local function setGroup99(game, ids)
    return setGroupCount(game, ids, 99)
  end

  local function itemStatus(game, id)
    local save = ensureSave(game)
    if not save then return "--" end
    if registryGet(mod.content.items, id) == nil then return "N/A" end
    return tostring(tonumber(save.inventory[id]) or 0)
  end

  local function currentItemCount(game, id)
    local save = ensureSave(game)
    if not save then return 0 end
    return tonumber(save.inventory[id]) or 0
  end

  local function groupStatus(game, ids)
    local first, registered = nil, 0
    for _, id in ipairs(ids) do
      if registryGet(mod.content.items, id) ~= nil then
        registered = registered + 1
        local n = currentItemCount(game, id)
        if first == nil then first = n elseif first ~= n then return "MIX" end
      end
    end
    if registered == 0 then return "N/A" end
    return tostring(first or 0)
  end

  local function quantityStartFromStatus(game, status)
    if type(status) ~= "function" then return 1 end
    local ok, value = pcall(status, game)
    if not ok then return 1 end
    local n = tostring(value or ""):match("(%d+)")
    n = tonumber(n) or 1
    return math.max(1, math.min(99, math.floor(n)))
  end

  local function itemDisplayName(id, def)
    local name = type(def) == "table" and (def.name or def.label) or nil
    return tostring(name or id):gsub("_", " ")
  end

  local function isRealItemRecord(id, def)
    -- Gold's data.items table also carries metadata keys such as generation,
    -- source and pockets. Registry:each() exposes those base keys too, so an
    -- item picker must only treat actual extracted item records as items.
    return type(id) == "string"
      and type(def) == "table"
      and type(def.id) == "string"
      and def.id == id
  end

  local function speciesName(game, id)
    local def = game and game.data and game.data.pokemon and game.data.pokemon[id]
    if not def then def = registryGet(mod.content.pokemon, id) end
    return (def and def.name) or tostring(id)
  end

  -- ---------- cheats

  local function maxMoney(game)
    local save = ensureSave(game)
    if not save then return false, "NO SAVE" end
    local cap = registryGet(mod.content.constants, "moneyCap")
    if type(cap) ~= "number" then cap = 999999 end
    save.player.money = math.max(0, math.floor(cap))
    return true, tostring(save.player.money)
  end

  local function moneyStatus(game)
    local save = ensureSave(game)
    if not save then return "--" end
    return tostring(math.floor(tonumber(save.player.money) or 0))
  end

  local function healMon(mon)
    if type(mon) ~= "table" then return false end
    local maxHp = tonumber(mon.maxHp) or (type(mon.stats) == "table" and tonumber(mon.stats.hp))
    if maxHp then mon.hp = maxHp end
    mon.status = nil
    if type(mon.moves) == "table" then
      for _, move in ipairs(mon.moves) do
        if type(move) == "table" then
          local def = registryGet(mod.content.moves, move.id)
          if tonumber(move.maxPp) then
            move.pp = tonumber(move.maxPp)
          elseif type(def) == "table" and type(def.pp) == "number" then
            local ups = math.max(0, math.floor(tonumber(move.ppUps) or 0))
            move.pp = def.pp + ups * math.floor(def.pp / 5)
          end
        end
      end
    end
    return true
  end

  local function healParty(game)
    local save = ensureSave(game)
    if not save then return false, "NO SAVE" end
    local healed = 0
    for _, mon in ipairs(save.party) do
      if healMon(mon) then healed = healed + 1 end
    end
    return true, tostring(healed)
  end

  local function healPC(game)
    local save = ensureSave(game)
    if not save then return false, "NO SAVE" end
    local healed = 0
    for _, box in ipairs(ensureBoxes(save)) do
      for _, mon in ipairs(box) do
        if healMon(mon) then healed = healed + 1 end
      end
    end
    return true, tostring(healed)
  end

  local function partyStatus(game)
    local save = ensureSave(game)
    return save and ("%d/6"):format(#save.party) or "--"
  end

  local JOHTO_BADGES = Gen2FieldMoves.JOHTO_BADGES or {
    "ZEPHYR", "HIVE", "PLAIN", "FOG", "MINERAL", "STORM", "GLACIER", "RISING",
  }
  local KANTO_BADGES = Gen2FieldMoves.KANTO_BADGES or {
    "BOULDER", "CASCADE", "THUNDER", "RAINBOW", "SOUL", "MARSH", "VOLCANO", "EARTH",
  }

  local function badgeCounts(game)
    local save = ensureSave(game)
    if not save then return 0, 16 end
    local have = 0
    for _, name in ipairs(JOHTO_BADGES) do if save.player.badges[name] then have = have + 1 end end
    for _, name in ipairs(KANTO_BADGES) do if save.player.kantoBadges[name] then have = have + 1 end end
    return have, #JOHTO_BADGES + #KANTO_BADGES
  end

  local function allBadges(game)
    local save = ensureSave(game)
    if not save then return false, "NO SAVE" end
    for _, name in ipairs(JOHTO_BADGES) do save.player.badges[name] = true end
    for _, name in ipairs(KANTO_BADGES) do save.player.kantoBadges[name] = true end
    return true, tostring(#JOHTO_BADGES + #KANTO_BADGES)
  end

  local function badgeStatus(game)
    local have, total = badgeCounts(game)
    return ("%d/%d"):format(have, total)
  end

  local function dexCounts(game)
    local save = ensureSave(game)
    if not save then return 0, 0, 0 end
    local seen, owned, total = 0, 0, 0
    for id in mod.content.pokemon:each() do
      total = total + 1
      if save.pokedex.seen[id] then seen = seen + 1 end
      if save.pokedex.caught[id] then owned = owned + 1 end
    end
    return seen, owned, total
  end

  local function seeAllDex(game)
    local save = ensureSave(game)
    if not save then return false, "NO SAVE" end
    local n = 0
    for id in mod.content.pokemon:each() do
      save.pokedex.seen[id] = true
      n = n + 1
    end
    return true, tostring(n)
  end

  local function completeDex(game)
    local save = ensureSave(game)
    if not save then return false, "NO SAVE" end
    local n = 0
    for id in mod.content.pokemon:each() do
      save.pokedex.seen[id] = true
      save.pokedex.caught[id] = true
      n = n + 1
    end
    return true, tostring(n)
  end

  local function seenStatus(game)
    local seen, _, total = dexCounts(game)
    return ("%d/%d"):format(seen, total)
  end

  local function ownedStatus(game)
    local _, owned, total = dexCounts(game)
    return ("%d/%d"):format(owned, total)
  end

  -- ---------- Gold Pokémon creation through the engine's own Gen2 builder

  local function createPokemon(game, species, level)
    local save = ensureSave(game)
    if not save then return nil, "NO SAVE" end
    level = math.max(1, math.min(100, math.floor(tonumber(level) or 5)))
    local mon = Gen2Mon.new(game and game.data, species, level)
    if not mon then return nil, "BAD SPECIES" end
    Gen2Mon.stampOT(save, mon)
    save.pokedex.seen[species] = true
    save.pokedex.caught[species] = true
    return mon
  end

  local function addPokemonToParty(game, species, level)
    local save = ensureSave(game)
    if not save then return false, "NO SAVE" end
    if #save.party >= 6 then return false, "PARTY FULL" end
    local mon, err = createPokemon(game, species, level)
    if not mon then return false, err end
    save.party[#save.party + 1] = mon
    return true, ("P%d"):format(#save.party), mon
  end

  local function addPokemonToPC(game, species, level)
    local save = ensureSave(game)
    if not save then return false, "NO SAVE" end
    local boxNum = findFreeBox(save)
    if not boxNum then return false, "PC FULL" end
    local mon, err = createPokemon(game, species, level)
    if not mon then return false, err end
    if not depositExactBox(save, boxNum, mon) then return false, "PC FULL" end
    return true, ("BOX %d"):format(boxNum), mon
  end

  -- ---------- grouped item cheats

  local BALLS = { "MASTER_BALL", "ULTRA_BALL", "GREAT_BALL", "POKE_BALL" }
  local STONES = { "MOON_STONE", "FIRE_STONE", "THUNDER_STONE", "WATER_STONE", "LEAF_STONE", "SUN_STONE" }
  local MEDICINE = {
    "FULL_RESTORE", "MAX_POTION", "HYPER_POTION", "SUPER_POTION", "POTION",
    "MAX_REVIVE", "REVIVE", "FULL_HEAL", "ANTIDOTE", "BURN_HEAL",
    "ICE_HEAL", "AWAKENING", "PARLYZ_HEAL",
  }
  local FIELD_SUPPLIES = { "ESCAPE_ROPE", "REPEL", "SUPER_REPEL", "MAX_REPEL" }
  local VITAMINS = { "HP_UP", "PROTEIN", "IRON", "CARBOS", "CALCIUM" }
  local BATTLE_ITEMS = {
    "X_ACCURACY", "GUARD_SPEC", "DIRE_HIT", "X_ATTACK", "X_DEFEND",
    "X_SPEED", "X_SPECIAL",
  }
  -- Pokered calls these ELIXER/MAX_ELIXER; alternate spellings make this
  -- friendly to content packs that normalize the names. Unknown IDs skip.
  local PP_ITEMS = { "ETHER", "MAX_ETHER", "ELIXER", "MAX_ELIXER", "ELIXIR", "MAX_ELIXIR" }
  local TREASURE = { "NUGGET", "PEARL", "BIG_PEARL", "STARDUST", "STAR_PIECE" }

  local function machineIds(prefix)
    local out = {}
    for id in mod.content.items:each() do
      local text = tostring(id)
      if text:match("^" .. prefix .. "_?%d+") then out[#out + 1] = id end
    end
    table.sort(out)
    return out
  end

  local function setMachines(game, prefix, count)
    local changed = 0
    for _, id in ipairs(machineIds(prefix)) do
      local ok = setItemCount(game, id, count)
      if ok then changed = changed + 1 end
    end
    if changed == 0 then return false, "N/A" end
    return true, tostring(math.max(1, math.min(99, math.floor(tonumber(count) or 1))))
  end

  local function flagStatus(key)
    return session[key] and "ON" or "OFF"
  end

  local function toggleFlag(key, game)
    session[key] = not session[key]
    if game then liveGame = game end
    return true, flagStatus(key)
  end

  local function toggleNoWild(game) return toggleFlag("noWild", game) end
  local function noWildStatus() return flagStatus("noWild") end
  local function toggleGuaranteedCatch(game) return toggleFlag("guaranteedCatch", game) end
  local function toggleAlwaysHit(game) return toggleFlag("alwaysHit", game) end
  local function toggleAlwaysCrit(game) return toggleFlag("alwaysCrit", game) end
  local function toggleAlwaysEscape(game) return toggleFlag("alwaysEscape", game) end
  local function toggleAlwaysFirst(game) return toggleFlag("alwaysFirst", game) end
  local function toggleOneHitKO(game) return toggleFlag("oneHitKO", game) end
  local function toggleNoEnemyDamage(game) return toggleFlag("noEnemyDamage", game) end
  local function toggleWalkThroughWalls(game) return toggleFlag("walkThroughWalls", game) end
  local function toggleTurboMovement(game) return toggleFlag("turboMovement", game) end

  local function setExpMultiplier(_, amount)
    amount = math.max(1, math.min(10, math.floor(tonumber(amount) or 1)))
    session.expMultiplier = amount
    return true, "x" .. tostring(amount)
  end

  local function expStatus() return "x" .. tostring(session.expMultiplier) end

  -- Public exports make the same safe actions callable by another mod.
  mod.exports.maxMoney = maxMoney
  mod.exports.healParty = healParty
  mod.exports.setItem99 = setItem99
  mod.exports.allBadges = allBadges
  mod.exports.seeAllDex = seeAllDex
  mod.exports.completeDex = completeDex
  mod.exports.addPokemonToParty = addPokemonToParty
  mod.exports.addPokemonToPC = addPokemonToPC
  mod.exports.healPC = healPC
  mod.exports.toggleNoWild = toggleNoWild
  mod.exports.setItemCount = setItemCount
  mod.exports.setGroupCount = setGroupCount
  mod.exports.toggleGuaranteedCatch = toggleGuaranteedCatch
  mod.exports.toggleAlwaysHit = toggleAlwaysHit
  mod.exports.toggleAlwaysCrit = toggleAlwaysCrit
  mod.exports.toggleAlwaysEscape = toggleAlwaysEscape
  mod.exports.toggleAlwaysFirst = toggleAlwaysFirst
  mod.exports.toggleOneHitKO = toggleOneHitKO
  mod.exports.toggleNoEnemyDamage = toggleNoEnemyDamage
  mod.exports.toggleWalkThroughWalls = toggleWalkThroughWalls
  mod.exports.toggleTurboMovement = toggleTurboMovement
  mod.exports.setExpMultiplier = setExpMultiplier

  -- ---------- UI helpers

  local function push(game, id, ...)
    return mod.ui.push(game, id, ...)
  end

  local function speciesRows(game)
    local rows = {}
    for id, def in mod.content.pokemon:each() do
      rows[#rows + 1] = {
        label = (def and def.name) or tostring(id),
        value = id,
      }
    end
    table.sort(rows, function(a, b)
      local al, bl = tostring(a.label):upper(), tostring(b.label):upper()
      if al == bl then return tostring(a.value) < tostring(b.value) end
      return al < bl
    end)
    return rows
  end

  local function monLabel(game, mon, prefix)
    local name = mon.nickname or speciesName(game, mon.species)
    return prefix and (prefix .. " " .. name) or name
  end

  local function evolutionDef(game, mon)
    return game.data and game.data.pokemon and game.data.pokemon[mon.species]
  end

  local function evolutionTarget(evo)
    return evo and (evo.into or evo.species) or nil
  end

  local function evoRight(game, evo)
    local method = tostring(evo.method or "EVOLVE")
    if method == "EVOLVE_LEVEL" or method == "LEVEL" then return "L" .. tostring(evo.level or "?") end
    if method == "EVOLVE_ITEM" or method == "ITEM" then return tostring(evo.item or "ITEM"):gsub("_", " ") end
    if method == "EVOLVE_TRADE" or method == "TRADE" then return "TRADE" end
    if method == "EVOLVE_HAPPINESS" then return "HAPPY" end
    if method == "EVOLVE_STAT" then return "STATS" end
    return method:gsub("^EVOLVE_", "")
  end

  local function forceEvolve(game, mon, evo)
    local save = ensureSave(game)
    local target = evolutionTarget(evo)
    if not (save and mon and target) then return false, "N/A" end
    local evolved = Gen2Evolution.apply(game.data, mon, evo)
    if not evolved then return false, "FAILED" end
    Gen2Mon.stampOT(save, evolved)
    Gen2Evolution.markPokedex(save, evolved.species)
    -- Preserve references held by an open party/PC menu: replace the live
    -- record in place with the engine-built evolved record.
    for key in pairs(mon) do mon[key] = nil end
    for key, value in pairs(evolved) do mon[key] = value end
    return true, speciesName(game, mon.species)
  end

  mod.exports.forceEvolve = forceEvolve

  local function closeEvolutionMenus(game)
    local closable = {
      [SCREEN_EVOLVE_TARGET] = true,
      [SCREEN_EVOLVE_PARTY] = true,
      [SCREEN_EVOLVE_PC] = true,
    }
    if not (game and game.stack and game.stack.top and game.stack.pop) then return end
    for _ = 1, 3 do
      local top = game.stack:top()
      if not top or not closable[top.screenId] then break end
      game.stack:pop()
    end
  end

  -- Native cheat-menu helper. Every cheat/category screen uses the recomp's
  -- public ListMenu so it keeps the same modern rendering, scrolling, sounds,
  -- theme hooks, and controller behavior as the rest of the game.
  local function newNativeCheatMenu(game, title, items, footer)
    local function refresh()
      for _, item in ipairs(items) do
        if type(item.status) == "function" then
          local ok, value = pcall(item.status, game)
          item.right = ok and tostring(value or "") or "ERR"
        end
      end
    end

    refresh()
    return mod.ui.ListMenu.new(game, title, items, {
      wrap = true,
      pageJump = true,
      keyRepeat = true,
      footer = footer or "A: OPEN/USE  B: BACK",
      onChoose = function(item)
        if not item then return end
        if item.nav then
          push(game, item.nav)
          return
        end
        if type(item.quantity) == "function" then
          local max = math.max(1, math.floor(tonumber(item.quantityMax) or 99))
          local start = item.quantityStart
          if type(start) == "function" then
            local okStart, value = pcall(start, game)
            start = okStart and value or 1
          elseif start == nil then
            start = quantityStartFromStatus(game, item.status)
          end
          start = math.max(1, math.min(max, math.floor(tonumber(start) or 1)))
          push(game, SCREEN_QUANTITY, item, item.quantity, max, start)
          return
        end
        if type(item.action) ~= "function" then return end
        local ok, success, result = pcall(item.action, game)
        if not ok then
          item.right = "ERR"
          return
        end
        if success == false then
          item.right = tostring(result or "N/A")
          return
        end
        refresh()
      end,
    })
  end

  local function teleportRows(game)
    local rows = {
      { label = "LAST HEAL", value = { kind = "heal" }, right = "SAFE" },
    }
    local world = worldOf(game)
    local currentMap = world and world.map and world.map.id
    local landmarks = world and world.landmarks and world.landmarks.landmarks or {}
    for _, point in ipairs(Gen2FieldMoves.FLYPOINTS or {}) do
      local landmark = point.landmark and landmarks[point.landmark]
      local label = (landmark and landmark.name) or point.landmark or point.spawn
      label = tostring(label or "FLY POINT"):gsub("^LANDMARK_", ""):gsub("_", " ")
      rows[#rows + 1] = {
        label = label,
        right = (point.map and point.map == currentMap) and "HERE" or nil,
        value = { kind = "fly", spawn = point.spawn },
      }
    end
    return rows
  end

  local function leaveMenusForWorld(game)
    -- Gold's World is persistent at game.world rather than a stack state, so
    -- clearing menus does not destroy the live overworld object.
    local stack = game and game.stack
    if stack and type(stack.clear) == "function" then stack:clear() end
  end

  local function teleportTo(game, dest)
    local world = worldOf(game)
    if not world then return false, "NO WORLD" end
    if type(dest) ~= "table" then return false, "BAD WARP" end
    leaveMenusForWorld(game)
    if dest.kind == "heal" then
      if type(world.warpToSpawn) ~= "function" then return false, "N/A" end
      world:warpToSpawn()
      return true, "WARP"
    end
    if dest.kind == "fly" then
      if type(world.flyTo) ~= "function" or not dest.spawn then return false, "N/A" end
      local ok = world:flyTo(dest.spawn)
      if ok == false then return false, world.status or "FAILED" end
      return true, "WARP"
    end
    return false, "BAD WARP"
  end

  mod.exports.teleportTo = teleportTo

  -- ---------- registered screens

  -- Shared native quantity picker. Item cheats use 1..99; other cheats may
  -- supply a smaller max (EXP multiplier uses 1..10).
  mod.content.screens:register(SCREEN_QUANTITY, {
    new = function(game, row, apply, max, start)
      return mod.ui.QuantityBox.new(game, {
        max = max or 99,
        start = start or 1,
        onDone = function(qty)
          if qty == nil or type(apply) ~= "function" then return end
          local ok, success, result = pcall(apply, game, qty)
          if not ok then
            if row then row.right = "ERR" end
            return
          end
          if row then
            if success == false then row.right = tostring(result or "N/A")
            else row.right = tostring(result or qty) end
          end
        end,
      })
    end,
  })

  mod.content.screens:register(SCREEN_ITEM_PICKER, {
    new = function(game)
      local rows = {}
      for id, def in mod.content.items:each() do
        if isRealItemRecord(id, def) and not isBadge(id) then
          rows[#rows + 1] = {
            label = itemDisplayName(id, def),
            right = itemStatus(game, id),
            value = id,
          }
        end
      end
      table.sort(rows, function(a, b)
        local al, bl = tostring(a.label):upper(), tostring(b.label):upper()
        if al == bl then return tostring(a.value) < tostring(b.value) end
        return al < bl
      end)
      return mod.ui.ListMenu.new(game, "ANY ITEM", rows, {
        wrap = true, pageJump = true, keyRepeat = true,
        footer = "A: QTY  B: BACK",
        onChoose = function(item)
          if not (item and item.value) then return end
          local id = item.value
          local start = math.max(1, currentItemCount(game, id))
          push(game, SCREEN_QUANTITY, item,
            function(g, qty) return setItemCount(g, id, qty) end, 99, start)
        end,
      })
    end,
  })

  mod.content.screens:register(SCREEN_POKEMON, {
    new = function(game)
      local rows = speciesRows(game)
      return mod.ui.ListMenu.new(game, "ADD POKEMON", rows, {
        pageJump = true, wrap = true, keyRepeat = true,
        footer = "A: PICK  B: BACK",
        onChoose = function(item)
          if item and item.value then push(game, SCREEN_LEVEL, item.value) end
        end,
      })
    end,
  })

  mod.content.screens:register(SCREEN_LEVEL, {
    new = function(game, species)
      return mod.ui.QuantityBox.new(game, {
        max = 100,
        start = 5,
        onDone = function(level)
          if level then push(game, SCREEN_DEST, species, level) end
        end,
      })
    end,
  })

  mod.content.screens:register(SCREEN_DEST, {
    new = function(game, species, level)
      local rows = {
        { label = "ADD TO PARTY", value = "party" },
        { label = "ADD TO PC", value = "pc" },
      }
      return mod.ui.ListMenu.new(game,
        ("%s L%d"):format(speciesName(game, species), level), rows, {
          wrap = true,
          footer = "A: ADD  B: BACK",
          onChoose = function(item)
            if not item then return end
            local ok, result
            if item.value == "party" then
              ok, result = addPokemonToParty(game, species, level)
            else
              ok, result = addPokemonToPC(game, species, level)
            end
            item.right = ok and tostring(result or "OK") or tostring(result or "ERR")
          end,
        })
    end,
  })

  mod.content.screens:register(SCREEN_EVOLVE_SOURCE, {
    new = function(game)
      return mod.ui.ListMenu.new(game, "EVOLVE POKEMON", {
        { label = "PARTY POKEMON", value = "party" },
        { label = "PC POKEMON", value = "pc" },
      }, {
        wrap = true,
        footer = "A: OPEN  B: BACK",
        onChoose = function(item)
          if item.value == "party" then push(game, SCREEN_EVOLVE_PARTY)
          elseif item.value == "pc" then push(game, SCREEN_EVOLVE_PC) end
        end,
      })
    end,
  })

  mod.content.screens:register(SCREEN_EVOLVE_PARTY, {
    new = function(game)
      local save = ensureSave(game)
      local rows = {}
      for i, mon in ipairs(save and save.party or {}) do
        rows[#rows + 1] = {
          label = monLabel(game, mon, tostring(i) .. "."),
          right = "L" .. tostring(mon.level or "?"),
          value = mon,
        }
      end
      return mod.ui.ListMenu.new(game, "EVOLVE PARTY", rows, {
        wrap = true, pageJump = true,
        footer = "A: PICK  B: BACK",
        onChoose = function(item)
          local mon = item and item.value
          if not mon then return end
          local def = evolutionDef(game, mon)
          if not def or type(def.evolutions) ~= "table" or #def.evolutions == 0 then
            item.right = "FINAL"
            return
          end
          push(game, SCREEN_EVOLVE_TARGET, mon)
        end,
      })
    end,
  })

  mod.content.screens:register(SCREEN_EVOLVE_PC, {
    new = function(game)
      local save = ensureSave(game)
      local boxes = save and ensureBoxes(save) or {}
      local rows = {}
      for b = 1, BOX_COUNT do
        for i, mon in ipairs(boxes[b] or {}) do
          rows[#rows + 1] = {
            label = monLabel(game, mon, ("B%d-%02d"):format(b, i)),
            right = "L" .. tostring(mon.level or "?"),
            value = mon,
          }
        end
      end
      return mod.ui.ListMenu.new(game, "EVOLVE PC", rows, {
        wrap = true, pageJump = true, keyRepeat = true,
        footer = "A: PICK  B: BACK",
        onChoose = function(item)
          local mon = item and item.value
          if not mon then return end
          local def = evolutionDef(game, mon)
          if not def or type(def.evolutions) ~= "table" or #def.evolutions == 0 then
            item.right = "FINAL"
            return
          end
          push(game, SCREEN_EVOLVE_TARGET, mon)
        end,
      })
    end,
  })

  mod.content.screens:register(SCREEN_EVOLVE_TARGET, {
    new = function(game, mon)
      local def = evolutionDef(game, mon)
      local rows = {}
      for _, evo in ipairs((def and def.evolutions) or {}) do
        rows[#rows + 1] = {
          label = speciesName(game, evolutionTarget(evo)),
          right = evoRight(game, evo),
          value = evo,
        }
      end
      return mod.ui.ListMenu.new(game, "FORCE EVOLVE TO", rows, {
        wrap = true,
        footer = "A: EVOLVE  B: BACK",
        onChoose = function(item)
          local evo = item and item.value
          if not evolutionTarget(evo) then return end
          local ok, result = forceEvolve(game, mon, evo)
          item.right = ok and "DONE" or tostring(result or "ERR")
          if ok then closeEvolutionMenus(game) end
        end,
      })
    end,
  })

  mod.content.screens:register(SCREEN_TELEPORT, {
    new = function(game)
      local rows = teleportRows(game)
      return mod.ui.ListMenu.new(game, "TELEPORT", rows, {
        wrap = true, pageJump = true, keyRepeat = true,
        footer = "A: WARP  B: BACK",
        onChoose = function(item)
          if not (item and item.value) then return end
          local ok, result = teleportTo(game, item.value)
          if not ok then item.right = tostring(result or "ERR") end
        end,
      })
    end,
  })

  -- Category row factories. The same row definitions are reused by both the
  -- focused category screens and the long main CHEAT MENU, so adding a cheat
  -- in the future cannot make one view silently drift from the other.
  local function pokemonCheatItems(game)
    return {
      { label = "ADD POKEMON", nav = SCREEN_POKEMON, status = partyStatus },
      { label = "EVOLVE POKEMON", nav = SCREEN_EVOLVE_SOURCE,
        status = function() return "FORCE" end },
      { label = "HEAL PARTY", action = healParty, status = partyStatus },
      { label = "HEAL PC BOXES", action = healPC,
        status = function() return "ALL" end },
    }
  end

  local function worldCheatItems(game)
    return {
      { label = "TELEPORT", nav = SCREEN_TELEPORT,
        status = function() return "LIST" end },
      { label = "NO WILD ENCOUNTERS", action = toggleNoWild, status = noWildStatus },
      { label = "WALK THROUGH WALLS", action = toggleWalkThroughWalls,
        status = function() return flagStatus("walkThroughWalls") end },
      { label = "4X MOVE SPEED", action = toggleTurboMovement,
        status = function() return flagStatus("turboMovement") end },
    }
  end

  local function battleCheatItems(game)
    return {
      { label = "GUARANTEED CATCH", action = toggleGuaranteedCatch,
        status = function() return flagStatus("guaranteedCatch") end },
      { label = "ALWAYS HIT", action = toggleAlwaysHit,
        status = function() return flagStatus("alwaysHit") end },
      { label = "ALWAYS CRIT", action = toggleAlwaysCrit,
        status = function() return flagStatus("alwaysCrit") end },
      { label = "ALWAYS MOVE FIRST", action = toggleAlwaysFirst,
        status = function() return flagStatus("alwaysFirst") end },
      { label = "ALWAYS ESCAPE", action = toggleAlwaysEscape,
        status = function() return flagStatus("alwaysEscape") end },
      { label = "ONE-HIT KO", action = toggleOneHitKO,
        status = function() return flagStatus("oneHitKO") end },
      { label = "NO ENEMY DAMAGE", action = toggleNoEnemyDamage,
        status = function() return flagStatus("noEnemyDamage") end },
      { label = "EXP MULTIPLIER", quantity = setExpMultiplier, quantityMax = 10,
        quantityStart = function() return session.expMultiplier end, status = expStatus },
    }
  end

  local function playerCheatItems(game)
    return {
      { label = "MAX MONEY", action = maxMoney, status = moneyStatus },
      { label = "ALL BADGES", action = allBadges, status = badgeStatus },
    }
  end

  local function itemCheatItems(game)
    local tms, hms = machineIds("TM"), machineIds("HM")
    local balls = {}
    for id, def in mod.content.items:each() do
      if type(def) == "table" and def.pocket == "BALL" then balls[#balls + 1] = id end
    end
    if #balls == 0 then balls = BALLS end
    table.sort(balls)
    return {
      { label = "ANY ITEM", nav = SCREEN_ITEM_PICKER, status = function() return "LIST" end },
      { label = "ALL TMS", quantity = function(g, q) return setMachines(g, "TM", q) end,
        status = function(g) return groupStatus(g, tms) end },
      { label = "ALL HMS", quantity = function(g, q) return setMachines(g, "HM", q) end,
        status = function(g) return groupStatus(g, hms) end },
      { label = "ALL BALLS", quantity = function(g, q) return setGroupCount(g, balls, q) end,
        status = function(g) return groupStatus(g, balls) end },
      { label = "EVO STONES", quantity = function(g, q) return setGroupCount(g, STONES, q) end,
        status = function(g) return groupStatus(g, STONES) end },
      { label = "MEDICINE", quantity = function(g, q) return setGroupCount(g, MEDICINE, q) end,
        status = function(g) return groupStatus(g, MEDICINE) end },
      { label = "FIELD ITEMS", quantity = function(g, q) return setGroupCount(g, FIELD_SUPPLIES, q) end,
        status = function(g) return groupStatus(g, FIELD_SUPPLIES) end },
      { label = "VITAMINS", quantity = function(g, q) return setGroupCount(g, VITAMINS, q) end,
        status = function(g) return groupStatus(g, VITAMINS) end },
      { label = "BATTLE ITEMS", quantity = function(g, q) return setGroupCount(g, BATTLE_ITEMS, q) end,
        status = function(g) return groupStatus(g, BATTLE_ITEMS) end },
      { label = "PP ITEMS", quantity = function(g, q) return setGroupCount(g, PP_ITEMS, q) end,
        status = function(g) return groupStatus(g, PP_ITEMS) end },
      { label = "TREASURE", quantity = function(g, q) return setGroupCount(g, TREASURE, q) end,
        status = function(g) return groupStatus(g, TREASURE) end },
      { label = "MASTER BALL", quantity = function(g, q) return setItemCount(g, "MASTER_BALL", q) end,
        status = function(g) return itemStatus(g, "MASTER_BALL") end },
      { label = "RARE CANDY", quantity = function(g, q) return setItemCount(g, "RARE_CANDY", q) end,
        status = function(g) return itemStatus(g, "RARE_CANDY") end },
      { label = "FULL RESTORE", quantity = function(g, q) return setItemCount(g, "FULL_RESTORE", q) end,
        status = function(g) return itemStatus(g, "FULL_RESTORE") end },
      { label = "MAX REVIVE", quantity = function(g, q) return setItemCount(g, "MAX_REVIVE", q) end,
        status = function(g) return itemStatus(g, "MAX_REVIVE") end },
      { label = "PP UP", quantity = function(g, q) return setItemCount(g, "PP_UP", q) end,
        status = function(g) return itemStatus(g, "PP_UP") end },
    }
  end

  local function pokedexCheatItems(game)
    return {
      { label = "SEE ALL DEX", action = seeAllDex, status = seenStatus },
      { label = "COMPLETE DEX", action = completeDex, status = ownedStatus },
    }
  end

  mod.content.screens:register(SCREEN_POKEMON_TOOLS, {
    new = function(game)
      return newNativeCheatMenu(game, "POKEMON CHEATS", pokemonCheatItems(game))
    end,
  })

  mod.content.screens:register(SCREEN_WORLD_TOOLS, {
    new = function(game)
      return newNativeCheatMenu(game, "WORLD CHEATS", worldCheatItems(game))
    end,
  })

  mod.content.screens:register(SCREEN_BATTLE_TOOLS, {
    new = function(game)
      return newNativeCheatMenu(game, "BATTLE CHEATS", battleCheatItems(game))
    end,
  })

  mod.content.screens:register(SCREEN_PLAYER_TOOLS, {
    new = function(game)
      return newNativeCheatMenu(game, "PLAYER CHEATS", playerCheatItems(game))
    end,
  })

  mod.content.screens:register(SCREEN_ITEM_TOOLS, {
    new = function(game)
      return newNativeCheatMenu(game, "ITEM CHEATS", itemCheatItems(game),
        "A: PICK QTY  B: BACK")
    end,
  })

  mod.content.screens:register(SCREEN_POKEDEX_TOOLS, {
    new = function(game)
      return newNativeCheatMenu(game, "POKEDEX CHEATS", pokedexCheatItems(game))
    end,
  })

  -- Keep the root menu compact and fully native. Each category opens its own
  -- scrolling ListMenu, which avoids a huge flat root while preserving the
  -- modern Gen1Recomp look and input behavior.
  mod.content.screens:register(SCREEN, {
    new = function(game)
      local items = {
        { label = "POKEMON", nav = SCREEN_POKEMON_TOOLS },
        { label = "WORLD", nav = SCREEN_WORLD_TOOLS },
        { label = "BATTLE", nav = SCREEN_BATTLE_TOOLS },
        { label = "PLAYER", nav = SCREEN_PLAYER_TOOLS },
        { label = "ITEMS", nav = SCREEN_ITEM_TOOLS },
        { label = "POKEDEX", nav = SCREEN_POKEDEX_TOOLS },
      }
      return newNativeCheatMenu(game, "CHEAT MENU", items, "A: OPEN  B: BACK")
    end,
  })

  -- ---------- public runtime cheat hooks

  mod.hooks:wrap("encounter.roll", function(next, encDef, ctx)
    if session.noWild then return nil end
    return next(encDef, ctx)
  end)

  mod.hooks:wrap("catch.rate", function(next, ball, mon, def, opts)
    if session.guaranteedCatch then return true, 3 end
    return next(ball, mon, def, opts)
  end)

  mod.hooks:wrap("battle.accuracy", function(next, ctx)
    if session.alwaysHit and playerSide(ctx, ctx and ctx.user) == true then return true end
    return next(ctx)
  end)

  mod.hooks:wrap("battle.crit", function(next, ctx)
    if session.alwaysCrit and playerSide(ctx, ctx and ctx.attacker) == true then return true end
    return next(ctx)
  end)

  mod.hooks:wrap("battle.turn_order", function(next, playerBattler, playerMove, enemyBattler, enemyMove, ctx)
    if session.alwaysFirst then return true end
    return next(playerBattler, playerMove, enemyBattler, enemyMove, ctx)
  end)

  mod.hooks:wrap("battle.run", function(next, ctx)
    if session.alwaysEscape then return true end
    return next(ctx)
  end)

  mod.hooks:wrap("battle.damage", function(next, ctx)
    local damage, info = next(ctx)
    damage = tonumber(damage) or 0
    local side = playerSide(ctx, ctx and ctx.user)
    if session.noEnemyDamage and side == false then
      damage = 0
    elseif session.oneHitKO and side == true then
      local target = ctx and ctx.target
      local hp = target and (tonumber(target.hp)
        or (target.mon and tonumber(target.mon.hp)))
      if hp then damage = math.max(damage, hp) end
    end
    return math.max(0, math.floor(damage)), info
  end)

  mod.hooks:wrap("exp.gain", function(next, ctx)
    local amount = tonumber(next(ctx)) or 0
    return math.max(0, math.floor(amount * (session.expMultiplier or 1)))
  end)

  mod.hooks:wrap("movement.collision", function(next, allowed, ctx)
    allowed = next(allowed, ctx)
    local world = worldOf(liveGame)
    if session.walkThroughWalls and world
       and ctx and ctx.mover == world.player and ctx.reason ~= "bounds" then
      ctx.reason = "cheat"
      return true
    end
    return allowed
  end)

  mod.hooks:wrap("movement.speed", function(next, frames, ctx)
    frames = tonumber(next(frames, ctx)) or 16
    if session.turboMovement then return math.max(1, math.floor(frames / 4)) end
    return frames
  end)

  -- The screen shown by START/Escape is src/ui/StartMenu.lua. It runs the
  -- documented ui.start_menu.items hook after it has built all native rows.
  -- Use a high hook priority, call next() first, and decorate the final list so
  -- lower-priority menu mods (including a MOD MENUS provider) cannot erase us.
  -- This gives the requested order: MOD MENUS -> Cheat Menu -> MODS.
  mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
    liveGame = game or liveGame
    local out = next(game, items)
    if type(out) ~= "table" then return out end

    -- Defensive de-dupe for upgrades/hot reloads and older builds of this mod.
    local clean = {}
    for _, row in ipairs(out) do
      local label = type(row) == "table" and row.label or nil
      if label ~= "CHEATS" and label ~= "Cheat Menu" then
        clean[#clean + 1] = row
      end
    end

    local cheatRow = {
      label = "Cheat Menu",
      onSelect = function() push(game, SCREEN) end,
    }

    local decorated, inserted = {}, false
    for _, row in ipairs(clean) do
      local label = type(row) == "table" and row.label or nil
      if not inserted and label == "MODS" then
        decorated[#decorated + 1] = cheatRow
        inserted = true
      end
      decorated[#decorated + 1] = row
    end

    -- MODS can be hidden on unusual/minimal builds. In that case, keep the
    -- shortcut on the main START menu immediately before QUIT instead.
    if not inserted then
      decorated = {}
      for _, row in ipairs(clean) do
        local label = type(row) == "table" and row.label or nil
        if not inserted and label == "QUIT" then
          decorated[#decorated + 1] = cheatRow
          inserted = true
        end
        decorated[#decorated + 1] = row
      end
      if not inserted then decorated[#decorated + 1] = cheatRow end
    end

    return decorated
  end, 10000)
end
