--//Pirate_Gun — AimScript (client)
--//While the gun is equipped, sends the AIM pitch (muzzle → cursor) to the server,
--//which tilts the gun's Grip to match. Uses the mouse's world target (mouse.Hit), so
--//it works in BOTH first- and third-person — the gun points where the cursor is,
--//matching where the charge actually flies.

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local tool      = script.Parent.Parent
local player    = Players.LocalPlayer
local mouse     = player:GetMouse()
local handle    = tool:WaitForChild("Handle")
local remotes   = tool:WaitForChild("Remotes")
local aimRemote = remotes:WaitForChild("Aim") -- created by the server (BackendScript)

local SEND_DT   = 0.03          -- ~30 Hz updates to the server
local MIN_DELTA = math.rad(0.5) -- skip sub-degree changes to save bandwidth

local conn
local lastSent, acc = nil, 0

local function stop()
	if conn then conn:Disconnect(); conn = nil end
	lastSent = nil
end

local function start()
	acc = 0
	conn = RunService.RenderStepped:Connect(function(dt)
		acc += dt
		if acc < SEND_DT then return end
		acc = 0
		--//elevation of the shot: muzzle → where the cursor points. mouse.Hit is the
		--//cursor's world target in any camera mode, so this works in 1st AND 3rd person.
		local dir = mouse.Hit.Position - handle:GetPivot().Position
		if dir.Magnitude < 0.001 then return end
		local pitch = math.asin(math.clamp(dir.Unit.Y, -1, 1))
		if lastSent == nil or math.abs(pitch - lastSent) >= MIN_DELTA then
			lastSent = pitch
			aimRemote:FireServer(pitch)
		end
	end)
end

tool.Equipped:Connect(start)
tool.Unequipped:Connect(stop)
