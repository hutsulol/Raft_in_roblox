-- Fire_Axe Script
-- Живёт ВНУТРИ тула Fire_Axe, как и у Stone_Axe: замах и кулдаун — здесь, игровая
-- логика рубки — в StoneAxeClient (он же обслуживает и этот топор), урон по живым —
-- в AxeCombat, разбор построек — в RaftDemolish.
--
-- Почему Script, а не LocalScript: Humanoid:LoadAnimation создаёт трек на Animator'е
-- рига, и тот реплицирует проигрывание ВСЕМ — замах видит не только сам игрок.
-- LocalScript внутри тула ещё и успевает проспать первый Equipped при авто-экипировке.
--
-- ОТЛИЧИЕ ОТ Stone_Axe: у нового топора внутри может не быть своей анимации замаха
-- (в модели только Handle). Поэтому, не найдя её у себя, берём анимацию у любого
-- другого топора из ReplicatedStorage — топор машется одинаково, и докладывать
-- анимацию руками не нужно.

local Tool = script.Parent
Tool.Enabled = true

local Handle = Tool:WaitForChild("Handle")

local Services = {
	Players           = game:GetService("Players"),
	ReplicatedStorage = game:GetService("ReplicatedStorage"),
}

local AssetFind = require(Services.ReplicatedStorage:WaitForChild("AssetFind"))

local function findSound(parent, names)
	for _, n in ipairs(names) do
		local s = parent:FindFirstChild(n, true)
		if s and s:IsA("Sound") then return s end
	end
	return nil
end
local SwingSound = findSound(Handle, { "Swing", "SwingSound", "Whoosh" })

local SWING_COOLDOWN = 0.8   -- то же, что у Stone_Axe и в AxeCombat/RaftDemolish

local Animations = {}
local events = {}
local Player, Character, Humanoid

local function Activated()
	if not Tool.Enabled or not Humanoid or Humanoid.Health <= 0 then return end
	Tool.Enabled = false
	task.delay(SWING_COOLDOWN, function()
		Tool.Enabled = true
	end)

	local track = Animations.ChopAnim
	if track then
		pcall(function()
			track:Stop(0)
			track:Play(0.05)
		end)
	end
	if SwingSound then
		pcall(function() SwingSound:Play() end)
	end
end

-- анимация замаха: сперва своя, потом — донорская от другого топора
local function findAnim()
	local own = Tool:FindFirstChild("HitTree" .. Humanoid.RigType.Name)
		or Tool:FindFirstChild("HitTreeR6")
		or Tool:FindFirstChildWhichIsA("Animation", true)
	if own and own:IsA("Animation") then return own end

	for _, name in ipairs({ "Stone_Axe", "Axe" }) do
		local donor = AssetFind.find(name)
		if donor then
			local a = donor:FindFirstChild("HitTree" .. Humanoid.RigType.Name)
				or donor:FindFirstChild("HitTreeR6")
				or donor:FindFirstChildWhichIsA("Animation", true)
			if a and a:IsA("Animation") then return a end
		end
	end
	return nil
end

local function loadChopAnim()
	if not Humanoid or not Tool then return nil end
	local anim = findAnim()
	if not anim then return nil end
	local ok, track = pcall(function() return Humanoid:LoadAnimation(anim) end)
	if ok and track then
		track.Priority = Enum.AnimationPriority.Action
		return track
	end
	return nil
end

local function Equipped()
	Character = Tool.Parent
	Player    = Services.Players:GetPlayerFromCharacter(Character)
	Humanoid  = Character:FindFirstChildOfClass("Humanoid")
	if not Humanoid or Humanoid.Health <= 0 then return end

	Animations.ChopAnim = loadChopAnim()
	events[#events + 1] = Tool.Activated:Connect(Activated)
end

local function Unequipped()
	for i = 1, #events do
		if events[i] then
			events[i]:Disconnect()
			events[i] = nil
		end
	end
	if Animations.ChopAnim then
		pcall(function() Animations.ChopAnim:Stop(0) end)
		Animations.ChopAnim = nil
	end
end

Tool.Equipped:Connect(Equipped)
Tool.Unequipped:Connect(Unequipped)
