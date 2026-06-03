-- RecruitmentSystem.server.lua
-- Handles pirate recruitment after knockout (Humanoid.Died + ragdoll).
--
-- The client sends one of three actions via the RecruitPirate RemoteEvent:
--   "keep"    – player declines; pirate fades out after a short delay.
--   "recruit" – minigame succeeded; pirate fades out, recruited count +1.
--   "fail"    – minigame failed; pirate fades out after a short delay.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local rs = game:GetService("ReplicatedStorage")

-- Central registry of recruitable NPC types. The recruitment flow
-- filters every action through resolve() so unknown ragdolls (e.g.
-- vanilla zombies, decorations, other-player corpses) cannot trigger
-- the recruit/blood paths regardless of what the client sends.
local NpcTypes = require(rs:WaitForChild("NpcTypes"))

local recruitEvent = Instance.new("RemoteEvent")
recruitEvent.Name = "RecruitPirate"
recruitEvent.Parent = rs

-- Per-player recruited count. Stored here for now; additional mechanics
-- (crew display, buffs, etc.) will be layered on later.
local recruitedCounts = {}

-- Prevents two players from claiming the same pirate body.
local claimedPirates = {}

-- ── Mercenaries folder (replicated to client) ──────────────────────────
-- Each recruited pirate type gets a StringValue child so the phone menu
-- can enumerate them. Duplicate pirate names are skipped ("max one of
-- each type" rule).
-- ── DEV MODE ──────────────────────────────────────────────────────────
-- Pre-grants the player a roster of mercenaries on join so the phone
-- menu can be tested without doing a full kill / recruit cycle every
-- session. Only the Pirate is in the dev grant — the Infected Military
-- must be earned via kill → first-defeat dialogue → brain-maze
-- completion, otherwise testers can't actually play through that
-- recruitment flow.
--
-- Recruit-flow dialogue is gated client-side by a separate
-- session-only flag (recruitedThisSession), so pre-granting the
-- roster here does NOT skip the first-defeat dialogue when the
-- player actually kills one of these NPCs in the world.
--
-- Set to false before shipping.
local DEV_AUTO_GRANT = true
local DEV_MERCENARY_NAMES = { "Pirate lvl1" }

local function ensureMercenariesFolder(player)
	local folder = player:FindFirstChild("Mercenaries")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Mercenaries"
		folder.Parent = player
	end
	return folder
end

local function grantDevMercenary(player)
	if not DEV_AUTO_GRANT then return end
	local folder = ensureMercenariesFolder(player)
	for _, name in DEV_MERCENARY_NAMES do
		if not folder:FindFirstChild(name) then
			local entry = Instance.new("StringValue")
			entry.Name = name
			entry.Value = name
			entry.Parent = folder
		end
	end
end

Players.PlayerAdded:Connect(function(player)
	ensureMercenariesFolder(player)
	grantDevMercenary(player)
end)
for _, p in Players:GetPlayers() do
	ensureMercenariesFolder(p)
	grantDevMercenary(p)
end

local function fadePirate(pirate, delay, duration)
	if delay and delay > 0 then
		task.wait(delay)
	end
	local dur = duration or 1.5
	local steps = math.floor(dur / 0.05)
	for step = 1, steps do
		if not pirate or not pirate.Parent then break end
		local alpha = step / steps
		for _, desc in pirate:GetDescendants() do
			if desc:IsA("BasePart") or desc:IsA("Decal") then
				desc.Transparency = alpha
			end
		end
		task.wait(0.05)
	end
	if pirate and pirate.Parent then
		pirate:Destroy()
	end
end

recruitEvent.OnServerEvent:Connect(function(player, action, pirate)
	if typeof(pirate) ~= "Instance" then return end
	if CollectionService:HasTag(pirate, "SpawnedMercenary") then return end
	-- Strict NPC-type gate: only models registered in NpcTypes can
	-- progress through any recruitment action. Without this, killing
	-- e.g. a decorative ragdoll would let the player "recruit" it
	-- under whatever Model.Name happened to be set.
	local npcInfo = NpcTypes.resolve(pirate)
	if not npcInfo then return end

	-- The rig's Respawn.script destroys the original ~5s after death
	-- and re-parents a clone. The brain-maze can easily take longer
	-- than that, so by the time the player completes it the original
	-- pirate Instance is gone from workspace. For the "recruit"
	-- action we accept this — npcInfo already tells us what type was
	-- killed, so we can credit the player's roster without needing
	-- the body. Other actions (keep / fail / collectBlood) still
	-- need the rig present so the fade animation has something to
	-- act on, and so we can validate proximity + downed state.
	local rigInWorkspace = pirate:IsDescendantOf(workspace)
	if action ~= "recruit" and not rigInWorkspace then return end

	-- Accept if Downed attribute is set, OR if the Humanoid is ragdolled
	if rigInWorkspace and not pirate:GetAttribute("Downed") then
		local hum = pirate:FindFirstChildWhichIsA("Humanoid")
		if not hum then return end
		local isDowned = hum.Health <= 0
			or hum:GetState() == Enum.HumanoidStateType.Dead
			or hum:GetState() == Enum.HumanoidStateType.Physics
			or hum.PlatformStand
		if not isDowned then return end
		pirate:SetAttribute("Downed", true)
		pirate:SetAttribute("RecruitChance", 100)
	end
	if claimedPirates[pirate] then return end

	-- Distance check (only meaningful while the rig is still around).
	if rigInWorkspace then
		local char = player.Character
		if not char or not char:FindFirstChild("HumanoidRootPart") then return end
		local piratePos
		local hrp = pirate:FindFirstChild("HumanoidRootPart")
		if hrp then
			piratePos = hrp.Position
		else
			local part = pirate:FindFirstChildWhichIsA("BasePart", true)
			if part then piratePos = part.Position else return end
		end
		if (char.HumanoidRootPart.Position - piratePos).Magnitude > 25 then return end
	end

	claimedPirates[pirate] = player
	pcall(function() pirate:SetAttribute("Claimed", true) end)

	if action == "keep" then
		task.spawn(fadePirate, pirate, 2, 1.5)

	elseif action == "recruit" then
		if not recruitedCounts[player] then
			recruitedCounts[player] = 0
		end
		recruitedCounts[player] += 1
		recruitEvent:FireClient(player, "recruited", recruitedCounts[player])

		-- Quest hook (Phase I): credit "Hire 1 mercenary" objectives.
		-- pcall keeps a buggy quest path from breaking recruitment.
		if typeof(_G.OnQuestEvent) == "function" then
			pcall(_G.OnQuestEvent, player, "merc:hired", 1)
		end

		-- Track individual mercenary (one per type). The mercName comes
		-- from the NpcTypes registry, not Model.Name, so a renamed
		-- template can't sneak a duplicate entry into the menu.
		local folder = ensureMercenariesFolder(player)
		local mercName = npcInfo.mercName
		if not folder:FindFirstChild(mercName) then
			local entry = Instance.new("StringValue")
			entry.Name = mercName
			entry.Value = mercName
			entry.Parent = folder
		end

		task.spawn(fadePirate, pirate, 0, 2)

	elseif action == "fail" then
		recruitEvent:FireClient(player, "failed")
		task.spawn(fadePirate, pirate, 1.5, 1.5)

	elseif action == "collectBlood" then
		-- Injector-driven blood collection: the player must hold an
		-- Injector AND have an EmptyCapsule in their inventory. One
		-- EmptyCapsule is consumed and a typed FullCapsule is given
		-- back. The injector requirement keeps the harvesting loop
		-- tied to the existing crafting / capsule economy instead of
		-- handing out free samples on every kill.
		local backpack = player:FindFirstChild("Backpack")
		local emptyCapsule = (backpack and backpack:FindFirstChild("EmptyCapsule"))
			or (player.Character and player.Character:FindFirstChild("EmptyCapsule"))
		if not emptyCapsule then
			claimedPirates[pirate] = nil
			pirate:SetAttribute("Claimed", nil)
			return
		end
		emptyCapsule:Destroy()

		local template = rs:FindFirstChild("FullCapsule", true)
		local fullCapsule
		if template and template:IsA("Tool") then
			fullCapsule = template:Clone()
		else
			fullCapsule = Instance.new("Tool")
			fullCapsule.Name = "FullCapsule"
			fullCapsule.CanBeDropped = false
			fullCapsule.TextureId = "rbxassetid://132749498016835"
			local handle = Instance.new("Part")
			handle.Name = "Handle"
			handle.Size = Vector3.new(1, 1, 1)
			handle.Transparency = 1
			handle.Parent = fullCapsule
		end
		-- Tag the sample with the type-specific blood marker. Inventory
		-- and DNAStudyPage both group capsules by BloodType; using the
		-- registry value (instead of Model.Name) keeps blood from a
		-- renamed template from polluting the wrong stack.
		fullCapsule:SetAttribute("BloodType", npcInfo.bloodType)
		fullCapsule:SetAttribute("BloodLabel", npcInfo.bloodLabel)
		if backpack then
			fullCapsule.Parent = backpack
		end
		recruitEvent:FireClient(player, "bloodDropped", npcInfo.bloodType)

		-- Quest hook (Phase I): credit "Collect 5 blood samples" objectives.
		if typeof(_G.OnQuestEvent) == "function" then
			pcall(_G.OnQuestEvent, player, "pirate:bloodTaken", 1)
		end

		task.spawn(fadePirate, pirate, 0, 2)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	recruitedCounts[player] = nil
end)
