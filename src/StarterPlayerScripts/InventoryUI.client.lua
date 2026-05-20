local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)

local inventoryEvent = ReplicatedStorage:WaitForChild("InventoryUpdate")
local inventoryCraftEvent = ReplicatedStorage:WaitForChild("InventoryCraft")

-- Seed-as-Tool flow was retired — seeds now live in the leaf bag
-- container (see SeedBagSystem.server.lua) and never appear as a
-- main-inventory stack. Empty whitelist + nil event keep any stale
-- click-on-seed handlers below as harmless no-ops.
local equipSeedEvent = nil
local SEED_RESOURCE_SET = {}

-- Food-as-Tool flow. Clicking a Banana / Coconut / Pineapple slot
-- in the inventory tells the server to spawn the matching Tool in
-- the player's hand (and decrement the stack by 1). A second click
-- while the Tool is held eats it for hunger + HP; an unequip
-- without eating refunds the resource. Server lives in
-- ServerScriptService/FoodSystem.server.lua.
local equipFoodEvent = ReplicatedStorage:FindFirstChild("EquipFoodAsTool")
if not equipFoodEvent then
	equipFoodEvent = ReplicatedStorage:WaitForChild("EquipFoodAsTool", 5)
end

local FOOD_RESOURCE_SET = {
	Banana    = true,
	Coconut   = true,
	Pineapple = true,
}

-- Bush-seed-as-Tool flow. Riding on the same BushAction RemoteEvent
-- HungerSystem already exposes for berry-bush placement avoids
-- depending on a new server script being added to Studio. Clicking
-- a Pineapple_Bush_Seed inventory slot fires
-- BushAction("equipBushSeed", resourceName) and the server spawns
-- the matching placement Tool in the player's hand (refund-on-
-- unequip-without-place is handled server-side).
local bushActionEvent = ReplicatedStorage:FindFirstChild("BushAction")
if not bushActionEvent then
	bushActionEvent = ReplicatedStorage:WaitForChild("BushAction", 5)
end

local BUSH_SEED_RESOURCE_SET = {
	Pineapple_Bush_Seed = true,
}

local LOG_ICON = "rbxassetid://116178347748793"
local PLASTIC_ICON = "rbxassetid://132919988751848"
local STONE_ICON = "rbxassetid://96450657403376"
local IRON_ORE_ICON = "rbxassetid://78456892304314"
local IRON_INGOT_ICON = "rbxassetid://72890243946368"
-- Leaves / Sand / Clay / Wet_Brick / Dry_Brick had asset ids that were
-- updated in WorkbenchUI but never propagated here, so the inventory's
-- crafting panel kept rendering the old artwork while every other UI
-- (workbench, furnace, mining highlight, resource pull) showed the
-- new one. Synced to the WorkbenchUI ids below.
local LEAVES_ICON = "rbxassetid://96691360298069"

local PLANK_ICON = "rbxassetid://118108820731466"
local ROPE_ICON = "rbxassetid://78492721752628"
local SAND_ICON = "rbxassetid://92407877736322"
local CLAY_ICON = "rbxassetid://129473903672183"
local WET_BRICK_ICON = "rbxassetid://139059474647090"
local DRY_BRICK_ICON = "rbxassetid://97609326528615"
local BAG_EMPTY_ICON = "rbxassetid://89398456198664"
local BAG_WITH_CLAY_ICON = "rbxassetid://126238050436106"
local BAG_WITH_SAND_ICON = "rbxassetid://77748685223141"
local GLASS_ICON = "rbxassetid://85347221722445"
local GLASS_PANEL_ICON = "rbxassetid://79199838395462"

local BLUE_FISH_ICON = "rbxassetid://95052485461834"
local CARP_FISH_ICON = "rbxassetid://122853256629696"
local FISH_BONES_ICON = "rbxassetid://118274743954023"
local FOIL_FISH_ICON = "rbxassetid://86978570169083"
local JELLY_FISH_ICON = "rbxassetid://139713210103014"
local LEGENDARY_FISH_ICON = "rbxassetid://73775072217611"
local SEABASS_FISH_ICON = "rbxassetid://112734818459787"
local TILAPIA_FISH_ICON = "rbxassetid://128104970819877"

local RESOURCE_ICONS = {
	Log = LOG_ICON,
	Plastic = PLASTIC_ICON,
	Stone = STONE_ICON,
	Iron_Ore = IRON_ORE_ICON,
	Iron_Ingot = IRON_INGOT_ICON,
	Plank = PLANK_ICON,
	Leaves = LEAVES_ICON,
	Rope = ROPE_ICON,
	Sand = SAND_ICON,
	Clay = CLAY_ICON,
	Wet_Brick = WET_BRICK_ICON,
	Dry_Brick = DRY_BRICK_ICON,
	bag_with_clay_2 = BAG_WITH_CLAY_ICON,
	bag_with_sand_2 = BAG_WITH_SAND_ICON,
	glass = GLASS_ICON,
	glass_panel = GLASS_PANEL_ICON,
	Blue_Fish = BLUE_FISH_ICON,
	Carp_Fish = CARP_FISH_ICON,
	Fish_Bones = FISH_BONES_ICON,
	Foil_Fish = FOIL_FISH_ICON,
	Jelly_Fish = JELLY_FISH_ICON,
	Legendary_Fish = LEGENDARY_FISH_ICON,
	Seabass_Fish = SEABASS_FISH_ICON,
	Tilapia_Fish = TILAPIA_FISH_ICON,
	-- Fruits dropped from trees (Banana/Coconut) and the new
	-- hand-harvested Pineapple, plus the matching seeds the player
	-- can replant.
	Banana          = "rbxassetid://95041000167181",
	Banana_Seed     = "rbxassetid://73140419103065",
	Coconut         = "rbxassetid://120321968340866",
	Coconut_Seed    = "rbxassetid://138995623166184",
	Pineapple       = "rbxassetid://93324727574975",
	Pineapple_Seed  = "rbxassetid://128520746024640",
	-- Bush seed (harvested from a Pineapple bush). Stored in the
	-- regular inventory; equipping it spawns a placement Tool that
	-- drives CupPurifier's ghost just like the berry bush.
	Pineapple_Bush_Seed = "rbxassetid://128520746024640",
}

local TOOL_ICONS = {
	["Hammer"] = "rbxassetid://72168072336946",
	["Pick-Axe"] = "rbxassetid://102411845666126",
	["Cup"] = "rbxassetid://99673504095026",
	["Destitalor"] = "rbxassetid://90221080738714",
	["Furnace"] = "rbxassetid://117760352651529",
	["bush"] = "rbxassetid://93957489757544",

	["Machete"] = "rbxassetid://92926554091794",
	["Wood_Knife"] = "rbxassetid://110032041583533",
	["WorkBench"] = "rbxassetid://116083064101694",
	["Bed"] = "rbxassetid://85069521486600",
	["Garden"] = "rbxassetid://137766871451752",
	["Bed_T"] = "rbxassetid://137766871451752",
	["Paddle"] = "rbxassetid://93358108538106",
	["Sawmill"] = "rbxassetid://75858978626954",
	["Shovel"] = "rbxassetid://123765089142597",
	["Hook"] = "rbxassetid://110032041583533",
	["Axe"] = "rbxassetid://110032041583533",
	-- Stone_Axe inherits the Pick-Axe icon as a placeholder until a
	-- dedicated axe asset lands; the equipped Tool's TextureId
	-- override on line 775 takes precedence in the hotbar anyway.
	["Stone_Axe"] = "rbxassetid://112306255674133",
	["[GRAPES]"] = "rbxassetid://137478230275649",
	["Grapes"] = "rbxassetid://137478230275649",
	["FishingRod"] = "rbxassetid://105180666555503",
	["Injector"] = "rbxassetid://81132472504693",
	["EmptyCapsule"] = "rbxassetid://116714708119585",
	["FullCapsule"] = "rbxassetid://132749498016835",
	["Phone"] = "rbxassetid://123703470055474",
	["Anchor_part"] = "rbxassetid://120414328052740",
	["bag_empty_2"] = BAG_EMPTY_ICON,
	["Sand Bag"]    = "rbxassetid://107012847180882",
	-- Seed-as-Tool variants. The Tool templates the user authored
	-- carry these names; the icons mirror the matching seed resource
	-- so they read the same as the inventory stack form.
	["Palm_seed"]           = "rbxassetid://138995623166184",
	["Banana_Seed"]         = "rbxassetid://73140419103065",
	["Pineapple_seed"]      = "rbxassetid://128520746024640",
	-- Bush-seed Tool variant — same art as the tree seed; the suffix
	-- differentiates "plant a bush on a Garden" from "plant a tree
	-- sapling on Bed_T". Without this entry the slot fell back to
	-- LOG_ICON when the Tool was rebuilt into a slot.
	["Pineapple_Bush_Seed"] = "rbxassetid://128520746024640",
	-- Food Tools that the player can temporarily equip from the
	-- main-inventory resource stack. Same icons as the resource
	-- form so the hotbar slot stays visually consistent.
	["Banana"]         = "rbxassetid://95041000167181",
	["Coconut"]        = "rbxassetid://120321968340866",
	["Pineapple"]      = "rbxassetid://93324727574975",
}

-- Sand Bag fill stages — one table per resource the bag can hold.
-- Mirrors SandBagUI.client.lua's STAGES_BY_CONTENT exactly so the
-- hotbar icon always matches the inspector. Empty (pct = 0) is the
-- same image across types so picking either table is fine for an
-- empty bag.
local BAG_STAGES_BY_CONTENT = {
	Sand = {
		{ pct =   0, image = "rbxassetid://107012847180882" },
		{ pct =  10, image = "rbxassetid://87535824644391"  },
		{ pct =  30, image = "rbxassetid://102984915310557" },
		{ pct =  50, image = "rbxassetid://132918131694676" },
		{ pct =  70, image = "rbxassetid://135545427179049" },
		{ pct = 100, image = "rbxassetid://76170913773356"  },
	},
	Clay = {
		{ pct =   0, image = "rbxassetid://107012847180882" },
		{ pct =  10, image = "rbxassetid://137121316772176" },
		{ pct =  30, image = "rbxassetid://94079996711573"  },
		{ pct =  50, image = "rbxassetid://71260002598684"  },
		{ pct =  70, image = "rbxassetid://85470636629483"  },
		{ pct = 100, image = "rbxassetid://115968010442225" },
	},
}

local function isSandBagTool(tool)
	if not tool or not tool:IsA("Tool") then return false end
	local a = tool.Name:lower():gsub("[_%s]", "")
	return a == "sandbag"
end

local function getSandBagIcon(tool)
	if not tool then return nil end
	local fill    = tool:GetAttribute("SandFill")    or 0
	local content = tool:GetAttribute("BagContent")
	local stages  = BAG_STAGES_BY_CONTENT[content] or BAG_STAGES_BY_CONTENT.Sand
	for i = #stages, 1, -1 do
		if fill >= stages[i].pct then
			return stages[i].image
		end
	end
	return stages[1].image
end

-- Forward-declared so the SandFill listener (created early) can reach
-- the in-place icon swapper (defined later, because it has to read
-- `slotData` and `hotbarGui` which haven't been declared yet at this
-- point in the file).
local refreshSandBagIconInPlace

-- Tools we've already wired a SandFill listener on, so we don't stack
-- N connections on the same instance across rebuilds.
local sandBagHooked = {}
local function ensureSandBagHook(tool)
	if not tool or sandBagHooked[tool] then return end
	if not isSandBagTool(tool) then return end
	sandBagHooked[tool] = true
	local function onChange()
		-- Don't trigger a full slot rebuild — that destroys the icon
		-- and creates a new one, which leaves a one-frame gap. Stack
		-- the new texture on top of the old icon, wait a render, then
		-- drop the underlying one. The two stages line up exactly, so
		-- the only thing that visually changes is the sand level (or
		-- the resource type, on a Sand ↔ Clay swap).
		if refreshSandBagIconInPlace then
			refreshSandBagIconInPlace(tool)
		end
	end
	-- Both attributes can change the icon: SandFill drives the stage,
	-- BagContent drives which texture family (sand vs clay) we sample
	-- from. Re-render on either.
	tool:GetAttributeChangedSignal("SandFill"):Connect(onChange)
	tool:GetAttributeChangedSignal("BagContent"):Connect(onChange)
	tool.AncestryChanged:Connect(function()
		if not tool:IsDescendantOf(game) then
			sandBagHooked[tool] = nil
		end
	end)
end

-- Forward-declared so functions above line 1585 (quickTransfer,
-- drag-drop handlers, etc.) can reference it via the same upvalue
-- that gets assigned later. Without this, those call sites resolve
-- against a nil global and throw 'attempt to call a nil value'.
local syncSlotLayoutToServer

-- Exposed so the mercenary backpack UI can reuse the same icons.
_G.GetItemIcon = function(itemName)
	if not itemName then return "" end
	return RESOURCE_ICONS[itemName] or TOOL_ICONS[itemName] or ""
end

local inventory = {Log = 0, Plastic = 0, Stone = 0, Iron_Ore = 0, Iron_Ingot = 0, Leaves = 0}
local recipes = {}
local selectedRecipe = nil
local selectedCategory = nil
local detailOverlay = nil
local categoryOverlay = nil
local CATEGORIES = {"Tools", "Technology", "Misc", "Resources"}
local isOpen = false
local screenGui = nil
local hotbarGui = nil

-- Wooden / tan inventory palette.
local COLORS = {
	panelBg = Color3.fromRGB(139, 109, 63),
	panelBorder = Color3.fromRGB(100, 75, 40),
	slotBg = Color3.fromRGB(175, 145, 95),
	slotBorder = Color3.fromRGB(120, 90, 50),
	titleText = Color3.fromRGB(50, 35, 15),
	lightText = Color3.fromRGB(255, 245, 220),
	craftPanelBg = Color3.fromRGB(220, 205, 175),
	craftItemBg = Color3.fromRGB(200, 180, 140),
	craftItemHover = Color3.fromRGB(180, 160, 120),
	affordable = Color3.fromRGB(60, 160, 60),
	notAffordable = Color3.fromRGB(160, 60, 60),
	hotbarBg = Color3.fromRGB(139, 109, 63),
	separator = Color3.fromRGB(200, 185, 150),
	equipped = Color3.fromRGB(200, 170, 100),
}

local HOTBAR_SLOTS = 8
local GRID_SLOTS = 20
local TOTAL_SLOTS = HOTBAR_SLOTS + GRID_SLOTS
local SLOT_SIZE = 80
local SLOT_PAD = 8
local COLS = 5
local BASE_UNLOCKED_SLOTS = HOTBAR_SLOTS + 5 -- hotbar + first grid row until Strength unlocks more

-- ── Responsive UI scaling ─────────────────────────────────────────────
-- The inventory / hotbar / crafting UI is laid out in pixel offsets at a
-- reference resolution. On smaller screens (phones, vertical windows,
-- studio emulator) we attach a `UIScale` that shrinks everything so the
-- combined block + hotbar always fit. On large screens we never scale
-- above 1.0 so the UI doesn't grow absurdly large on 4K monitors.
local UI_REF_WIDTH  = 1280   -- combined UI (craft + inventory) is ~700 wide
local UI_REF_HEIGHT = 720    -- hotbar + inventory panel comfortably fit
local UI_MIN_SCALE  = 0.45
local UI_MAX_SCALE  = 1.0

local function computeUIScale()
	local camera = workspace.CurrentCamera
	local vp = camera and camera.ViewportSize or Vector2.new(UI_REF_WIDTH, UI_REF_HEIGHT)
	local s = math.min(vp.X / UI_REF_WIDTH, vp.Y / UI_REF_HEIGHT)
	return math.clamp(s, UI_MIN_SCALE, UI_MAX_SCALE)
end

-- Every ScreenGui that holds part of the inventory UI should be
-- registered here so the scale stays in sync when the viewport resizes.
local scaledGuis = setmetatable({}, { __mode = "k" })

local function attachResponsiveScale(gui)
	if not gui then return end
	local scaleObj = gui:FindFirstChildOfClass("UIScale")
	if not scaleObj then
		scaleObj = Instance.new("UIScale")
		scaleObj.Parent = gui
	end
	scaleObj.Scale = computeUIScale()
	scaledGuis[gui] = scaleObj
end

-- Exposed so other client scripts (e.g. the mercenary backpack window)
-- can share the same responsive scaling.
_G.AttachInventoryUIScale = attachResponsiveScale

do
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			local s = computeUIScale()
			for gui, scaleObj in pairs(scaledGuis) do
				if gui and gui.Parent and scaleObj then
					scaleObj.Scale = s
				end
			end
		end)
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		local newCam = workspace.CurrentCamera
		if newCam then
			newCam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				local s = computeUIScale()
				for gui, scaleObj in pairs(scaledGuis) do
					if gui and gui.Parent and scaleObj then
						scaleObj.Scale = s
					end
				end
			end)
		end
	end)
end

-- How many total slots (hotbar + grid) the player currently has unlocked.
-- Driven by `Characteristics.UnlockedInventorySlots` which is computed from
-- the player's Strength stat by Strength.server.lua. Defaults to the
-- base 13 so the UI is usable before the value replicates.
local unlockedSlots = BASE_UNLOCKED_SLOTS

-- Populated while the inventory window is built. Each entry is a
-- { button = TextButton, stroke = UIStroke } record for the grid slot
-- at `HOTBAR_SLOTS + i`. Used by applyUnlockedSlots() to repaint the
-- locked / unlocked visuals whenever the unlocked-count changes.
local gridSlotVisuals = {}
local lockedOverlayLabel = nil

local function isSlotLocked(globalIdx)
	return globalIdx > unlockedSlots
end

-- Highest grid slot index (global) that writes are allowed to touch.
-- Used to clamp `findEmptySlot` / distribution ranges so that new items
-- never land in a locked slot.
local function maxWritableSlot()
	return math.min(TOTAL_SLOTS, unlockedSlots)
end

-- Repaints every grid slot for the current `unlockedSlots` count and
-- positions the big "NEED STRENGTH" overlay over the locked region.
-- Called whenever `Characteristics.UnlockedInventorySlots` changes and
-- once after the inventory UI is built.
local function applyUnlockedSlots()
	if #gridSlotVisuals == 0 then return end

	for i, rec in ipairs(gridSlotVisuals) do
		local globalIdx = HOTBAR_SLOTS + i
		local locked    = globalIdx > unlockedSlots
		if rec.button then
			rec.button.BackgroundTransparency = locked and 0.55 or 0.05
			rec.button.AutoButtonColor        = false
			rec.button.Active                 = not locked
		end
		if rec.stroke then
			rec.stroke.Transparency = locked and 0.7 or 0
		end
	end

	if lockedOverlayLabel then
		-- Only span rows whose slots are ALL locked. A row that's still
		-- partially usable keeps its normal per-slot dimming instead of
		-- being covered by the banner (otherwise the banner would
		-- obscure the slots the player can still interact with).
		--
		-- The banner is only shown while the player is still at the
		-- base unlock count (Strength 0). The instant they upgrade
		-- Strength to level 2 and earn their first extra slot, the
		-- banner disappears for good — by then they already know how
		-- to get more slots and the reminder becomes visual noise.
		local unlockedGrid      = math.max(unlockedSlots - HOTBAR_SLOTS, 0)
		local firstFullLockRow  = math.ceil(unlockedGrid / COLS)
		local totalRows         = math.ceil(GRID_SLOTS / COLS)
		local atBaseUnlock      = unlockedSlots <= BASE_UNLOCKED_SLOTS

		if atBaseUnlock and firstFullLockRow < totalRows then
			local rows = totalRows - firstFullLockRow
			local y = SLOT_PAD + firstFullLockRow * (SLOT_SIZE + SLOT_PAD)
			local h = rows * (SLOT_SIZE + SLOT_PAD) - SLOT_PAD
			lockedOverlayLabel.Position = UDim2.new(0, SLOT_PAD, 0, y)
			lockedOverlayLabel.Size     = UDim2.new(1, -SLOT_PAD * 2, 0, h)
			lockedOverlayLabel.Visible  = true
		else
			lockedOverlayLabel.Visible = false
		end
	end
end

-- ─── Unified Slot Data ───
-- Slots 1..8 = hotbar, slots 9..28 = inventory grid
local slotData = {}
_G.InventorySlotData = slotData
local slotsInitialized = false

-- Overlay-then-remove icon swap for a Sand Bag tool whose SandFill
-- attribute changed. Sequence:
--   1. SandFill changes → schedule the swap with task.delay so the
--      texture has a generous moment to finish decoding into the GPU
--      cache before we put it on screen.
--   2. After the delay, clone the existing ItemIcon, point the clone
--      at the new stage texture and parent it ON TOP of the old one.
--   3. Wait ~3 render frames (well past any decode hiccup), then
--      destroy the underlying icon and rename / re-Z the clone so it
--      becomes the new canonical ItemIcon.
-- The two stages line up exactly (same anchor / size / position), so
-- the only thing the player visually sees change is the sand level.
local SWAP_DELAY_SEC   = 0.1   -- delay between attribute change and overlay
local POST_OVERLAY_GAP = 0.10  -- delay between overlay and old-icon removal

refreshSandBagIconInPlace = function(tool)
	if not tool or not hotbarGui then return end
	local bar = hotbarGui:FindFirstChild("Hotbar")
	if not bar then return end

	for i = 1, HOTBAR_SLOTS do
		local data = slotData[i]
		if data and data.type == "tool" and data.toolInst == tool then
			local slot = bar:FindFirstChild("HotbarSlot_" .. i)
			if not slot then return end
			local oldIcon = slot:FindFirstChild("ItemIcon")
			if not oldIcon or not oldIcon:IsA("ImageLabel") then return end

			local nextImage = getSandBagIcon(tool)
			if not nextImage or nextImage == oldIcon.Image then return end

			task.delay(SWAP_DELAY_SEC, function()
				-- Re-check between the delay and the swap: the slot, the
				-- icon or the tool itself might be gone by now.
				if not oldIcon or not oldIcon.Parent then return end
				if not slot or not slot.Parent then return end
				if data ~= slotData[i] or data.toolInst ~= tool then return end

				local stillNext = getSandBagIcon(tool)
				if not stillNext or stillNext == oldIcon.Image then return end

				local origZ    = oldIcon.ZIndex
				local newIcon  = oldIcon:Clone()
				newIcon.Name   = "ItemIcon_swap"
				newIcon.Image  = stillNext
				newIcon.ZIndex = origZ + 1
				newIcon.Parent = slot

				task.delay(POST_OVERLAY_GAP, function()
					if oldIcon and oldIcon.Parent then oldIcon:Destroy() end
					if newIcon and newIcon.Parent then
						newIcon.Name   = "ItemIcon"
						newIcon.ZIndex = origZ
					end
				end)
			end)
			return
		end
	end
end

-- ─── Drag ───
local dragState = {
	active = false,
	sourceSlot = nil,
	data = nil,
	ghost = nil,
	ghostGui = nil,
	didDrag = false,
	startPos = nil,
	splitMode = false, -- right-click: move only 1 item
}
local DRAG_THRESHOLD = 5

-- ─── Tooltip ───
local tooltipGui = nil
local tooltipLabel = nil

local DISPLAY_NAMES = {
	Iron_Ore = "Iron Ore",
	Iron_Ingot = "Iron Ingot",
	Wet_Brick = "Wet Brick",
	Dry_Brick = "Dry Brick",
	["Pick-Axe"] = "Pick-Axe",
	WorkBench = "Workbench",

	Wood_Knife = "Wood Knife",
	Stone_Axe = "Stone Axe",
}

local function getDisplayName(data)
	if not data then return nil end
	-- Blood capsules carry a per-NPC-type label in data.displayName
	-- (e.g. "Pirate Blood", "Infected Military Blood") so the tooltip shows
	-- the differentiated name instead of the generic "FullCapsule".
	if data.displayName and data.displayName ~= "" then
		return data.displayName
	end
	local key = data.name or data.toolName
	if not key then return nil end
	if DISPLAY_NAMES[key] then return DISPLAY_NAMES[key] end
	return (key:gsub("_", " "))
end

-- Shared with the chest / mercenary backpack UIs so their hover
-- tooltips use the same underscore-stripping + override table as the
-- main inventory.
_G.GetItemDisplayName = function(name)
	if typeof(name) ~= "string" or name == "" then return nil end
	if DISPLAY_NAMES[name] then return DISPLAY_NAMES[name] end
	return (name:gsub("_", " "))
end

local function ensureTooltipGui()
	if tooltipGui and tooltipGui.Parent then return end
	tooltipGui = Instance.new("ScreenGui")
	tooltipGui.Name = "InventoryTooltip"
	tooltipGui.ResetOnSpawn = false
	tooltipGui.IgnoreGuiInset = true
	tooltipGui.DisplayOrder = 200
	tooltipGui.Enabled = false
	tooltipGui.Parent = playerGui

	tooltipLabel = Instance.new("TextLabel")
	tooltipLabel.Name = "Label"
	tooltipLabel.AutomaticSize = Enum.AutomaticSize.XY
	tooltipLabel.Size = UDim2.new(0, 0, 0, 0)
	tooltipLabel.BackgroundColor3 = Color3.fromRGB(30, 22, 10)
	tooltipLabel.BackgroundTransparency = 0.1
	tooltipLabel.BorderSizePixel = 0
	tooltipLabel.TextColor3 = Color3.fromRGB(255, 245, 220)
	tooltipLabel.Font = Enum.Font.GothamMedium
	tooltipLabel.TextSize = 14
	tooltipLabel.Text = ""
	tooltipLabel.Parent = tooltipGui

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = tooltipLabel

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = tooltipLabel

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(120, 90, 50)
	stroke.Thickness = 1
	stroke.Parent = tooltipLabel
end

local function hideTooltip()
	if tooltipGui then tooltipGui.Enabled = false end
end

-- Short-lived popup used when the player tries to drop an item into a
-- locked inventory slot. Lives in its own ScreenGui so it doesn't mess
-- with the regular hover tooltip, and auto-destroys after fading out.
local function showLockedDropMessage(mousePos)
	local gui = Instance.new("ScreenGui")
	gui.Name = "LockedSlotPopup"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 250
	gui.Parent = playerGui

	local label = Instance.new("TextLabel")
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.BackgroundColor3 = Color3.fromRGB(40, 15, 15)
	label.BackgroundTransparency = 0.1
	label.BorderSizePixel = 0
	label.TextColor3 = Color3.fromRGB(255, 220, 180)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.Text = "Slot blocked, upgrade your strength"
	label.Parent = gui

	local pad = Instance.new("UIPadding")
	pad.PaddingTop    = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.PaddingLeft   = UDim.new(0, 10)
	pad.PaddingRight  = UDim.new(0, 10)
	pad.Parent = label

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = label

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(180, 90, 90)
	stroke.Thickness = 1.5
	stroke.Parent = label

	-- Position near the mouse; flip below if it would overflow the top.
	label.Position = UDim2.fromOffset(mousePos.X + 14, mousePos.Y - 34)
	task.defer(function()
		if label.AbsolutePosition.Y < 4 then
			label.Position = UDim2.fromOffset(mousePos.X + 14, mousePos.Y + 18)
		end
	end)

	task.delay(0.9, function()
		if not gui.Parent then return end
		local t = TweenService:Create(
			label,
			TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 1, TextTransparency = 1 }
		)
		stroke.Enabled = false
		t:Play()
		t.Completed:Connect(function()
			gui:Destroy()
		end)
	end)
end

local function updateTooltipPosition(mousePos)
	if not tooltipGui or not tooltipGui.Enabled or not tooltipLabel then return end
	local x = mousePos.X + 14
	local y = mousePos.Y - tooltipLabel.AbsoluteSize.Y - 10
	if y < 4 then y = mousePos.Y + 18 end
	tooltipLabel.Position = UDim2.fromOffset(x, y)
end

-- Returns true when another full-screen overlay is on top of the
-- inventory (phone menu, shop, etc.) and hotbar hover tooltips
-- would visually bleed through. PhoneMenu publishes _G.PhoneScreenGui
-- which flips .Enabled on open/close, so checking that is enough for
-- the current UI set; future overlays can hook the same handshake.
local function isHoverBlockingOverlayOpen()
	local phone = _G.PhoneScreenGui
	if phone and phone:IsA("ScreenGui") and phone.Enabled then
		return true
	end
	return false
end

local function showTooltipForSlot(slotIndex)
	-- Don't show while the phone (or any future overlay) is covering
	-- the playfield — the cursor may still technically be over a
	-- hotbar slot, but the tooltip would render on top of the overlay.
	if isHoverBlockingOverlayOpen() then
		hideTooltip()
		return
	end
	local data = slotData[slotIndex]
	local name = getDisplayName(data)
	if not name then
		hideTooltip()
		return
	end
	if dragState.active then
		hideTooltip()
		return
	end
	-- Don't show tooltip while crafting overlays cover the inventory
	if categoryOverlay or detailOverlay then
		hideTooltip()
		return
	end
	ensureTooltipGui()
	tooltipLabel.Text = name
	tooltipGui.Enabled = true
	updateTooltipPosition(UserInputService:GetMouseLocation())
end

-- ─── Helpers ───

local function canAfford(recipe)
	if not recipe or not recipe.costs then return false end
	for item, amount in recipe.costs do
		if (inventory[item] or 0) < amount then return false end
	end
	return true
end

-- Tools that opt out of the per-instance one-tool-per-slot rule and
-- instead get visually stacked by NPC-type via mergeBloodCapsules().
-- Each member of this set must carry a "BloodType" attribute set by
-- the recruitment server when the capsule is created.
local STACKABLE_TOOL_NAMES = { FullCapsule = true }
local BLOOD_STACK_SIZE = 12

local function getToolList()
	local tools = {}
	local backpack = player:FindFirstChild("Backpack")
	local char = player.Character
	if backpack then
		for _, t in backpack:GetChildren() do
			-- Stackable tools are handled separately; excluding them
			-- here prevents the standard "one Tool, one slot" path
			-- from allocating a fresh slot per blood capsule.
			if t:IsA("Tool") and not STACKABLE_TOOL_NAMES[t.Name] then
				table.insert(tools, t)
			end
		end
	end
	if char then
		for _, t in char:GetChildren() do
			if t:IsA("Tool") and not STACKABLE_TOOL_NAMES[t.Name] then
				table.insert(tools, t)
			end
		end
	end
	return tools
end

-- Returns every blood capsule the player currently holds, regardless of
-- whether the tool is in Backpack or equipped to the character.
local function getBloodCapsules()
	local out = {}
	local backpack = player:FindFirstChild("Backpack")
	local char = player.Character
	if backpack then
		for _, t in backpack:GetChildren() do
			if t:IsA("Tool") and t.Name == "FullCapsule" then
				table.insert(out, t)
			end
		end
	end
	if char then
		for _, t in char:GetChildren() do
			if t:IsA("Tool") and t.Name == "FullCapsule" then
				table.insert(out, t)
			end
		end
	end
	return out
end

local function findEmptySlot(startIdx, endIdx)
	for i = startIdx, endIdx do
		if not slotData[i] then return i end
	end
	return nil
end

-- Count how many "food Tool" instances of `toolName` the player owns
-- right now (Backpack + Character). Used to fold the in-hand /
-- standing-by Tool into the resource slot's displayed total — the
-- player sees a single banana / coconut / pineapple slot whose count
-- reflects "things you own", regardless of whether one of them is
-- currently in your hand as a Tool or sitting in inv as a stack.
local function countFoodToolsForName(toolName)
	if not FOOD_RESOURCE_SET[toolName] then return 0 end
	local total = 0
	local function gather(container)
		if not container then return end
		for _, child in container:GetChildren() do
			if child:IsA("Tool") and child.Name == toolName and child:GetAttribute("FoodResource") == toolName then
				total = total + 1
			end
		end
	end
	gather(player.Character)
	gather(player:FindFirstChild("Backpack"))
	return total
end

-- True if `tool` is one of those "borrowed from stack" food Tools we
-- promoted via EquipFoodAsTool. They live shadowed by the resource
-- slot, so the Tool-placement pass in rebuildSlotData skips them.
local function isFoodTool(tool)
	return tool
		and tool:IsA("Tool")
		and FOOD_RESOURCE_SET[tool.Name]
		and tool:GetAttribute("FoodResource") == tool.Name
end

local function findItemSlot(itemType, itemName)
	for i = 1, TOTAL_SLOTS do
		if slotData[i] and slotData[i].type == itemType and slotData[i].name == itemName then
			return i
		end
	end
	return nil
end

local MAX_STACK = 30

-- Update resource slots: preserve existing layout, only add/remove the difference
local function distributeResource(name, totalCount, icon)
	-- Find all existing slots with this resource
	local existingSlots = {}
	local currentTotal = 0
	for i = 1, TOTAL_SLOTS do
		if slotData[i] and slotData[i].type == "resource" and slotData[i].name == name then
			table.insert(existingSlots, i)
			currentTotal = currentTotal + slotData[i].count
		end
	end

	local diff = totalCount - currentTotal

	if diff == 0 then return end

	if diff > 0 then
		local added = 0

		-- Priority: if there's a pending target slot (merc backpack drag),
		-- place items there first before falling back to default logic.
		local pending = _G.PendingTargetSlot
		if pending and pending.name == name then
			local tgt = pending.slot
			_G.PendingTargetSlot = nil
			if tgt and tgt >= 1 and tgt <= TOTAL_SLOTS and not isSlotLocked(tgt) then
				local dst = slotData[tgt]
				if dst and dst.type == "resource" and dst.name == name then
					local space = MAX_STACK - dst.count
					if space > 0 then
						local toAdd = math.min(diff - added, space)
						dst.count = dst.count + toAdd
						added = added + toAdd
					end
				elseif not dst then
					local amount = math.min(diff - added, MAX_STACK)
					slotData[tgt] = {type = "resource", name = name, count = amount, icon = icon}
					added = added + amount
				end
			end
		end

		-- Fill existing non-full slots (last ones first for natural stacking)
		for j = #existingSlots, 1, -1 do
			if added >= diff then break end
			local idx = existingSlots[j]
			local space = MAX_STACK - slotData[idx].count
			if space > 0 then
				local toAdd = math.min(diff - added, space)
				slotData[idx].count = slotData[idx].count + toAdd
				added = added + toAdd
			end
		end

		-- Still need more? Create new slots
		while added < diff do
			local empty = findEmptySlot(1, HOTBAR_SLOTS) or findEmptySlot(HOTBAR_SLOTS + 1, maxWritableSlot())
			if not empty then break end
			local amount = math.min(diff - added, MAX_STACK)
			slotData[empty] = {type = "resource", name = name, count = amount, icon = icon}
			added = added + amount
		end
	else
		-- Removing items: take from last slots first
		local toRemove = -diff
		for j = #existingSlots, 1, -1 do
			local idx = existingSlots[j]
			if toRemove >= slotData[idx].count then
				toRemove = toRemove - slotData[idx].count
				slotData[idx] = nil
			else
				slotData[idx].count = slotData[idx].count - toRemove
				toRemove = 0
			end
			if toRemove <= 0 then break end
		end
	end
end

local function updateResourceSlots(name, count, icon)
	if count > 0 then
		distributeResource(name, count, icon)
	else
		for i = 1, TOTAL_SLOTS do
			if slotData[i] and slotData[i].type == "resource" and slotData[i].name == name then
				slotData[i] = nil
			end
		end
	end
end

-- Group all FullCapsule tool instances by BloodType and lay them out
-- into stacks of up to BLOOD_STACK_SIZE per inventory slot. Pirate
-- and Infected Military blood land in different slots even though they share
-- the same Tool.Name, because the slot is keyed off BloodType.
local function mergeBloodCapsules()
	local capsules = getBloodCapsules()

	-- Drop any existing blood-stack slots; we rebuild them fresh each
	-- pass to keep the layout in sync with what's actually in Backpack.
	for i = 1, TOTAL_SLOTS do
		local d = slotData[i]
		if d and d.type == "tool" and d.toolName == "FullCapsule" then
			slotData[i] = nil
		end
	end

	if #capsules == 0 then return end

	-- Bucket by BloodType so each NPC type produces a distinct stack.
	-- Untagged legacy capsules collapse into "" so they still display.
	local groups = {}
	local order  = {}
	for _, t in capsules do
		local bt = t:GetAttribute("BloodType") or ""
		if not groups[bt] then
			groups[bt] = { tools = {}, label = t:GetAttribute("BloodLabel") }
			table.insert(order, bt)
		end
		table.insert(groups[bt].tools, t)
		if not groups[bt].label then
			groups[bt].label = t:GetAttribute("BloodLabel")
		end
	end

	local FALLBACK_ICON = "rbxassetid://132749498016835"

	for _, bt in order do
		local g = groups[bt]
		local label = g.label
			or (bt ~= "" and (bt .. " Blood"))
			or "Blood"
		local i = 1
		while i <= #g.tools do
			local stackTools = {}
			for j = 1, BLOOD_STACK_SIZE do
				local t = g.tools[i]
				if not t then break end
				table.insert(stackTools, t)
				i = i + 1
			end

			local target = findEmptySlot(1, HOTBAR_SLOTS)
				or findEmptySlot(HOTBAR_SLOTS + 1, maxWritableSlot())
			if not target then break end

			local primary = stackTools[1]
			local extras  = {}
			for k = 2, #stackTools do extras[k - 1] = stackTools[k] end

			local icon = (primary.TextureId ~= "" and primary.TextureId) or FALLBACK_ICON

			slotData[target] = {
				type        = "tool",
				name        = "FullCapsule",
				toolName    = "FullCapsule",
				toolInst    = primary,
				extraInsts  = extras,
				icon        = icon,
				count       = #stackTools,
				displayName = label,
				bloodType   = bt,
			}
		end
	end
end

local function rebuildSlotData()
	local tools = getToolList()

	if not slotsInitialized then
		for i = 1, TOTAL_SLOTS do slotData[i] = nil end

		for resName, resIcon in RESOURCE_ICONS do
			local count = inventory[resName] or 0
			-- Food Tools that are currently in the player's hand or
			-- Backpack count towards the resource slot's total so the
			-- player sees a single "Pineapple x10" entry even when
			-- one of those 10 is held as a Tool.
			count = count + countFoodToolsForName(resName)
			if count > 0 then
				distributeResource(resName, count, resIcon)
			end
		end

		-- Tools never stack: each Tool Instance gets its own slot so
		-- duplicates (e.g. two Machetes) occupy separate cells. The
		-- Tool reference is stored so rebuildSlotData can match a
		-- slot back to the same instance on subsequent refreshes.
		-- Food Tools are skipped here because the resource slot above
		-- already owns their visual representation.
		local slot = 2
		for _, tool in tools do
			if not isFoodTool(tool) then
				while slot <= HOTBAR_SLOTS and slotData[slot] do
					slot = slot + 1
				end
				if slot > HOTBAR_SLOTS then break end
				local toolIcon = TOOL_ICONS[tool.Name] or (tool.TextureId ~= "" and tool.TextureId) or LOG_ICON
				ensureSandBagHook(tool)
				slotData[slot] = {
					type = "tool",
					name = tool.Name,
					toolName = tool.Name,
					toolInst = tool,
					icon = toolIcon,
					count = 1,
				}
				slot = slot + 1
			end
		end

		-- First pass: still run the blood-stack merge so capsules
		-- present at boot collapse into 12-per-slot stacks like every
		-- subsequent refresh.
		mergeBloodCapsules()
		slotsInitialized = true
		return
	end

	-- Update all resources. Food resources include any in-hand /
	-- Backpack Food Tools so the slot count reflects "things you own"
	-- regardless of whether one of them is currently equipped — see
	-- countFoodToolsForName.
	for resName, resIcon in RESOURCE_ICONS do
		local count = inventory[resName] or 0
		count = count + countFoodToolsForName(resName)
		updateResourceSlots(resName, count, resIcon)
	end

	-- Tools don't stack; each Tool Instance claims its own slot. Match
	-- surviving instances to their existing slot; re-bind slots whose
	-- instance ref went stale (e.g. after a layout restore from the
	-- server saved state, which only carries the tool name) to any
	-- unclaimed same-name tool; drop orphan slots.
	local currentSet = {}
	for _, tool in tools do currentSet[tool] = true end

	local claimed = {}
	for i = 1, TOTAL_SLOTS do
		local entry = slotData[i]
		if entry and entry.type == "tool" then
			if FOOD_RESOURCE_SET[entry.toolName] then
				-- Food Tools no longer claim slots — the resource slot
				-- handles their visual via countFoodToolsForName.
				-- Drop any leftover entry from before this consolidation.
				slotData[i] = nil
			else
				local inst = entry.toolInst
				if inst and currentSet[inst] and not claimed[inst] then
					claimed[inst] = true
					entry.count = 1
				else
					local name = entry.toolName or entry.name
					local bound
					for _, t in tools do
						if not claimed[t] and t.Name == name then
							bound = t
							break
						end
					end
					if bound then
						entry.toolInst = bound
						entry.count = 1
						claimed[bound] = true
					else
						slotData[i] = nil
					end
				end
			end
		end
	end

	-- Any Tool instances not yet bound to a slot get a fresh one —
	-- honouring _G.PendingTargetSlot so a chest → inventory drag lands
	-- where the user released the drag. Food Tools are shadowed by
	-- their resource slot (countFoodToolsForName above), so we skip
	-- claiming a slot for them entirely.
	for _, tool in tools do
		if not claimed[tool] and not isFoodTool(tool) then
			local target
			local pending = _G.PendingTargetSlot
			if pending and pending.name == tool.Name then
				local tgt = pending.slot
				if tgt and tgt >= 1 and tgt <= TOTAL_SLOTS
					and not isSlotLocked(tgt) and not slotData[tgt] then
					target = tgt
					_G.PendingTargetSlot = nil
				end
			end
			target = target or findEmptySlot(1, HOTBAR_SLOTS) or findEmptySlot(HOTBAR_SLOTS + 1, maxWritableSlot())
			if target then
				local toolIcon = TOOL_ICONS[tool.Name] or (tool.TextureId ~= "" and tool.TextureId) or LOG_ICON
				ensureSandBagHook(tool)
				slotData[target] = {
					type = "tool",
					name = tool.Name,
					toolName = tool.Name,
					toolInst = tool,
					icon = toolIcon,
					count = 1,
				}
				claimed[tool] = true
			end
		end
	end

	-- Blood capsules are routed through their own stacking pass so
	-- they collapse by BloodType into 12-per-slot stacks. Run last so
	-- it sees the latest Backpack state and never collides with the
	-- one-Tool-one-slot binding loop above.
	mergeBloodCapsules()
end

-- ─── Rendering ───

local function clearSlotUI(slot)
	for _, child in slot:GetChildren() do
		if child:IsA("ImageLabel") or (child:IsA("TextLabel") and child.Name ~= "") then
			child:Destroy()
		end
	end
end

local function renderSlot(slot, data)
	clearSlotUI(slot)
	if not data then return end

	-- Sand Bag tools swap their hotbar icon based on the SandFill
	-- attribute so the slot art mirrors the inspection panel's current
	-- bag stage. Falls through to the static icon if the tool ref is
	-- gone (e.g. mid-respawn before rebuildSlotData rebinds it).
	local iconAsset = data.icon or ""
	if data.type == "tool" and data.toolInst and isSandBagTool(data.toolInst) then
		iconAsset = getSandBagIcon(data.toolInst) or iconAsset
	end

	local img = Instance.new("ImageLabel")
	img.Name = "ItemIcon"
	img.AnchorPoint = Vector2.new(0.5, 0.5)
	img.Size = UDim2.new(0.7, 0, 0.7, 0)
	img.Position = UDim2.new(0.5, 0, 0.5, 0)
	img.BackgroundTransparency = 1
	img.Image = iconAsset
	img.ScaleType = Enum.ScaleType.Fit
	img.ZIndex = 2
	img.Parent = slot

	if data.count and data.count > 1 then
		local count = Instance.new("TextLabel")
		count.Name = "ItemCount"
		count.Size = UDim2.new(0, 25, 0, 16)
		count.Position = UDim2.new(1, -27, 1, -18)
		count.BackgroundTransparency = 1
		count.Text = tostring(data.count)
		count.TextColor3 = COLORS.lightText
		count.TextStrokeTransparency = 0.3
		count.TextStrokeColor3 = Color3.new(0, 0, 0)
		count.Font = Enum.Font.GothamBold
		count.TextSize = 13
		count.TextXAlignment = Enum.TextXAlignment.Right
		count.ZIndex = 3
		count.Parent = slot
	end
end

function renderAllSlots()
	local char = player.Character

	-- Render hotbar (slots 1-8)
	if hotbarGui then
		local bar = hotbarGui:FindFirstChild("Hotbar")
		if bar then
			for i = 1, HOTBAR_SLOTS do
				local slot = bar:FindFirstChild("HotbarSlot_" .. i)
				if slot then
					renderSlot(slot, slotData[i])
					local data = slotData[i]
					if data and data.type == "tool" and char then
						-- Match by Tool INSTANCE, not by Tool.Name —
						-- otherwise equipping a single tool highlights
						-- every hotbar slot that holds an item of the
						-- same name (two EmptyCapsules both lighting
						-- up, etc.). Fall back to name match only when
						-- the slot's toolInst ref has gone stale
						-- (e.g. right after a save/restore round-trip
						-- that only stored the name).
						local isEquipped = false
						local inst = data.toolInst
						if inst and inst:IsA("Tool") and inst.Parent == char then
							isEquipped = true
						elseif not inst then
							for _, t in char:GetChildren() do
								if t:IsA("Tool") and t.Name == data.toolName then isEquipped = true break end
							end
						end
						slot.BackgroundColor3 = isEquipped and COLORS.equipped or COLORS.slotBg
					elseif data and data.type == "resource" and data.name and FOOD_RESOURCE_SET[data.name] and char then
						-- Food resource slot lights up the same way as
						-- a tool slot when the matching food Tool is
						-- in the player's hand. countFoodToolsForName
						-- doesn't distinguish hand vs Backpack — we
						-- need the strict "in hand right now" check
						-- here, mirroring the tool-instance test
						-- above.
						local isFoodEquipped = false
						for _, t in char:GetChildren() do
							if t:IsA("Tool") and t.Name == data.name and t:GetAttribute("FoodResource") == data.name then
								isFoodEquipped = true
								break
							end
						end
						slot.BackgroundColor3 = isFoodEquipped and COLORS.equipped or COLORS.slotBg
					else
						slot.BackgroundColor3 = COLORS.slotBg
					end
				end
			end
		end
	end

	-- Render inventory grid (slots 9-28)
	if screenGui then
		local grid = screenGui:FindFirstChild("InventoryGrid", true)
		if grid then
			for i = 1, GRID_SLOTS do
				local slot = grid:FindFirstChild("Slot_" .. i)
				if slot then
					renderSlot(slot, slotData[HOTBAR_SLOTS + i])
				end
			end
		end

		-- Sum resource counts from slotData (what's actually in visible slots)
		-- instead of raw inventory values, so the counter matches the UI.
		local function countResourceInSlots(resName)
			local total = 0
			for i = 1, TOTAL_SLOTS do
				local d = slotData[i]
				if d and d.type == "resource" and d.name == resName then
					total = total + (d.count or 0)
				end
			end
			return total
		end
		local lc = screenGui:FindFirstChild("LogCount", true)
		if lc then lc.Text = tostring(countResourceInSlots("Log")) end
		local pc = screenGui:FindFirstChild("PlasticCount", true)
		if pc then pc.Text = tostring(countResourceInSlots("Plastic")) end
	end
end

-- ─── Drag & Drop ───

local function beginDragPending(slotIndex, data, mousePos, isSplit)
	if not data then return end
	-- Never start a drag while the phone (or any other full-screen
	-- overlay) is on top — the hotbar's MouseButton1Down still fires
	-- because the phone's backdrop Frames don't sink pointer events,
	-- but the ghost visual would bleed over the overlay.
	if isHoverBlockingOverlayOpen() then return end
	dragState.sourceSlot = slotIndex
	dragState.data = data
	dragState.startPos = mousePos
	dragState.active = false
	dragState.didDrag = false
	dragState.splitMode = isSplit or false
end

local function activateDrag(mousePos)
	if dragState.active then return end
	dragState.active = true
	dragState.didDrag = true
	hideTooltip()

	local data = dragState.data
	local ghostGui = Instance.new("ScreenGui")
	ghostGui.Name = "DragGhost"
	ghostGui.DisplayOrder = 100
	ghostGui.IgnoreGuiInset = true
	ghostGui.Parent = playerGui

	local ghost = Instance.new("ImageLabel")
	ghost.AnchorPoint = Vector2.new(0.5, 0.5)
	ghost.Size = UDim2.new(0, SLOT_SIZE - 8, 0, SLOT_SIZE - 8)
	ghost.Position = UDim2.new(0, mousePos.X, 0, mousePos.Y)
	ghost.BackgroundTransparency = 1
	ghost.Image = data.icon or ""
	ghost.ScaleType = Enum.ScaleType.Fit
	ghost.ImageTransparency = 0.3
	ghost.Parent = ghostGui

	local displayCount = (dragState.splitMode and 1) or (data.count)
	if displayCount and displayCount > 0 then
		local cl = Instance.new("TextLabel")
		cl.Size = UDim2.new(0, 25, 0, 16)
		cl.Position = UDim2.new(1, -25, 1, -16)
		cl.BackgroundTransparency = 1
		cl.Text = tostring(displayCount)
		cl.TextColor3 = COLORS.lightText
		cl.TextStrokeTransparency = 0.3
		cl.TextStrokeColor3 = Color3.new(0, 0, 0)
		cl.Font = Enum.Font.GothamBold
		cl.TextSize = 13
		cl.TextXAlignment = Enum.TextXAlignment.Right
		cl.Parent = ghost
	end

	dragState.ghost = ghost
	dragState.ghostGui = ghostGui
end

local function updateDragPosition(mousePos)
	if dragState.startPos and not dragState.active and dragState.data then
		local dx = mousePos.X - dragState.startPos.X
		local dy = mousePos.Y - dragState.startPos.Y
		if math.sqrt(dx * dx + dy * dy) >= DRAG_THRESHOLD then
			activateDrag(mousePos)
		end
	end
	if dragState.active and dragState.ghost then
		dragState.ghost.Position = UDim2.new(0, mousePos.X, 0, mousePos.Y)
	end
end

local function findSlotUnderMouse(mousePos)
	-- GetMouseLocation() includes the GUI inset, AbsolutePosition does not
	local inset = GuiService:GetGuiInset()
	local mx = mousePos.X
	local my = mousePos.Y - inset.Y
	-- Check hotbar slots (1-8)
	if hotbarGui then
		local bar = hotbarGui:FindFirstChild("Hotbar")
		if bar then
			for i = 1, HOTBAR_SLOTS do
				local slot = bar:FindFirstChild("HotbarSlot_" .. i)
				if slot then
					local p = slot.AbsolutePosition
					local s = slot.AbsoluteSize
					if mx >= p.X and mx <= p.X + s.X and my >= p.Y and my <= p.Y + s.Y then
						return i
					end
				end
			end
		end
	end

	-- Check inventory grid slots (9-28)
	if screenGui then
		local grid = screenGui:FindFirstChild("InventoryGrid", true)
		if grid then
			for i = 1, GRID_SLOTS do
				local slot = grid:FindFirstChild("Slot_" .. i)
				if slot then
					local p = slot.AbsolutePosition
					local s = slot.AbsoluteSize
					if mx >= p.X and mx <= p.X + s.X and my >= p.Y and my <= p.Y + s.Y then
						return HOTBAR_SLOTS + i
					end
				end
			end
		end
	end

	return nil
end

local function cancelDrag()
	if dragState.ghostGui then dragState.ghostGui:Destroy() end
	dragState.active = false
	dragState.sourceSlot = nil
	dragState.data = nil
	dragState.ghost = nil
	dragState.ghostGui = nil
	dragState.startPos = nil
end

-- Exposed so other client scripts (e.g. the chest UI) can ask which
-- inventory slot the mouse is currently over - same hit-test the
-- inventory's own drag-drop uses, including the GUI inset correction.
_G.FindInventorySlotUnderMouse = findSlotUnderMouse

local function endDrag(mousePos)
	if not dragState.active then
		cancelDrag()
		return
	end

	local targetSlot = findSlotUnderMouse(mousePos)
	local srcSlot = dragState.sourceSlot
	local isSplit = dragState.splitMode

	-- Drops onto locked grid slots are cancelled outright: nothing moves,
	-- nothing is dropped into the world, and we flash a "Slot blocked"
	-- popup at the drop point. We short-circuit here so the drag simply
	-- snaps back to the source slot on the next render.
	if targetSlot and isSlotLocked(targetSlot) then
		showLockedDropMessage(mousePos)
		cancelDrag()
		dragState.didDrag = true
		renderAllSlots()
		return
	end

	if targetSlot and targetSlot ~= srcSlot then
		local srcData = slotData[srcSlot]
		local dstData = slotData[targetSlot]

		if isSplit and srcData and srcData.type == "resource" and srcData.count and srcData.count > 1 then
			-- Right-click split: move exactly 1 to target
			if dstData and dstData.type == "resource" and dstData.name == srcData.name then
				if dstData.count < MAX_STACK then
					dstData.count = dstData.count + 1
					srcData.count = srcData.count - 1
				end
			elseif not dstData then
				slotData[targetSlot] = {
					type = srcData.type,
					name = srcData.name,
					count = 1,
					icon = srcData.icon,
				}
				srcData.count = srcData.count - 1
			end
		elseif srcData and dstData
			and srcData.type == "resource" and dstData.type == "resource"
			and srcData.name == dstData.name then
			-- Left-click same resource: stack them (up to MAX_STACK)
			local space = MAX_STACK - dstData.count
			if space > 0 then
				local toMove = math.min(srcData.count, space)
				dstData.count = dstData.count + toMove
				srcData.count = srcData.count - toMove
				if srcData.count <= 0 then
					slotData[srcSlot] = nil
				end
			else
				-- Target full: swap
				slotData[targetSlot] = srcData
				slotData[srcSlot] = dstData
			end
		else
			-- Different items or tools: swap
			slotData[targetSlot] = srcData
			slotData[srcSlot] = dstData
		end
	elseif not targetSlot and srcSlot then
		-- Dropped outside any slot. If a chest/container is open and the
		-- release was inside one of its slots, push the stack in there
		-- instead of dumping to the world. Tools go via "tool" kind so
		-- the server moves Tool Instances; resources still go as counts.
		if _G.ActiveContainer and typeof(_G.ContainerTryDrop) == "function" then
			local data = slotData[srcSlot]
			if data and data.type == "resource"
				and _G.ContainerTryDrop(mousePos, data.name, data.count, "resource")
			then
				local dropCount = isSplit and 1 or data.count
				if dropCount >= data.count then
					slotData[srcSlot] = nil
				else
					data.count = data.count - dropCount
				end
				cancelDrag()
				dragState.didDrag = true
				renderAllSlots()
				syncSlotLayoutToServer()
				return
			end
			if data and data.type == "tool"
				and _G.ContainerTryDrop(mousePos, data.toolName, data.count or 1, "tool")
			then
				-- Backpack.ChildRemoved will trigger updateUI and clear
				-- the slot; we just stop the world-drop fallback here.
				cancelDrag()
				dragState.didDrag = true
				renderAllSlots()
				syncSlotLayoutToServer()
				return
			end
		end

		local srcData = slotData[srcSlot]
		if srcData then
			local dropEvt = ReplicatedStorage:FindFirstChild("DropItem")
			if dropEvt then
				-- Raycast from mouse to find drop position in the world
				local cam = workspace.CurrentCamera
				local mPos = UserInputService:GetMouseLocation()
				local ray = cam:ViewportPointToRay(mPos.X, mPos.Y)
				local rayParams = RaycastParams.new()
				rayParams.FilterType = Enum.RaycastFilterType.Exclude
				local char = player.Character
				if char then rayParams.FilterDescendantsInstances = {char} end
				local result = workspace:Raycast(ray.Origin, ray.Direction * 500, rayParams)
				local dropPos = result and result.Position or nil

				if srcData.type == "resource" then
					local dropCount = isSplit and 1 or srcData.count
					if dropCount >= srcData.count then
						slotData[srcSlot] = nil
					else
						srcData.count = srcData.count - dropCount
					end
					dropEvt:FireServer(srcData.name, dropCount, dropPos)
				elseif srcData.type == "tool" then
					slotData[srcSlot] = nil
					dropEvt:FireServer(srcData.toolName, 1, dropPos)
				end
			end
		end
	end

	cancelDrag()
	dragState.didDrag = true
	renderAllSlots()
	syncSlotLayoutToServer()
end

-- ─── Quick-transfer: Shift+click moves item between hotbar and grid ───
-- If a chest/container UI is open, shift-clicking an inventory slot
-- pushes the stack into the container instead. We drain the clicked
-- slot locally before the server call so the specific slot the user
-- aimed at is the one that empties — otherwise distributeResource
-- picks the last slot with that item and the wrong one clears.
local function quickTransfer(slotIndex)
	local data = slotData[slotIndex]
	if not data then return end

	if _G.ActiveContainer and data.type == "resource"
		and typeof(_G.ContainerTransferFromPlayer) == "function" then
		local name = data.name
		local amount = data.count
		slotData[slotIndex] = nil
		renderAllSlots()
		_G.ContainerTransferFromPlayer(name, amount, "resource")
		return
	end

	if _G.ActiveContainer and data.type == "tool"
		and typeof(_G.ContainerTransferFromPlayer) == "function" then
		-- Tools live in Backpack, not slotData. The server moves the
		-- Tool Instances out; Backpack.ChildRemoved then clears the
		-- local slot via updateUI. Don't pre-drain here.
		_G.ContainerTransferFromPlayer(data.toolName, data.count or 1, "tool")
		return
	end

	local isHotbar = slotIndex >= 1 and slotIndex <= HOTBAR_SLOTS
	local targetStart, targetEnd

	if isHotbar then
		-- From hotbar → inventory grid
		if not isOpen then return end -- grid must be open
		targetStart = HOTBAR_SLOTS + 1
		targetEnd = maxWritableSlot()
	else
		-- From inventory grid → hotbar
		targetStart = 1
		targetEnd = HOTBAR_SLOTS
	end

	-- For resources, try to stack first with same item in target area
	if data.type == "resource" then
		local remaining = data.count
		-- Stack into existing slots of same type
		for i = targetStart, targetEnd do
			if remaining <= 0 then break end
			if slotData[i] and slotData[i].type == "resource" and slotData[i].name == data.name then
				local space = MAX_STACK - slotData[i].count
				if space > 0 then
					local toMove = math.min(remaining, space)
					slotData[i].count = slotData[i].count + toMove
					remaining = remaining - toMove
				end
			end
		end
		-- Put rest into empty slots
		while remaining > 0 do
			local empty = findEmptySlot(targetStart, targetEnd)
			if not empty then break end
			local amount = math.min(remaining, MAX_STACK)
			slotData[empty] = {type = data.type, name = data.name, count = amount, icon = data.icon}
			remaining = remaining - amount
		end
		-- Update source
		if remaining <= 0 then
			slotData[slotIndex] = nil
		else
			slotData[slotIndex].count = remaining
		end
	else
		-- Tools: just swap to first empty slot in target area
		local empty = findEmptySlot(targetStart, targetEnd)
		if empty then
			slotData[empty] = data
			slotData[slotIndex] = nil
		end
	end

	renderAllSlots()
	syncSlotLayoutToServer()
end

-- ─── Equip ───

-- Toggle / switch tool by instance. Clicking a slot routes here with
-- the exact Tool instance held in `slotData[i].toolInst`, so two slots
-- holding same-named Tools (e.g. two Sand Bags) each get their own
-- specific Tool — clicking slot 4 never equips slot 3's instance.
--
-- Behaviour:
--   * the same instance is already in hand → unequip
--   * another Tool is in hand (or nothing)  → equip this one (Roblox
--                                              auto-unequips the prior
--                                              tool so it's a one-click
--                                              swap, not a two-step)
local function equipToolInstance(tool)
	if not tool or not tool:IsA("Tool") or not tool.Parent then return end
	local char = player.Character
	if not char then return end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	if tool.Parent == char then
		humanoid:UnequipTools()
		return
	end

	humanoid:EquipTool(tool)
end

-- Name-based fallback for callers that don't have a specific instance
-- (legacy hotbar keys, debug code). Same toggle rule, but picks the
-- first matching Tool in the backpack.
local function equipToolByName(toolName)
	local char = player.Character
	if not char then return end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	for _, t in char:GetChildren() do
		if t:IsA("Tool") and t.Name == toolName then
			humanoid:UnequipTools()
			return
		end
	end

	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		for _, t in backpack:GetChildren() do
			if t:IsA("Tool") and t.Name == toolName then
				humanoid:EquipTool(t)
				return
			end
		end
	end
end

-- ─── UI Update ───

local rebuildCraftList

local function closeDetailOverlay()
	if detailOverlay then
		detailOverlay:Destroy()
		detailOverlay = nil
	end
	selectedRecipe = nil
end

local function closeCategoryOverlay()
	closeDetailOverlay()
	if categoryOverlay then
		categoryOverlay:Destroy()
		categoryOverlay = nil
	end
	selectedCategory = nil
	if screenGui then
		local tabFrame = screenGui:FindFirstChild("CategoryTabs", true)
		if tabFrame then
			for _, tab in tabFrame:GetChildren() do
				if tab:IsA("TextButton") then
					tab.BackgroundColor3 = COLORS.craftItemBg
					tab.TextColor3 = COLORS.titleText
				end
			end
		end
	end
end

local function openCategoryOverlay(cat)
	if not screenGui then return end
	local centerPanel = screenGui:FindFirstChild("CenterPanel")
	if not centerPanel then return end

	closeDetailOverlay()
	if categoryOverlay then
		categoryOverlay:Destroy()
		categoryOverlay = nil
	end
	selectedCategory = cat

	categoryOverlay = Instance.new("Frame")
	categoryOverlay.Name = "CategoryOverlay"
	categoryOverlay.Size = centerPanel.Size
	categoryOverlay.Position = centerPanel.Position
	categoryOverlay.BackgroundColor3 = COLORS.panelBg
	categoryOverlay.BorderSizePixel = 0
	categoryOverlay.ZIndex = 15
	categoryOverlay.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = categoryOverlay

	local stroke = Instance.new("UIStroke")
	stroke.Color = COLORS.panelBorder
	stroke.Thickness = 3
	stroke.Parent = categoryOverlay

	local backBtn = Instance.new("TextButton")
	backBtn.Size = UDim2.new(0, 60, 0, 28)
	backBtn.Position = UDim2.new(0, 10, 0, 8)
	backBtn.BackgroundColor3 = COLORS.craftItemBg
	backBtn.Text = "< Back"
	backBtn.TextColor3 = COLORS.titleText
	backBtn.Font = Enum.Font.GothamBold
	backBtn.TextSize = 13
	backBtn.BorderSizePixel = 0
	backBtn.ZIndex = 16
	backBtn.Parent = categoryOverlay

	local backCorner = Instance.new("UICorner")
	backCorner.CornerRadius = UDim.new(0, 6)
	backCorner.Parent = backBtn

	backBtn.MouseButton1Click:Connect(closeCategoryOverlay)

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -90, 0, 30)
	title.Position = UDim2.new(0, 80, 0, 8)
	title.BackgroundTransparency = 1
	title.Text = cat
	title.TextColor3 = COLORS.titleText
	title.Font = Enum.Font.GothamMedium
	title.TextSize = 22
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 16
	title.Parent = categoryOverlay

	local sep = Instance.new("Frame")
	sep.Size = UDim2.new(1, -30, 0, 2)
	sep.Position = UDim2.new(0, 15, 0, 42)
	sep.BackgroundColor3 = COLORS.separator
	sep.BorderSizePixel = 0
	sep.ZIndex = 16
	sep.Parent = categoryOverlay

	local craftList = Instance.new("ScrollingFrame")
	craftList.Name = "CraftList"
	craftList.Size = UDim2.new(1, -20, 1, -60)
	craftList.Position = UDim2.new(0, 10, 0, 50)
	craftList.BackgroundTransparency = 1
	craftList.BorderSizePixel = 0
	craftList.ScrollBarThickness = 6
	-- Matches the detail-overlay scroll bar; darker than the tan panel
	-- so it stands out against the wooden background.
	craftList.ScrollBarImageColor3 = COLORS.panelBorder
	craftList.CanvasSize = UDim2.new(0, 0, 0, 0)
	craftList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	craftList.ZIndex = 17
	craftList.Parent = categoryOverlay

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 5)
	listLayout.Parent = craftList

	rebuildCraftList()
end

local function openDetailOverlay(recipe)
	closeDetailOverlay()
	selectedRecipe = recipe
	if not screenGui then return end

	local centerPanel = screenGui:FindFirstChild("CenterPanel")
	if not centerPanel then return end

	-- Create overlay same size/position as center panel
	detailOverlay = Instance.new("Frame")
	detailOverlay.Name = "DetailOverlay"
	detailOverlay.Size = centerPanel.Size
	detailOverlay.Position = centerPanel.Position
	detailOverlay.BackgroundColor3 = COLORS.panelBg
	detailOverlay.BorderSizePixel = 0
	detailOverlay.ZIndex = 20
	detailOverlay.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = detailOverlay

	local stroke = Instance.new("UIStroke")
	stroke.Color = COLORS.panelBorder
	stroke.Thickness = 3
	stroke.Parent = detailOverlay

	-- Back button
	local backBtn = Instance.new("TextButton")
	backBtn.Size = UDim2.new(0, 80, 0, 36)
	backBtn.Position = UDim2.new(0, 12, 0, 10)
	backBtn.BackgroundColor3 = COLORS.craftItemBg
	backBtn.Text = "< Back"
	backBtn.TextColor3 = COLORS.titleText
	backBtn.Font = Enum.Font.GothamBold
	backBtn.TextSize = 18
	backBtn.BorderSizePixel = 0
	backBtn.ZIndex = 21
	backBtn.Parent = detailOverlay

	local backCorner = Instance.new("UICorner")
	backCorner.CornerRadius = UDim.new(0, 6)
	backCorner.Parent = backBtn

	backBtn.MouseButton1Click:Connect(closeDetailOverlay)

	-- Item name
	local itemTitle = Instance.new("TextLabel")
	itemTitle.Size = UDim2.new(1, -24, 0, 44)
	itemTitle.Position = UDim2.new(0, 12, 0, 54)
	itemTitle.BackgroundTransparency = 1
	itemTitle.Text = recipe.displayName or recipe.name
	itemTitle.TextColor3 = COLORS.titleText
	itemTitle.Font = Enum.Font.GothamBold
	itemTitle.TextSize = 32
	itemTitle.TextXAlignment = Enum.TextXAlignment.Left
	itemTitle.ZIndex = 21
	itemTitle.Parent = detailOverlay

	-- Separator
	local sep = Instance.new("Frame")
	sep.Size = UDim2.new(1, -24, 0, 2)
	sep.Position = UDim2.new(0, 12, 0, 104)
	sep.BackgroundColor3 = COLORS.separator
	sep.BorderSizePixel = 0
	sep.ZIndex = 21
	sep.Parent = detailOverlay

	-- Icon — enlarged so the crafted item is clearly legible.
	local iconFrame = Instance.new("ImageLabel")
	iconFrame.Size = UDim2.new(0, 110, 0, 110)
	iconFrame.Position = UDim2.new(0, 20, 0, 118)
	iconFrame.BackgroundTransparency = 1
	iconFrame.Image = recipe.icon or ""
	iconFrame.ScaleType = Enum.ScaleType.Fit
	iconFrame.ZIndex = 21
	iconFrame.Parent = detailOverlay

	-- Description — sits to the right of the icon, vertical extent
	-- matches the icon's height so wrapped text has room to breathe.
	local descLabel = Instance.new("TextLabel")
	descLabel.Size = UDim2.new(1, -160, 0, 110)
	descLabel.Position = UDim2.new(0, 145, 0, 118)
	descLabel.BackgroundTransparency = 1
	descLabel.Text = recipe.description or ""
	descLabel.TextColor3 = COLORS.titleText
	descLabel.Font = Enum.Font.Gotham
	descLabel.TextSize = 20
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.TextYAlignment = Enum.TextYAlignment.Top
	descLabel.TextWrapped = true
	descLabel.ZIndex = 21
	descLabel.Parent = detailOverlay

	-- Materials section
	local matTitle = Instance.new("TextLabel")
	matTitle.Size = UDim2.new(1, -24, 0, 30)
	matTitle.Position = UDim2.new(0, 12, 0, 240)
	matTitle.BackgroundTransparency = 1
	matTitle.Text = "Materials:"
	matTitle.TextColor3 = COLORS.titleText
	matTitle.Font = Enum.Font.GothamBold
	matTitle.TextSize = 22
	matTitle.TextXAlignment = Enum.TextXAlignment.Left
	matTitle.ZIndex = 21
	matTitle.Parent = detailOverlay

	-- Material items — in a ScrollingFrame so recipes with many
	-- ingredients don't slide under the Craft button. The frame spans
	-- from just below the "Materials:" header to just above the craft
	-- button (which sits at bottom -68, height 54).
	local matScroll = Instance.new("ScrollingFrame")
	matScroll.Name = "MaterialsScroll"
	matScroll.Size = UDim2.new(1, -34, 1, -348)
	matScroll.Position = UDim2.new(0, 17, 0, 274)
	matScroll.BackgroundTransparency = 1
	matScroll.BorderSizePixel = 0
	matScroll.ScrollBarThickness = 6
	matScroll.ScrollBarImageColor3 = COLORS.panelBorder
	matScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	matScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	matScroll.ScrollingDirection = Enum.ScrollingDirection.Y
	matScroll.ZIndex = 21
	matScroll.ClipsDescendants = true
	matScroll.Parent = detailOverlay

	local matLayout = Instance.new("UIListLayout")
	matLayout.FillDirection = Enum.FillDirection.Vertical
	matLayout.SortOrder = Enum.SortOrder.LayoutOrder
	matLayout.Padding = UDim.new(0, 6)
	matLayout.Parent = matScroll

	-- Small right-side padding so rows don't sit under the scroll bar.
	local matPadding = Instance.new("UIPadding")
	matPadding.PaddingRight = UDim.new(0, 8)
	matPadding.Parent = matScroll

	local matOrder = 0
	for item, amount in recipe.costs do
		matOrder = matOrder + 1
		local matRow = Instance.new("Frame")
		matRow.Size = UDim2.new(1, 0, 0, 48)
		matRow.LayoutOrder = matOrder
		matRow.BackgroundColor3 = COLORS.craftItemBg
		matRow.BorderSizePixel = 0
		matRow.ZIndex = 21
		matRow.Parent = matScroll

		local matCorner = Instance.new("UICorner")
		matCorner.CornerRadius = UDim.new(0, 6)
		matCorner.Parent = matRow

		local matIcon = Instance.new("ImageLabel")
		matIcon.Size = UDim2.new(0, 36, 0, 36)
		matIcon.Position = UDim2.new(0, 8, 0.5, -18)
		matIcon.BackgroundTransparency = 1
		matIcon.Image = RESOURCE_ICONS[item] or ""
		matIcon.ScaleType = Enum.ScaleType.Fit
		matIcon.ZIndex = 22
		matIcon.Parent = matRow

		local have = inventory[item] or 0
		local matLabel = Instance.new("TextLabel")
		matLabel.Name = "MatLabel_" .. item
		matLabel.Size = UDim2.new(1, -60, 1, 0)
		matLabel.Position = UDim2.new(0, 52, 0, 0)
		matLabel.BackgroundTransparency = 1
		matLabel.Text = item .. ": " .. have .. " / " .. amount
		matLabel.TextColor3 = have >= amount and COLORS.affordable or COLORS.notAffordable
		matLabel.Font = Enum.Font.GothamBold
		matLabel.TextSize = 20
		matLabel.TextXAlignment = Enum.TextXAlignment.Left
		matLabel.ZIndex = 22
		matLabel.Parent = matRow
		matRow:SetAttribute("ItemName", item)
		matRow:SetAttribute("ItemAmount", amount)
	end

	-- Craft button at bottom
	local craftBtn = Instance.new("TextButton")
	craftBtn.Name = "DetailCraftButton"
	craftBtn.Size = UDim2.new(1, -34, 0, 54)
	craftBtn.Position = UDim2.new(0, 17, 1, -68)
	craftBtn.BackgroundColor3 = canAfford(recipe) and COLORS.affordable or Color3.fromRGB(120, 120, 120)
	craftBtn.Text = "Craft " .. (recipe.displayName or recipe.name)
	craftBtn.TextColor3 = Color3.new(1, 1, 1)
	craftBtn.Font = Enum.Font.GothamBold
	craftBtn.TextSize = 24
	craftBtn.BorderSizePixel = 0
	craftBtn.ZIndex = 21
	craftBtn.Parent = detailOverlay

	local craftCorner = Instance.new("UICorner")
	craftCorner.CornerRadius = UDim.new(0, 8)
	craftCorner.Parent = craftBtn

	craftBtn.MouseButton1Click:Connect(function()
		if canAfford(recipe) then
			inventoryCraftEvent:FireServer("craft", recipe.name)
		end
	end)
end

function rebuildCraftList()
	if not screenGui then return end
	if not selectedCategory then return end
	local craftList = screenGui:FindFirstChild("CraftList", true)
	if not craftList then return end

	-- Clear existing items
	for _, child in craftList:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	-- Filter recipes by selected category
	local idx = 0
	for _, recipe in recipes do
		if recipe.category == selectedCategory then
			idx = idx + 1

			local btn = Instance.new("TextButton")
			btn.Name = "Recipe_" .. recipe.name
			btn.Size = UDim2.new(1, 0, 0, 90)
			btn.BackgroundColor3 = COLORS.craftItemBg
			btn.Text = ""
			btn.BorderSizePixel = 0
			btn.LayoutOrder = idx
			btn.AutoButtonColor = false
			btn.ZIndex = 17
			btn.Parent = craftList
			btn:SetAttribute("RecipeName", recipe.name)

			local btnCorner = Instance.new("UICorner")
			btnCorner.CornerRadius = UDim.new(0, 6)
			btnCorner.Parent = btn

			local icon = Instance.new("ImageLabel")
			icon.Size = UDim2.new(0, 64, 0, 64)
			icon.Position = UDim2.new(0, 12, 0.5, -32)
			icon.BackgroundTransparency = 1
			icon.Image = recipe.icon or ""
			icon.ScaleType = Enum.ScaleType.Fit
			icon.ZIndex = 18
			icon.Parent = btn

			local nameLabel = Instance.new("TextLabel")
			nameLabel.Size = UDim2.new(1, -96, 0, 26)
			nameLabel.Position = UDim2.new(0, 86, 0, 14)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Text = recipe.displayName or recipe.name
			nameLabel.TextColor3 = COLORS.titleText
			nameLabel.Font = Enum.Font.Gotham
			nameLabel.TextSize = 18
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
			nameLabel.ZIndex = 18
			nameLabel.Parent = btn

			local costText = ""
			for item, amount in recipe.costs do
				costText = amount .. " " .. item
			end

			local costLabel = Instance.new("TextLabel")
			costLabel.Name = "CostLabel"
			costLabel.Size = UDim2.new(1, -96, 0, 22)
			costLabel.Position = UDim2.new(0, 86, 0, 48)
			costLabel.BackgroundTransparency = 1
			costLabel.Text = costText
			costLabel.TextColor3 = canAfford(recipe) and COLORS.affordable or COLORS.notAffordable
			costLabel.Font = Enum.Font.Gotham
			costLabel.TextSize = 15
			costLabel.TextXAlignment = Enum.TextXAlignment.Left
			costLabel.ZIndex = 18
			costLabel.Parent = btn

			btn.MouseEnter:Connect(function()
				btn.BackgroundColor3 = COLORS.craftItemHover
			end)
			btn.MouseLeave:Connect(function()
				btn.BackgroundColor3 = COLORS.craftItemBg
			end)
			btn.MouseButton1Click:Connect(function()
				openDetailOverlay(recipe)
			end)
		end
	end
end

local function updateCategoryTabs()
	if not screenGui then return end
	local tabFrame = screenGui:FindFirstChild("CategoryTabs", true)
	if not tabFrame then return end
	for _, tab in tabFrame:GetChildren() do
		if tab:IsA("TextButton") then
			local cat = tab:GetAttribute("Category")
			local color
			if cat == selectedCategory then
				tab.BackgroundColor3 = COLORS.panelBg
				color = COLORS.lightText
			else
				tab.BackgroundColor3 = COLORS.craftItemBg
				color = COLORS.titleText
			end
			tab.TextColor3 = color
			local label = tab:FindFirstChild("Label")
			if label then
				label.TextColor3 = color
			end
		end
	end
end

local function updateCraftPanel()
	if not screenGui then return end

	-- Update cost colors in the list
	local craftList = screenGui:FindFirstChild("CraftList", true)
	if craftList then
		for _, btn in craftList:GetChildren() do
			if btn:IsA("TextButton") then
				local rName = btn:GetAttribute("RecipeName")
				for _, r in recipes do
					if r.name == rName then
						local costLabel = btn:FindFirstChild("CostLabel")
						if costLabel then
							costLabel.TextColor3 = canAfford(r) and COLORS.affordable or COLORS.notAffordable
						end
					end
				end
			end
		end
	end

	-- Update detail overlay craft button if open
	if detailOverlay and selectedRecipe then
		local craftBtn = detailOverlay:FindFirstChild("DetailCraftButton")
		if craftBtn then
			craftBtn.BackgroundColor3 = canAfford(selectedRecipe) and COLORS.affordable or Color3.fromRGB(120, 120, 120)
		end

		-- Refresh the "Log: have / need" material rows so a just-
		-- completed craft immediately reflects the drained inventory.
		local matScroll = detailOverlay:FindFirstChild("MaterialsScroll")
		if matScroll then
			for _, row in matScroll:GetChildren() do
				local item = row:GetAttribute("ItemName")
				local amount = row:GetAttribute("ItemAmount")
				if item and amount then
					local label = row:FindFirstChild("MatLabel_" .. item)
					if label then
						local have = inventory[item] or 0
						label.Text = item .. ": " .. have .. " / " .. amount
						label.TextColor3 = have >= amount and COLORS.affordable or COLORS.notAffordable
					end
				end
			end
		end
	end
end

-- ─── Slot layout sync to server ───
local slotLayoutEvent = ReplicatedStorage:FindFirstChild("SlotLayoutSync")

function syncSlotLayoutToServer()
	if not slotLayoutEvent then
		slotLayoutEvent = ReplicatedStorage:FindFirstChild("SlotLayoutSync")
	end
	if not slotLayoutEvent then return end

	-- Build a serializable copy of slotData (no userdata)
	local layout = {}
	for i = 1, TOTAL_SLOTS do
		if slotData[i] then
			layout[tostring(i)] = {
				type = slotData[i].type,
				name = slotData[i].name,
				count = slotData[i].count,
				icon = slotData[i].icon,
				toolName = slotData[i].toolName,
			}
		end
	end
	slotLayoutEvent:FireServer(layout)
end

local function updateUI()
	rebuildSlotData()
	renderAllSlots()
	updateCraftPanel()
	syncSlotLayoutToServer()
end

-- ─── Close ───

local function closeUI(isRebuild)
	closeDetailOverlay()
	if categoryOverlay then
		categoryOverlay:Destroy()
		categoryOverlay = nil
	end
	if screenGui then
		screenGui:Destroy()
		screenGui = nil
	end
	-- Drop stale grid slot refs; buildUI() re-populates them next open.
	table.clear(gridSlotVisuals)
	lockedOverlayLabel = nil
	hideTooltip()
	isOpen = false
	selectedRecipe = nil
	selectedCategory = nil
	if hotbarGui then hotbarGui.DisplayOrder = 5 end
	-- Also close the mercenary backpack / container panels if they
	-- were open, but NOT during a rebuild (recipe refresh) — only on
	-- a real close.
	if not isRebuild then
		if _G.CloseMercInventory then _G.CloseMercInventory() end
		if _G.CloseContainer then _G.CloseContainer() end
	end
end

-- Expose a force-close hook so other scripts (e.g. the phone menu) can
-- dismiss the inventory when they take over the screen.
_G.CloseInventory = function()
	if isOpen then closeUI() end
end

-- ─── Build Hotbar ───

local function buildHotbar()
	if hotbarGui then hotbarGui:Destroy() end

	hotbarGui = Instance.new("ScreenGui")
	hotbarGui.Name = "HotbarGui"
	hotbarGui.ResetOnSpawn = false
	hotbarGui.DisplayOrder = 5
	hotbarGui.Parent = playerGui
	attachResponsiveScale(hotbarGui)

	local barWidth = HOTBAR_SLOTS * (SLOT_SIZE + SLOT_PAD) + SLOT_PAD
	local bar = Instance.new("Frame")
	bar.Name = "Hotbar"
	bar.Size = UDim2.new(0, barWidth, 0, SLOT_SIZE + SLOT_PAD * 2)
	bar.Position = UDim2.new(0.5, -barWidth / 2, 1, -(SLOT_SIZE + SLOT_PAD * 2) - 10)
	bar.BackgroundColor3 = COLORS.hotbarBg
	bar.BackgroundTransparency = 0.15
	bar.BorderSizePixel = 0
	bar.Parent = hotbarGui

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 8)
	barCorner.Parent = bar

	local barStroke = Instance.new("UIStroke")
	barStroke.Color = COLORS.panelBorder
	barStroke.Thickness = 2
	barStroke.Parent = bar

	for i = 1, HOTBAR_SLOTS do
		local slot = Instance.new("TextButton")
		slot.Name = "HotbarSlot_" .. i
		slot.Size = UDim2.new(0, SLOT_SIZE, 0, SLOT_SIZE)
		slot.Position = UDim2.new(0, SLOT_PAD + (i - 1) * (SLOT_SIZE + SLOT_PAD), 0, SLOT_PAD)
		slot.BackgroundColor3 = COLORS.slotBg
		slot.BackgroundTransparency = 0.1
		slot.BorderSizePixel = 0
		slot.Text = ""
		slot.AutoButtonColor = false
		slot.Parent = bar

		local slotCorner = Instance.new("UICorner")
		slotCorner.CornerRadius = UDim.new(0, 6)
		slotCorner.Parent = slot

		local slotStroke = Instance.new("UIStroke")
		slotStroke.Color = COLORS.slotBorder
		slotStroke.Thickness = 1.5
		slotStroke.Parent = slot

		local slotIndex = i

		slot.MouseEnter:Connect(function()
			showTooltipForSlot(slotIndex)
		end)
		slot.MouseLeave:Connect(function()
			hideTooltip()
		end)

		slot.MouseButton1Down:Connect(function()
			if isHoverBlockingOverlayOpen() then return end
			local shiftHeld = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
			if shiftHeld then
				quickTransfer(slotIndex)
				dragState.didDrag = true
				return
			end
			dragState.didDrag = false
			local mousePos = UserInputService:GetMouseLocation()
			local data = slotData[slotIndex]
			if data then
				beginDragPending(slotIndex, data, mousePos, false)
			end
		end)

		slot.MouseButton2Down:Connect(function()
			if isHoverBlockingOverlayOpen() then return end
			local shiftHeld = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
			if shiftHeld then
				quickTransfer(slotIndex)
				dragState.didDrag = true
				return
			end
			dragState.didDrag = false
			local mousePos = UserInputService:GetMouseLocation()
			local data = slotData[slotIndex]
			if data and data.type == "resource" and data.count and data.count > 1 then
				beginDragPending(slotIndex, data, mousePos, true)
			end
		end)

		slot.MouseButton1Click:Connect(function()
			if dragState.didDrag then
				dragState.didDrag = false
				return
			end
			if isHoverBlockingOverlayOpen() then return end
			local data = slotData[slotIndex]
			if data and data.type == "tool" then
				if data.toolInst then
					equipToolInstance(data.toolInst)
				else
					equipToolByName(data.toolName)
				end
				task.wait(0.1)
				renderAllSlots()
			elseif data and data.type == "resource" and data.name and BUSH_SEED_RESOURCE_SET[data.name] and bushActionEvent then
				-- Bush-seed resource (Pineapple_Bush_Seed): server clones
				-- the matching placement Tool into the player's hand,
				-- decrements the stack by 1, refunds on unequip-without-
				-- use. Identical pattern to food but routes to the
				-- bush ghost flow in CupPurifier rather than the
				-- "eat me" Tool script.
				bushActionEvent:FireServer("equipBushSeed", data.name)
			elseif data and data.type == "resource" and data.name and SEED_RESOURCE_SET[data.name] and equipSeedEvent then
				-- Seed resource: ask the server to spawn a matching
				-- Tool in the character's hand and decrement the stack.
				-- Server handles the refund if the Tool is unequipped
				-- without being used.
				equipSeedEvent:FireServer(data.name)
			elseif data and data.type == "resource" and data.name and FOOD_RESOURCE_SET[data.name] and equipFoodEvent then
				-- Food resource (Banana / Coconut / Pineapple): same
				-- pattern as seeds — server clones a Tool into the
				-- player's hand, decrements the stack by 1, refunds
				-- if the Tool is unequipped without being eaten.
				-- The Tool itself doesn't claim a slot; the resource
				-- slot's displayed count includes the in-hand Tool so
				-- visually the slot just stays where it was.
				--
				-- Toggle behaviour: if the same food Tool is already
				-- in hand, clicking the slot again unequips it (which
				-- routes through the server's AncestryChanged refund
				-- hook back to the resource stack).
				local char     = player.Character
				local humanoid = char and char:FindFirstChildOfClass("Humanoid")
				local heldFoodTool = nil
				if char then
					for _, t in char:GetChildren() do
						if t:IsA("Tool") and t.Name == data.name and t:GetAttribute("FoodResource") == data.name then
							heldFoodTool = t
							break
						end
					end
				end
				if heldFoodTool and humanoid then
					humanoid:UnequipTools()
				else
					equipFoodEvent:FireServer(data.name)
				end
			end
		end)
	end

	-- ─── Mana / health / hunger / thirst bars ──────────────────────────
	-- All four stat bars live together in StarterPlayerScripts/
	-- UIManager.client.lua. Nothing to build from here.
end

-- ─── Build Inventory UI ───

local function buildUI()
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "InventoryGui"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 10
	screenGui.Parent = playerGui
	attachResponsiveScale(screenGui)

	local gridWidth = COLS * (SLOT_SIZE + SLOT_PAD) + SLOT_PAD
	local gridHeight = 4 * (SLOT_SIZE + SLOT_PAD) + SLOT_PAD
	local panelWidth = gridWidth + 40
	local panelHeight = gridHeight + 80

	-- Center the combined block (CraftPanel on the left + CenterPanel)
	-- horizontally on screen.
	local craftPanelWidth = 180
	local craftGap = 12
	local combinedWidth = craftPanelWidth + craftGap + panelWidth
	local centerPanelLeft = -combinedWidth / 2 + craftPanelWidth + craftGap

	local centerPanel = Instance.new("Frame")
	centerPanel.Name = "CenterPanel"
	centerPanel.Size = UDim2.new(0, panelWidth, 0, panelHeight)
	centerPanel.Position = UDim2.new(0.5, centerPanelLeft, 0.5, -panelHeight / 2)
	centerPanel.BackgroundColor3 = COLORS.panelBg
	centerPanel.BorderSizePixel = 0
	centerPanel.Parent = screenGui

	local centerCorner = Instance.new("UICorner")
	centerCorner.CornerRadius = UDim.new(0, 10)
	centerCorner.Parent = centerPanel

	local centerStroke = Instance.new("UIStroke")
	centerStroke.Color = COLORS.panelBorder
	centerStroke.Thickness = 3
	centerStroke.Parent = centerPanel

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -80, 0, 30)
	title.Position = UDim2.new(0, 10, 0, 8)
	title.BackgroundTransparency = 1
	title.Text = "Inventory"
	title.TextColor3 = COLORS.titleText
	title.Font = Enum.Font.GothamBold
	title.TextSize = 22
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = centerPanel

	local sep = Instance.new("Frame")
	sep.Size = UDim2.new(1, -30, 0, 2)
	sep.Position = UDim2.new(0, 15, 0, 42)
	sep.BackgroundColor3 = COLORS.separator
	sep.BorderSizePixel = 0
	sep.Parent = centerPanel

	-- Log counter
	local logIcon = Instance.new("ImageLabel")
	logIcon.Size = UDim2.new(0, 20, 0, 20)
	logIcon.Position = UDim2.new(1, -130, 0, 13)
	logIcon.BackgroundTransparency = 1
	logIcon.Image = LOG_ICON
	logIcon.ScaleType = Enum.ScaleType.Fit
	logIcon.Parent = centerPanel

	local logCount = Instance.new("TextLabel")
	logCount.Name = "LogCount"
	logCount.Size = UDim2.new(0, 30, 0, 20)
	logCount.Position = UDim2.new(1, -108, 0, 13)
	logCount.BackgroundTransparency = 1
	logCount.Text = "0" -- updated by renderAllSlots from slotData
	logCount.TextColor3 = COLORS.titleText
	logCount.Font = Enum.Font.GothamBold
	logCount.TextSize = 14
	logCount.TextXAlignment = Enum.TextXAlignment.Left
	logCount.Parent = centerPanel

	-- Plastic counter
	local plasticIcon = Instance.new("ImageLabel")
	plasticIcon.Size = UDim2.new(0, 20, 0, 20)
	plasticIcon.Position = UDim2.new(1, -70, 0, 13)
	plasticIcon.BackgroundTransparency = 1
	plasticIcon.Image = PLASTIC_ICON
	plasticIcon.ScaleType = Enum.ScaleType.Fit
	plasticIcon.Parent = centerPanel

	local plasticCount = Instance.new("TextLabel")
	plasticCount.Name = "PlasticCount"
	plasticCount.Size = UDim2.new(0, 30, 0, 20)
	plasticCount.Position = UDim2.new(1, -48, 0, 13)
	plasticCount.BackgroundTransparency = 1
	plasticCount.Text = "0" -- updated by renderAllSlots from slotData
	plasticCount.TextColor3 = COLORS.titleText
	plasticCount.Font = Enum.Font.GothamBold
	plasticCount.TextSize = 14
	-- Inventory grid (these are slots 9-28)
	local gridFrame = Instance.new("Frame")
	gridFrame.Name = "InventoryGrid"
	gridFrame.Size = UDim2.new(0, gridWidth, 0, gridHeight)
	gridFrame.Position = UDim2.new(0.5, -gridWidth / 2, 0, 52)
	gridFrame.BackgroundTransparency = 1
	gridFrame.Parent = centerPanel

	-- Clear any stale refs from a previous rebuild.
	table.clear(gridSlotVisuals)

	for i = 1, GRID_SLOTS do
		local row = math.floor((i - 1) / COLS)
		local col = (i - 1) % COLS

		local slot = Instance.new("TextButton")
		slot.Name = "Slot_" .. i
		slot.Size = UDim2.new(0, SLOT_SIZE, 0, SLOT_SIZE)
		slot.Position = UDim2.new(0, SLOT_PAD + col * (SLOT_SIZE + SLOT_PAD), 0, SLOT_PAD + row * (SLOT_SIZE + SLOT_PAD))
		slot.BackgroundColor3 = COLORS.slotBg
		slot.BackgroundTransparency = 0.05
		slot.BorderSizePixel = 0
		slot.Text = ""
		slot.AutoButtonColor = false
		slot.Parent = gridFrame

		local slotCorner = Instance.new("UICorner")
		slotCorner.CornerRadius = UDim.new(0, 5)
		slotCorner.Parent = slot

		local slotStroke = Instance.new("UIStroke")
		slotStroke.Color = COLORS.slotBorder
		slotStroke.Thickness = 1.5
		slotStroke.Parent = slot

		gridSlotVisuals[i] = { button = slot, stroke = slotStroke }

		local globalIdx = HOTBAR_SLOTS + i

		slot.MouseEnter:Connect(function()
			if isSlotLocked(globalIdx) then return end
			showTooltipForSlot(globalIdx)
		end)
		slot.MouseLeave:Connect(function()
			hideTooltip()
		end)

		slot.MouseButton1Down:Connect(function()
			if isSlotLocked(globalIdx) then return end
			local shiftHeld = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
			if shiftHeld then
				quickTransfer(globalIdx)
				dragState.didDrag = true
				return
			end
			dragState.didDrag = false
			local mousePos = UserInputService:GetMouseLocation()
			local data = slotData[globalIdx]
			if data then
				beginDragPending(globalIdx, data, mousePos, false)
			end
		end)

		slot.MouseButton2Down:Connect(function()
			if isSlotLocked(globalIdx) then return end
			local shiftHeld = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
			if shiftHeld then
				quickTransfer(globalIdx)
				dragState.didDrag = true
				return
			end
			dragState.didDrag = false
			local mousePos = UserInputService:GetMouseLocation()
			local data = slotData[globalIdx]
			if data and data.type == "resource" and data.count and data.count > 1 then
				beginDragPending(globalIdx, data, mousePos, true)
			end
		end)
	end

	-- Big "NEED STRENGTH" overlay that covers the locked portion of the
	-- grid. applyUnlockedSlots() repositions/hides it based on the
	-- current unlocked-count.
	lockedOverlayLabel = Instance.new("TextLabel")
	lockedOverlayLabel.Name = "LockedOverlay"
	lockedOverlayLabel.BackgroundTransparency = 1
	lockedOverlayLabel.Text = "NEED STRENGTH"
	lockedOverlayLabel.Font = Enum.Font.GothamBold
	lockedOverlayLabel.TextScaled = true
	lockedOverlayLabel.TextColor3 = Color3.fromRGB(240, 240, 240)
	lockedOverlayLabel.TextTransparency = 0.25
	lockedOverlayLabel.TextStrokeTransparency = 0.4
	lockedOverlayLabel.TextStrokeColor3 = Color3.fromRGB(20, 20, 20)
	lockedOverlayLabel.ZIndex = 10
	lockedOverlayLabel.Parent = gridFrame

	applyUnlockedSlots()

	-- ─── Left Crafting Panel (vertical category list) ───
	-- `craftPanelWidth`, `craftGap`, and `combinedWidth` are defined above
	-- when computing `centerPanelLeft`.
	local craftPanel = Instance.new("Frame")
	craftPanel.Name = "CraftPanel"
	craftPanel.Size = UDim2.new(0, craftPanelWidth, 0, panelHeight)
	craftPanel.Position = UDim2.new(0.5, -combinedWidth / 2, 0.5, -panelHeight / 2)
	craftPanel.BackgroundColor3 = COLORS.craftPanelBg
	craftPanel.BorderSizePixel = 0
	craftPanel.Parent = screenGui

	local craftCorner = Instance.new("UICorner")
	craftCorner.CornerRadius = UDim.new(0, 10)
	craftCorner.Parent = craftPanel

	local craftStroke = Instance.new("UIStroke")
	craftStroke.Color = COLORS.panelBorder
	craftStroke.Thickness = 2
	craftStroke.Parent = craftPanel

	local craftTitle = Instance.new("TextLabel")
	craftTitle.Size = UDim2.new(1, -15, 0, 28)
	craftTitle.Position = UDim2.new(0, 10, 0, 8)
	craftTitle.BackgroundTransparency = 1
	craftTitle.Text = "Crafting"
	craftTitle.TextColor3 = COLORS.titleText
	craftTitle.Font = Enum.Font.GothamMedium
	craftTitle.TextSize = 18
	craftTitle.TextXAlignment = Enum.TextXAlignment.Left
	craftTitle.Parent = craftPanel

	local craftSep = Instance.new("Frame")
	craftSep.Size = UDim2.new(1, -20, 0, 2)
	craftSep.Position = UDim2.new(0, 10, 0, 38)
	craftSep.BackgroundColor3 = COLORS.panelBorder
	craftSep.BorderSizePixel = 0
	craftSep.Parent = craftPanel

	-- Vertical category tabs
	local tabFrame = Instance.new("Frame")
	tabFrame.Name = "CategoryTabs"
	tabFrame.Size = UDim2.new(1, -20, 1, -55)
	tabFrame.Position = UDim2.new(0, 10, 0, 48)
	tabFrame.BackgroundTransparency = 1
	tabFrame.Parent = craftPanel

	local tabsLayout = Instance.new("UIListLayout")
	tabsLayout.FillDirection = Enum.FillDirection.Vertical
	tabsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabsLayout.Padding = UDim.new(0, 8)
	tabsLayout.Parent = tabFrame

	for i, cat in CATEGORIES do
		local tab = Instance.new("TextButton")
		tab.Name = "Tab_" .. cat
		tab.Size = UDim2.new(1, 0, 0, 76)
		tab.LayoutOrder = i
		tab.BackgroundColor3 = COLORS.craftItemBg
		tab.TextColor3 = COLORS.titleText
		tab.Text = ""
		tab.Font = Enum.Font.GothamMedium
		tab.TextSize = 14
		tab.BorderSizePixel = 0
		tab.AutoButtonColor = false
		tab.Parent = tabFrame
		tab:SetAttribute("Category", cat)

		-- Centered text label (category icons were removed on user request).
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.new(1, -20, 1, 0)
		label.Position = UDim2.new(0, 10, 0, 0)
		label.BackgroundTransparency = 1
		label.Text = cat
		label.TextColor3 = COLORS.titleText
		label.Font = Enum.Font.GothamMedium
		label.TextSize = 18
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.Parent = tab

		local tabCorner = Instance.new("UICorner")
		tabCorner.CornerRadius = UDim.new(0, 6)
		tabCorner.Parent = tab

		local tabStroke = Instance.new("UIStroke")
		tabStroke.Color = COLORS.panelBorder
		tabStroke.Thickness = 1
		tabStroke.Parent = tab

		tab.MouseEnter:Connect(function()
			if selectedCategory ~= cat then
				tab.BackgroundColor3 = COLORS.craftItemHover
			end
		end)
		tab.MouseLeave:Connect(function()
			if selectedCategory ~= cat then
				tab.BackgroundColor3 = COLORS.craftItemBg
			end
		end)

		tab.MouseButton1Click:Connect(function()
			openCategoryOverlay(cat)
			updateCategoryTabs()
		end)
	end

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 28, 0, 28)
	closeBtn.Position = UDim2.new(1, -32, 0, 6)
	closeBtn.BackgroundColor3 = Color3.fromRGB(180, 60, 50)
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 16
	closeBtn.BorderSizePixel = 0
	closeBtn.Parent = centerPanel

	local closeBtnCorner = Instance.new("UICorner")
	closeBtnCorner.CornerRadius = UDim.new(0, 6)
	closeBtnCorner.Parent = closeBtn

	closeBtn.MouseButton1Click:Connect(closeUI)

	-- Raise hotbar above inventory
	if hotbarGui then hotbarGui.DisplayOrder = 15 end

	updateUI()
end

local function toggleInventory()
	if isOpen then
		closeUI()
	else
		isOpen = true
		inventoryCraftEvent:FireServer("requestRecipes")
		buildUI()
	end
end

-- Expose an open hook so other scripts (e.g. the mercenary backpack
-- UI) can force the main inventory open alongside their own UI.
_G.OpenInventory = function()
	if not isOpen then
		isOpen = true
		inventoryCraftEvent:FireServer("requestRecipes")
		buildUI()
	end
end
_G.IsInventoryOpen = function() return isOpen end

-- Expose slot hit-testing so external UIs (merc backpack drag) can find
-- which player-inventory slot the mouse is over.
_G.FindSlotUnderMouse = function(mousePos)
	return findSlotUnderMouse(mousePos)
end

-- Queue a preferred target slot for the next distributeResource call.
-- Used by the merc backpack drag so items land where the user drops them.
_G.PendingTargetSlot = nil

-- ─── Input ───

local numberKeys = {
	[Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4, [Enum.KeyCode.Five] = 5, [Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7, [Enum.KeyCode.Eight] = 8,
}

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.E then
		-- Hard guard: if the player is currently holding the Phone tool the
		-- inventory must NEVER toggle on E, even if PhoneMenu's
		-- `_G.SuppressInventoryToggle` hook hasn't caught up yet. We check
		-- the live character directly so the two UIs can't race.
		local char = player.Character
		local equipped = char and char:FindFirstChildOfClass("Tool")
		if equipped and (equipped.Name == "Phone" or equipped.Name == "leaf bag" or equipped.Name == "Sand Bag" or equipped:GetAttribute("CupState") ~= nil) then
			-- Phone owns its own E binding (close phone UI). Leaf bag
			-- owns its own E binding too (open seed picker via
			-- SeedBagUI.client.lua) — letting the regular inventory
			-- toggle on top of it would cover the picker. Cup uses E
			-- to water a garden bed (CupPurifier.client.lua), so any
			-- tool that carries a CupState attribute (Cup, Cup
			-- (Saltwater), Cup (Fresh Water)) is treated the same way.
			return
		end
		-- Defer the toggle decision until the end of the current
		-- resumption cycle. Roblox does not guarantee InputBegan handler
		-- order between scripts, so DropItem.client.lua's E handler may
		-- run either before or after this one. By deferring, we're
		-- guaranteed that any pickup-in-the-same-frame has already
		-- stamped `_G.LastPickupTime` by the time we re-check — and we
		-- can reject the toggle cleanly without fighting over ordering.
		task.defer(function()
			if (os.clock() - (_G.LastPickupTime or 0)) < 0.2 then
				return
			end
			if _G.SuppressInventoryToggle then
				return
			end
			-- Re-check the Phone guard: the player could have equipped
			-- the Phone between the original press and this deferred
			-- evaluation (unlikely, but cheap to verify).
			local char2 = player.Character
			local equipped2 = char2 and char2:FindFirstChildOfClass("Tool")
			if equipped2 and (equipped2.Name == "Phone" or equipped2.Name == "leaf bag" or equipped2.Name == "Sand Bag" or equipped2:GetAttribute("CupState") ~= nil) then
				return
			end
			toggleInventory()
		end)
	end
	local slotNum = numberKeys[input.KeyCode]
	if slotNum then
		-- Don't swap to a hotbar tool while the phone (or any other
		-- full-screen overlay) is on top — the player is interacting
		-- with the overlay, not trying to switch tools. Prevents
		-- pressing "1..8" from unequipping the phone and revealing
		-- a hotbar item behind the open menu.
		if isHoverBlockingOverlayOpen() then
			return
		end
		local data = slotData[slotNum]
		if data and data.type == "tool" then
			if data.toolInst then
				equipToolInstance(data.toolInst)
			else
				equipToolByName(data.toolName)
			end
			task.wait(0.1)
			renderAllSlots()
		elseif data and data.type == "resource" and data.name and BUSH_SEED_RESOURCE_SET[data.name] and bushActionEvent then
			-- Number-key on a bush-seed slot: same as the slot-click
			-- branch above — server hands the placement Tool to the
			-- player.
			bushActionEvent:FireServer("equipBushSeed", data.name)
		elseif data and data.type == "resource" and data.name and SEED_RESOURCE_SET[data.name] and equipSeedEvent then
			-- Number-key on a seed-resource slot equips it as a Tool
			-- via the server bridge. Same path as the slot-click
			-- handler above.
			equipSeedEvent:FireServer(data.name)
		elseif data and data.type == "resource" and data.name and FOOD_RESOURCE_SET[data.name] and equipFoodEvent then
			-- Number-key on a food-resource slot toggles the food Tool
			-- in hand: equip if nothing held of this kind, unequip
			-- (refund via the server's AncestryChanged hook) if the
			-- player is already holding one. Mirrors the slot-click
			-- handler above so 1-8 and mouse-click behave the same.
			local char     = player.Character
			local humanoid = char and char:FindFirstChildOfClass("Humanoid")
			local heldFoodTool = nil
			if char then
				for _, t in char:GetChildren() do
					if t:IsA("Tool") and t.Name == data.name and t:GetAttribute("FoodResource") == data.name then
						heldFoodTool = t
						break
					end
				end
			end
			if heldFoodTool and humanoid then
				humanoid:UnequipTools()
			else
				equipFoodEvent:FireServer(data.name)
			end
		end
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		if dragState.startPos then
			updateDragPosition(UserInputService:GetMouseLocation())
		end
		if tooltipGui and tooltipGui.Enabled then
			-- Self-heal: if an overlay opened after the tooltip was
			-- already showing (MouseLeave never fired because the
			-- cursor stayed inside the slot's rect), drop the
			-- tooltip on the next mouse move so it doesn't linger
			-- on top of the phone / shop / etc.
			if isHoverBlockingOverlayOpen() then
				hideTooltip()
			else
				updateTooltipPosition(UserInputService:GetMouseLocation())
			end
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.MouseButton2
		or input.UserInputType == Enum.UserInputType.Touch then
		if dragState.active or dragState.startPos then
			endDrag(UserInputService:GetMouseLocation())
		end
	end
end)

-- ─── Events ───

inventoryEvent.OnClientEvent:Connect(function(inv)
	inventory = inv
	updateUI()
end)

inventoryCraftEvent.OnClientEvent:Connect(function(action, data, inv)
	if action == "recipes" then
		recipes = data
		-- Inject Pick-Axe recipe if not present (server file may not sync)
		local hasPickAxe = false
		for _, r in recipes do
			if r.name == "Pick-Axe" then hasPickAxe = true break end
		end
		if not hasPickAxe then
			table.insert(recipes, {
				name = "Pick-Axe",
				displayName = "Pick-Axe",
				icon = "rbxassetid://102411845666126",
				costs = {Log = 2},
				craftType = "tool",
				category = "Tools",
				description = "A pickaxe for mining rocks on islands to collect stone.",
			})
		end
		-- Inject Stone_Axe recipe if not present (StoneAxeSystem
		-- handles crafting via its own InventoryCraft listener; the
		-- recipe metadata only needs to reach the menu so the player
		-- can SEE + click the entry).
		local hasStoneAxe = false
		for _, r in recipes do
			if r.name == "Stone_Axe" then hasStoneAxe = true break end
		end
		if not hasStoneAxe then
			table.insert(recipes, {
				name = "Stone_Axe",
				displayName = "Stone Axe",
				icon = "rbxassetid://112306255674133",
				costs = {Log = 1, Stone = 3, Rope = 1},
				craftType = "tool",
				category = "Tools",
				description = "A stone-bladed axe for chopping palm and banana trees on islands. Yields logs.",
			})
		end
		if inv then inventory = inv end
		if isOpen then
			closeUI(true)
			isOpen = true
			buildUI()
		end
	elseif action == "success" then
		local msgGui = Instance.new("ScreenGui")
		msgGui.DisplayOrder = 20
		msgGui.Parent = playerGui

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(0, 250, 0, 40)
		label.Position = UDim2.new(0.5, -125, 0.3, 0)
		label.BackgroundTransparency = 1
		label.Text = "Crafted!"
		label.TextColor3 = Color3.fromRGB(100, 255, 100)
		label.TextStrokeTransparency = 0.3
		label.TextStrokeColor3 = Color3.new(0, 0, 0)
		label.Font = Enum.Font.GothamBold
		label.TextSize = 28
		label.Parent = msgGui

		local tween = TweenService:Create(label, TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, -125, 0.25, 0),
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		})
		tween:Play()
		tween.Completed:Connect(function() msgGui:Destroy() end)
	end
end)

-- ─── Init ───
rebuildSlotData()
buildHotbar()
renderAllSlots()

-- Track the replicated `Characteristics.UnlockedInventorySlots` value
-- (written by Strength.server.lua based on the player's Strength stat)
-- and repaint the grid whenever it changes.
task.spawn(function()
	local folder = player:WaitForChild("Characteristics")
	local value  = folder:WaitForChild("UnlockedInventorySlots")

	local function refresh()
		unlockedSlots = math.clamp(value.Value, BASE_UNLOCKED_SLOTS, TOTAL_SLOTS)
		applyUnlockedSlots()
	end

	refresh()
	value:GetPropertyChangedSignal("Value"):Connect(refresh)
end)

local backpack = player:WaitForChild("Backpack")
backpack.ChildAdded:Connect(function() task.wait(0.1) updateUI() end)
backpack.ChildRemoved:Connect(function() task.wait(0.1) updateUI() end)

player.CharacterAdded:Connect(function(char)
	-- Reconnect to new Backpack after respawn
	local newBackpack = player:WaitForChild("Backpack")
	newBackpack.ChildAdded:Connect(function() task.wait(0.1) updateUI() end)
	newBackpack.ChildRemoved:Connect(function() task.wait(0.1) updateUI() end)

	char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then task.wait(0.1) updateUI() end
	end)
	char.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then task.wait(0.1) updateUI() end
	end)
end)

if player.Character then
	player.Character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then task.wait(0.1) updateUI() end
	end)
	player.Character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then task.wait(0.1) updateUI() end
	end)
end

-- ─── Listen for saved slot layout restore from server ───
task.spawn(function()
	if not slotLayoutEvent then
		slotLayoutEvent = ReplicatedStorage:WaitForChild("SlotLayoutSync", 10)
	end
	if slotLayoutEvent then
		slotLayoutEvent.OnClientEvent:Connect(function(action, savedLayout)
			if action == "restore" and typeof(savedLayout) == "table" then
				-- Apply saved slot positions
				for i = 1, TOTAL_SLOTS do
					slotData[i] = nil
				end
				for slotStr, itemData in savedLayout do
					local slotNum = tonumber(slotStr)
					if slotNum and slotNum >= 1 and slotNum <= TOTAL_SLOTS and typeof(itemData) == "table" then
						slotData[slotNum] = {
							type = itemData.type,
							name = itemData.name,
							count = itemData.count,
							icon = itemData.icon,
							toolName = itemData.toolName,
						}
					end
				end
				slotsInitialized = true
				renderAllSlots()
				print("[InventoryUI] Restored saved slot layout")
			end
		end)
	end
end)

-- ─── Periodic sync: keep server layout up to date at all times ───
task.spawn(function()
	while true do
		task.wait(0.2)
		syncSlotLayoutToServer()
	end
end)
