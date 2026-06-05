local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local cannon = script.Parent

local function findPartNamed(name)
	for _, d in cannon:GetDescendants() do
		if d:IsA("BasePart") and d.Name == name then
			return d
		end
	end
	return nil
end

local raft = workspace:FindFirstChild("Raft")
local raftLocalCF = cannon:GetAttribute("RaftLocalCF")
if raft and raft.PrimaryPart and typeof(raftLocalCF) == "CFrame" then
	cannon:PivotTo(raft.PrimaryPart.CFrame:ToWorldSpace(raftLocalCF))
end

local main = findPartNamed("Main")
local baseplate = findPartNamed("Baseplate")

if raft and raft.PrimaryPart and not cannon:GetAttribute("Welded") then
	local primary = raft.PrimaryPart
	local linVel = primary.AssemblyLinearVelocity
	local angVel = primary.AssemblyAngularVelocity

	for _, part in cannon:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end

	for _, part in cannon:GetDescendants() do
		if part:IsA("BasePart") and part ~= main then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = part
			weld.Part1 = primary
			weld.Parent = part
		end
	end

	if main then
		local anchorPart = baseplate or primary
		local recoilWeld = Instance.new("Weld")
		recoilWeld.Name = "RecoilWeld"
		recoilWeld.Part0 = anchorPart
		recoilWeld.Part1 = main
		recoilWeld.C0 = anchorPart.CFrame:ToObjectSpace(main.CFrame)
		recoilWeld.Parent = main
	end

	for _, part in cannon:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
		end
	end

	primary.AssemblyLinearVelocity = linVel
	primary.AssemblyAngularVelocity = angVel

	cannon:SetAttribute("Welded", true)
end

local recoilWeld = main and main:FindFirstChild("RecoilWeld")

local function stripWelds(inst)
	for _, d in inst:GetDescendants() do
		if d:IsA("WeldConstraint") or d:IsA("Weld") or d:IsA("Motor6D") then
			d:Destroy()
		end
	end
end

local bulletRoot = cannon:FindFirstChild("Bullet_Cannon")
local bulletTemplate = nil
if bulletRoot then
	bulletTemplate = bulletRoot:Clone()
	stripWelds(bulletTemplate)
	bulletRoot:Destroy()
end

if cannon:GetAttribute("Loaded") == nil then
	cannon:SetAttribute("Loaded", false)
end

local CANNON_RANGE = 14

local function isLoaded()
	return cannon:GetAttribute("Loaded") == true
end

local function load()
	cannon:SetAttribute("Loaded", true)
end

local RECOIL_BACK = 1
local RECOIL_DOWN = 1
local RECOIL_OUT_TIME = 0.045
local RECOIL_RETURN_TIME = 0.09

local muzzleLocalDir = Vector3.new(0, 0, -1)
if main then
	local off = main.PivotOffset.Position
	if off.Magnitude > 0.05 then
		muzzleLocalDir = off.Unit
	end
end

local function muzzleDirection()
	if not main then return Vector3.new(0, 0, -1) end
	return main.CFrame:VectorToWorldSpace(muzzleLocalDir).Unit
end

local recoilOffsetLocal = Vector3.zero
if main then
	local downLocal = main.CFrame:VectorToObjectSpace(Vector3.new(0, -1, 0))
	recoilOffsetLocal = (-muzzleLocalDir) * RECOIL_BACK + downLocal * RECOIL_DOWN
end

local restC0 = recoilWeld and recoilWeld.C0
local recoilTween = nil

local function playRecoil()
	if not recoilWeld or not restC0 then return end
	if recoilTween then
		recoilTween:Cancel()
	end
	recoilWeld.C0 = restC0
	local outTween = TweenService:Create(
		recoilWeld,
		TweenInfo.new(RECOIL_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ C0 = restC0 * CFrame.new(recoilOffsetLocal) }
	)
	recoilTween = outTween
	outTween.Completed:Connect(function(state)
		if state ~= Enum.PlaybackState.Completed then return end
		local backTween = TweenService:Create(
			recoilWeld,
			TweenInfo.new(RECOIL_RETURN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ C0 = restC0 }
		)
		recoilTween = backTween
		backTween:Play()
	end)
	outTween:Play()
end

local BULLET_SPEED = 140
local BULLET_LIFETIME = 8
local MUZZLE_FORWARD = 3
local ARM_TIME = 0.15
local BOOM_LIFETIME = 3
local EXPLOSION_RADIUS = 18
local EXPLOSION_DAMAGE = 300
local DEFAULT_PART_HP = 100
local CASCADE_ABOVE_HEIGHT = 8

local function getRaftUnit(part)
	if not raft or not part:IsDescendantOf(raft) then return nil end
	local node = part
	while node and node.Parent ~= raft do
		node = node.Parent
	end
	if not node or node == raft then return nil end
	return node
end

local function unitMainPart(unit)
	if unit:IsA("BasePart") then return unit end
	return unit.PrimaryPart or unit:FindFirstChildWhichIsA("BasePart")
end

local function containsPrimary(unit)
	local primary = raft.PrimaryPart
	if not primary then return false end
	return unit == primary or primary:IsDescendantOf(unit)
end

local function collectUnitsInBox(boxCF, boxSize, out)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { raft }
	local parts = workspace:GetPartBoundsInBox(boxCF, boxSize, params)
	for _, p in parts do
		local unit = getRaftUnit(p)
		if unit and not containsPrimary(unit) then
			out[unit] = true
		end
	end
end

local function findUnitsAbove(tile)
	local part = unitMainPart(tile)
	if not part then return {} end
	local pos, size
	if tile:IsA("Model") then
		local cf, sz = tile:GetBoundingBox()
		pos, size = cf.Position, sz
	else
		pos, size = part.Position, part.Size
	end
	local boxCF = CFrame.new(pos + Vector3.new(0, size.Y / 2 + CASCADE_ABOVE_HEIGHT / 2, 0))
	local boxSize = Vector3.new(math.max(size.X * 0.9, 1), CASCADE_ABOVE_HEIGHT, math.max(size.Z * 0.9, 1))
	local found = {}
	collectUnitsInBox(boxCF, boxSize, found)
	found[tile] = nil
	return found
end

local function applyAreaDamage(position)
	if not raft or not raft.PrimaryPart then return end

	local r = EXPLOSION_RADIUS
	local hitUnits = {}
	collectUnitsInBox(CFrame.new(position), Vector3.new(r * 2, r * 2, r * 2), hitUnits)

	local toDestroy = {}
	for unit in hitUnits do
		local part = unitMainPart(unit)
		if part and (part.Position - position).Magnitude <= r then
			local hp = unit:GetAttribute("HP") or DEFAULT_PART_HP
			hp = hp - EXPLOSION_DAMAGE
			if hp <= 0 then
				toDestroy[unit] = true
			else
				unit:SetAttribute("HP", hp)
			end
		end
	end

	local queue = {}
	for unit in toDestroy do
		table.insert(queue, unit)
	end
	while #queue > 0 do
		local unit = table.remove(queue)
		if unit:GetAttribute("BuildType") == "raft" then
			for u in findUnitsAbove(unit) do
				if not toDestroy[u] then
					toDestroy[u] = true
					table.insert(queue, u)
				end
			end
		end
	end

	local primary = raft.PrimaryPart
	local linVel = primary.AssemblyLinearVelocity
	local angVel = primary.AssemblyAngularVelocity

	for unit in toDestroy do
		unit:Destroy()
	end

	primary.AssemblyLinearVelocity = linVel
	primary.AssemblyAngularVelocity = angVel
end

local function explode(position)
	local boom = ReplicatedStorage:FindFirstChild("Boom")
	if boom then
		local fx = boom:Clone()
		for _, d in fx:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
			elseif d:IsA("ParticleEmitter") or d:IsA("Fire") or d:IsA("Smoke") or d:IsA("Sparkles") then
				d.Enabled = true
			end
		end
		if fx:IsA("BasePart") then
			fx.Anchored = true
			fx.CanCollide = false
			fx.CFrame = CFrame.new(position)
		elseif fx:IsA("Model") then
			if not fx.PrimaryPart then
				fx.PrimaryPart = fx:FindFirstChildWhichIsA("BasePart")
			end
			fx:PivotTo(CFrame.new(position))
		end
		fx.Parent = workspace
		Debris:AddItem(fx, BOOM_LIFETIME)
	end
	applyAreaDamage(position)
end

local function launchProjectile(player)
	if not bulletTemplate or not main then return end

	local shooterChar = player and player.Character
	local dir = muzzleDirection()
	local origin = main:GetPivot().Position + dir * MUZZLE_FORWARD
	local muzzle = CFrame.lookAt(origin, origin + dir)
	local bullet = bulletTemplate:Clone()
	local bulletPart = bullet:IsA("BasePart") and bullet or bullet:FindFirstChildWhichIsA("BasePart")
	if not bulletPart then
		bullet:Destroy()
		return
	end

	for _, d in bullet:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
		elseif d:IsA("ParticleEmitter") or d:IsA("Fire") or d:IsA("Smoke") or d:IsA("Sparkles") then
			d.Enabled = true
		end
	end
	bulletPart.Anchored = false
	bulletPart.CanCollide = false
	bulletPart.CanTouch = true

	if bullet:IsA("Model") then
		if not bullet.PrimaryPart then bullet.PrimaryPart = bulletPart end
		bullet:PivotTo(muzzle)
	else
		bullet.CFrame = muzzle
	end

	bullet.Parent = workspace

	bulletPart.AssemblyLinearVelocity = dir * BULLET_SPEED
	pcall(function()
		bulletPart:SetNetworkOwner(nil)
	end)

	local launchClock = os.clock()
	local exploded = false
	local touchConn
	touchConn = bulletPart.Touched:Connect(function(hit)
		if exploded then return end
		if os.clock() - launchClock < ARM_TIME then return end
		if not hit or not hit.Parent then return end
		if hit:IsDescendantOf(cannon) then return end
		if hit:IsDescendantOf(bullet) then return end
		if shooterChar and hit:IsDescendantOf(shooterChar) then return end
		exploded = true
		if touchConn then touchConn:Disconnect() end
		explode(bulletPart.Position)
		bullet:Destroy()
	end)

	Debris:AddItem(bullet, BULLET_LIFETIME)
end

local function fire(player)
	if not isLoaded() then return end
	cannon:SetAttribute("Loaded", false)
	launchProjectile(player)
	playRecoil()
end

local promptPart = baseplate or main or cannon:FindFirstChildWhichIsA("BasePart", true)

if promptPart and not promptPart:FindFirstChild("CannonPrompt") then
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "CannonPrompt"
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = CANNON_RANGE
	prompt.ObjectText = "Cannon"
	prompt.ActionText = isLoaded() and "Fire" or "Load"
	prompt.Parent = promptPart

	prompt.Triggered:Connect(function(player)
		if isLoaded() then
			fire(player)
		else
			load()
		end
	end)

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "CannonStatus"
	billboard.Size = UDim2.new(0, 210, 0, 56)
	billboard.StudsOffset = Vector3.new(0, 3.5, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = CANNON_RANGE + 8
	billboard.Parent = promptPart

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextStrokeTransparency = 0.4
	label.Parent = billboard

	local function refresh()
		local loaded = isLoaded()
		prompt.ActionText = loaded and "Fire" or "Load"
		label.Text = loaded and "Loaded\n[F] Fire" or "Not loaded\n[F] Load"
		label.TextColor3 = loaded and Color3.fromRGB(120, 255, 120) or Color3.fromRGB(255, 205, 120)
	end

	refresh()
	cannon:GetAttributeChangedSignal("Loaded"):Connect(refresh)
end
