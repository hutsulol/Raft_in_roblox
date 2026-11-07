-- WeaponIcons.server.lua
-- Назначает иконки оружиям игрока через Tool.TextureId. Шаблоны Revolver/Pirate_Gun
-- лежат в Studio-плейсе (не в Rojo-исходниках), а Revolver ещё и переименовывает себя
-- под патроны ("Revolver" → "Revolver (6)"), поэтому вешаем иконку в рантайме по
-- БАЗОВОМУ имени: на шаблоны (ReplicatedStorage/StarterPack) и на выданные тулы
-- (Character/Backpack). TextureId реплицируется клиентам; инвентарь (InventoryUI)
-- берёт его как иконку слота (TOOL_ICONS этих оружий не содержит → fallback на TextureId).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPack       = game:GetService("StarterPack")
local Players           = game:GetService("Players")

local ICONS = {
	Revolver   = "rbxassetid://133241956272699",
	PirateGun  = "rbxassetid://92804972080593",
	Pirate_Gun = "rbxassetid://92804972080593",
	Torch      = "rbxassetid://131695611244502",
}

-- "Revolver (6)" → "Revolver" (снимаем счётчик патронов в конце имени)
local function baseName(name)
	return (name:gsub("%s*%(%d+%)%s*$", ""))
end

local function applyIcon(inst)
	if not inst:IsA("Tool") then return end
	local icon = ICONS[baseName(inst.Name)]
	if icon and inst.TextureId ~= icon then
		inst.TextureId = icon
	end
end

-- шаблоны + любые уже существующие тулы в общих контейнерах
for _, container in ipairs({ ReplicatedStorage, StarterPack }) do
	for _, d in ipairs(container:GetDescendants()) do applyIcon(d) end
	container.DescendantAdded:Connect(applyIcon)
end

-- тулы в руках и рюкзаках игроков (выданные BackPackPickUp / StarterPack)
local function watchContainer(c)
	if not c then return end
	for _, d in ipairs(c:GetChildren()) do applyIcon(d) end
	c.ChildAdded:Connect(applyIcon)
end

local function watchPlayer(plr)
	if plr.Character then watchContainer(plr.Character) end
	plr.CharacterAdded:Connect(watchContainer)
	watchContainer(plr:FindFirstChildOfClass("Backpack"))
	plr.ChildAdded:Connect(function(c)
		if c:IsA("Backpack") then watchContainer(c) end
	end)
end

Players.PlayerAdded:Connect(watchPlayer)
for _, plr in ipairs(Players:GetPlayers()) do watchPlayer(plr) end

print("[WeaponIcons] iconized: Revolver + Pirate_Gun")
