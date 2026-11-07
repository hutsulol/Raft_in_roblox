--[[
	УСТАНОВКА ПУГАЛА НА ПЛОТ. Тул-заготовку "Raft_scarecrow" даёт крафт
	(InventoryCrafting, «Технологии»), призрак ведёт ScarecrowPlace.client, сюда
	приходит CupAction "placeScarecrow" с позой относительно PrimaryPart плота.

	Поведения у пугала на сервере нет: качает его клиент (ScarecrowSway), чаек на
	него сажает SeagullAI — оба находят его сами по MeshPart "raft_scarecrow_base".
	Сохранение — общим путём «1в1» (RaftSaveSystem ищет шаблон по имени модели).
	Разбирается топором, как любая постройка плота (RaftDemolish).
]]

local RaftShake = require(game:GetService("ReplicatedStorage"):WaitForChild("RaftShake"))   -- постройка без рывка плота
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AssetFind  = require(ReplicatedStorage:WaitForChild("AssetFind"))
local PlaceCheck = require(ReplicatedStorage:WaitForChild("PlaceCheck"))

local NAME = "Raft_scarecrow"
local MAX_DIST = 60

local cupActionEvent = ReplicatedStorage:WaitForChild("CupAction")

cupActionEvent.OnServerEvent:Connect(function(player, action, target)
	if action ~= "placeScarecrow" then return end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local tool = char and char:FindFirstChildWhichIsA("Tool")
	if not (hrp and tool and tool.Name == NAME) then return end
	local raft = workspace:FindFirstChild("Raft")
	if not (raft and raft.PrimaryPart) or typeof(target) ~= "CFrame" then return end

	local template = AssetFind.find(NAME)
	if not template then
		warn("[Пугало] шаблона Raft_scarecrow нет в ReplicatedStorage — ставить нечего")
		return
	end
	local primary = raft.PrimaryPart
	local worldCF = primary.CFrame:ToWorldSpace(target)
	if (worldCF.Position - hrp.Position).Magnitude > MAX_DIST then return end

	local model = template:Clone()
	model.Name = NAME
	if model:IsA("Model") then
		local bbCF = model:GetBoundingBox()
		model.WorldPivot = CFrame.new(bbCF.Position)
	end
	model:PivotTo(worldCF)
	if PlaceCheck.refuseIfBlocked(model, raft, player) then return end   -- в предмет ставить нельзя
	model.Parent = raft

	-- как у плавильни: заякорить → приварить к плоту → отпустить, скорость вернуть
	local linVel, angVel = primary.AssemblyLinearVelocity, primary.AssemblyAngularVelocity
	local parts = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then table.insert(parts, d) end
	end
	for _, part in ipairs(parts) do part.Anchored = true end
	for _, part in ipairs(parts) do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = part
		weld.Part1 = primary
		weld.Parent = part
		part.Massless = true
	end
	for _, part in ipairs(parts) do part.Anchored = false end
	primary.AssemblyLinearVelocity = linVel
	primary.AssemblyAngularVelocity = angVel
	RaftShake.notify()   -- скорость ещё раз после шага физики + удержать игроков (RaftShake)

	tool:Destroy()
	if typeof(_G.OnQuestEvent) == "function" then pcall(_G.OnQuestEvent, player, "built:Scarecrow", 1) end
	print(("[Пугало] %s поставил пугало на плот"):format(player.Name))
end)

print("[Пугало] готово: крафт «Технологии» → тул Raft_scarecrow → установка на плот")
