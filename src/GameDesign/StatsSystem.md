# 📊 ALLY STATS SYSTEM: STRENGTH / SPEED / LUCK
## Full DNA-based progression for Roblox Studio

---

## 1. OVERVIEW

Each NPC ally has **3 stats**:

| Stat | What It Affects | Scale |
|---|---|---|
| 💪 **Strength** | Fist damage (when ally has no weapon equipped) | 10–200 |
| ⚡ **Speed** | Resource gathering time (in farm mode) | 10–200 |
| 🎲 **Luck** | Fishing time + rare catch chance | 10–200 |

**Universal scale 10–200** for all stats and all NPC types. Different NPCs have different **base values** — Pirate starts at 10, Prototype at 165–180.

---

## 2. UNIVERSAL FORMULAS (stat → effect)

### 💪 Strength → Fist Damage:
```
fist_damage = 5 + (strength - 10) * 0.5
```
| Strength | Fist Damage |
|---|---|
| 10 | 5 |
| 50 | 25 |
| 100 | 50 |
| 150 | 75 |
| 200 | 100 |

### ⚡ Speed → Resource Gather Time (seconds):
```
gather_time = 15 - (speed - 10) * 11/190
```
| Speed | Gather Time |
|---|---|
| 10 | 15.0 sec |
| 45 | 13.0 sec |
| 62 | 12.0 sec |
| 96 | 10.0 sec |
| 131 | 8.0 sec |
| 165 | 6.0 sec |
| 200 | 4.0 sec |

### 🎲 Luck → Fishing Time + Rare Catch Chance:
```
fishing_time = 15 - (luck - 10) * 11/190
rare_catch_chance = (luck / 200) * 0.35  -- 0%–35%
```
| Luck | Fishing Time | Rare Catch Chance |
|---|---|---|
| 10 | 15.0 sec | 1.75% |
| 50 | 12.7 sec | 8.75% |
| 100 | 9.8 sec | 17.5% |
| 150 | 6.9 sec | 26.25% |
| 200 | 4.0 sec | 35% |

**Rare catch** isn't normal fish — it's a **bonus**: sometimes a small chest, sometimes a rare component (washer, gear), sometimes a unique mutant fish (used to craft bio-weapons).

---

## 3. BASE VALUES PER NPC (Level 1, no upgrades)

| NPC | Strength | Speed | Luck | Fist Dmg | Gather Time | Fishing Time |
|---|---|---|---|---|---|---|
| 🏴‍☠️ **Pirate** | 10 | 10 | 10 | 5 | 15.0 sec | 15.0 sec |
| 🔫 **Marauder** | 30 | 62 | 35 | 15 | 12.0 sec | 13.6 sec |
| 🦠 **Mutant** | 80 | 96 | 50 | 40 | 10.0 sec | 12.7 sec |
| 🪖 **Military** | 110 | 131 | 75 | 55 | 8.0 sec | 11.2 sec |
| 🤖 **Prototype** | 180 | 165 | 130 | 90 | 6.0 sec | 7.6 sec |

### Principle: each higher tier NPC is stronger across ALL stats than lower tier.
- Prototype even WITHOUT upgrades gathers faster than fully upgraded Pirate.
- This means: **no point grinding Pirate too long** — better to find next NPC type.

---

## 4. MAX VALUES (Level 10, fully upgraded)

| NPC | Strength | Speed | Luck | Fist Dmg | Gather Time | Fishing Time |
|---|---|---|---|---|---|---|
| 🏴‍☠️ **Pirate** | 45 | 45 | 45 | 22.5 | 13.0 sec | 13.0 sec |
| 🔫 **Marauder** | 65 | 97 | 70 | 32.5 | 10.0 sec | 11.5 sec |
| 🦠 **Mutant** | 115 | 131 | 85 | 57.5 | 8.0 sec | 10.7 sec |
| 🪖 **Military** | 145 | 166 | 110 | 72.5 | 6.0 sec | 9.2 sec |
| 🤖 **Prototype** | 200 | 200 | 165 | 100 | 4.0 sec | 5.5 sec |

### Principle: fully upgraded lower NPC ≈ base higher NPC
- Marauder L10 (97 speed, 10 sec) ≈ Mutant L1 (96 speed, 10 sec)
- Mutant L10 (131) ≈ Military L1 (131)
- Military L10 (166) ≈ Prototype L1 (165)

**This transition is smooth** — player isn't punished for replacing fully maxed Marauder with fresh Mutant.

---

## 5. UPGRADE SYSTEM (Levels 1–10)

### Each stat has 10 levels. Each level adds **+3.5 stat points**.
For each NPC, values upgrade **within their tier range** (not up to 200 universally).

### Example: Pirate Upgrade Path
| Level | Strength | Speed | Luck |
|---|---|---|---|
| 1 (base) | 10 | 10 | 10 |
| 2 | 13.5 | 13.5 | 13.5 |
| 3 | 17 | 17 | 17 |
| 4 | 20.5 | 20.5 | 20.5 |
| 5 | 24 | 24 | 24 |
| 6 | 27.5 | 27.5 | 27.5 |
| 7 | 31 | 31 | 31 |
| 8 | 34.5 | 34.5 | 34.5 |
| 9 | 38 | 38 | 38 |
| 10 (max) | 45 | 45 | 45 |

### Example: Prototype Upgrade Path
| Level | Strength | Speed | Luck |
|---|---|---|---|
| 1 (base) | 180 | 165 | 130 |
| 5 | 187.5 | 178 | 144 |
| 10 (max) | 200 | 200 | 165 |

---

## 6. DNA SYSTEM (upgrade cost)

### How DNA accumulates:
- **Each kill of NPC of that type = 1 DNA sample** (added to inventory)
- DNA sample is analyzed in Lab (10–15 sec) → converted into **DNA point**
- DNA points are spent to buy upgrade levels

### Upgrade cost (per stat):
| Transition | Cost (DNA points) |
|---|---|
| L1 → L2 | 1 |
| L2 → L3 | 2 |
| L3 → L4 | 3 |
| L4 → L5 | 5 |
| L5 → L6 | 7 |
| L6 → L7 | 10 |
| L7 → L8 | 14 |
| L8 → L9 | 19 |
| L9 → L10 | 25 |
| **Total** | **86 DNA points per stat** |

### Full upgrade of one NPC (all 3 stats to L10):
**86 × 3 = 258 DNA points = 258 kills of that NPC type**

---

## 7. TIER SYSTEM (kill-based level cap)

### Principle: **tier limits the maximum level** you can purchase.

| Tier | Kills Required | Max Level Available |
|---|---|---|
| **I** | 1–5 | Level 2 |
| **II** | 6–15 | Level 4 |
| **III** | 16–30 | Level 6 |
| **IV** | 31–50 | Level 8 |
| **V** | 51+ | Level 10 (max) |

### This means:
- With 5 Marauder kills, even with 100 DNA points, you cannot raise stat above L2
- Tier acts as "unlock", DNA points act as currency
- Player must **both kill AND spend points**

---

## 8. FULL EXAMPLE: PIRATE PROGRESSION

| Stage | Kills | Tier | Max Level Available | DNA Points |
|---|---|---|---|---|
| Start | 0 | — | 1 | 0 |
| Early fights | 5 | I | 2 | 5 |
| Buy L2 (1 stat) | 5 | I | 2 | 4 (-1) |
| More farming | 15 | II | 4 | 14 |
| Bought L2-L4 on 1 stat | 15 | II | 4 | 14 - (1+2+3) = 8 |
| More fights | 30 | III | 6 | 23 |
| All into one stat to L6 | 30 | III | 6 | 23 - (5+7) = 11 |
| Tier IV | 50 | IV | 8 | 43 |
| Tier V | 51+ | V | 10 | unlimited |

### Conclusion:
- After **50 kills** of Pirate you'll have **43 DNA points + Tier IV access**
- Enough for: 1 stat to L8 (1+2+3+5+7+10+14 = 42), or 2 stats to L5 + L4
- Full max upgrade of Pirate (L10 on all 3 stats): **~258 kills**

---

## 9. BALANCE: IS IT WORTH MAXING?

### Is it worth maxing Pirate?
- 258 kills → 13 sec gather instead of 15 sec = **2 sec saved**
- In the same time you can find 1 Marauder (10 sec gather from base)
- **Conclusion:** No, don't max Pirate. Just upgrade to L4-5, then move on.

### Is it worth maxing Prototype?
- L10: 200 speed = 4 sec gather. **Fastest in game**
- But getting 100+ Prototype kills is impossible (only ~5-10 in entire campaign)
- **Conclusion:** Prototype maxing is for New Game+ or special events

### Sweet spot of balance:
- **Marauder L4-6** and **Mutant L4-6** — best ROI for most players
- Military maxed for top combat performance
- Prototype is prestige tier, rare

---

## 10. ALLY OPERATING MODES

Ally on raft can be in one of these modes:

| Mode | What It Does | Stat That Matters |
|---|---|---|
| ⚔️ **Combat** | Attacks enemies on raft/island | Strength (+ weapon if equipped) |
| 🛒 **Resource Gathering** | Picks up planks/plastic/wood from sea around raft | Speed |
| 🎣 **Fishing** | Catches fish and rare items at fishing spot | Luck |
| 🛡️ **Guard** | Stands still, attacks enemies in 15-stud radius | Strength |
| 😴 **Idle** | Standing, doesn't consume food (saves resources) | — |

Player switches mode through **phone** (ally management UI).

---

## 11. LUA PSEUDOCODE FOR IMPLEMENTATION

```lua
-- Base values per NPC type
local NPC_BASE_STATS = {
  Pirate    = {strength = 10,  speed = 10,  luck = 10},
  Marauder  = {strength = 30,  speed = 62,  luck = 35},
  Mutant    = {strength = 80,  speed = 96,  luck = 50},
  Military  = {strength = 110, speed = 131, luck = 75},
  Prototype = {strength = 180, speed = 165, luck = 130},
}

-- Max values (Level 10)
local NPC_MAX_STATS = {
  Pirate    = {strength = 45,  speed = 45,  luck = 45},
  Marauder  = {strength = 65,  speed = 97,  luck = 70},
  Mutant    = {strength = 115, speed = 131, luck = 85},
  Military  = {strength = 145, speed = 166, luck = 110},
  Prototype = {strength = 200, speed = 200, luck = 165},
}

-- Tier table (max level cap)
local TIER_THRESHOLDS = {
  {kills = 5,   maxLevel = 2},
  {kills = 15,  maxLevel = 4},
  {kills = 30,  maxLevel = 6},
  {kills = 50,  maxLevel = 8},
  {kills = 999, maxLevel = 10},
}

-- Upgrade cost (DNA points)
local LEVEL_COSTS = {1, 2, 3, 5, 7, 10, 14, 19, 25}  -- L1→L2, L2→L3, ...

-- Calculate current stat value
function getCurrentStat(npcType, statName, level)
  local base = NPC_BASE_STATS[npcType][statName]
  local max  = NPC_MAX_STATS[npcType][statName]
  local progress = (level - 1) / 9  -- 0 to 1
  return base + (max - base) * progress
end

-- Convert stat to gameplay effect
function statToEffect(statName, statValue)
  if statName == "strength" then
    return 5 + (statValue - 10) * 0.5  -- fist damage
  elseif statName == "speed" then
    return 15 - (statValue - 10) * 11/190  -- gather time
  elseif statName == "luck" then
    return {
      fishTime = 15 - (statValue - 10) * 11/190,
      rareChance = (statValue / 200) * 0.35,
    }
  end
end

-- Check if upgrade is allowed
function canUpgrade(player, npcType, statName)
  local kills = player.dnaKills[npcType] or 0
  local currentLevel = player.npcStats[npcType][statName].level
  local dnaPoints = player.dnaPoints[npcType] or 0
  
  local maxLevel = 1
  for _, tier in ipairs(TIER_THRESHOLDS) do
    if kills >= tier.kills then maxLevel = tier.maxLevel end
  end
  
  if currentLevel >= maxLevel then return false, "tier_locked" end
  if currentLevel >= 10 then return false, "max_level" end
  
  local cost = LEVEL_COSTS[currentLevel]
  if dnaPoints < cost then return false, "not_enough_dna" end
  
  return true, cost
end
```

---

## 12. PHONE UI ELEMENTS

### Ally Card:
```
┌─────────────────────────────┐
│  🏴‍☠️ PIRATE #03              │
│  Tier: III (Kills: 23/30)   │
│  HP: 50/50 | Hunger: 80%    │
│                             │
│  💪 Strength:  ████░░ L4    │
│      Fist dmg: 12.5         │
│      [+] L5 (5 DNA)         │
│                             │
│  ⚡ Speed:     █████░ L5    │
│      Gather: 13.6 sec       │
│      [+] L6 (7 DNA)         │
│                             │
│  🎲 Luck:      ███░░░ L3    │
│      Fishing: 14.4 sec      │
│      Rare catch: 3%         │
│      [+] L4 (3 DNA)         │
│                             │
│  💉 DNA Available: 18        │
│  ⚙️ Mode: 🛒 Gathering        │
└─────────────────────────────┘
```

---

## 13. IMPLEMENTATION CHECKLIST

- [ ] Data tables: NPC_BASE_STATS, NPC_MAX_STATS, TIER_THRESHOLDS, LEVEL_COSTS
- [ ] ServerScript for tracking kills and granting DNA
- [ ] ProfileService/DataStore for saving upgrade progress
- [ ] Ally card UI in phone
- [ ] DNA analysis trigger in Lab (10–15 sec animation)
- [ ] Ally mode switcher (Combat/Gather/Fish/Guard/Idle)
- [ ] NPC animations for different modes
- [ ] Sound effects for level-up

---

*The system supports smooth progression from Pirate to Prototype. Early tiers level fast but give little; late tiers are very powerful but hard to access.*
