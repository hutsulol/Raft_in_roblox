-- EventBootstrap.server.lua
-- Pre-creates a small handful of RemoteEvents at server startup so
-- the matching client scripts can WaitForChild on them without
-- racing the lazy creators.
--
-- Background: a few RemoteEvents in this project are created lazily
-- by the script that owns them. WorkBench/WorkBenchPrompt creates
-- "OpenWorkbench" the first time a WorkBench model loads — but if
-- the player spawns into a world without any WorkBench (e.g. fresh
-- save, lobby), the event doesn't exist yet and the client's
-- WaitForChild yields long enough to trip Roblox's "Infinite yield
-- possible" warning. This script just guarantees the event exists
-- from frame zero so the client wait resolves instantly.
--
-- Adding more events here is a one-line change: call ensureEvent()
-- with the name. Idempotent — does nothing if the event already
-- exists, so the lazy creators continue to no-op as expected.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function ensureEvent(name)
	if ReplicatedStorage:FindFirstChild(name) then return end
	local e = Instance.new("RemoteEvent")
	e.Name = name
	e.Parent = ReplicatedStorage
end

ensureEvent("OpenWorkbench")
