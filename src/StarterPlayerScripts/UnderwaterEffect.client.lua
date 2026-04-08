-- Underwater screen effect: when the camera dips below the water surface,
-- fully blur and tint the screen so the player can't see through it.
-- The effect ignores the surface entirely; only true submersion triggers it.

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local terrain = Workspace.Terrain

-- ─── Tunables ────────────────────────────────────────────────────────────────
local SUBMERGE_DEPTH = 2.5         -- studs below the water surface required to activate
local VOXEL_RES = 4                -- terrain voxel resolution (Roblox uses 4 studs per voxel)
local BLUR_SIZE = 56               -- how strong the blur is when underwater
local TINT_COLOR = Color3.fromRGB(0, 120, 140)
local SATURATION = -0.3
local CONTRAST = 0.05
local BRIGHTNESS = -0.1

-- ─── Lighting effects (created once) ─────────────────────────────────────────
local blur = Lighting:FindFirstChild("UnderwaterBlur")
if not blur then
	blur = Instance.new("BlurEffect")
	blur.Name = "UnderwaterBlur"
	blur.Size = 0
	blur.Parent = Lighting
end

local colorCorrection = Lighting:FindFirstChild("UnderwaterColor")
if not colorCorrection then
	colorCorrection = Instance.new("ColorCorrectionEffect")
	colorCorrection.Name = "UnderwaterColor"
	colorCorrection.TintColor = TINT_COLOR
	colorCorrection.Saturation = SATURATION
	colorCorrection.Contrast = CONTRAST
	colorCorrection.Brightness = BRIGHTNESS
	colorCorrection.Enabled = false
	colorCorrection.Parent = Lighting
end

-- ─── State ───────────────────────────────────────────────────────────────────
local isUnderwater = false

local function setUnderwater(state)
	if state == isUnderwater then return end
	isUnderwater = state
	if state then
		blur.Size = BLUR_SIZE
		colorCorrection.Enabled = true
	else
		blur.Size = 0
		colorCorrection.Enabled = false
	end
end

-- ─── Voxel-based water test ──────────────────────────────────────────────────
-- Sample a tiny region around the camera. Roblox snaps Region3 to the voxel
-- grid, so we expand a touch and ask for a single voxel's worth of data.
local function isPointInWater(position)
	local min = Vector3.new(position.X - 2, position.Y - 2, position.Z - 2)
	local max = Vector3.new(position.X + 2, position.Y + 2, position.Z + 2)
	local region = Region3.new(min, max):ExpandToGrid(VOXEL_RES)

	local ok, materials, occupancies = pcall(function()
		return terrain:ReadVoxels(region, VOXEL_RES)
	end)
	if not ok or not materials then return false, 0 end

	-- ReadVoxels returns 3D arrays; we asked for a 1×1×1 region.
	local material = materials[1] and materials[1][1] and materials[1][1][1]
	local occupancy = occupancies[1] and occupancies[1][1] and occupancies[1][1][1] or 0
	if material == Enum.Material.Water and occupancy > 0.5 then
		return true, occupancy
	end
	return false, 0
end

-- ─── Surface exclusion ───────────────────────────────────────────────────────
-- Even if the camera point is inside a water voxel, we don't want to trigger
-- right at the waterline. Sample a voxel SUBMERGE_DEPTH studs above the camera;
-- if THAT point is also water, the camera is genuinely submerged below the
-- surface. If it isn't, the camera is near the surface and we leave the effect
-- off — no flicker, no half-submerged tinting.
local function isCameraSubmerged()
	local camera = Workspace.CurrentCamera
	if not camera then return false end

	local pos = camera.CFrame.Position
	local hereInWater = isPointInWater(pos)
	if not hereInWater then return false end

	local abovePos = pos + Vector3.new(0, SUBMERGE_DEPTH, 0)
	local aboveInWater = isPointInWater(abovePos)
	return aboveInWater
end

-- ─── Per-frame check ─────────────────────────────────────────────────────────
RunService.RenderStepped:Connect(function()
	setUnderwater(isCameraSubmerged())
end)

-- Reset state on respawn so a fresh character can't be left with stuck effects.
local Players = game:GetService("Players")
local player = Players.LocalPlayer
player.CharacterAdded:Connect(function()
	setUnderwater(false)
end)
