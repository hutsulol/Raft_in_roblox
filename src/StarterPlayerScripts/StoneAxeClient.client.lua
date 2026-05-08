-- StoneAxeClient.client.lua
-- Client-side Stone_Axe tool: highlights choppable trees on hover,
-- handles click-to-chop, plays the HitTreeR6 animation and shows
-- mining-style "+N Log / hits left" feedback.
--
-- Mirrors the Pick-Axe / rock-mining client almost line-for-line so
-- the two tools feel identical to the player. Differences:
--   * Tree models are MODELS (not BaseParts) — raycasts walk the
--     parent chain to find the Choppable Model.
--   * Cooldown matches the user's brief: 0.8 s between swings.
--   * Animation comes from the user-authored HitTreeR6 child of
--     Stone_Axe (asset id rbxassetid://82172717244396).
--   * Highlight reads green to differentiate "wood" from the
--     yellow rock outline.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService      = game:GetService("SoundService")
local Debris            = game:GetService("Debris")
local RunService        = game:GetService("RunService")

local player = Players.LocalPlayer
local mouse  = player:GetMouse()
local camera = workspace.CurrentCamera

local chopTreeEvent = ReplicatedStorage:WaitForChild("ChopTree")

-- ─── Tunables ─────────────────────────────────────────────────────────
local CHOP_COOLDOWN  = 0.8     -- per the user's brief
local CHOP_AIM_RANGE = 200     -- studs of mouse-ray raycast

-- ─── State ────────────────────────────────────────────────────────────
local axeEquipped     = false
local currentTool     = nil
local highlightedTree = nil
local highlightBox    = nil
local chopAnimTrack   = nil
local choppingCooldown = false

-- ─── Hint UI (matches PickAxeClient styling so the two tools share a
-- consistent on-screen affordance) ───────────────────────────────────
local playerGui = player:WaitForChild("PlayerGui")
local hintGui = Instance.new("ScreenGui")
hintGui.Name = "StoneAxeHint"
hintGui.DisplayOrder = 51
hintGui.IgnoreGuiInset = true
hintGui.Parent = playerGui

local hintLabel = Instance.new("TextLabel")
hintLabel.Name = "HintText"
hintLabel.AnchorPoint = Vector2.new(0.5, 1)
hintLabel.Position = UDim2.new(0.5, 0, 0.8, 0)
hintLabel.Size = UDim2.new(0, 300, 0, 40)
hintLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
hintLabel.BackgroundTransparency = 0.4
hintLabel.Text = ""
hintLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
hintLabel.TextSize = 18
hintLabel.Font = Enum.Font.GothamBold
hintLabel.Visible = false
hintLabel.Parent = hintGui

local hintCorner = Instance.new("UICorner")
hintCorner.CornerRadius = UDim.new(0, 8)
hintCorner.Parent = hintLabel

-- "+2 Log" / "Chopping… (3 hits left)" floater
local feedbackLabel = Instance.new("TextLabel")
feedbackLabel.Name = "ChopFeedback"
feedbackLabel.AnchorPoint = Vector2.new(0.5, 0.5)
feedbackLabel.Position = UDim2.new(0.5, 0, 0.45, 0)
feedbackLabel.Size = UDim2.new(0, 260, 0, 36)
feedbackLabel.BackgroundTransparency = 1
feedbackLabel.Text = ""
feedbackLabel.TextColor3 = Color3.fromRGB(180, 240, 130)
feedbackLabel.TextSize = 22
feedbackLabel.Font = Enum.Font.GothamBold
feedbackLabel.TextStrokeTransparency = 0.5
feedbackLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
feedbackLabel.Visible = false
feedbackLabel.Parent = hintGui

-- ─── Highlight (green outline so it reads as "wood" not "rock") ───
local function createHighlight()
	if highlightBox then highlightBox:Destroy() end
	highlightBox = Instance.new("Highlight")
	highlightBox.FillTransparency = 1
	highlightBox.OutlineColor = Color3.fromRGB(120, 220, 90)
	highlightBox.OutlineTransparency = 0
	highlightBox.Parent = playerGui
end

local function clearHighlight()
	if highlightBox then
		highlightBox.Adornee = nil
	end
	highlightedTree = nil
end

-- ─── Resolve a Choppable tree from the raycast hit ────────────────
-- Trees are multi-part Models (trunk + leaves + fruit). The raycast
-- almost always lands on a leaf or a trunk part; walk up the parent
-- chain until we hit the Model that carries the "Choppable" attribute.
local function findChoppableTree(instance)
	if not instance then return nil end
	local current = instance
	while current and current ~= workspace do
		if current:IsA("Model") and current:GetAttribute("Choppable") then
			return current
		end
		current = current.Parent
	end
	return nil
end

-- ─── HitTreeR6 animation track (loaded once per equip) ────────────
local function ensureChopAnimation()
	if chopAnimTrack then return chopAnimTrack end
	local char = player.Character
	if not char then return nil end
	local humanoid = char:FindFirstChildWhichIsA("Humanoid")
	if not humanoid or not currentTool then return nil end

	-- Prefer the user-authored HitTreeR6 child of the Stone_Axe tool.
	-- Fall back to any Animation under the tool so a future asset
	-- rename doesn't silently disable the swing.
	local anim = currentTool:FindFirstChild("HitTreeR6")
		or currentTool:FindFirstChildWhichIsA("Animation", true)
	if not anim or not anim:IsA("Animation") then return nil end

	local ok, track = pcall(function() return humanoid:LoadAnimation(anim) end)
	if ok and track then
		chopAnimTrack = track
		track.Priority = Enum.AnimationPriority.Action
	end
	return chopAnimTrack
end

local function playChopAnimation()
	local track = ensureChopAnimation()
	if not track then return end
	pcall(function()
		track:Stop(0)
		track:Play(0.05)
	end)
end

-- ─── Per-frame highlight update ───────────────────────────────────
local function updateHighlight()
	if not axeEquipped then
		clearHighlight()
		return
	end

	local unitRay = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filterList = {}
	if player.Character then table.insert(filterList, player.Character) end
	params.FilterDescendantsInstances = filterList

	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * CHOP_AIM_RANGE, params)
	if result and result.Instance then
		local tree = findChoppableTree(result.Instance)
		if tree then
			highlightedTree = tree
			if highlightBox then
				highlightBox.Adornee = tree
			end
			hintLabel.Text = "Click to chop tree"
			hintLabel.Visible = true
			return
		end
	end

	clearHighlight()
	hintLabel.Text = "Aim at trees on islands to chop"
	hintLabel.Visible = true
end

-- ─── Tool equip / unequip plumbing ────────────────────────────────
local function onToolEquipped(tool)
	if tool.Name == "Stone_Axe" then
		axeEquipped = true
		currentTool = tool
		chopAnimTrack = nil   -- reload for the new instance
		createHighlight()
		hintLabel.Visible = true
	end
end

local function onToolUnequipped(tool)
	if tool.Name == "Stone_Axe" then
		axeEquipped = false
		currentTool = nil
		if chopAnimTrack then
			pcall(function() chopAnimTrack:Stop(0) end)
		end
		chopAnimTrack = nil
		clearHighlight()
		hintLabel.Visible = false
	end
end

local function setupCharacter(char)
	if not char then return end
	char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then onToolEquipped(child) end
	end)
	char.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then onToolUnequipped(child) end
	end)
	for _, child in char:GetChildren() do
		if child:IsA("Tool") and child.Name == "Stone_Axe" then
			onToolEquipped(child)
			break
		end
	end
end

local char = player.Character
if char then setupCharacter(char) end
player.CharacterAdded:Connect(setupCharacter)

-- ─── Frame loop ───────────────────────────────────────────────────
RunService.RenderStepped:Connect(function()
	if axeEquipped then
		updateHighlight()
	end
end)

-- ─── Click → chop (0.8 s cooldown matches the brief) ──────────────
mouse.Button1Down:Connect(function()
	if not axeEquipped then return end
	if choppingCooldown then return end
	if not highlightedTree then return end

	choppingCooldown = true
	playChopAnimation()
	chopTreeEvent:FireServer(highlightedTree)

	task.delay(CHOP_COOLDOWN, function()
		choppingCooldown = false
	end)
end)

-- ─── Server feedback ──────────────────────────────────────────────
chopTreeEvent.OnClientEvent:Connect(function(action, value, extra)
	if action == "destroyed" then
		local text = "+" .. tostring(value) .. " Log"
		if extra and extra.resource and extra.count and extra.count > 0 then
			text = text .. "  +" .. tostring(extra.count) .. " " .. extra.resource
		end
		feedbackLabel.Text = text
		feedbackLabel.Visible = true
		feedbackLabel.TextTransparency = 0
		clearHighlight()

		-- Wood Break SFX, mirrors the rock-crush sound on Pick-Axe.
		local logTemplate = ReplicatedStorage:FindFirstChild("Log")
		local woodBreak = logTemplate and logTemplate:FindFirstChild("Wood Break", true)
		if woodBreak and woodBreak:IsA("Sound") then
			local clone = woodBreak:Clone()
			clone.Parent = SoundService
			clone:Play()
			Debris:AddItem(clone, 5)
		end

		task.spawn(function()
			task.wait(1)
			for i = 0, 10 do
				feedbackLabel.TextTransparency = i / 10
				feedbackLabel.TextStrokeTransparency = 0.5 + (i / 10) * 0.5
				task.wait(0.05)
			end
			feedbackLabel.Visible = false
			feedbackLabel.TextTransparency = 0
			feedbackLabel.TextStrokeTransparency = 0.5
		end)
	elseif action == "hit" then
		feedbackLabel.Text = "Chopping... (" .. tostring(value) .. " hits left)"
		feedbackLabel.Visible = true
		feedbackLabel.TextTransparency = 0
		task.spawn(function()
			task.wait(0.8)
			if feedbackLabel.Text:find("Chopping") then
				feedbackLabel.Visible = false
			end
		end)
	end
end)
