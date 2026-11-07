-- DeathAnimation.server.lua
-- Смерть пирата: РЭГДОЛЛ + отброс от убийцы, как у зомби-пожирателя (RaftEater).
--
-- Раньше здесь отрывались шляпа и оружие (detachPart → part.Parent = workspace):
-- со стороны это выглядело как «пират распался на две части» — отдельно летящая
-- деталь и отдельно целое тело. Теперь тело остаётся ЦЕЛЫМ: суставы конечностей
-- меняются на свободные шарниры, и труп отлетает по инерции от удара.

local Players = game:GetService("Players")
local Debris  = game:GetService("Debris")

local pirate = script.Parent
local humanoid = pirate:WaitForChild("Humanoid")

local KNOCKBACK_SPEED = 45 -- те же цифры, что у зомби, чтобы смерти читались одинаково
local KNOCKBACK_UP    = 20
local CORPSE_LIFETIME = 12 -- через столько труп убирается

-- родной рэгдоллер модели мешает нашему: сносим, как и раньше
local ragdoller = pirate:FindFirstChild("RagDoller") or pirate:FindFirstChild("Ragdoller")
if ragdoller and (ragdoller:IsA("Script") or ragdoller:IsA("LocalScript")) then
	ragdoller.Disabled = true
	ragdoller:Destroy()
end

-- КЛЮЧЕВОЕ: без этого Roblox сам разрывает все суставы в момент смерти, и модель
-- рассыпается на отдельные части — именно то, что мы убираем.
humanoid.BreakJointsOnDeath = false

local function nearestPlayerPos(from)
	local best, bd = nil, math.huge
	for _, plr in ipairs(Players:GetPlayers()) do
		local c = plr.Character
		local p = c and c:FindFirstChild("HumanoidRootPart")
		if p then
			local d = (p.Position - from).Magnitude
			if d < bd then best, bd = p.Position, d end
		end
	end
	return best
end

local dead = false
humanoid.Died:Connect(function()
	if dead then return end
	dead = true

	local hrp = pirate:FindFirstChild("HumanoidRootPart") or pirate:FindFirstChild("Torso")
	if not hrp then return end

	-- гасим анимации: поза больше не управляет телом
	local animate = pirate:FindFirstChild("Animate")
	if animate and animate:IsA("BaseScript") then animate.Disabled = true end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, t in ipairs(animator:GetPlayingAnimationTracks()) do t:Stop(0) end
	end
	pcall(function() humanoid.PlatformStand = true end)

	-- РЭГДОЛЛ: Motor6D конечностей → BallSocketConstraint. Сустав HRP↔Torso
	-- оставляем жёстким как «ядро», иначе тело складывается само в себя.
	for _, m in ipairs(pirate:GetDescendants()) do
		if m:IsA("Motor6D") and m.Part0 and m.Part1 and m.Part0 ~= hrp and m.Part1 ~= hrp then
			local a0 = Instance.new("Attachment"); a0.CFrame = m.C0; a0.Parent = m.Part0
			local a1 = Instance.new("Attachment"); a1.CFrame = m.C1; a1.Parent = m.Part1
			local bs = Instance.new("BallSocketConstraint")
			bs.Attachment0, bs.Attachment1 = a0, a1
			bs.Parent = m.Part0
			local ncc = Instance.new("NoCollisionConstraint")
			ncc.Part0, ncc.Part1 = m.Part0, m.Part1
			ncc.Parent = m.Part0
			m:Destroy()
		end
	end

	-- труп не должен толкать игрока и постройки
	for _, d in ipairs(pirate:GetDescendants()) do
		if d:IsA("BasePart") then d.CanCollide = false end
	end

	-- ОТБРОС от того, кто убил: направление считаем от ближайшего игрока
	pcall(function()
		local src = nearestPlayerPos(hrp.Position)
		local away = src and (hrp.Position - src) or (hrp.CFrame.LookVector * -1)
		away = Vector3.new(away.X, 0, away.Z)
		away = (away.Magnitude > 0.01) and away.Unit or Vector3.new(0, 0, 1)
		hrp.AssemblyLinearVelocity = away * KNOCKBACK_SPEED + Vector3.new(0, KNOCKBACK_UP, 0)
		hrp.AssemblyAngularVelocity = Vector3.new(away.Z, 0.5, -away.X) * 7 -- кувырок
	end)

	Debris:AddItem(pirate, CORPSE_LIFETIME)
end)
