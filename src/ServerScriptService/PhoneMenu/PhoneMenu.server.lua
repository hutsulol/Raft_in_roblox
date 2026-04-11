-- PhoneMenu.server.lua
-- Server-side entry point for the Phone full-screen menu.
--
-- This script currently only sets up a RemoteEvent that future phone-menu
-- features (attribute upgrades, daily quest claiming, arsenal/mercenary
-- interactions) will use to talk to the server. No gameplay logic yet —
-- the menu is visuals-only for now.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Shared RemoteEvent for any phone-menu traffic. Keeping one event and
-- dispatching by action string (same pattern used by CupAction /
-- WetBrickAction / InventoryCraft in this project) avoids flooding
-- ReplicatedStorage with per-feature events.
local phoneMenuEvent = ReplicatedStorage:FindFirstChild("PhoneMenuAction")
if not phoneMenuEvent then
	phoneMenuEvent = Instance.new("RemoteEvent")
	phoneMenuEvent.Name = "PhoneMenuAction"
	phoneMenuEvent.Parent = ReplicatedStorage
end

-- Placeholder handler. Real actions (upgradeAttribute, claimDailyReward,
-- openArsenal, openMercenaries, …) will be added here as the menu gains
-- functionality.
phoneMenuEvent.OnServerEvent:Connect(function(_player, _action, _data)
	-- Intentionally empty: visuals-only milestone.
end)
