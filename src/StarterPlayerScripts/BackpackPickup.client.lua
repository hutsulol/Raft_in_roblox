-- BackpackPickup.client.lua
-- Фидбек подбора рюкзака (пара к BackpackPickup.server.lua):
--   • звук подбора — «Pick Up» из SoundService (fallback rbxassetid://9122561016);
--   • уведомление через NotificationCenter: «Новое: Рюкзак»;
--   • локальное скрытие модели Workspace.BackPack у подобравшего — у остальных
--     игроков рюкзак остаётся лежать (подбор персональный).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService      = game:GetService("SoundService")
local Workspace         = game:GetService("Workspace")

local MODEL_NAME = "BackPack"
local SOUND_NAME = "Pick Up"
local SOUND_ID   = "rbxassetid://9122561016"

local player = Players.LocalPlayer
local pickupEvent = ReplicatedStorage:WaitForChild("BackpackPickup")

local function playPickupSound()
	local s = SoundService:FindFirstChild(SOUND_NAME) or SoundService:FindFirstChild(SOUND_NAME, true)
	if s == nil or not s:IsA("Sound") then
		s = Instance.new("Sound")
		s.Name = SOUND_NAME
		s.SoundId = SOUND_ID
		s.Volume = 1
		s.Parent = SoundService
	end
	s:Play()
end

local function findBackpackModel()
	local direct = Workspace:FindFirstChild(MODEL_NAME)
	if direct then return direct end
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("Model") and d.Name == MODEL_NAME then
			return d
		end
	end
	return nil
end

-- Прячем рюкзак только на этом клиенте: парты в прозрачность, гуи и промпт
-- выключаем. Изменения локальные — другим игрокам модель видна как прежде.
local function hideBackpackLocally()
	local model = findBackpackModel()
	if model == nil then return end
	if model:IsA("BasePart") then model.Transparency = 1 end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Transparency = 1
			d.CanCollide = false
		elseif d:IsA("Decal") or d:IsA("Texture") then
			d.Transparency = 1
		elseif d:IsA("BillboardGui") or d:IsA("SurfaceGui") then
			d.Enabled = false
		elseif d:IsA("ProximityPrompt") then
			d.Enabled = false
		end
	end
end

pickupEvent.OnClientEvent:Connect(function()
	hideBackpackLocally()
	playPickupSound()
	if _G.Notify then
		_G.Notify({
			type  = "reward",
			icon  = "🎒",
			title = "Новое: Рюкзак",
			body  = "Нажмите E, чтобы открыть инвентарь",
		})
	end
end)

-- Рюкзак уже подобран в этой сессии (скрипт перезапустился) — просто прячем.
if player:GetAttribute("HasBackpack") then
	hideBackpackLocally()
end
