--//Pirate_Gun — FrontendScript (client)
--//Animations + input. Instead of raycasting a hitscan bullet, it sends the world
--//aim direction (muzzle → cursor) to the server, which spawns the cannon charge.

--//Variables\\--
local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")

local tool = script.Parent.Parent
local player = Players.LocalPlayer
local mouse = player:GetMouse()
local handle = tool:WaitForChild("Handle")
local equipped = false

--//Folders\\--
local animations = tool:WaitForChild("Animations")
local remotes = tool:WaitForChild("Remotes")

--//Animations\\--
local recoilAnim = animations:WaitForChild("Recoil")
local reloadAnim = animations:WaitForChild("Reload")
local holdAnim = animations:WaitForChild("Hold")

--//Animation Tracks\\--
local recoilTrack
local reloadTrack
local holdTrack

--//Remotes\\--
local canShoot = remotes:WaitForChild("CanShoot")
local canReload = remotes:WaitForChild("CanReload")
local reloadRemote = remotes:WaitForChild("Reload")
local shootRemote = remotes:WaitForChild("Shoot")

--//Functions\\--
local function equip()
	equipped = true

	local character = player.Character or player.CharacterAdded:Wait()
	local humanoid = character:WaitForChild("Humanoid")
	if humanoid then
		pcall(function()
			holdTrack = humanoid:LoadAnimation(holdAnim)
			holdTrack:Play()
		end)
		pcall(function()
			reloadTrack = humanoid:LoadAnimation(reloadAnim)
		end)
		pcall(function()
			recoilTrack = humanoid:LoadAnimation(recoilAnim)
		end)
	end
end

local function unequip()
	equipped = false
	if holdTrack then holdTrack:Stop() end
	if reloadTrack then reloadTrack:Stop() end
	if recoilTrack then recoilTrack:Stop() end
end

local function reload()
	if not equipped then return end
	if canReload:InvokeServer() then
		reloadRemote:FireServer()
		if reloadTrack then reloadTrack:Play() end
	end
end

local function fire()
	if not equipped then return end
	if canShoot:InvokeServer() then
		if recoilTrack then recoilTrack:Play() end

		--//Aim from the muzzle (Handle pivot) toward the cursor; the server lobs the
		--//charge in this direction and gravity arcs it (like the Cannon).
		local origin = handle:GetPivot().Position
		local dir = mouse.Hit.Position - origin
		if dir.Magnitude < 0.001 then return end
		shootRemote:FireServer(dir.Unit)
	end
end

--//Event listeners\\--
tool.Equipped:Connect(equip)
tool.Unequipped:Connect(unequip)
tool.Activated:Connect(fire) --//semi-auto: one charge per click

--//Reload on R (unique action name so it never clobbers the AK-47's binding)
ContextActionService:BindAction("PirateGunReload", function(_, state)
	if state == Enum.UserInputState.Begin then
		reload()
	end
end, false, Enum.KeyCode.R)
