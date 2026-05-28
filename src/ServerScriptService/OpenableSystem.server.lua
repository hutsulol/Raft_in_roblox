-- OpenableSystem.server.lua
-- Server handler for Models tagged with "Openable" (CollectionService).
-- The client raycasts in OpenableHint.client.lua, shows an E-key
-- prompt while aimed at a tagged Model, and fires OpenableOpen when
-- the player presses E. We validate the request, play the "Open"
-- Animation on the model's AnimationController if both are present,
-- award a random roll of the configured drop (default Log x1..3),
-- then after FADE_DELAY tween every BasePart's Transparency up to 1
-- across FADE_DURATION and destroy the model.
--
-- Model-level attribute overrides (optional):
--   DropName  (string) — resource name added to inventory (default "Log")
--   DropMin   (number) — minimum roll (default 1)
--   DropMax   (number) — maximum roll (default 3)

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local OPEN_TAG = "Openable"
local OPEN_RANGE = 14
local FADE_DELAY = 0.5
local FADE_DURATION = 0.8        -- 0.5 + 0.8 = 1.3s total
local DEFAULT_DROP = "Log"
local DEFAULT_MIN = 1
local DEFAULT_MAX = 3
local ANIMATION_NAME = "Open"

local openEvent = ReplicatedStorage:FindFirstChild("OpenableOpen")
if not openEvent then
	openEvent = Instance.new("RemoteEvent")
	openEvent.Name = "OpenableOpen"
	openEvent.Parent = ReplicatedStorage
end

local opening = {}

local function getModelPos(model)
	local ok, cf = pcall(function() return model:GetPivot() end)
	return ok and cf.Position or nil
end

local function findAnimationController(model)
	local direct = model:FindFirstChildOfClass("AnimationController")
	if direct then return direct end
	for _, d in model:GetDescendants() do
		if d:IsA("AnimationController") then return d end
	end
	return nil
end

local function findAnimation(model)
	local direct = model:FindFirstChild(ANIMATION_NAME)
	if direct and direct:IsA("Animation") then return direct end
	for _, d in model:GetDescendants() do
		if d:IsA("Animation") and d.Name == ANIMATION_NAME then return d end
	end
	return nil
end

-- AnimationController:LoadAnimation is deprecated and silently fails
-- without an Animator child. Resolve (or create) the Animator and
-- load the track from there.
local function getAnimator(controller)
	local animator = controller:FindFirstChildOfClass("Animator")
	if animator then return animator end
	animator = Instance.new("Animator")
	animator.Parent = controller
	return animator
end

local function playOpenAnimation(model)
	local controller = findAnimationController(model)
	if not controller then return end
	local anim = findAnimation(model)
	if not anim then return end
	local animator = getAnimator(controller)
	local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
	if ok and track then
		track:Play()
	end
end

local function fadeAndDestroy(model)
	local info = TweenInfo.new(FADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			TweenService:Create(d, info, { Transparency = 1 }):Play()
		elseif d:IsA("Decal") or d:IsA("Texture") then
			TweenService:Create(d, info, { Transparency = 1 }):Play()
		end
	end
	Debris:AddItem(model, FADE_DURATION + 0.2)
end

openEvent.OnServerEvent:Connect(function(player, target)
	if typeof(target) ~= "Instance" then return end
	if not target:IsA("Model") then return end
	if not target:IsDescendantOf(workspace) then return end
	if not CollectionService:HasTag(target, OPEN_TAG) then return end
	if opening[target] then return end

	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local pos = getModelPos(target)
	if not pos then return end
	if (pos - hrp.Position).Magnitude > OPEN_RANGE then return end

	opening[target] = true

	-- Signal in-model Scripts that the chest is opening. They watch
	-- via :GetAttributeChangedSignal("_Opening") to drive their own
	-- per-chest animations (e.g. lid rotation) without needing to
	-- ship a Roblox Animation track.
	target:SetAttribute("_Opening", true)

	playOpenAnimation(target)

	local dropName = target:GetAttribute("DropName") or DEFAULT_DROP
	local minAmount = tonumber(target:GetAttribute("DropMin")) or DEFAULT_MIN
	local maxAmount = tonumber(target:GetAttribute("DropMax")) or DEFAULT_MAX
	if minAmount < 1 then minAmount = 1 end
	if maxAmount < minAmount then maxAmount = minAmount end
	local amount = math.random(minAmount, maxAmount)

	if _G.AddResourceToInventory then
		_G.AddResourceToInventory(player, dropName, amount, pos)
	end

	task.delay(FADE_DELAY, function()
		if target.Parent then
			-- Sync any InteractHighlight on this model with the part
			-- fade. The highlight script watches for _Fading and uses
			-- _FadingDuration to size its ramp-out, so the glow dies
			-- at the same moment the model finishes fading out.
			target:SetAttribute("_FadingDuration", FADE_DURATION)
			target:SetAttribute("_Fading", true)
			fadeAndDestroy(target)
		end
		opening[target] = nil
	end)
end)

print("[OpenableSystem] Loaded — tag models with " .. OPEN_TAG)
