class_name MapNode
extends Resource

enum Type {
	START, FIGHT, ELITE, SHOP, REST, EVENT, BOSS, ENCHANT, FORGE,
	MYSTERY,   # "?" — unknown until entered; mostly good, rare disaster
	GAMBLE,    # wager coins, demon deals
	TREASURE,  # free chest
	SHRINE,    # cursed shrine — strong loot for a max-HP curse
	DOJO,      # win a fight → free guaranteed card upgrade
	BOUNTY,    # win within N rounds → triple coins
	SECRET,    # hidden node — jackpot content
}

var id: int = 0
var type: Type = Type.FIGHT
var pos: Vector2 = Vector2.ZERO
var connections: Array[int] = []
var visited: bool = false
## When true, the node stays clickable even after being visited (shop/enchant/forge re-entry).
## Set to false to permanently close it (e.g. after a successful enchant).
var always_accessible: bool = false
## Shop stock, generated once on first visit and persisted so re-entering
## the shop shows the remaining items instead of fresh stock.
var shop_stocked: bool = false
var shop_stock_equip: Array = []    # Array[EquipmentData]
var shop_stock_scrolls: Array = []  # Array[ScrollData]
## SECRET nodes only: stays invisible on the map until revealed
## (by visiting an adjacent node, or marked by an event).
var secret_revealed: bool = false
