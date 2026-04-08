local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local RAY_LENGTH = 4
local BLUR_UNDERWATER = 20
local TINT_UNDERWATER = Color3.fromRGB(0, 120, 90)
local SATURATION_UNDERWATER = -0.3
local CONTRAST_UNDERWATER = 0.05

local FOG_COLOR_UNDERWATER = Color3.fromRGB(25, 95, 80)
local FOG_END_UNDERWATER = 130
local BRIGHTNESS_UNDERWATER = -0.05

local defaultFogColor = Lighting.FogColor
local defaultFogEnd = Lighting.FogEnd
local defaultBrightness = Lighting.Brightness

local blur = Lighting:FindFirstChild("UnderwaterBlur")
if not blur or not blur:IsA("BlurEffect") then
	if blur then blur:Destroy() end
	blur = Instance.new("BlurEffect")
	blur.Name = "UnderwaterBlur"
	blur.Size = 0
	blur.Parent = Lighting
end

local colorFx = Lighting:FindFirstChild("UnderwaterColorCorrection")
if not colorFx or not colorFx:IsA("ColorCorrectionEffect") then
	if colorFx then colorFx:Destroy() end
	colorFx = Instance.new("ColorCorrectionEffect")
	colorFx.Name = "UnderwaterColorCorrection"
	colorFx.Enabled = false
	colorFx.Parent = Lighting
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = false

local isUnderwater = false

local function setUnderwaterEffects(enabled)
	if enabled then
		blur.Size = BLUR_UNDERWATER
		colorFx.Enabled = true
		colorFx.TintColor = TINT_UNDERWATER
		colorFx.Saturation = SATURATION_UNDERWATER
		colorFx.Contrast = CONTRAST_UNDERWATER
		Lighting.FogColor = FOG_COLOR_UNDERWATER
		Lighting.FogEnd = FOG_END_UNDERWATER
		Lighting.Brightness = BRIGHTNESS_UNDERWATER
	else
		blur.Size = 0
		colorFx.Enabled = false
		Lighting.FogColor = defaultFogColor
		Lighting.FogEnd = defaultFogEnd
		Lighting.Brightness = defaultBrightness
	end
end

RunService.RenderStepped:Connect(function()
	local camera = Workspace.CurrentCamera
	if not camera then return end

	rayParams.FilterDescendantsInstances = {camera}
	local origin = camera.CFrame.Position
	local result = Workspace:Raycast(origin, Vector3.new(0, -RAY_LENGTH, 0), rayParams)
	local nowUnderwater = result ~= nil and result.Material == Enum.Material.Water

	if nowUnderwater ~= isUnderwater then
		isUnderwater = nowUnderwater
		setUnderwaterEffects(isUnderwater)
	end
end)
