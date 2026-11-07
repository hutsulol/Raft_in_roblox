-- AnimalStabilizer.server.lua
-- Decorative animal rigs (Cow, Sheep, …: a Model with an AnimationController and NO Humanoid) are
-- loose physics bodies with REAL mass and player-assigned network ownership. One of them near the
-- raft is a raft-bounce pump: the nearest player's client simulates the animal, the server simulates
-- the raft, and their contacts resolve across the ownership boundary with a frame of lag — shoving
-- the buoyancy spring every frame (this is why the raft only bounced while a player stood aboard,
-- and why it started the second a new Cow spawned / its "[CowAnimation]" script printed).
-- Fix: every such rig is neutralized the moment it appears —
--   • all parts Massless (its weight can't load the raft's spring; its contacts can't shove anything)
--   • network ownership pinned to the SERVER (no client/server contact boundary)
-- Purely visual rigs keep colliding and animating exactly as before.

local Workspace = game:GetService("Workspace")
local PhysicsService = game:GetService("PhysicsService")

-- the "FloatingResource" collision group (registered by BoatMovement, ensured here for start order)
-- does NOT collide with the raft — putting the props there makes touching the raft IMPOSSIBLE.
pcall(function() PhysicsService:RegisterCollisionGroup("FloatingResource") end)

local function isAnimalRig(m)
	if not m:IsA("Model") then return false end
	if m:FindFirstChildOfClass("Humanoid") then return false end
	-- animated decor rigs (Cow etc.)
	if m:FindFirstChildOfClass("AnimationController") then return true end
	-- Tripo AI-mesh props (tripo_convert_*/tripo_node_*) — some have NO AnimationController; one such
	-- loose massy mesh wedged inside the raft hull was caught by RaftTiltProbe pumping the raft
	if m.Name:sub(1, 13) == "tripo_convert" then return true end
	return false
end

local function neutralizePart(p)
	if not p:IsA("BasePart") then return end
	p.Massless = true
	-- CANNOT touch the raft: massless alone wasn't enough — a massless prop wedged between the deck
	-- and a walking player still bridges the player's force into the raft (RaftTiltProbe caught
	-- tripo_convert_01697dc8 doing exactly that, up to a full 169° capsize). In FloatingResource the
	-- prop keeps colliding with terrain/islands (stands & floats) but physically ignores the raft.
	pcall(function() p.CollisionGroup = "FloatingResource" end)
	if not p.Anchored then
		task.defer(function()
			if p.Parent and not p.Anchored then pcall(function() p:SetNetworkOwner(nil) end) end
		end)
	end
end

local function neutralize(m)
	if m:GetAttribute("_AnimalStabilized") then return end
	m:SetAttribute("_AnimalStabilized", true)
	for _, p in ipairs(m:GetDescendants()) do neutralizePart(p) end
	m.DescendantAdded:Connect(neutralizePart)
	print("[AnimalStabilizer] neutralized: " .. m:GetFullName())
end

-- catch rigs that spawn at runtime (cloned cows etc.)
Workspace.DescendantAdded:Connect(function(d)
	if d:IsA("Model") and isAnimalRig(d) then
		task.defer(neutralize, d)
	elseif d:IsA("AnimationController") then
		-- the controller can arrive after the model
		local m = d.Parent
		if m and isAnimalRig(m) then task.defer(neutralize, m) end
	end
end)

--[[ ⚠️ ОБХОД ТЕПЕРЬ РАЗОВЫЙ, А НЕ КАЖДЫЕ ПЯТЬ СЕКУНД.
     GetDescendants по Workspace строит таблицу со ссылками на ВСЕ инстансы мира —
     это десятки тысяч записей и столько же вызовов isAnimalRig, целиком в одном
     кадре. Раз в пять секунд сервер, который тем же кадром считает физику плота,
     получал гарантированный длинный кадр, а игрок — рывок плота на ровном месте.
     Повторять обход незачем: рантайм-риги ловит Workspace.DescendantAdded выше,
     а neutralize идемпотентен. Один проход на старте оставлен ради тех, что уже
     лежат в плейсе к моменту запуска скрипта.
     Если когда-нибудь появится риг, который собирают в несколько шагов и
     DescendantAdded его не покрывает, — вешать точечный сигнал на его сборку, а не
     возвращать обход всего мира. ]]
task.spawn(function()
	for _, d in ipairs(Workspace:GetDescendants()) do
		if isAnimalRig(d) then neutralize(d) end
	end
end)

print("[AnimalStabilizer] active")
