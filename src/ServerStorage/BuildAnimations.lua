--!strict
-- Turn PirateCrewClips into real KeyframeSequences, straight in Studio.
--
-- Roblox does not import R6 animation from FBX: that path is for R15 with
-- skinned meshes, and the 3D Importer only brings in geometry. An R6 animation
-- is six Motor6D CFrames per keyframe, which is exactly what a KeyframeSequence
-- holds - so we build one instead of importing anything.
--
-- ⚠️ ЭТО ИНСТРУМЕНТ ДЛЯ STUDIO, А НЕ ИГРОВОЙ СКРИПТ.
-- Он ничего не делает во время игры и намеренно лежит в ServerStorage
-- ModuleScript'ом: сам по себе модуль не запускается, только по require.
-- Если положить его Script'ом в ServerScriptService, он молотил бы на каждом
-- старте сервера впустую.
--
-- Как пользоваться (оба файла уже в проекте, вставлять руками ничего не надо):
--   1. В командной строке Studio:
--        require(game.ServerStorage.BuildAnimations)
--   2. В ServerStorage.PirateCrewAnimations появятся KeyframeSequence по числу
--      клипов в PirateCrewClips (сейчас их 9: IdleAim, IdleCrouch, IdleLook,
--      IdleSit, Run, SitDown, StandUp, Suspicious, Walk).
--   3. Правой кнопкой по каждой → «Save to Roblox», чтобы опубликовать и
--      получить ID для Animation.
--
--   ⚠️ Модуль кешируется: чтобы прогнать его повторно за одну сессию Studio,
--   нажми Stop/Play или пересоздай сессию — иначе require вернёт прошлый
--   результат и ничего не пересоберёт.
--
-- PREVIEW = true также проигрывает каждый клип на риге с именем PREVIEW_RIG в
-- Workspace, чтобы посмотреть позы до публикации. Работает через
-- KeyframeSequenceProvider, то есть только внутри Studio.

local ServerStorage = game:GetService("ServerStorage")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local RunService = game:GetService("RunService")

local DATA = require(ServerStorage:WaitForChild("PirateCrewClips"))
local PREVIEW = true
local PREVIEW_RIG = "NormalDummy"
local PREVIEW_HOLD = 2.5           -- seconds per clip while previewing

local LIMBS = { "Head", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }

local function toCFrame(n: { number }): CFrame
	return CFrame.new(n[1], n[2], n[3],
		n[4], n[5], n[6],
		n[7], n[8], n[9],
		n[10], n[11], n[12])
end

local function buildSequence(name: string, clip): KeyframeSequence
	local seq = Instance.new("KeyframeSequence")
	seq.Name = name
	seq.Loop = clip.loop
	seq.Priority = Enum.AnimationPriority.Action

	for _, k in clip.keys do
		local kf = Instance.new("Keyframe")
		kf.Time = k.t

		-- Pose tree mirrors the joint tree: root -> torso -> everything else
		local root = Instance.new("Pose")
		root.Name = "HumanoidRootPart"
		root.CFrame = CFrame.identity
		root.Weight = 1
		root.Parent = kf

		local torso = Instance.new("Pose")
		torso.Name = "Torso"
		torso.CFrame = toCFrame(k.p["Torso"])
		torso.Weight = 1
		torso.EasingStyle = Enum.PoseEasingStyle.Cubic
		torso.EasingDirection = Enum.PoseEasingDirection.InOut
		torso.Parent = root

		for _, limb in LIMBS do
			local p = Instance.new("Pose")
			p.Name = limb
			p.CFrame = toCFrame(k.p[limb])
			p.Weight = 1
			p.EasingStyle = Enum.PoseEasingStyle.Cubic
			p.EasingDirection = Enum.PoseEasingDirection.InOut
			p.Parent = torso
		end

		kf.Parent = seq
	end
	return seq
end

local folder = ServerStorage:FindFirstChild("PirateCrewAnimations")
if folder then
	folder:Destroy()
end
folder = Instance.new("Folder")
folder.Name = "PirateCrewAnimations"
folder.Parent = ServerStorage

local built = {}
for name, clip in DATA.clips do
	local seq = buildSequence(name, clip)
	seq.Parent = folder
	built[name] = seq
	print(("built %-12s %2d keys  %.2fs  loop=%s")
		:format(name, #clip.keys, clip.length, tostring(clip.loop)))
end

if PREVIEW then
	task.spawn(function()
		local rig = workspace:FindFirstChild(PREVIEW_RIG)
		local hum = rig and rig:FindFirstChildOfClass("Humanoid")
		if not hum then
			warn(("preview: no Humanoid in workspace.%s"):format(PREVIEW_RIG))
			return
		end
		if not RunService:IsStudio() then
			warn("preview only works in Studio")
			return
		end
		local animator = hum:FindFirstChildOfClass("Animator")
			or Instance.new("Animator", hum)
		for name, seq in built do
			local id = KeyframeSequenceProvider:RegisterKeyframeSequence(seq)
			local a = Instance.new("Animation")
			a.AnimationId = id
			local track = animator:LoadAnimation(a)
			track.Looped = seq.Loop
			print("preview:", name)
			track:Play(0.2)
			task.wait(PREVIEW_HOLD)
			track:Stop(0.2)
		end
		print("preview done")
	end)
end

return built
