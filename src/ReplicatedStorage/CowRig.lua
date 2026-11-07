local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
--[[
	CowRig — превращает импортированную модель «Cow» (7 MeshPart) в Motor6D-риг.

	Модульная версия авторского Cow_BuildRig.luau из пакета коровы: без Selection
	и автозапуска, зато идемпотентная — можно звать на каждом клоне при спавне.

	НИКАКИХ КОСТЕЙ. Семь отдельных MeshPart на Motor6D, ровно как штатный R6:
	скиннед-меш с арматурой — это один коллайдер, который спорит с каждым
	суставом (прошлая корова этим и болела). Дерево суставов:

		HumanoidRootPart --RootJoint--> Torso
			Torso --Neck--------------> Head
			Torso --HipFL / HipFR-----> LegFL / LegFR
			Torso --HipRL / HipRR-----> LegRL / LegRR
			Torso --TailJoint---------> Tail

	Точки крепления — ДОЛИ от Size каждой детали (из cow.json), не студы: пивот
	MeshPart всегда в центре его bounding box, а масштаб импорта — какой выбрали;
	доли переживают и то, и другое. Перегенерировали меш — сверить с cow.json.

	⚠️ Суставы строятся ПО ТЕКУЩЕЙ ПОЗЕ: детали клона должны стоять так, как
	приехали из FBX (авторская стойка). Звать setup ДО перестановки модели.
]]

local ATTACH = {
	Head  = { 0.0000, -0.1783, 0.3397 },
	LegFL = { 0.0000, 0.5000, 0.0000 },
	LegFR = { 0.0000, 0.5000, 0.0000 },
	LegRL = { 0.0000, 0.5000, 0.0000 },
	LegRR = { 0.0000, 0.5000, 0.0000 },
	Tail  = { -0.2366, 0.5000, -0.4249 },
}

local JOINT_NAME = {
	Head  = "Neck",
	LegFL = "HipFL",
	LegFR = "HipFR",
	LegRL = "HipRL",
	LegRR = "HipRR",
	Tail  = "TailJoint",
}

local CowRig = {}

function CowRig.setup(model)
	local torso = model:FindFirstChild("Torso", true)
	assert(torso and torso:IsA("BasePart"), "CowRig: в модели нет детали Torso — " .. model.Name)

	-- масса и коллизия только у торса; невесомые конечности не дают шарнирной
	-- тушке разболтать саму себя, как только её разанкорят
	torso.Anchored = false
	torso.CanCollide = true

	local root = model:FindFirstChild("HumanoidRootPart")
	if not root then
		root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Size = torso.Size * 0.9
		root.CFrame = torso.CFrame
		root.Transparency = 1
		root.CanCollide = false
		root.CanQuery = false
		root.CanTouch = false
		root.Parent = model
	end
	root.Anchored = false
	model.PrimaryPart = root

	-- идемпотентность: прошлые суставы и сварки под снос
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") or d:IsA("Weld") or d:IsA("WeldConstraint") then
			d:Destroy()
		end
	end

	local rj = Instance.new("Motor6D")
	rj.Name = "RootJoint"
	rj.Part0 = root
	rj.Part1 = torso
	rj.C0 = root.CFrame:Inverse() * torso.CFrame
	rj.C1 = CFrame.identity
	rj.Parent = root

	for name, frac in pairs(ATTACH) do
		local part = model:FindFirstChild(name, true)
		if part and part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
			part.Massless = true

			-- точка сустава в мире, снятая с ДЕТАЛИ: части уже стоят по местам
			local at = part.CFrame * CFrame.new(
				part.Size.X * frac[1],
				part.Size.Y * frac[2],
				part.Size.Z * frac[3]
			)

			local m = Instance.new("Motor6D")
			m.Name = JOINT_NAME[name]
			m.Part0 = torso
			m.Part1 = part
			m.C0 = torso.CFrame:Inverse() * at
			m.C1 = part.CFrame:Inverse() * at
			m.Parent = torso
		else
			warn("CowRig: нет детали " .. name .. " в " .. model.Name)
		end
	end

	return model
end

return CowRig
