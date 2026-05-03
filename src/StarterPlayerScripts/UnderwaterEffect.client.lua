-- Underwater screen effect: smoothly blurs and tints the screen as the camera
-- descends below the water surface. The strength scales linearly with depth so
-- the transition is cinematic instead of a hard on/off snap.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local terrain = Workspace.Terrain
local player = Players.LocalPlayer

-- ─── Tunables ────────────────────────────────────────────────────────────────
local MAX_DEPTH = 5                    -- studs below the surface for full effect
local MAX_BLUR = 56                    -- blur size at full depth
local VOXEL_RES = 4                    -- terrain voxel resolution
local TINT_COLOR = Color3.fromRGB(0, 120, 140)
local SATURATION = -0.3
local CONTRAST = 0.05
local BRIGHTNESS = -0.1
local ALPHA_EPSILON = 0.005            -- skip writes when alpha barely moved

-- ─── Lighting effects (created once, reused forever) ────────────────────────
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
	colorCorrection.TintColor = Color3.new(1, 1, 1)
	colorCorrection.Saturation = 0
	colorCorrection.Contrast = 0
	colorCorrection.Brightness = 0
	colorCorrection.Enabled = false
	colorCorrection.Parent = Lighting
end

-- ─── Raycast params (created once, character filter updated on respawn) ─────
local rayParams = RaycastParams.new()
rayParams.IgnoreWater = false           -- we WANT to hit water boundaries
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.FilterDescendantsInstances = {}

local function refreshCharacterFilter(char)
	rayParams.FilterDescendantsInstances = char and { char } or {}
end

if player.Character then
	refreshCharacterFilter(player.Character)
end
player.CharacterAdded:Connect(refreshCharacterFilter)

-- ─── State ───────────────────────────────────────────────────────────────────
local currentAlpha = -1                 -- forces first write

-- ─── Voxel-based water test ──────────────────────────────────────────────────
-- Cheap "is the camera even in water?" check. Region3 is snapped to the voxel
-- grid so we expand a tiny box and read a single voxel.
local function isPointInWater(position)
	local min = Vector3.new(position.X - 2, position.Y - 2, position.Z - 2)
	local max = Vector3.new(position.X + 2, position.Y + 2, position.Z + 2)
	local region = Region3.new(min, max):ExpandToGrid(VOXEL_RES)

	local ok, materials, occupancies = pcall(function()
		return terrain:ReadVoxels(region, VOXEL_RES)
	end)
	if not ok or not materials then return false end

	local material = materials[1] and materials[1][1] and materials[1][1][1]
	local occupancy = occupancies[1] and occupancies[1][1] and occupancies[1][1][1] or 0
	return material == Enum.Material.Water and occupancy > 0.5
end

-- ─── Depth measurement ──────────────────────────────────────────────────────
-- Returns how many studs the camera is below the water surface, or 0 if it
-- isn't underwater at all.
--
-- Strategy: when inside water, an upward Roblox raycast with IgnoreWater=false
-- exits the water voxel at the surface — that exit point is our waterline.
local function getCameraDepth(cameraPos)
	if not isPointInWater(cameraPos) then
		return 0
	end

	local result = Workspace:Raycast(
		cameraPos,
		Vector3.new(0, MAX_DEPTH + 10, 0),
		rayParams
	)

	if not result then
		-- Ray never exited water within MAX_DEPTH+10 studs → we're deep.
		return MAX_DEPTH
	end

	local depth = result.Position.Y - cameraPos.Y
	if depth <= 0 then
		return 0
	end
	return depth
end

-- ─── Effect application ─────────────────────────────────────────────────────
local function applyAlpha(alpha)
	if math.abs(alpha - currentAlpha) < ALPHA_EPSILON then return end
	currentAlpha = alpha

	if alpha <= 0 then
		blur.Size = 0
		colorCorrection.Enabled = false
		return
	end

	-- Lerp every visual property from "neutral" to "full underwater".
	blur.Size = alpha * MAX_BLUR
	colorCorrection.Enabled = true
	colorCorrection.TintColor = Color3.new(1, 1, 1):Lerp(TINT_COLOR, alpha)
	colorCorrection.Saturation = SATURATION * alpha
	colorCorrection.Brightness = BRIGHTNESS * alpha
	colorCorrection.Contrast = CONTRAST * alpha
end

-- ─── Per-frame update ────────────────────────────────────────────────────────
RunService.RenderStepped:Connect(function()
	local camera = Workspace.CurrentCamera
	if not camera then
		applyAlpha(0)
		return
	end

	local depth = getCameraDepth(camera.CFrame.Position)
	local alpha = math.clamp(depth / MAX_DEPTH, 0, 1)
	applyAlpha(alpha)
end)

-- Reset effects on respawn so a fresh character never inherits a stuck blur.
player.CharacterAdded:Connect(function()
	applyAlpha(0)
end)
