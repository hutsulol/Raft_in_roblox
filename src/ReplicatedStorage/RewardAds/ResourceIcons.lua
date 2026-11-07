--!strict
-- Uploaded through Roblox Studio Asset Manager on 2026-09-24.
-- Creator: hutsulG. Asset type: Image. Source: design/icons/*.png.
-- Keys match filenames; map to your game's resource IDs where needed.
local Icons = {
	log = "rbxassetid://74909880665704",
	plank = "rbxassetid://76871204043178",
	ingot = "rbxassetid://99725173670942",
	fuel = "rbxassetid://139546274520095",
	rope = "rbxassetid://105807820085903",
	food = "rbxassetid://108608862093815",
	water = "rbxassetid://128612985575989",
	tv = "rbxassetid://95072252101164",
	chest = "rbxassetid://79673240977178",
	play = "rbxassetid://123954245622353",
	close = "rbxassetid://85678482114605",
	check = "rbxassetid://83933527175920",
	crown = "rbxassetid://87007656843998",
}

--[[ НАШЕ: ключи игры → иконки пакета. По правилу хендоффа (§7) клиент сначала
     берёт ИГРОВУЮ иконку предмета (_G.GetItemIcon из инвентаря), эти — только
     если своей нет. Пираты — монета HUD. ]]
Icons.byItem = {
	Log = Icons.log, Plank = Icons.plank, Iron_Ingot = Icons.ingot, Fuel = Icons.fuel,
	Rope = Icons.rope, Food = Icons.food, Water = Icons.water,
	Pirates = "rbxassetid://93617165412571",
}
return Icons
