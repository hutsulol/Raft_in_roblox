local Players = game:GetService("Players")
local rs = game:GetService("ReplicatedStorage")

-- ─── Config ───
local WATER_DRY_TIME = 60 -- seconds before watered garden dries out

-- Tree growth progression for planted seeds. The seedling stage is
-- shared across every seed type ("Bed_T_1_all" = "bed with any tree
-- sapling"); only palm seeds continue past it into the per-species
-- stages. Banana / pineapple art will get its own *_B_*/_P_* set if /
-- when those species need distinct intermediate stages.
local TREE_STAGES = {
	"Bed_T_1_all",
	"Bed_T_P_2",
	"Bed_T_P_3",
	"Bed_T_P_Finish",
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
local function swapBedModelChildren(garden, templateName)
	local template = rs:FindFirstChild(templateName)
		or rs:FindFirstChild(templateName, true)
		or workspace:FindFirstChild(templateName)
		or workspace:FindFirstChild(templateName, true)
	if not template then
		warn("GardenSystem: model not found: " .. templateName)
		return false
	end

	-- Snapshot raft velocity + capture garden pose AS RAFT-RELATIVE
	-- BEFORE any destroy/clone work (T14/T19). The destroy + clone
	-- steps span a couple of physics frames during which the raft
	-- drifts, so saving a world CFrame and PivotTo'ing it back later
	-- places the new parts against a stale raft pose. Welds then
	-- lock that drift in and the solver kicks the assembly to fix
	-- it → the bouncing.
	local raft = workspace:FindFirstChild("Raft")
	local raftPrimary = raft and raft.PrimaryPart or nil
	local linVel, angVel
	if raftPrimary then
		linVel = raftPrimary.AssemblyLinearVelocity
		angVel = raftPrimary.AssemblyAngularVelocity
	end

	-- Clear PrimaryPart FIRST so the saved pivot below reads the
	-- wrapper's actual Origin (WorldPivot), not the previous template's
	-- primary CFrame which is offset by that primary's local pose. On
	-- the first swap these would have matched; on every subsequent
	-- swap the offset compounded and tilted the model further.
	garden.PrimaryPart = nil

	-- Save the wrapper's current PIVOT (its "Origin" in world space).
	-- With PrimaryPart cleared, GetPivot returns WorldPivot, which is
	-- the only stable per-wrapper Origin across consecutive swaps.
	local savedPivot = garden:GetPivot()
	local savedRelPivot
	if raftPrimary then
		savedRelPivot = raftPrimary.CFrame:ToObjectSpace(savedPivot)
	end

	-- Save bush children (don't destroy them during swap!). Tree-stage
	-- swaps don't have bushes, so this loop is a no-op for them.
	local bushes = {}
	for _, child in garden:GetChildren() do
		if child:GetAttribute("IsBush") then
			table.insert(bushes, child)
			child.Parent = workspace
		end
	end

	-- Clear old children
	for _, child in garden:GetChildren() do
		child:Destroy()
	end

	-- Clone new model contents, anchor everything first
	if template:IsA("Model") then
		for _, child in template:GetChildren() do
			local clone = child:Clone()
			if clone:IsA("BasePart") then clone.Anchored = true end
			for _, desc in clone:GetDescendants() do
				if desc:IsA("BasePart") then desc.Anchored = true end
			end
			clone.Parent = garden
		end

		-- ✱ Adopt the template's authored Origin as the wrapper's pivot.
		-- The cloned children sit at template-local positions around
		-- this pivot, so PivotTo below moves everything consistently
		-- relative to the new template's authored layout.
		garden.WorldPivot = template:GetPivot()
	end

	-- Move the (just-rebuilt) model so its pivot lands at the saved
	-- pose. With WorldPivot now aligned with the template's origin
	-- and PrimaryPart cleared, PivotTo translates+rotates every clone
	-- by exactly the same delta — orientation is preserved.
	local desiredPivot = (savedRelPivot and raftPrimary)
		and (raftPrimary.CFrame * savedRelPivot)
		or savedPivot
	garden:PivotTo(desiredPivot)

	-- Deliberately DO NOT re-bind a PrimaryPart on the wrapper. The
	-- only consumer that cared (StoneAxeSystem) reads
	-- treeModel:GetPivot().Position, which works either way; setting a
	-- primary would make WorldPivot start tracking that part again and
	-- reintroduce the offset drift the swap pipeline just got rid of.
	-- garden.WorldPivot is now the single source of truth for the bed's
	-- Origin and it survives every future swap unchanged.

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

	if not swapBedModelChildren(garden, templateName) then return end

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
-- brief, banana / pineapple seedlings stop at Stage_1 until further
-- per-species art lands. The palm check looks for "palm" or
-- "coconut" inside the PlantedSeed string so both the Tool name
-- "Palm_seed" and the resource name "Coconut_Seed" qualify.
local function isPalmSeed(plantedSeed)
	if type(plantedSeed) ~= "string" then return false end
	local lower = plantedSeed:lower()
	return lower:find("palm") ~= nil or lower:find("coconut") ~= nil
end

local function growTree(garden, idx)
	if not garden or not garden.Parent then
		print(string.format("[GardenSystem] growTree(%s) skipped: garden parent missing", tostring(idx)))
		return
	end
	local currentStage = garden:GetAttribute("GrowthStage")
	if currentStage ~= idx - 1 then
		print(string.format(
			"[GardenSystem] growTree(%s) skipped: GrowthStage=%s, expected %s",
			tostring(idx), tostring(currentStage), tostring(idx - 1)
		))
		return
	end
	local stageTemplate = TREE_STAGES[idx]
	if not stageTemplate then
		print(string.format("[GardenSystem] growTree(%s) skipped: no TREE_STAGES[%s]", tostring(idx), tostring(idx)))
		return
	end

	print(string.format(
		"[GardenSystem] growTree(%s) → swap to %q (PlantedSeed=%s)",
		tostring(idx), stageTemplate, tostring(garden:GetAttribute("PlantedSeed"))
	))

	if not swapBedModelChildren(garden, stageTemplate) then
		print(string.format("[GardenSystem] growTree(%s) FAILED: swapBedModelChildren returned false", tostring(idx)))
		return
	end

	-- Keep the wrapper name + attributes stable so save/load + the
	-- placement overlap checks still recognise this as the tree bed.
	garden.Name = garden:GetAttribute("DryTemplate") or "Bed_T"
	garden:SetAttribute("GrowthStage", idx)

	local palm = isPalmSeed(garden:GetAttribute("PlantedSeed"))

	if idx == #TREE_STAGES then
		-- Final stage is a fully-grown tree the player can chop.
		-- StoneAxeSystem checks Choppable + TreeHealth on the model;
		-- IsPlantedTree tells it to swap-instead-of-Destroy when
		-- finished (handled below via _G.OnPlantedTreeChopped).
		garden:SetAttribute("Choppable", true)
		garden:SetAttribute("IsPlantedTree", true)
		garden:SetAttribute("TreeHealth", 5)
		print(string.format("[GardenSystem] growTree(%s) reached final stage — marked Choppable", tostring(idx)))
	elseif palm then
		print(string.format("[GardenSystem] growTree(%s) scheduling next stage in %ds", tostring(idx), TREE_STAGE_INTERVAL))
		task.delay(TREE_STAGE_INTERVAL, function()
			growTree(garden, idx + 1)
		end)
	else
		print(string.format("[GardenSystem] growTree(%s) stopping — PlantedSeed isn't a palm (%s)", tostring(idx), tostring(garden:GetAttribute("PlantedSeed"))))
	end
	-- else: non-palm seed → stays at Stage_1 indefinitely.
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

		-- Reset WorldPivot to bounding box center with identity rotation
		if placed:IsA("Model") then
			local bbCF = placed:GetBoundingBox()
			placed.WorldPivot = CFrame.new(bbCF.Position)
		end

		placed:PivotTo(worldCF)
		placed.Parent = raft

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
