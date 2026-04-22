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
-- Set to true to auto-grant a mercenary on join for testing.
-- Remove or set to false before shipping.
local DEV_AUTO_GRANT = true
local DEV_MERCENARY_NAME = "Pirate lvl1"

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
	if not folder:FindFirstChild(DEV_MERCENARY_NAME) then
		local entry = Instance.new("StringValue")
		entry.Name = DEV_MERCENARY_NAME
		entry.Value = DEV_MERCENARY_NAME
		entry.Parent = folder
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
	if not pirate:IsDescendantOf(workspace) then return end
	if CollectionService:HasTag(pirate, "SpawnedMercenary") then return end
	-- Accept if Downed attribute is set, OR if the Humanoid is ragdolled
	if not pirate:GetAttribute("Downed") then
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

	-- Distance check
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

	claimedPirates[pirate] = player
	pirate:SetAttribute("Claimed", true)

	if action == "keep" then
		task.spawn(fadePirate, pirate, 2, 1.5)

	elseif action == "recruit" then
		if not recruitedCounts[player] then
			recruitedCounts[player] = 0
		end
		recruitedCounts[player] += 1
		recruitEvent:FireClient(player, "recruited", recruitedCounts[player])

		-- Track individual mercenary (one per name)
		local folder = ensureMercenariesFolder(player)
		local pirateName = pirate.Name
		if not folder:FindFirstChild(pirateName) then
			local entry = Instance.new("StringValue")
			entry.Name = pirateName
			entry.Value = pirateName
			entry.Parent = folder
		end

		task.spawn(fadePirate, pirate, 0, 2)

	elseif action == "fail" then
		recruitEvent:FireClient(player, "failed")
		task.spawn(fadePirate, pirate, 1.5, 1.5)

	elseif action == "collectBlood" then
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
		-- Tag the sample with the merc it came from. DNAStudyPage filters
		-- capsules by this attribute so a Pirate's DNA cannot be studied
		-- under a different mercenary (and the SAMPLES counter on the
		-- top bar only counts matching-blood capsules).
		fullCapsule:SetAttribute("BloodType", pirate.Name)
		if backpack then
			fullCapsule.Parent = backpack
		end

		task.spawn(fadePirate, pirate, 0, 2)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	recruitedCounts[player] = nil
end)
