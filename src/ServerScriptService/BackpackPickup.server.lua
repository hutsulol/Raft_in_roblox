-- BackpackPickup.server.lua
-- Подбор рюкзака-туториала (модель Workspace.BackPack).
--
-- На самый крупный парт модели вешается ProximityPrompt: на ПК это кнопка «E»,
-- на телефоне — кнопка-прикосновение (нативное поведение промпта). По триггеру
-- игроку ставится атрибут HasBackpack (его читает InventoryUI — до подбора
-- инвентарь не открывается) и клиенту летит RemoteEvent BackpackPickup
-- (звук + уведомление + локальное скрытие модели — BackpackPickup.client.lua).
--
-- Подбор ПЕРСОНАЛЬНЫЙ: модель остаётся в мире для остальных игроков (каждый
-- подбирает свой рюкзак), у подобравшего она прячется на клиенте. Если модели
-- на карте нет вовсе (например, лобби) — атрибут выдаётся всем сразу, чтобы
-- гейт не заблокировал инвентарь там, где механика не нужна.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local MODEL_NAME = "BackPack"
local ATTR       = "HasBackpack"

local pickupEvent = ReplicatedStorage:FindFirstChild("BackpackPickup")
if not pickupEvent then
	pickupEvent = Instance.new("RemoteEvent")
	pickupEvent.Name = "BackpackPickup"
	pickupEvent.Parent = ReplicatedStorage
end

-- Модель рюкзака: сперва прямой ребёнок Workspace, потом поиск в глубину.
local function findBackpackModel()
	local direct = Workspace:WaitForChild(MODEL_NAME, 10)
	if direct then return direct end
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("Model") and d.Name == MODEL_NAME then
			return d
		end
	end
	return nil
end

-- Самый крупный парт модели — носитель промпта. Парт "BillboardGui" не
-- подходит: он прозрачный и качается вверх-вниз (Gui22Bob).
local function findPromptPart(model)
	if model:IsA("BasePart") then return model end
	local best, bestVolume = nil, 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "BillboardGui" then
			local s = d.Size
			local v = s.X * s.Y * s.Z
			if v > bestVolume then
				best, bestVolume = d, v
			end
		end
	end
	return best
end

-- Тихая выдача (без звука/уведомления) — для карт без рюкзака.
local function grantSilently(player)
	if not player:GetAttribute(ATTR) then
		player:SetAttribute(ATTR, true)
	end
end

local model = findBackpackModel()
local promptPart = model and findPromptPart(model)

if promptPart == nil then
	for _, player in ipairs(Players:GetPlayers()) do
		grantSilently(player)
	end
	Players.PlayerAdded:Connect(grantSilently)
	return
end

local prompt = Instance.new("ProximityPrompt")
prompt.Name = "BackpackPrompt"
prompt.ActionText = "Подобрать"
prompt.ObjectText = "Рюкзак"
prompt.KeyboardKeyCode = Enum.KeyCode.E
prompt.MaxActivationDistance = 9
prompt.RequiresLineOfSight = false
prompt.HoldDuration = 0
prompt.Parent = promptPart

prompt.Triggered:Connect(function(player)
	if player:GetAttribute(ATTR) then return end
	player:SetAttribute(ATTR, true)
	pickupEvent:FireClient(player)
end)
