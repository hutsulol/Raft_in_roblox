local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

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

local RECOIL_OFFSET = Vector3.new(0, -1, 1)
local RECOIL_OUT_TIME = 0.045
local RECOIL_RETURN_TIME = 0.09

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
		{ C0 = restC0 * CFrame.new(RECOIL_OFFSET) }
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
local MUZZLE_FORWARD = 2

local function launchProjectile()
	if not bulletTemplate or not main then return end

	local muzzle = main:GetPivot() * CFrame.new(0, 0, -MUZZLE_FORWARD)
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
	bulletPart.CanCollide = true
	bulletPart.CanTouch = true

	if bullet:IsA("Model") then
		if not bullet.PrimaryPart then bullet.PrimaryPart = bulletPart end
		bullet:PivotTo(muzzle)
	else
		bullet.CFrame = muzzle
	end

	bullet.Parent = workspace

	bulletPart.AssemblyLinearVelocity = muzzle.LookVector * BULLET_SPEED
	pcall(function()
		bulletPart:SetNetworkOwner(nil)
	end)

	Debris:AddItem(bullet, BULLET_LIFETIME)
end

local function fire()
	if not isLoaded() then return end
	cannon:SetAttribute("Loaded", false)
	launchProjectile()
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

	prompt.Triggered:Connect(function()
		if isLoaded() then
			fire()
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
