extends RefCounted
## Data only. Rules and transactions live in game_state.gd, never in the HUD.

const VERSION: String = "0.4.0"
const BAG_CAPACITY: int = 28
const BAIT_PRICE: int = 1
const BAIT_PACKS: Array[int] = [1, 5, 10]
const MAX_ITEM_COUNT: int = 100000
const SKILLS: Array[String] = ["Woodcutting", "Mining", "Fishing", "Cooking", "Smithing", "Combat"]
const FRONTIER_GOALS: Dictionary = {"wolves": 3, "coal": 3, "warden": 1}
const FRONTIER_LABELS: Dictionary = {"wolves": "Defeat 3 briar wolves", "coal": "Mine 3 coal (Mining 3)", "warden": "Defeat the Watchwarden"}
const ITEMS: Dictionary = {
	"coal": {"name": "Coal", "short": "COAL", "sell": 7, "color": "52565c"},
	"steel_bar": {"name": "Steel bar", "short": "S.BAR", "sell": 25, "color": "b2c2c9"},
	"steel_sword": {"name": "Steel sword", "short": "STEEL", "sell": 95, "damage": 12, "color": "dbe4e9"},
	"wolf_pelt": {"name": "Briar wolf pelt", "short": "PELT", "sell": 9, "color": "aaa08d"},
	"stone_shard": {"name": "Living stone shard", "short": "SHARD", "sell": 12, "color": "849994"},
	"warden_core": {"name": "Watchwarden core", "short": "CORE", "sell": 45, "color": "baae79"},
	"fishing_bait": {"name": "Fishing bait", "short": "BAIT", "sell": 1, "stackable": true, "color": "c89b7c"},
	"logs": {"name": "Pine logs", "short": "LOG", "sell": 2, "color": "ae8053"},
	"oak_logs": {"name": "Oak logs", "short": "OAK", "sell": 5, "color": "865d3b"},
	"copper_ore": {"name": "Copper ore", "short": "COP", "sell": 3, "color": "ca895d"},
	"tin_ore": {"name": "Tin ore", "short": "TIN", "sell": 3, "color": "a6bfc3"},
	"iron_ore": {"name": "Iron ore", "short": "IRON", "sell": 6, "color": "8b939a"},
	"bronze_bar": {"name": "Bronze bar", "short": "BAR", "sell": 8, "color": "d3a569"},
	"iron_bar": {"name": "Iron bar", "short": "I.BAR", "sell": 15, "color": "b3cad8"},
	"raw_trout": {"name": "Raw trout", "short": "RAW", "sell": 2, "color": "78aaa6"},
	"cooked_trout": {"name": "Cooked trout", "short": "FOOD", "sell": 4, "heal": 12, "color": "e4ac78"},
	"slime_gel": {"name": "Moss gel", "short": "GEL", "sell": 5, "color": "99c883"},
	"wood_sword": {"name": "Practice sword", "short": "WOOD", "sell": 1, "damage": 3, "color": "a77f55"},
	"bronze_sword": {"name": "Bronze sword", "short": "BLADE", "sell": 26, "damage": 6, "color": "d6ad75"},
	"iron_sword": {"name": "Iron sword", "short": "IRON", "sell": 52, "damage": 9, "color": "c5dbe2"},
}
const RECIPES: Dictionary = {
	"smelt_steel": {"name": "Smelt steel bar", "station": "forge", "skill": "Smithing", "level": 5, "requires_frontier": true,
		"cost": {"iron_bar": 1, "coal": 2}, "output": "steel_bar", "xp": 45},
	"forge_steel": {"name": "Forge steel sword", "station": "forge", "skill": "Smithing", "level": 5, "requires_frontier": true,
		"cost": {"steel_bar": 3}, "output": "steel_sword", "xp": 125},
	"cook_trout": {"name": "Cook trout", "station": "campfire", "skill": "Cooking", "level": 1,
		"cost": {"raw_trout": 1}, "output": "cooked_trout", "xp": 20},
	"smelt_bronze": {"name": "Smelt bronze bar", "station": "forge", "skill": "Smithing", "level": 1,
		"cost": {"copper_ore": 1, "tin_ore": 1}, "output": "bronze_bar", "xp": 18},
	"forge_bronze": {"name": "Forge bronze sword", "station": "forge", "skill": "Smithing", "level": 1,
		"cost": {"bronze_bar": 3}, "output": "bronze_sword", "xp": 60},
	"smelt_iron": {"name": "Smelt iron bar", "station": "forge", "skill": "Smithing", "level": 3,
		"cost": {"iron_ore": 2}, "output": "iron_bar", "xp": 30},
	"forge_iron": {"name": "Forge iron sword", "station": "forge", "skill": "Smithing", "level": 3,
		"cost": {"iron_bar": 3}, "output": "iron_sword", "xp": 90},
}
const QUEST_GOALS: Dictionary = {"wood": 5, "ore": 6, "cooked": 3, "blade": 1, "slimes": 3}
const QUEST_LABELS: Dictionary = {
	"wood": "Chop 5 pine logs", "ore": "Mine 6 ore (3 copper + 3 tin recommended)",
	"cooked": "Cook 3 trout", "blade": "Forge a bronze sword", "slimes": "Defeat 3 mosslings"
}

static func inventory_slots(inventory: Dictionary) -> int:
	# Bait stacks in one slot. Existing supplies still occupy one slot per unit.
	var total: int = 0
	for id: String in inventory:
		var amount: int = maxi(0, int(inventory[id]))
		if amount > 0:
			total += 1 if bool(ITEMS.get(id, {}).get("stackable", false)) else amount
	return total

static func item_name(id: String) -> String:
	return str(ITEMS.get(id, {}).get("name", id))

static func level_for_xp(xp: int) -> int:
	return mini(50, 1 + int(sqrt(float(maxi(0, xp)) / 40.0)))

static func xp_for_level(level: int) -> int:
	return 40 * (level - 1) * (level - 1)

static func recipe_cost_text(recipe: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	var costs: Dictionary = recipe["cost"]
	for id: String in costs:
		parts.append("%d %s" % [int(costs[id]), item_name(id)])
	return ", ".join(parts)
