-- WoodBoostProducts.server.lua
-- Донат «2x / 4x дерево» у фермы деревьев (Tree_Farm).
--
-- Игрок кликает по иконке-биллборду у камня (WoodBoostBillboard.client.lua) →
-- клиент шлёт RemoteEvent WoodBoostBuy → сервер открывает родное окно покупки
-- Roblox (PromptProductPurchase) СЛЕДУЮЩЕГО тира:
--   тир 1 → «2x дерево» за 50 Robux;
--   тир 2 → «4x дерево» за 75 Robux;
--   тир 4 → максимум, покупать больше нечего (биллборд прячется).
--
-- Текущий тир хранится в атрибуте игрока WoodMultiplier (1|2|4):
--   • его читает биллборд (какой тир предлагать);
--   • его читает TreeFarmSystem — рабочие кладут на склад 1/2/4 бревна за ходку;
--   • он сохраняется в DataStore WoodBoostV1 (покупка за робуксы обязана
--     переживать перезаход).
--
-- ⚠ ЗАПОЛНИ ID ПРОДУКТОВ: Creator Dashboard → твой опыт → Monetization →
--   Developer Products. Создай «2x дерево» (50 R) и «4x дерево» (75 R) и впиши
--   их ID ниже. Пока ID = 0 клик по иконке просто пишет warn в Output.
--
-- ⚠ ProcessReceipt на игру может быть ТОЛЬКО ОДИН — сейчас он живёт здесь.
--   Новые девпродукты подключай через таблицу GRANTS в этом файле.

local Players            = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService   = game:GetService("DataStoreService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")

local PRODUCT_2X = 3603970313 -- девпродукт «2x дерево» (50 Robux)
local PRODUCT_4X = 3603970680 -- девпродукт «4x дерево» (75 Robux)

local ATTR = "WoodMultiplier"

-- DataStore может быть недоступен (Studio без API-доступа) — работаем без него.
local store
pcall(function()
	store = DataStoreService:GetDataStore("WoodBoostV1")
end)

local buyRemote = ReplicatedStorage:FindFirstChild("WoodBoostBuy")
if not buyRemote then
	buyRemote = Instance.new("RemoteEvent")
	buyRemote.Name = "WoodBoostBuy"
	buyRemote.Parent = ReplicatedStorage
end

local function getMult(player)
	local m = player:GetAttribute(ATTR)
	return type(m) == "number" and m or 1
end

-- Выдать множитель (никогда не понижаем) и сохранить. Возвращает false, если
-- сохранение не прошло — чек тогда не закрываем, Roblox повторит позже
-- (повторная выдача безопасна: max() идемпотентен).
local function applyMult(player, mult)
	if getMult(player) < mult then
		player:SetAttribute(ATTR, mult)
	end
	if store == nil then return true end
	local ok = pcall(function()
		store:UpdateAsync("u" .. player.UserId, function(old)
			old = type(old) == "number" and old or 1
			return math.max(old, mult)
		end)
	end)
	return ok
end

-- Загрузка купленного тира при входе.
local function loadPlayer(player)
	player:SetAttribute(ATTR, 1)
	if store == nil then return end
	local ok, saved = pcall(function()
		return store:GetAsync("u" .. player.UserId)
	end)
	if ok and type(saved) == "number" and saved > 1 then
		player:SetAttribute(ATTR, math.min(saved, 4))
	end
end

Players.PlayerAdded:Connect(loadPlayer)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(loadPlayer, p)
end

-- Клик по иконке: показать окно покупки следующего тира. ID продуктов клиенту
-- не нужны — сервер сам решает, что предлагать.
buyRemote.OnServerEvent:Connect(function(player)
	local mult = getMult(player)
	local productId
	if mult < 2 then
		productId = PRODUCT_2X
	elseif mult < 4 then
		productId = PRODUCT_4X
	end
	if productId == nil then return end -- уже 4x — максимум
	if productId == 0 then
		warn("[WoodBoost] ID девпродукта не заполнен — впиши PRODUCT_2X/PRODUCT_4X в WoodBoostProducts.server.lua")
		return
	end
	MarketplaceService:PromptProductPurchase(player, productId)
end)

-- Какой продукт какой множитель выдаёт (нулевые ID не регистрируем).
local GRANTS = {}
if PRODUCT_2X ~= 0 then GRANTS[PRODUCT_2X] = 2 end
if PRODUCT_4X ~= 0 then GRANTS[PRODUCT_4X] = 4 end

MarketplaceService.ProcessReceipt = function(receiptInfo)
	local mult = GRANTS[receiptInfo.ProductId]
	if mult == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if player == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- выдадим, когда игрок вернётся
	end
	if not applyMult(player, mult) then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- DataStore упал, повторим
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end
