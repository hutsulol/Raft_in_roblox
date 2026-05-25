-- FoodSystem.server.lua
-- Lets the player "take fruit in hand" and eat it for hunger + HP.
-- Mirrors the seed-as-Tool pattern from SeedToolSystem (now retired):
-- the resource lives in the main inventory as a stack, clicking the
-- slot temporarily promotes one unit into a Tool, and an unconsumed
-- Tool returns to the stack on unequip.
--
-- Per-fruit hunger / HP values live in FOOD_DATA — extend that table
-- to add new consumables (cooked fish, jelly, etc.) without
-- touching the equip logic.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FOOD_DATA = {
	Banana    = { hunger = 15, hp = 5 },
	Coconut   = { hunger = 25, hp = 5 },
	Pineapple = { hunger = 20, hp = 5 },
	-- The user's Tool template is "PineApple" (capital A). Mirror
	-- the data here so the in-tool Script can look up by Tool.Name
	-- without a casing helper.
	PineApple = { hunger = 20, hp = 5 },
}

-- Cooked fish are an open-ended family: any inventory key ending in
-- "_Cooked" (produced by the campfire from a raw fish) is edible for
-- a flat ~35 % hunger. Keeping it a suffix rule means a newly adapted
-- fish needs zero changes here.
local COOKED_SUFFIX     = "_Cooked"
local COOKED_FISH_HUNGER = 35   -- ~35 % of MAX_HUNGER (100)
local COOKED_FISH_HP     = 5
local TILAPIA_RAW_TEXTURE_ID = "rbxassetid://711628404"
local TILAPIA_COOKED_TEXTURE_ID = "rbxassetid://121725790433759"

local function isCookedFish(name)
	return type(name) == "string"
		and #name > #COOKED_SUFFIX
		and name:sub(-#COOKED_SUFFIX) == COOKED_SUFFIX
end

-- Published for the in-Tool Script (src/Fruits/<Name> ( Tool )/Script).
-- The Script calls this on Tool.Activated to figure out how much
-- hunger / HP to grant, so the values stay in one place and a tuning
-- pass touches only this table.
_G.GetFoodData = function(name)
	if FOOD_DATA[name] then return FOOD_DATA[name] end
	if isCookedFish(name) then
		return { hunger = COOKED_FISH_HUNGER, hp = COOKED_FISH_HP }
	end
	return nil
end

-- Shared eating animation. Anything held as a food Tool plays this
-- on Tool.Activated. User-authored templates that already ship with
-- an Animation child named "Eat" keep theirs; we only inject one
-- when the template is missing it (e.g. the Banana / Pineapple Tools
-- + the wrapped Coconut model).
local EAT_ANIMATION_ID = "rbxassetid://5973758927"

local function ensureEatAnimation(tool)
	local existing = tool:FindFirstChild("Eat")
	if existing and existing:IsA("Animation") then
		if existing.AnimationId == "" then
			existing.AnimationId = EAT_ANIMATION_ID
		end
		return existing
	end
	local anim = Instance.new("Animation")
	anim.Name        = "Eat"
	anim.AnimationId = EAT_ANIMATION_ID
	anim.Parent      = tool
	return anim
end

local equipEvent = ReplicatedStorage:FindFirstChild("EquipFoodAsTool")
if not equipEvent then
	equipEvent = Instance.new("RemoteEvent")
	equipEvent.Name = "EquipFoodAsTool"
	equipEvent.Parent = ReplicatedStorage
end

while not _G.AddResourceToInventory or not _G.RemoveResourceFromInventory or not _G.GetInventory do
	task.wait(0.1)
end

local function findFoodTemplate(foodName)
	-- The user can author the template as either a Tool (already
	-- holdable) or a Model (we wrap it). Look top-level first, then
	-- recurse so a "Fruits" / "Trees_Grow" folder doesn't hide it.
	local function ok(inst)
		return inst and (inst:IsA("Tool") or inst:IsA("Model") or inst:IsA("BasePart"))
	end
	local hit = ReplicatedStorage:FindFirstChild(foodName)
	if ok(hit) then return hit end
	hit = ReplicatedStorage:FindFirstChild(foodName, true)
	if ok(hit) then return hit end
	-- Case-insensitive fallback. The user's Pineapple Tool template
	-- is authored as "PineApple" (capital A) — FindFirstChild is
	-- case-sensitive, so a direct lookup misses it and we'd fall
	-- through to the invisible placeholder. Walk descendants once
	-- comparing lowercase names so any casing of the same word
	-- still resolves.
	local lower = foodName:lower()
	for _, child in ReplicatedStorage:GetDescendants() do
		if ok(child) and child.Name:lower() == lower then
			return child
		end
	end
	return nil
end

-- Prep a part so Roblox's Tool grip logic is happy with it: not
-- anchored, no collision against players, low mass so the rig isn't
-- dragged. Applied to every BasePart in the cloned template before
-- wrapping it in a Tool.
local function prepHoldablePart(part)
	if not part or not part:IsA("BasePart") then return end
	part.Anchored   = false
	part.CanCollide = false
	part.Massless   = true
end

-- Build a Tool around a Model / BasePart template. The Tool's Handle
-- is the Model's PrimaryPart (or its first BasePart). Every other
-- BasePart in the clone gets WeldConstrained to the Handle so the
-- whole shape follows the player's grip as one unit.
local function wrapModelAsTool(modelClone, foodName)
	local handle
	if modelClone:IsA("BasePart") then
		modelClone.Name = "Handle"
		handle = modelClone
		local tool = Instance.new("Tool")
		tool.Name = foodName
		prepHoldablePart(handle)
		handle.Parent = tool
		return tool
	end

	handle = modelClone.PrimaryPart or modelClone:FindFirstChildWhichIsA("BasePart", true)
	if not handle then
		modelClone:Destroy()
		return nil
	end
	handle.Name = "Handle"

	-- Capture every other BasePart so we can weld them post-hoc.
	local others = {}
	for _, desc in modelClone:GetDescendants() do
		if desc:IsA("BasePart") and desc ~= handle then
			table.insert(others, desc)
		end
	end

	local tool = Instance.new("Tool")
	tool.Name = foodName

	-- Move everything from the model into the Tool, preserving the
	-- relative positioning that the user authored.
	for _, child in modelClone:GetChildren() do
		child.Parent = tool
	end
	modelClone:Destroy()

	prepHoldablePart(handle)
	for _, part in others do
		prepHoldablePart(part)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = part
		weld.Parent = handle
	end

	return tool
end

-- Build an edible Tool for a cooked fish. There is no separate cooked
-- template — we reuse the raw fish model, strip its authored (wiggle)
-- scripts so it sits still in hand, and show the "cooked" decal.
local function makeCookedFishTool(foodName)
	local rawKey = foodName:sub(1, #foodName - #COOKED_SUFFIX)
	local template = findFoodTemplate(rawKey)
		or findFoodTemplate((rawKey:gsub("_", " ")))
	if not template then return nil end

	local tool
	if template:IsA("Tool") then
		tool = template:Clone()
		tool.Name = foodName
		for _, d in tool:GetDescendants() do prepHoldablePart(d) end
	else
		tool = wrapModelAsTool(template:Clone(), foodName)
	end
	if not tool then return nil end

	-- Kill the authored wiggle/flop logic so the held fish is static.
	for _, d in tool:GetDescendants() do
		if d:IsA("Script") or d:IsA("LocalScript") then d:Destroy() end
	end

	-- Show cooked, hide raw. Names are normalized (trim + lowercase)
	-- because the raw decal is authored as " raw" with a leading space —
	-- an exact == "raw" left it visible and overlapping the cooked look.
	for _, d in tool:GetDescendants() do
		if d:IsA("Decal") or d:IsA("Texture") then
			local n = (d.Name:gsub("%s+", "")):lower()
			if n == "raw" then d.Transparency = 1
			elseif n == "cooked" then d.Transparency = 0 end
		elseif d:IsA("SurfaceAppearance") and (d.Name:gsub("%s+", "")):lower() == "raw" then
			d:Destroy()
		elseif d:IsA("MeshPart") and d.TextureID == TILAPIA_RAW_TEXTURE_ID then
			-- Tilapia cooked visual is authored via MeshPart.TextureID
			-- rather than raw/cooked decals, so convert it explicitly
			-- for the held Tool variant.
			d.TextureID = TILAPIA_COOKED_TEXTURE_ID
		end
	end

	return tool
end

local function makeFoodTool(foodName)
	if isCookedFish(foodName) then
		local fishTool = makeCookedFishTool(foodName)
		if fishTool then return fishTool end
	end

	local template = findFoodTemplate(foodName)
	if template then
		if template:IsA("Tool") then
			local clone = template:Clone()
			clone.Name = foodName
			-- Defensive: a hand-authored Tool template might still
			-- have anchored / collidable parts that throw on equip.
			for _, desc in clone:GetDescendants() do
				prepHoldablePart(desc)
			end
			return clone
		else
			-- Model or BasePart → wrap into a Tool so the player can
			-- actually hold it. Failed wrap (no BasePart inside) falls
			-- through to the placeholder below.
			local tool = wrapModelAsTool(template:Clone(), foodName)
			if tool then return tool end
		end
	end
	-- Placeholder Tool — invisible Handle so the equip mechanic still
	-- works even when no model has been authored yet. The icon shows
	-- up correctly in the hotbar via TOOL_ICONS in InventoryUI.
	local tool = Instance.new("Tool")
	tool.Name = foodName
	local handle = Instance.new("Part")
	handle.Name         = "Handle"
	handle.Size         = Vector3.new(1, 1, 1)
	handle.Transparency = 1
	handle.CanCollide   = false
	handle.Massless     = true
	handle.Parent       = tool
	return tool
end

local function alreadyHoldingFood(player, foodName)
	local char     = player.Character
	local backpack = player:FindFirstChild("Backpack")
	for _, container in ipairs({ char, backpack }) do
		if container then
			for _, child in container:GetChildren() do
				if child:IsA("Tool") and child.Name == foodName and child:GetAttribute("FoodResource") == foodName then
					return true
				end
			end
		end
	end
	return false
end

local function refundFood(player, tool)
	if not tool or tool:GetAttribute("Refunded") or tool:GetAttribute("Consumed") then
		if tool then tool:Destroy() end
		return
	end
	tool:SetAttribute("Refunded", true)
	local foodName = tool:GetAttribute("FoodResource")
	if foodName and player and player.Parent then
		_G.AddResourceToInventory(player, foodName, 1, nil, true)
	end
	tool:Destroy()
end

equipEvent.OnServerEvent:Connect(function(player, foodName)
	if typeof(foodName) ~= "string" then return end
	-- Whitelist check only — the actual hunger / hp values live
	-- in the in-tool Script (fruits) or _G.GetFoodData (cooked fish).
	if not _G.GetFoodData(foodName) then return end

	local inv = _G.GetInventory(player)
	if (inv[foodName] or 0) < 1 then return end

	if alreadyHoldingFood(player, foodName) then return end

	local char     = player.Character
	local backpack = player:FindFirstChild("Backpack")
	if not backpack then return end

	_G.RemoveResourceFromInventory(player, foodName, 1)
	if _G.SendInventory then
		_G.SendInventory(player)
	end

	local tool = makeFoodTool(foodName)
	if not tool then return end

	tool:SetAttribute("FoodResource", foodName)
	tool:SetAttribute("OwnerUserId", player.UserId)
	tool.CanBeDropped = false
	ensureEatAnimation(tool)

	tool.Parent = backpack

	-- Force-equip — drop whatever's currently held and put the fruit
	-- in the player's hand. Without this the new Tool just parks in
	-- Backpack and the player thinks the click did nothing.
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if humanoid then
		pcall(function() humanoid:UnequipTools() end)
		pcall(function() humanoid:EquipTool(tool) end)
	end

	-- Refund guard arms on first Equipped — the Backpack→Character
	-- shuffle EquipTool just performed otherwise looks like an
	-- unequip and triggers a false refund.
	tool.Equipped:Once(function()
		tool:SetAttribute("Ready", true)
	end)

	-- Fruits handle Tool.Activated via their own per-Tool Script. Cooked
	-- fish have no such script (we strip the authored one so it doesn't
	-- wiggle in hand), so eat them here: play the Eat animation + the
	-- authored "Eat" sound, then restore hunger and consume.
	if isCookedFish(foodName) then
		tool.Activated:Connect(function()
			if tool:GetAttribute("Consumed") then return end
			tool:SetAttribute("Consumed", true)

			local data = _G.GetFoodData(foodName)
			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local animator = hum and hum:FindFirstChildOfClass("Animator")
			local hrp = char and char:FindFirstChild("HumanoidRootPart")

			-- Eating animation. Force non-looping so Stopped fires and we
			-- can hold the fish for exactly the clip's length.
			local track
			local eatAnim = tool:FindFirstChild("Eat")
			if animator and eatAnim and eatAnim:IsA("Animation") then
				local ok, t = pcall(function() return animator:LoadAnimation(eatAnim) end)
				if ok and t then
					track = t
					track.Looped = false
					track:Play()
				end
			end

			-- Shared eating sound lives in ReplicatedStorage.Fish. The
			-- asset is named "Eating  Sound" (double space) — match on a
			-- normalized name / "eating" substring so spacing/casing don't
			-- matter. Parent it to the character (NOT the Handle) so it
			-- survives the tool being destroyed and plays to the end.
			local fishFolder = ReplicatedStorage:FindFirstChild("Fish")
			local eatSound
			if fishFolder then
				for _, c in fishFolder:GetChildren() do
					if c:IsA("Sound") then
						local n = (c.Name:gsub("%s+", "")):lower()
						if n == "eatingsound" or c.Name:lower():find("eating") then
							eatSound = c
							break
						end
					end
				end
			end
			if eatSound then
				-- Lag the bite sound ~0.4 s behind the animation start so
				-- it lands on the chomp, matching the fruit feel.
				task.delay(0.4, function()
					local s = eatSound:Clone()
					s.Parent = hrp or workspace
					s:Play()
					s.Ended:Once(function() s:Destroy() end)
					task.delay(8, function() if s and s.Parent then s:Destroy() end end)
				end)
			else
				warn("[FoodSystem] no Eating Sound under ReplicatedStorage.Fish")
			end

			-- Hold the fish in hand for the whole animation, then eat it.
			-- Flat short waits cut the clip off; wait on Stopped, capped.
			if track then
				local done = false
				track.Stopped:Once(function() done = true end)
				local waited = 0
				while not done and waited < 5 do
					task.wait(0.1)
					waited = waited + 0.1
				end
			else
				task.wait(2)
			end

			if data and player and player.Parent then
				_G.RestoreHunger(player, data.hunger, data.hp)
			end
			tool:Destroy()
		end)
	end

	tool.AncestryChanged:Connect(function(_, newParent)
		if not tool:GetAttribute("Ready") then return end
		if tool:GetAttribute("Consumed") then return end
		if newParent == nil then
			task.defer(function() refundFood(player, tool) end)
		elseif newParent and newParent:IsA("Backpack") then
			task.defer(function() refundFood(player, tool) end)
		end
	end)
end)
