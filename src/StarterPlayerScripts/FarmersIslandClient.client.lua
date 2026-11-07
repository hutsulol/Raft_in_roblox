local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
--[[
	КЛИЕНТ ОСТРОВА ФЕРМЕРОВ: позы и удар мутанта (трещины, обломки), свечение
	сундуков. Это клиентские entrypoint'ы пакета Farmers_Island_Transfer
	(MutantAnimator.client / ChestEffects.client), перенесённые из модели острова
	СЮДА: модель живёт в Studio, и её скрипты Rojo не обновляет, а модули они
	берут из ReplicatedStorage/FarmersIsland — те же копии, что и сервер.
	Родные MutantClient/ChestClient в модели сервер сносит при подъёме
	(WorldEventSpawner.killScripts), иначе эффект рисовался бы дважды.

	Тело аниматора — авторское, без правок; связь с сервером — атрибуты модели
	мутанта (FarmersAction/FarmersActionT, их пишет MutantAI) и сундука
	(TargetOpen/GlowStarted, их пишет ChestSpawner).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ISLAND_NAME = "Farmers_Game_Water"
local folder = ReplicatedStorage:WaitForChild("FarmersIsland")
local A = require(folder:WaitForChild("MutantPoses"))
local ImpactFX = require(folder:WaitForChild("MutantImpact"))
local ChestGlow = require(folder:WaitForChild("ChestGlow"))
local FX = require(folder:WaitForChild("GiantEffects"))   -- вирусный взрыв при смерти (оригинал лаборатории)

local function runMutant(island, gameplay)
	local impact = ImpactFX.new(island, gameplay)
	local rigs={}; local connections={}; local scan=0
	local function add(model)
	 if rigs[model] or not model:IsA('Model') or model:GetAttribute('FarmersRole')~='Mutant' then return end
	 local head=model:FindFirstChild('Head');local root=model:FindFirstChild('HumanoidRootPart');local hum=model:FindFirstChildOfClass('Humanoid')
	 if not head or not root or not hum then return end
	 local motors={}
	 for _,v in ipairs(model:GetDescendants()) do if v:IsA('Motor6D') and v.Part1 then motors[v.Part1.Name]=v end end
	 if not motors.LowerTorso or not motors.Head then return end
	 local animate=model:FindFirstChild('Animate');local wasDisabled=nil
	 if animate and (animate:IsA('Script') or animate:IsA('LocalScript')) then wasDisabled=animate.Disabled;animate.Disabled=true end
	 local animator=hum:FindFirstChildOfClass('Animator')
	 if animator then for _,track in ipairs(animator:GetPlayingAnimationTracks()) do track:Stop(.1) end end
	 local plane=model:FindFirstChild('PaintedEyes')
	 local owned=false
	 if not plane then
	  -- The approved giant's transparent eye/brow atlas overlays its sculpted jaw.
	  -- Head dimensions/offsets are the original authored rig's local coordinates.
	  local scale=model:GetScale()
	  plane=Instance.new('Part');plane.Name='PaintedEyes';plane.Size=Vector3.new(1.225,.975,.01)*scale
	  plane.Transparency=1;plane.CanCollide=false;plane.CanTouch=false;plane.CanQuery=false;plane.CastShadow=false;plane.Massless=true
	  plane.CFrame=head.CFrame*CFrame.new(Vector3.new(-.0029800534,6.935-6.585349083,.65-.1243027598)*scale)
	  plane.Parent=model
	  local weld=Instance.new('WeldConstraint');weld.Part0=head;weld.Part1=plane;weld.Parent=plane
	  local gui=Instance.new('SurfaceGui');gui.Name='PaintedExpressions';gui.Face=Enum.NormalId.Back;gui.CanvasSize=Vector2.new(512,512);gui.LightInfluence=.6;gui.AlwaysOnTop=false;gui.Parent=plane
	  local crop=Instance.new('Frame');crop.Size=UDim2.fromScale(1,1);crop.BackgroundTransparency=1;crop.ClipsDescendants=true;crop.Parent=gui
	  local face=Instance.new('ImageLabel');face.Name='ExpressionAtlas';face.BackgroundTransparency=1;face.Size=UDim2.fromScale(2,2);face.Image='rbxassetid://135568984781584';face.Parent=crop
	  owned=true
	 end
	 rigs[model]={head=head,root=root,hum=hum,motors=motors,face=plane:FindFirstChild('ExpressionAtlas',true),plane=owned and plane or nil,animate=animate,wasDisabled=wasDisabled,previous='',transition=0,from={},base={},gait=0,speed=0,lastRoot=root.Position,deathAt=nil}
	end
	local function remove(model,r)
	 for _,m in pairs(r.motors) do if m.Parent then m.Transform=CFrame.identity end end
	 if r.plane then r.plane:Destroy() end
	 if r.animate and r.animate.Parent and r.wasDisabled~=nil then r.animate.Disabled=r.wasDisabled end
	 rigs[model]=nil
	end
	local function discover()
	 local npcs=gameplay:FindFirstChild('NPCs');if not npcs then return end
	 for _,model in ipairs(npcs:GetChildren()) do add(model) end
	end
	local function stateFor(model,r,now)
	 local action=model:GetAttribute('FarmersAction') or ''
	 local state=model:GetAttribute('FarmersState') or 'Idle'
	 local started=model:GetAttribute('FarmersActionT') or now
	 if r.hum.Health<=0 then r.deathAt=r.deathAt or model:GetAttribute('DeathT') or now;return 'Death',now-r.deathAt end   -- НАШЕ: время смерти серверное (MutantAI.DeathT)
	 if action=='MutantSlam' then return 'Slam',math.max(0,now-started) end
	 if action=='Sweep' or action=='Backhand' or action=='Slam' then return action,math.max(0,now-started) end
	 if state=='Walk' or state=='Patrol' or state=='Chase' or action=='Walk' or action=='Run' then return action=='Run' and 'Run' or 'Walk',math.max(0,now-started) end
	 if state=='Attack' then return 'Slam',math.max(0,now-started) end
	 return 'Idle',math.max(0,now-started)
	end
	discover()
	connections[#connections+1]=RunService.PreSimulation:Connect(function(dt)
	 scan+=dt;if scan>1 then scan=0;discover() end
	 local now=workspace:GetServerTimeNow()
	 for model,r in pairs(rigs) do
	  if not model:IsDescendantOf(island) or not r.root.Parent then remove(model,r);continue end
	  local state,t=stateFor(model,r,now)
	  local attackStamp=model:GetAttribute('FarmersActionT')
	  if state=='Slam' and t>=A.timing.Slam.hit and t<A.timing.Slam.duration and r.lastImpact~=attackStamp then
	   r.lastImpact=attackStamp;impact.Impact(model)
	  end
	  local position=r.root.Position;local travel=Vector3.new(position.X-r.lastRoot.X,0,position.Z-r.lastRoot.Z).Magnitude;r.lastRoot=position
	  local measured=travel>4 and 0 or travel/math.max(dt,.001)
	  r.speed+=(math.min(measured,40)-r.speed)*(1-math.exp(-dt/.09))
	  if A.gaitStride[state] then r.gait+=r.speed*dt/(A.gaitStride[state]*model:GetScale()) end
	  if state~=r.previous then
	   r.previous=state;r.transition=0
	   for n,m in pairs(r.motors) do r.from[n]=r.base[n] or m.Transform end
	  end
	  r.transition=math.min(1,r.transition+dt/.10);local mix=r.transition*r.transition*(3-2*r.transition)
	  -- НАШЕ: ветка Death из Bloater.client — судороги, раздувание туши и вирусный выброс на .65 с
  local poses
  if state=='Death' then
   poses=FX.deathPose(t)
   if not r.deathStarted then
    r.deathStarted=true;r.deathSizes={}
    for _,v in model:GetDescendants() do if v:IsA('MeshPart') then r.deathSizes[v]=v.Size end end
    FX.virusDeath(model,t)
   end
   local swell=1+.13*math.clamp(t/FX.deathBurstTime,0,1)^2
   for p,size in pairs(r.deathSizes) do if p.Parent then p.Size=size*(p.Name=='UpperTorso' and swell or 1+(swell-1)*.35) end end
  else
   poses=A.pose(state,t,r.gait)
  end
  poses.Jaw=CFrame.Angles(math.rad(A.jawAngle(state,t)),0,0)
	  local hurt=now-(model:GetAttribute('HurtTime') or -100)
	  local hits=state~='Death' and A.hitPose(hurt,model:GetAttribute('HurtVariant'),model:GetAttribute('HurtStrength')) or {}
	  local scale=model:GetScale()
	  for n,m in pairs(r.motors) do
	   local pose=poses[n] or CFrame.identity
	   -- Scale only translation; preserve the authored local rotation and joint basis.
	   pose=CFrame.new(pose.Position*scale)*pose.Rotation
	   r.base[n]=(r.from[n] or CFrame.identity):Lerp(pose,mix)
	   m.Transform=r.base[n]*(hits[n] or CFrame.identity)
	  end
	  if r.face then
	   local index=state=='Death' and 3 or hurt<.40 and 2 or (state=='Slam' or state=='Sweep' or state=='Backhand' or state=='Run') and 1 or now%4.7<.12 and 2 or 0
	   r.face.Position=UDim2.fromScale(-(index%2),-math.floor(index/2))
	  end
	 end
	end)
	local stopped=false
	local function stop()
	 if stopped then return end;stopped=true
	 for _,c in ipairs(connections) do c:Disconnect() end
	 for model,r in pairs(rigs) do remove(model,r) end
	 impact.Stop()
	end
	connections[#connections+1]=island.AncestryChanged:Connect(function() if not island:IsDescendantOf(workspace) then stop() end end)

end

local function runChests(island, gameplay)
	local residents = gameplay:WaitForChild("ActiveChests", 10)
	if not residents then return end
	local started = setmetatable({}, { __mode = "k" })
	local function attach(chest)
		if started[chest] or not chest:IsA("Model") then return end
		started[chest] = true
		task.spawn(function() ChestGlow.attach(chest) end)
	end
	local added = residents.ChildAdded:Connect(attach)
	for _, chest in ipairs(residents:GetChildren()) do attach(chest) end
	local ancestry
	ancestry = island.AncestryChanged:Connect(function()
		if not island:IsDescendantOf(Workspace) then added:Disconnect() ancestry:Disconnect() end
	end)
end

local seen = setmetatable({}, { __mode = "k" })
local function hook(island)
	if seen[island] or not island:IsA("Model") or island.Name ~= ISLAND_NAME then return end
	seen[island] = true
	task.spawn(function()
		local gameplay = island:WaitForChild("Gameplay", 15)
		if not gameplay then return end
		print("[Фермеры/клиент] остров подхвачен: мутант и сундуки")
		task.spawn(runMutant, island, gameplay)
		task.spawn(runChests, island, gameplay)
	end)
end
for _, m in ipairs(Workspace:GetChildren()) do hook(m) end
Workspace.ChildAdded:Connect(hook)
