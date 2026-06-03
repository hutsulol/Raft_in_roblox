local Players = game:GetService("Players")
local rs = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- ─── Config ───
local WATER_DRY_TIME = 60 -- seconds before watered garden dries out

-- How long the cross-fade between two bed templates takes. Short
-- enough not to feel laggy; long enough to round off the visual pop.
local FADE_DURATION = 0.35

-- Tree growth progression for planted seeds. Stage 1 (Bed_T_1_all)
-- is the species-agnostic sapling — every seed uses it. Past stage 1
-- the chain branches by seed type:
--   * Palm   → Bed_T_P_2 → Bed_T_P_3 → Bed_T_P_Finish
--   * Banana → Bed_T_B_2 → Bed_T_B_3 → Bed_T_B_Finish
-- Seeds whose kind isn't listed here stop at Bed_T_1_all until art
-- for them lands.
local TREE_STAGES_BY_KIND = {
	Palm = {
		"Bed_T_1_all",
		"Bed_T_P_2",
		"Bed_T_P_3",
		"Bed_T_P_Finish",
	},
	Banana = {
		"Bed_T_1_all",
		"Bed_T_B_2",
		"Bed_T_B_3",
		"Bed_T_B_Finish",
	},
}
local TREE_STAGE_INTERVAL = 10  -- seconds between stage swaps

-- ─── Remote Events ───
local function getOrCreate(name)
	local e = rs:FindFirstChild(name)
	if not e then
		e = Instance.new("RemoteEvent")
		e.Name = name
		e.Parent = rs
	end
	return e
end

local gardenActionEvent = getOrCreate("GardenAction")

-- ─── Enable grapes on bushes inside a garden ───
local function enableBushGrapes(garden)
	for _, child in garden:GetChildren() do
		if child:GetAttribute("IsBush") then
			child:SetAttribute("GrapesAvailable", true)
			local grapes = child:FindFirstChild("grapes") or child:FindFirstChild("Grapes")
			if grapes then
				if grapes:IsA("BasePart") then
					grapes.Transparency = 0
				elseif grapes:IsA("Model") then
					for _, p in grapes:GetDescendants() do
						if p:IsA("BasePart") then p.Transparency = 0 end
					end
				end
			end
		end
	end
end

-- ─── Generic bed-model swap ───
-- Destroys the bed's current children, clones the requested template's
-- children in their place, welds the new parts to the raft, and
-- restores the bed pose relative to the raft. Returns true on success.
-- Used by both the dry/wet swap below AND the tree-growth stage swap.

-- Finds the model's "Center" BasePart — the per-template anchor the
-- artist authors at the same world spot on every variant. The Bed_T
-- art uses a wrapping Center folder/model that itself is named
-- "Center", so a recursive FindFirstChild("Center") returns the folder
-- (not a BasePart) and the swap silently falls back to bbox centre.
-- Iterate explicitly so we only ever pick the BasePart.
local function findCenterAnchor(model)
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") and desc.Name == "Center" then
			return desc
		end
	end
	return nil
end

-- Names that act as the bed's "chassis" — Center is the per-template
-- anchor, Model is the static bed art (stone border etc.). Earth is
-- treated as part of the chassis EXCEPT during dry↔wet swaps, where
-- the dirt texture itself is the thing the player is supposed to see
-- change. Callers control that via opts.swapEarth (see swapGardenModel
-- vs growTree).
local DEFAULT_STATIC_NAMES = { Center = true, Model = true, Earth = true }

-- Fade-out the provided list of children. They get reparented out of
-- the garden into a temp Folder so subsequent surgical adds don't
-- accidentally relocate them, then every BasePart's transparency
-- tweens to 1. WeldConstraints binding them to the raft stay valid
-- through the reparent (welds reference parts, not models), so they
-- don't drift while they fade. After FADE_DURATION the holder is
-- destroyed and GC reclaims everything.
local function fadeOutChildren(children)
	if #children == 0 then return end
	local fadeHolder = Instance.new("Folder")
	fadeHolder.Name = "BedFadeOut"
	fadeHolder.Parent = workspace
	local info = TweenInfo.new(FADE_DURATION, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	for _, child in children do
		child.Parent = fadeHolder
		if child:IsA("BasePart") then
			TweenService:Create(child, info, { Transparency = 1 }):Play()
		end
		for _, desc in child:GetDescendants() do
			if desc:IsA("BasePart") then
				TweenService:Create(desc, info, { Transparency = 1 }):Play()
			end
		end
	end
	task.delay(FADE_DURATION + 0.1, function()
		if fadeHolder.Parent then fadeHolder:Destroy() end
	end)
end

-- Snap every BasePart inside the given clones to Transparency = 1,
-- then tween each one back to its template-authored transparency.
-- Skips parts already at 1 (Center anchor, collision markers) so they
-- don't briefly flash visible mid-tween.
local function fadeInClones(clones)
	if #clones == 0 then return end
	local info = TweenInfo.new(FADE_DURATION, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	local function fadeInPart(part)
		local target = part.Transparency
		if target >= 1 then return end
		part.Transparency = 1
		TweenService:Create(part, info, { Transparency = target }):Play()
	end
	for _, clone in clones do
		if clone:IsA("BasePart") then fadeInPart(clone) end
		for _, desc in clone:GetDescendants() do
			if desc:IsA("BasePart") then fadeInPart(desc) end
		end
	end
end

-- Weld every BasePart inside a clone to the raft's primary, then
-- unanchor them so they ride the raft. Mirrors the 3-pass dance used
-- by placeBedTemplate but applied per-clone so the existing welded
-- static children (Center, Model) aren't re-welded redundantly.
local function weldCloneToRaft(clone, raftPrimary)
	if not raftPrimary then return end
	local parts = {}
	if clone:IsA("BasePart") then table.insert(parts, clone) end
	for _, desc in clone:GetDescendants() do
		if desc:IsA("BasePart") then table.insert(parts, desc) end
	end
	for _, part in parts do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = part
		weld.Part1 = raftPrimary
		weld.Parent = part
	end
	for _, part in parts do
		part.Anchored = false
	end
end

local function swapBedModelChildren(garden, templateName, opts)
	opts = opts or {}

	local template = rs:FindFirstChild(templateName)
		or rs:FindFirstChild(templateName, true)
		or workspace:FindFirstChild(templateName)
		or workspace:FindFirstChild(templateName, true)
	if not template then
		warn("GardenSystem: model not found: " .. templateName)
		return false
	end

	local raft = workspace:FindFirstChild("Raft")
	local raftPrimary = raft and raft.PrimaryPart or nil
	local linVel, angVel
	if raftPrimary then
		linVel = raftPrimary.AssemblyLinearVelocity
		angVel = raftPrimary.AssemblyAngularVelocity
	end

	garden.PrimaryPart = nil

	-- Save bushes so neither the diff nor the fade pipeline touches them.
	local bushes = {}
	for _, child in garden:GetChildren() do
		if child:GetAttribute("IsBush") then
			table.insert(bushes, child)
			child.Parent = workspace
		end
	end

	-- ─── Surgical swap mode (preferred) ───
	-- If the garden already has a Center BasePart and the template also
	-- has one, we can position new template children relative to the
	-- existing Center instead of re-cloning everything. Static children
	-- (Center, Model) stay put. Per-stage children (Earth, Rostok, Palm
	-- Tree, …) get the diff treatment: kept if unchanged by name,
	-- replaced if both present (cross-fade), added if new, removed if
	-- the template doesn't have them.
	local gardenCenter   = findCenterAnchor(garden)
	local templateCenter = template:IsA("Model") and findCenterAnchor(template) or nil
	if gardenCenter and templateCenter then
		local delta = gardenCenter.CFrame * templateCenter.CFrame:Inverse()

		-- Build the static set for THIS swap. Earth is static by
		-- default — only dry↔wet transitions (opts.swapEarth = true,
		-- driven by swapGardenModel) lift it out of the static list so
		-- the dirt texture actually changes. Tree-growth swaps leave
		-- swapEarth unset, so the wet Earth survives every stage.
		local staticNames = {}
		for k, v in DEFAULT_STATIC_NAMES do staticNames[k] = v end
		if opts.swapEarth then staticNames.Earth = nil end

		-- Index template children by name; static templates' children
		-- get filtered out below so we never re-clone them.
		local templateByName = {}
		for _, child in template:GetChildren() do
			templateByName[child.Name] = child
		end

		-- Plan additions: clone every non-static template child, plus
		-- any static one the garden somehow lost. Same-name same-static
		-- pair is a no-op (Center/Model carry forward as-is).
		local addedClones = {}
		for name, templateChild in templateByName do
			if staticNames[name] and garden:FindFirstChild(name) then
				-- static child already present → keep as-is
				continue
			end
			local clone = templateChild:Clone()
			if clone:IsA("BasePart") then clone.Anchored = true end
			for _, desc in clone:GetDescendants() do
				if desc:IsA("BasePart") then desc.Anchored = true end
			end
			-- Apply the template→garden delta so the clone sits at the
			-- same offset from the garden's Center that it had from the
			-- template's Center in RS.
			if clone:IsA("BasePart") then
				clone.CFrame = delta * clone.CFrame
			elseif clone:IsA("Model") then
				clone:PivotTo(delta * clone:GetPivot())
			end
			clone.Parent = garden
			table.insert(addedClones, clone)
		end

		-- Plan removals: anything in the garden that isn't a bush, isn't
		-- a static carry-over, and isn't one of the clones we just
		-- added (matched by reference, not name) needs to fade out. A
		-- name in both garden and template (e.g. Earth dry → Earth wet)
		-- ends up in `addedClones` AND has its old copy here — those
		-- cross-fade, which is exactly what we want.
		local addedSet = {}
		for _, c in addedClones do addedSet[c] = true end

		local toRemove = {}
		for _, child in garden:GetChildren() do
			if not addedSet[child]
				and not child:GetAttribute("IsBush")
				and not staticNames[child.Name] then
				table.insert(toRemove, child)
			end
		end

		fadeOutChildren(toRemove)
		fadeInClones(addedClones)
		for _, clone in addedClones do
			weldCloneToRaft(clone, raftPrimary)
		end
		if raftPrimary then
			raftPrimary.AssemblyLinearVelocity  = linVel
			raftPrimary.AssemblyAngularVelocity = angVel
		end

		for _, bush in bushes do
			bush.Parent = garden
		end
		return true
	end

	-- ─── Fallback: full re-clone + PivotTo ───
	-- Reached when either the garden or the template lacks a Center
	-- BasePart (regular garden, legacy beds). Same code path as before
	-- the surgical refactor: cross-fade the whole wrapper, clone the
	-- whole template, anchor by bbox/Center, PivotTo the saved
	-- placement pose.
	local relFromAttr = garden:GetAttribute("PlacedRelPivot")
	local desiredPivot
	if typeof(relFromAttr) == "CFrame" and raftPrimary then
		desiredPivot = raftPrimary.CFrame * relFromAttr
	else
		local fallback = garden:GetPivot()
		desiredPivot = fallback
		if raftPrimary then
			garden:SetAttribute("PlacedRelPivot",
				raftPrimary.CFrame:ToObjectSpace(fallback))
		end
	end

	local oldChildren = garden:GetChildren()
	fadeOutChildren(oldChildren)

	if template:IsA("Model") then
		for _, child in template:GetChildren() do
			local clone = child:Clone()
			if clone:IsA("BasePart") then clone.Anchored = true end
			for _, desc in clone:GetDescendants() do
				if desc:IsA("BasePart") then desc.Anchored = true end
			end
			clone.Parent = garden
		end

		local centerPart = findCenterAnchor(garden)
		local anchorPos = centerPart and centerPart.Position
			or garden:GetBoundingBox().Position
		garden.WorldPivot = CFrame.new(anchorPos)
	end

	garden:PivotTo(desiredPivot)

	fadeInClones(garden:GetChildren())

	if raftPrimary then
		for _, part in garden:GetDescendants() do
			if part:IsA("BasePart") then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = part
				weld.Part1 = raftPrimary
				weld.Parent = part
			end
		end
		for _, part in garden:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = false
			end
		end
		raftPrimary.AssemblyLinearVelocity  = linVel
		raftPrimary.AssemblyAngularVelocity = angVel
	end

	for _, bush in bushes do
		bush.Parent = garden
	end

	return true
end

-- ─── Model Swap (dry ↔ watered, like purifier) ───
-- Thin wrapper that picks the right template based on the watered
-- flag and the DryTemplate / WetTemplate attributes set at placement
-- time.
local function swapGardenModel(garden, watered)
	local placedBy = garden:GetAttribute("PlacedBy")
	local dryName = garden:GetAttribute("DryTemplate") or "Garden"
	local wetName = garden:GetAttribute("WetTemplate") or "Garden_watered"
	local templateName = watered and wetName or dryName

	-- swapEarth = true: this IS the dry↔wet transition, so the Earth
	-- texture should change. Tree-growth swaps don't pass this flag and
	-- the wet Earth survives untouched.
	if not swapBedModelChildren(garden, templateName, { swapEarth = true }) then
		return
	end

	garden:SetAttribute("IsGarden", true)
	garden:SetAttribute("IsWatered", watered)
	garden:SetAttribute("PlacedBy", placedBy)
	garden.Name = dryName

	if watered then
		enableBushGrapes(garden)
	end
end

-- ─── Tree growth ───
-- Called recursively via task.delay; each call swaps to stage `idx`
-- and schedules the next. We guard with the GrowthStage attribute so
-- a re-water / chop / unplant cycle can short-circuit a pending step.
--
-- Stage progression rule: every seed swaps to Stage_1 (the generic
-- seedling), but only "palm" seeds continue past it. Per the user
-- brief. Maps a planted seed (resource name like "Banana_Seed" or
-- Tool name like "Palm_seed") to the kind of tree it grows into. The
-- result keys TREE_STAGES_BY_KIND for the per-species progression.
local function getSeedKind(plantedSeed)
	if type(plantedSeed) ~= "string" then return nil end
	local lower = plantedSeed:lower()
	if lower:find("palm") or lower:find("coconut") then return "Palm" end
	if lower:find("banana") then return "Banana" end
	return nil
end

local function growTree(garden, idx)
	if not garden or not garden.Parent then return end
	local currentStage = garden:GetAttribute("GrowthStage")
	if currentStage ~= idx - 1 then return end

	-- Pick the stage chain for whatever was planted; fall back to a
	-- one-entry chain (just the sapling) so an unrecognised seed still
	-- shows the sapling instead of crashing.
	local kind = getSeedKind(garden:GetAttribute("PlantedSeed"))
	local stages = (kind and TREE_STAGES_BY_KIND[kind]) or { "Bed_T_1_all" }
	local stageTemplate = stages[idx]
	if not stageTemplate then return end

	if not swapBedModelChildren(garden, stageTemplate) then return end

	-- Keep the wrapper name + attributes stable so save/load + the
	-- placement overlap checks still recognise this as the tree bed.
	garden.Name = garden:GetAttribute("DryTemplate") or "Bed_T"
	garden:SetAttribute("GrowthStage", idx)

	if idx >= #stages then
		-- Final stage is a fully-grown tree the player can chop.
		-- StoneAxeSystem checks Choppable + TreeHealth on the model;
		-- IsPlantedTree tells it to swap-instead-of-Destroy when
		-- finished (handled below via _G.OnPlantedTreeChopped).
		garden:SetAttribute("Choppable", true)
		garden:SetAttribute("IsPlantedTree", true)
		garden:SetAttribute("TreeHealth", 5)
	else
		task.delay(TREE_STAGE_INTERVAL, function()
			growTree(garden, idx + 1)
		end)
	end
end

-- ─── Cross-script hooks ───
-- StoneAxeSystem calls OnPlantedTreeChopped when the player fells a
-- planted bed-tree; we revert the bed to its dry empty state instead
-- of letting :Destroy() take the whole bed down with the tree.
-- SeedBagSystem calls GrowTreeFromSeed after consuming a seed from
-- the player's inventory; we just kick off stage 1.

_G.GrowTreeFromSeed = function(garden)
	if not garden or not garden.Parent then
		print("[GardenSystem] GrowTreeFromSeed called with nil/orphan garden — skipping")
		return
	end
	print(string.format(
		"[GardenSystem] GrowTreeFromSeed: %s (PlantedSeed=%s)",
		garden:GetFullName(),
		tostring(garden:GetAttribute("PlantedSeed"))
	))
	growTree(garden, 1)
end

_G.OnPlantedTreeChopped = function(garden)
	if not garden or not garden.Parent then return end
	if not garden:GetAttribute("IsPlantedTree") then return end

	garden:SetAttribute("IsPlantedTree", nil)
	garden:SetAttribute("Choppable", nil)
	garden:SetAttribute("TreeHealth", nil)
	garden:SetAttribute("GrowthStage", nil)
	garden:SetAttribute("PlantedSeed", nil)
	garden:SetAttribute("IsWatered", false)
	garden:SetAttribute("WateredTime", nil)
	-- Drop back to the dry empty bed model.
	swapGardenModel(garden, false)
end

-- ─── Water a garden bed ───
local function waterGarden(garden, player)
	-- Check if player has a cup with fresh water equipped
	local char = player.Character
	if not char then return end

	local tool = char:FindFirstChildWhichIsA("Tool")
	if not tool then return end

	local cupState = tool:GetAttribute("CupState")
	if cupState ~= "fresh" then return end

	-- Empty the cup
	tool:SetAttribute("CupState", "empty")
	tool.Name = "Cup"

	-- Water the garden
	garden:SetAttribute("IsWatered", true)
	swapGardenModel(garden, true)

	-- Start dry timer
	local wateredTime = tick()
	garden:SetAttribute("WateredTime", wateredTime)

	task.delay(WATER_DRY_TIME, function()
		if not garden or not garden.Parent then return end
		-- Only dry out if this is still the same watering session
		if garden:GetAttribute("WateredTime") == wateredTime then
			garden:SetAttribute("IsWatered", false)
			swapGardenModel(garden, false)
		end
	end)
end

-- ─── Handle Garden Actions ───
gardenActionEvent.OnServerEvent:Connect(function(player, action, target)
	local char = player.Character
	if not char then return end

	-- Both action handlers below share the same place-a-static-bed-on-
	-- the-raft flow; only the tool name, ReplicatedStorage template,
	-- and post-place model Name differ.
	local function placeBedTemplate(toolName, templateName, finalName, extraAttributes)
		local tool = char:FindFirstChildWhichIsA("Tool")
		if not tool or tool.Name ~= toolName then
			warn(("GardenSystem[%s]: no equipped Tool named %s (got %s)"):format(
				toolName,
				toolName,
				tool and tool.Name or "<none>"
			))
			return
		end

		local raft = workspace:FindFirstChild("Raft")
		if not raft or not raft.PrimaryPart then return end

		if typeof(target) ~= "CFrame" then return end

		local worldCF = raft.PrimaryPart.CFrame:ToWorldSpace(target)

		-- Template lookup: ReplicatedStorage (direct then recursive),
		-- then Workspace (direct then recursive) as a fallback so a
		-- Studio-placed master template that wasn't moved to
		-- ReplicatedStorage still works. We Clone() either way so the
		-- original isn't destroyed when the player places one.
		local template = rs:FindFirstChild(templateName)
			or rs:FindFirstChild(templateName, true)
			or workspace:FindFirstChild(templateName)
			or workspace:FindFirstChild(templateName, true)
		if not template then
			warn(("GardenSystem[%s]: template not found (looked in ReplicatedStorage + Workspace, recursive). Move the Model named %q into ReplicatedStorage to fix."):format(toolName, templateName))
			return
		end

		local placed = template:Clone()
		placed.Name = finalName
		placed:SetAttribute("PlacedBy", player.UserId)
		if extraAttributes then
			for k, v in pairs(extraAttributes) do
				placed:SetAttribute(k, v)
			end
		end

		-- Remove scripts from the clone
		for _, desc in placed:GetDescendants() do
			if desc:IsA("Script") or desc:IsA("LocalScript") then
				desc:Destroy()
			end
		end

		-- Reset WorldPivot to the model's "Center" reference part (if it
		-- has one) or its bounding-box centre, with identity rotation.
		-- Using the Center part keeps growth-stage swaps stable: as the
		-- palm grows taller the bbox centre rises, but Center stays put.
		if placed:IsA("Model") then
			local centerPart = findCenterAnchor(placed)
			local anchorPos = centerPart and centerPart.Position
				or placed:GetBoundingBox().Position
			placed.WorldPivot = CFrame.new(anchorPos)
		end

		placed:PivotTo(worldCF)
		placed.Parent = raft

		-- Stamp the player's original placement pose as a raft-relative
		-- attribute. Every future template swap reads this so the
		-- visual bed always lands at the exact spot the player clicked,
		-- regardless of where the new template's authored pivot is
		-- relative to its visual centre.
		if raft.PrimaryPart then
			placed:SetAttribute("PlacedRelPivot",
				raft.PrimaryPart.CFrame:ToObjectSpace(worldCF))
		end

		-- Same 3-pass weld pattern used by the regular Garden / Bed /
		-- WorkBench placements: snapshot raft velocity, anchor, weld
		-- while anchored, unanchor, restore velocity. Without this the
		-- placement kicks the buoyancy spring into a vertical bob.
		local primary = raft.PrimaryPart
		local linVel = primary.AssemblyLinearVelocity
		local angVel = primary.AssemblyAngularVelocity

		for _, part in placed:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = true
			end
		end
		for _, part in placed:GetDescendants() do
			if part:IsA("BasePart") then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = part
				weld.Part1 = raft.PrimaryPart
				weld.Parent = part
			end
		end
		for _, part in placed:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = false
			end
		end

		primary.AssemblyLinearVelocity  = linVel
		primary.AssemblyAngularVelocity = angVel

		-- Remove tool from player
		tool:Destroy()
	end

	if action == "placeGarden" then
		placeBedTemplate("Garden", "Garden", "Garden", {
			IsGarden     = true,
			IsWatered    = false,
			DryTemplate  = "Garden",
			WetTemplate  = "Garden_watered",
		})

	elseif action == "placeBedGardenForTree" then
		-- Larger tree-sized garden bed. Same on-raft welding flow +
		-- watering flow as the regular garden (IsGarden = true so the
		-- shared waterGarden path picks it up), just with its own dry /
		-- wet template pair: Bed_T ↔ Bed_T_Wat.
		-- IsBedGardenForTree stays for future tree-planting logic that
		-- needs to distinguish the two bed kinds.
		placeBedTemplate("Bed_T", "Bed_T", "Bed_T", {
			IsGarden           = true,
			IsWatered          = false,
			IsBedGardenForTree = true,
			DryTemplate        = "Bed_T",
			WetTemplate        = "Bed_T_Wat",
		})

	elseif action == "waterGarden" then
		-- Player presses E while looking at a garden bed with fresh water cup
		if not target or not target:IsA("Model") or not target:GetAttribute("IsGarden") then return end
		if target:GetAttribute("IsWatered") == true then return end -- already watered
		waterGarden(target, player)

	elseif action == "plantSeed" then
		-- Player presses E on a watered tree bed while holding any
		-- seed in their inventory. Consumes one seed and kicks off
		-- the four-stage growth timer.
		if not target or not target:IsA("Model") then return end
		if not target:GetAttribute("IsBedGardenForTree") then return end
		if not target:GetAttribute("IsWatered") then return end
		if target:GetAttribute("GrowthStage") then return end -- already growing

		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp then return end
		if (hrp.Position - target:GetPivot().Position).Magnitude > 15 then return end

		-- Find the first seed the player owns. Order matters here only
		-- for picking which seed gets consumed when the player holds
		-- several types; the resulting tree currently uses the same
		-- palm stages for all three.
		local inv = _G.GetInventory and _G.GetInventory(player) or {}
		local seedName
		for _, candidate in ipairs({ "Pineapple_Seed", "Banana_Seed", "Coconut_Seed" }) do
			if (inv[candidate] or 0) > 0 then
				seedName = candidate
				break
			end
		end
		if not seedName then return end

		if _G.RemoveResourceFromInventory then
			_G.RemoveResourceFromInventory(player, seedName, 1)
		end

		target:SetAttribute("PlantedSeed", seedName)
		target:SetAttribute("GrowthStage", 0)
		-- Cancel the dry-out timer so the bed stays "watered enough"
		-- through the growth cycle. We clear WateredTime so the
		-- existing dry-out task.delay short-circuits.
		target:SetAttribute("WateredTime", nil)

		growTree(target, 1)

	elseif action == "plantSeedTool" then
		-- Player clicks a watered tree bed while holding a seed Tool
		-- (Banana_Seed / Palm_seed / etc.). Destroys the Tool +
		-- kicks off the growth chain. growTree's palm check uses the
		-- Tool's name verbatim, so "Palm_seed" / "Coconut_Seed"
		-- progress through all four stages and anything else
		-- (Banana_Seed / Pineapple_seed) freezes at the seedling.
		if not target or not target:IsA("Model") then return end
		if not target:GetAttribute("IsBedGardenForTree") then return end
		if not target:GetAttribute("IsWatered") then return end
		if target:GetAttribute("GrowthStage") then return end

		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp then return end
		if (hrp.Position - target:GetPivot().Position).Magnitude > 15 then return end

		local tool = char:FindFirstChildWhichIsA("Tool")
		if not tool then return end
		local lowerName = tool.Name:lower()
		if not lowerName:find("_seed") then return end

		local seedName = tool.Name
		-- Mark the Tool as consumed BEFORE destroying so the seed-Tool
		-- refund hook in SeedToolSystem treats this as a successful
		-- spend (no resource refund) rather than an unequip.
		tool:SetAttribute("Consumed", true)
		tool:Destroy()

		target:SetAttribute("PlantedSeed", seedName)
		target:SetAttribute("GrowthStage", 0)
		target:SetAttribute("WateredTime", nil)

		growTree(target, 1)
	end
end)
