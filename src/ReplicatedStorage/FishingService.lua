local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local Run=game:GetService("RunService")
local Lighting=game:GetService("Lighting")
local C=require(RS:WaitForChild("FishingConfig"))
local animations={}; require(RS:WaitForChild("FishingClips"))(animations)
local function duration(name) return animations["Fish_"..name].length end
local Catches=require(RS:WaitForChild("FishingCatches"))
local Rig=require(RS:WaitForChild("FishingRig"))
-- какая рыба попалась, вес, выручка и её 3D-модель — FishData
local FishData=require(RS:WaitForChild("FishData"))
local RaftShake=require(RS:WaitForChild("RaftShake"))   -- игроков на палубе не сносит при перестройке сборки
local Service={}
local active={}
local event=RS:FindFirstChild("FishingSale") or Instance.new("RemoteEvent")
event.Name="FishingSale"; event.Parent=RS
local function part(m,n) local p=m:FindFirstChild(n,true); return p and p:IsA("BasePart") and p end
local BL=require(RS:WaitForChild("BuildingLevels"))   -- уровень станции: множитель выручки
-- мимика рыбака-жителя (папка FaceTextures у модели); у остальных моделей — ничего не делает
local Face=require(RS:WaitForChild("FishermanFace"))
--[[ Удочка станции: цельная raft_fishing_rod (старая модель) или собранная из
     деталей с Zone «Rod_*» (станция с уровнями апгрейда): стержень Rod_Shaft +
     видимые на текущем уровне катушка/бандажи. Скрытые уровни не берём. ]]
local function rodParts(spot)
 local whole=part(spot,"raft_fishing_rod")
 if whole then return whole,{} end
 local shaft,extras=nil,{}
 for _,d in ipairs(spot:GetDescendants()) do
  local z=d:IsA("BasePart") and d:GetAttribute("Zone")
  if type(z)=="string" and z:sub(1,4)=="Rod_" and d.Transparency<1 then
   if z=="Rod_Shaft" then shaft=d else table.insert(extras,d) end
  end
 end
 return shaft,extras
end
function Service.hasRod(spot) return rodParts(spot)~=nil end
local function owner(spot)
 local id=spot:GetAttribute("OwnerUserId")
 if id then return Players:GetPlayerByUserId(id) end
 for _,p in ipairs(Players:GetPlayers()) do
  if typeof(_G.IsRaftOwner)=="function" and _G.IsRaftOwner(p) then return p end
 end
end
function Service.start(spot,options)
 if active[spot] then return active[spot] end
 options=options or {}
 local sit=assert(part(spot,"wp_sit"),"Fishing: missing wp_sit")
 local look=assert(part(spot,"wp_sit_look"),"Fishing: missing wp_sit_look")
 local grip=assert(part(spot,"wp_rod_grip"),"Fishing: missing wp_rod_grip")
 local rod,rodExtras=rodParts(spot)
 assert(rod,"Fishing: missing rod")
 local tpl=assert(options.Template or RS:FindFirstChild(C.TemplateName),"Fishing: install official R6 template first")
 local raft=workspace:FindFirstChild("Raft")
 local primary=options.Primary or (raft and raft.PrimaryPart) or sit
 local scale=(sit.Position-look.Position).Magnitude/9.6
 local forward=(look.Position-sit.Position).Unit
 local frame=CFrame.lookAt(sit.Position,sit.Position+forward,Vector3.yAxis)
 -- Authoring coordinates: Blender x,z,-y, facing positive Roblox Z.
 local origin=frame*CFrame.new(.8*scale,-2.6*scale,-.6*scale)
 local relative=primary.CFrame:ToObjectSpace(origin)
 local s={spot=spot,primary=primary,scale=scale,alive=true,original={},count=0}
 local random=Random.new()
 local function frameNow() return primary.CFrame*relative end
 local function point(x,y,z) return frameNow()*Vector3.new(x*scale,y*scale,z*scale) end
 local npc=tpl:Clone(); npc.Name="RaftFisherman"; s.npc=npc
 local root=assert(part(npc,"HumanoidRootPart")); local hum=assert(npc:FindFirstChildOfClass("Humanoid"))
 for _,d in ipairs(npc:GetDescendants()) do
  if d:IsA("BasePart") then d.Anchored=false; d.CanCollide=false; d.CanTouch=false; d.Massless=true; d.RootPriority=-10
  elseif (d:IsA("Script") or d:IsA("LocalScript")) and d:GetAttribute("KeepOnWorker") then d.Enabled=true   -- HD-лицо/аура жителя (SurvivorService)
  elseif d:IsA("Script") or d:IsA("LocalScript") then d:Destroy() end
 end
 hum.RequiresNeck=false; hum.BreakJointsOnDeath=false; hum.PlatformStand=true; hum.EvaluateStateMachine=false
 hum.DisplayDistanceType=Enum.HumanoidDisplayDistanceType.None
 npc.PrimaryPart=root; npc:ScaleTo(scale*(options.CharacterScale or 1)); npc:SetAttribute("CrewAnim",false); npc:SetAttribute("FishingAdaptive",true); npc:SetAttribute("Role","РЫБАК")
 npc:SetAttribute("FishingFrame",relative); npc:SetAttribute("FishingScale",scale)
 local fit=Rig.measure(npc,scale)
 active[spot]=s
 local function desired(x,y,z,target)
  local p=point(x,y+(fit.ground-3),z); local f=target or (p+frameNow().LookVector)
  return CFrame.lookAt(p,Vector3.new(f.X,p.Y,f.Z),Vector3.yAxis)
 end
 --[[ ⚠️ К ПЛОТУ РЫБАК ПРИВАРИВАЕТСЯ ОДИН РАЗ, УЖЕ СОБРАННЫМ (joinRaft ниже).
      Появление и уход рыбака (смена работника) — перестройка сборки плота.
      Поэтому: сначала рыбак стоит заякоренным и ему в руки приваривается всё
      нужное, потом одна сварка с плотом — со снимком скорости плота до и
      возвратом после (как BuildingSystem при постройке) и RaftShake.notify(). ]]
 npc:PivotTo(desired(-.8,3,-2)); root.Anchored=true; npc.Parent=workspace
 local weld=Instance.new("Weld"); weld.Name="RaftFishermanWeld"; weld.Part0=primary; weld.Part1=root; weld.C0=primary.CFrame:ToObjectSpace(root.CFrame)
 s.weld=weld
 local function keepRaftMotion(fn)
  local lin,ang=primary.AssemblyLinearVelocity,primary.AssemblyAngularVelocity
  fn()
  primary.AssemblyLinearVelocity=lin; primary.AssemblyAngularVelocity=ang
  RaftShake.notify()
 end
 local function joinRaft()
  keepRaftMotion(function() weld.Parent=root; root.Anchored=false end)
  -- сборка общая с плотом: владелец — сервер (одним вызовом, а не на каждую деталь)
  task.defer(function() pcall(function() if primary:GetNetworkOwner()~=nil then primary:SetNetworkOwner(nil) end end) end)
 end
 --[[ Рыбак лежит в workspace, а не в Raft, но приварен к плоту — значит, он часть
      сборки плота. BoatMovement метит только детали внутри Raft (без сил воды,
      физика за сервером). Без этого поплавок, леска и рыба в воде тормозили плот,
      а владение сборкой уходило игроку — плот вставал. Метим сами, и всё, что
      появится в рыбаке позже (удочка, поплавок, рыба). ]]
 local function pin(p)
  if not p:IsA("BasePart") then return end
  pcall(function() p.EnableFluidForces=false end)
  p.CollisionGroup="Raft"
 end
 for _,d in ipairs(npc:GetDescendants()) do pin(d) end
 npc.DescendantAdded:Connect(pin)
 local function alive() return s.alive and spot:IsDescendantOf(workspace) and npc.Parent and primary.Parent and hum.Health>0 end
 local function waitFor(seconds)
  local deadline=os.clock()+seconds
  repeat Run.Heartbeat:Wait(); if not alive() then error("Fishing cancelled",0) end until os.clock()>=deadline
 end
 local function clip(n) if npc:GetAttribute("Clip")~="Fish_"..n then npc:SetAttribute("ClipT",workspace:GetServerTimeNow()) end; npc:SetAttribute("Clip","Fish_"..n); npc:SetAttribute("Activity",n); spot:SetAttribute("FishingState",n) end
 local function once(n) npc:SetAttribute("ClipOnce","Fish_"..n); npc:SetAttribute("ClipOnceT",workspace:GetServerTimeNow()); npc:SetAttribute("Activity",n); spot:SetAttribute("FishingState",n) end
 local function isNight()
  return Lighting.ClockTime<C.WorkStart or Lighting.ClockTime>=C.WorkEnd
 end
 local function awaitBite()
  -- Accumulate daytime-equivalent waiting. Dusk slows the remaining clock;
  -- dawn accelerates it, without resetting the cast or granting a free bite.
  local target=(options.Fast and not isNight()) and 1.8 or random:NextNumber(C.WaitMin,C.WaitMax)
  local progress=0; local sleeping=false; local dozeEnd=0
  clip("Wait"); if not isNight() then Face.Ensure(npc,"Focused") end   -- следит за поплавком
  while progress<target do
   if spot:GetAttribute("FishingPaused") then
    npc:SetAttribute("FishingSleeping",false)
    if sleeping then Face.Sleep(npc,false); clip("Wait"); once("WakeCalm"); waitFor(duration("WakeCalm")) end
    return false
   end
   local night=isNight(); npc:SetAttribute("FishingNight",night)
   if night and not sleeping then
    sleeping=true; clip("Sleep"); once("DozeOff"); dozeEnd=os.clock()+duration("DozeOff")
    npc:SetAttribute("FishingSleeping",true); Face.Sleep(npc,true)   -- зевок → глаза слипаются → сон
   elseif not night and sleeping then
    sleeping=false; npc:SetAttribute("FishingSleeping",false); Face.Sleep(npc,false)   -- пробуждение
    clip("Wait"); once("WakeCalm")
   elseif sleeping and os.clock()>=dozeEnd and npc:GetAttribute("Activity")=="DozeOff" then
    clip("Sleep")
   end
   local dt=Run.Heartbeat:Wait(); if not alive() then error("Fishing cancelled",0) end
   progress=progress+dt/(night and C.NightWaitMultiplier or 1)
  end
  npc:SetAttribute("FishingSleeping",false)
  if sleeping then
   npc:SetAttribute("FishingBiteT",workspace:GetServerTimeNow())
   clip("Wait"); once("WakeBite"); waitFor(duration("WakeBite"))
  end
  return true
 end
 local function move(x,y,z,face,seconds)
  local from=weld.C0; local destination=primary.CFrame:ToObjectSpace(desired(x,y,z,face))
  local duration=seconds or math.max(.1,(destination.Position-from.Position).Magnitude/(C.WalkSpeed*scale))
  local t=0
  while t<duration do
   local dt=Run.Heartbeat:Wait(); if not alive() then error("Fishing cancelled",0) end
   t=math.min(duration,t+dt); local u=t/duration; u=u*u*(3-2*u); weld.C0=from:Lerp(destination,u)
  end
 end
 -- Stool top is 2.66 studs. Lift hips and fold legs while still IN FRONT,
 -- then back over the cushion above it. Never walk through the seat center.
 local function sitDown()
  clip("CarryWalk"); move(-.8,3,fit.approach,nil,.4)
  clip("Wait"); once("Sit")
  waitFor(.25)
  move(-.8,fit.seat+.16-(fit.ground-3),fit.approach,nil,.43)
  move(-.8,fit.seat+.16-(fit.ground-3),.6,nil,.42)
  move(-.8,fit.seat-(fit.ground-3),.6,nil,.30)
  waitFor(.32)
 end
 local function standUp()
  clip("CarryWalk"); once("Stand")
  move(-.8,fit.seat+.16-(fit.ground-3),.45,nil,.32)
  move(-.8,fit.seat+.16-(fit.ground-3),fit.approach,nil,.40)
  move(-.8,3,fit.approach,nil,.66)
  waitFor(.32)
 end
 local function visibility(p,visible)
  if s.original[p]==nil then s.original[p]=p.Transparency end
  p.Transparency=visible and s.original[p] or 1
 end
 local function fill(value)
  spot:SetAttribute("Fish",value)
  for i=1,4 do local p=part(spot,"raft_fishing_catch_"..i); if p then p.Transparency=(value>0 and i==1) and 0 or 1 end end
 end
 local function held(source,armName,offset,anchor)
  local p=source:Clone()
  for _,d in ipairs(p:GetDescendants()) do if d:IsA("JointInstance") or d:IsA("WeldConstraint") or d:IsA("Script") then d:Destroy() end end
  p.Name="Held"..source.Name; p.Transparency=0; p.Anchored=false; p.CanCollide=false; p.CanTouch=false; p.Massless=true; p.Parent=npc
  local w=Instance.new("Weld"); w.Part0=Rig.hand(npc,armName); w.Part1=p; w.C0=offset
  w.C1=anchor or CFrame.new(); w.Parent=p
  return p
 end
 local line=part(spot,"raft_fishing_line")
 local single=RS:FindFirstChild("FishermanFish")
 --[[ 3D-рыба улова: модель из FishData.ModelFor (Model или деталь), иначе FishermanFish.
      Подгоняется по длине под старую заглушку, части сварены с корнем.
      Возвращает объект и корневую деталь, к которой цепляется сварка. ]]
 local fishLength=(single and single:IsA("BasePart")) and math.max(single.Size.X,single.Size.Y,single.Size.Z) or 1.2
 local function makeFish(def,name,anchored)
  local src=FishData.ModelFor(def) or single
  if not src then error("fish asset missing") end
  local obj=src:Clone(); obj.Name=name
  for _,d in ipairs(obj:GetDescendants()) do if d:IsA("JointInstance") or d:IsA("WeldConstraint") or d:IsA("BaseScript") then d:Destroy() end end
  local root
  local length=(src~=single and def and def.size) or fishLength   -- длина в руке, студы (FishData.size)
  --[[ Поворот модели к позе заглушки: у FishermanFish длина по Y (рыба висит
       в руке), у моделей пака — по X. FishAlign = во что повернуть модель в
       хвате; его же берёт клиент, когда ведёт рыбу в полёте (FishingMotion). ]]
  local ext=obj:IsA("BasePart") and obj.Size or select(2,obj:GetBoundingBox())
  local align=CFrame.new()
  if ext.X>=ext.Y and ext.X>=ext.Z then align=CFrame.Angles(0,0,math.pi/2)
  elseif ext.Z>=ext.Y then align=CFrame.Angles(-math.pi/2,0,0) end
  obj:SetAttribute("FishAlign",align)
  if obj:IsA("BasePart") then
   root=obj
   obj.Size=obj.Size*(length/math.max(obj.Size.X,obj.Size.Y,obj.Size.Z))*scale
   if src==single then obj.Transparency=0 end
  else
   root=obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart",true)
   if not root then obj:Destroy(); error("fish model has no parts: "..src.Name) end
   obj.PrimaryPart=root
   local _,size=obj:GetBoundingBox()
   obj:ScaleTo(obj:GetScale()*length*scale/math.max(size.X,size.Y,size.Z,.01))
  end
  for _,p in ipairs(obj:IsA("BasePart") and {obj} or obj:GetDescendants()) do
   if p:IsA("BasePart") then
    p.Anchored=anchored==true and p==root; p.CanCollide=false; p.CanTouch=false; p.CanQuery=false; p.Massless=true
    if p~=root then local w=Instance.new("Weld"); w.Part0=root; w.Part1=p; w.C0=root.CFrame:ToObjectSpace(p.CFrame); w.Parent=p end
   end
  end
  obj.Parent=npc
  return obj,root
 end
 local rodHeld,fishHeld,beam,bobber
 --[[ ⚠️ УДОЧКА И РЫБА В РУКЕ СОЗДАЮТСЯ ОДИН РАЗ И ТОЛЬКО ПРЯЧУТСЯ.
      Рыбак приварен к плоту, значит всё, что приварено к его руке, — часть
      сборки плота. Приварить или убрать деталь = пересобрать сборку, и плот на
      этом подлагивал (как при постановке грядки). Поэтому всё нужное в руке
      приварено сразу при запуске станции, а дальше меняется только прозрачность
      (как уровни улова в ящике, FarmFill). ]]
 local function shown(obj,on)
  local list=obj:GetDescendants(); if obj:IsA("BasePart") then table.insert(list,obj) end
  for _,p in ipairs(list) do
   if p:IsA("BasePart") then
    if p:GetAttribute("HeldT")==nil then p:SetAttribute("HeldT",p.Transparency) end
    p.Transparency=on and p:GetAttribute("HeldT") or 1
   end
  end
 end
 local rodInHand=false
 --[[ ⚠️ УДОЧКА В РУКЕ — КОПИЯ, И ЕЁ НУЖНО УМЕТЬ ПЕРЕСОБРАТЬ НА МЕСТЕ.
      У каждого уровня станции свои детали удочки (rodParts берёт ВИДИМЫЕ), а в
      руке лежит клон, снятый один раз при запуске. Из-за этого улучшение
      станции раньше делалось так: рыбака целиком уничтожить и собрать заново —
      только ради того, чтобы клон удочки пересняли с новых деталей. Для плота
      это две перестройки сборки подряд (работник ушёл → пришёл) плюс возврат
      владения физикой серверу, и он заметно проседал прямо в момент апгрейда.
      Теперь то же самое делается, не снимая рыбака с плота: отпустить удочку,
      пересобрать копию, взять снова. Сборка плота не меняется вовсе. ]]
 local function buildHeldRod()
  if rodHeld then rodHeld:Destroy(); rodHeld=nil end
  --[[ Старые детали больше не наши: снимаем кэш прозрачности. Иначе releaseRod
       вернул бы «исходную» видимость детали, которую новый уровень прячет, и в
       станции торчала бы удочка от прошлого уровня. ]]
  if rod then s.original[rod]=nil end
  for _,e in ipairs(rodExtras or {}) do s.original[e]=nil end
  if line then s.original[line]=nil end
  rod,rodExtras=rodParts(spot)
  line=part(spot,"raft_fishing_line")   -- леска ищется по имени, у нового уровня она может быть своей
  if not rod then return false end
  local anchor=rod.CFrame:ToObjectSpace(CFrame.new(grip.Position)*frameNow().Rotation)
  local _,offset=Rig.grip(npc,"Right",false)
  rodHeld=held(rod,"Right",offset,anchor)
  rodHeld.Name="Heldraft_fishing_rod"   -- по этому имени FishingMotion.client находит удочку и водит поплавок (у составной стержень зовётся иначе)
  -- составная удочка: катушка и бандажи едут за стержнем
  for _,e in ipairs(rodExtras) do
   local c=e:Clone()
   for _,d in ipairs(c:GetDescendants()) do if d:IsA("JointInstance") or d:IsA("WeldConstraint") then d:Destroy() end end
   c.Transparency=0; c.Anchored=false; c.CanCollide=false; c.CanTouch=false; c.CanQuery=false; c.Massless=true; c.Parent=rodHeld
   local w=Instance.new("Weld"); w.Part0=rodHeld; w.Part1=c; w.C0=rod.CFrame:ToObjectSpace(e.CFrame); w.Parent=c
  end
  local tip=rodHeld:FindFirstChild("RodTipAuthored") or Instance.new("Attachment")
  local tipWorld=point(.6,5.3300682,-7.592633)
  if rod.Name~="raft_fishing_rod" then
   -- новый стержень: кончик — угол его габарита, дальний от хвата
   local best=-1
   for _,sx in ipairs({-.5,.5}) do for _,sy in ipairs({-.5,.5}) do for _,sz in ipairs({-.5,.5}) do
    local p=rod.CFrame*Vector3.new(rod.Size.X*sx,rod.Size.Y*sy,rod.Size.Z*sz)
    local d=(p-grip.Position).Magnitude
    if d>best then best=d; tipWorld=p end
   end end end
  end
  tip.Name="RodTipAuthored"; tip.Position=rod.CFrame:PointToObjectSpace(tipWorld); tip.Parent=rodHeld
  shown(rodHeld,false)
  return true
 end
 buildHeldRod()
 -- по рыбе в руке на каждую модель (у разных рыб может быть одна модель)
 local heldBySource={}
 do
  local _,offset=Rig.grip(npc,"Left",true)
  for _,def in ipairs(FishData.Fish) do
   local src=FishData.ModelFor(def) or single
   if src and not heldBySource[src] then
    local obj,root=makeFish(def,"HeldFishIdle")
    local hw=Instance.new("Weld"); hw.Name="HandWeld"; hw.Part0=Rig.hand(npc,"Left"); hw.Part1=root; hw.C0=offset
    hw.C1=(obj:GetAttribute("FishAlign") or CFrame.new()):Inverse(); hw.Parent=root
    shown(obj,false)
    heldBySource[src]=obj
   end
  end
 end
 joinRaft()
 local function showFish(def)
  local obj=heldBySource[FishData.ModelFor(def) or single]
  if not obj then return nil end
  obj.Name="HeldFishermanFish"; shown(obj,true)   -- имя ищет FishingMotion (покачивание в руке)
  return obj
 end
 local function hideFish()
  if fishHeld then shown(fishHeld,false); fishHeld.Name="HeldFishIdle"; fishHeld=nil end
 end
 --[[ ⚠️ ВСЁ, ЧТО В ВОДЕ, НЕ ПРИВАРЕНО К ПЛОТУ. Плот ведёт сила (BoatMovement),
      и приваренный поплавок / летящая рыба в воде тормозили всю сборку — плот
      вставал, пока леска заброшена. Поэтому они заякорены и каждый кадр
      переставляются за плотом: [деталь] = поза в осях PrimaryPart. ]]
 local follow={}
 local followConn=Run.Heartbeat:Connect(function()
  local base=primary.CFrame
  for p,rel in pairs(follow) do
   if p.Parent then p.CFrame=base*rel else follow[p]=nil end
  end
 end)
 local function releaseRod()
  if rodInHand then shown(rodHeld,false); rodInHand=false end
  hideFish()
  if beam then beam:Destroy(); beam=nil end
  if bobber then bobber:Destroy(); bobber=nil end
  visibility(rod,true); for _,e in ipairs(rodExtras) do visibility(e,true) end; if line then visibility(line,true) end
 end
 local function equipRod()
  visibility(rod,false); for _,e in ipairs(rodExtras) do visibility(e,false) end; if line then visibility(line,false) end
  shown(rodHeld,true); rodInHand=true
 end
 local function castLine()
  if not rodInHand then return end
  local a=rodHeld:FindFirstChild("RodTip") or Instance.new("Attachment"); a.Name="RodTip"; a.Position=rodHeld.CFrame:PointToObjectSpace(point(.6,4,-7.9)); a.Parent=rodHeld
  -- Authored rod tip attachment is cached before pickup by the installer when available.
  local authored=rodHeld:FindFirstChild("RodTipAuthored")
  if authored then a.CFrame=authored.CFrame end
  bobber=Instance.new("Part"); bobber.Name="FishingBobber"; bobber.Shape=Enum.PartType.Ball; bobber.Size=Vector3.new(.22,.22,.22)*scale; bobber.Color=Color3.fromRGB(235,64,51)
  bobber.Anchored=true; bobber.CanCollide=false; bobber.CanTouch=false; bobber.CanQuery=false; bobber.Massless=true; bobber.CFrame=CFrame.new(point(.6,-2.2,-8)); bobber.Parent=npc
  s.bobberRel=primary.CFrame:ToObjectSpace(bobber.CFrame)   -- дальше поплавок водит клиент (FishingMotion)
  local b=Instance.new("Attachment"); b.Parent=bobber
  beam=Instance.new("Beam"); beam.Attachment0=a; beam.Attachment1=b; beam.Width0=.018*scale; beam.Width1=.012*scale; beam.FaceCamera=true; beam.Color=ColorSequence.new(Color3.fromRGB(236,237,212)); beam.Parent=rodHeld
  npc:SetAttribute("FishingCatchT",nil); npc:SetAttribute("FishingCatchVariant",nil); npc:SetAttribute("FishingBiteT",nil); npc:SetAttribute("FishingFightT",nil); npc:SetAttribute("HookFlightT",nil)
  npc:SetAttribute("FishingCastT",workspace:GetServerTimeNow())
 end
 local function cleanup()
  s.alive=false; releaseRod(); followConn:Disconnect()
  for p,v in pairs(s.original) do if p.Parent then p.Transparency=v end end
  if spot.Parent then fill(0); spot:SetAttribute("FishingState","Stopped") end
  keepRaftMotion(function() npc:Destroy() end); active[spot]=nil
 end
 function s:stop() self.alive=false end
 --[[ Смена уровня станции без пересборки плота: рыбак остаётся где стоял, в
      руке обновляется удочка. Зовёт BuildingUpgradeServer (через
      _G.RaftFishingRelevel) уже ПОСЛЕ того, как выставлены детали нового
      уровня, — иначе rodParts снял бы копию со старых. ]]
 function s:relevel()
  releaseRod()
  return buildHeldRod()
 end
 task.spawn(function()
  local ok,err=xpcall(function()
   fill(0)
   while alive() do
    if spot:GetAttribute("FishingPaused") then
     -- FishingParked — для того, кто поставил паузу: удочка уже возвращена на
     -- место, рыбак стоит. До этой отметки менять детали станции нельзя.
     clip("Idle"); spot:SetAttribute("FishingParked",true); waitFor(.5)
    else
     spot:SetAttribute("FishingParked",false)
     clip("Walk"); move(-.8,3,-1.4,grip.Position)
     clip("Idle"); once("TakeRod"); waitFor(C.Events.TakeRod); equipRod(); waitFor(duration("TakeRod")-C.Events.TakeRod)
     sitDown(); clip("Wait")
     repeat
      fill(0); once("Cast"); waitFor(C.Events.Cast); castLine(); waitFor(duration("Cast")-C.Events.Cast)
      if not awaitBite() then break end
      if not isNight() and s.count%2==1 then once("CheckLine"); waitFor(duration("CheckLine")) end
      s.count=s.count+1
      local caught=options.Sequence and options.Sequence[(s.count-1)%#options.Sequence+1]
      if caught==nil then caught=random:NextNumber()<C.CatchChance end
      local fishDef,weightKg,price
      if caught then local r=FishData.Roll(random); fishDef,weightKg,price=FishData.FishById[r.fishId],r.weight,r.pay
       -- уровень станции (BuildingLevels): ×1 / ×1,5 / ×2 / ×3 к выручке
       -- бонус жителя (SurvivorDefs: fishIncome, атрибут IncomeBonus станции)
       price=math.floor(price*(BL.Mults[spot:GetAttribute("Level") or 0] or 1)*(1+(spot:GetAttribute("IncomeBonus") or 0))*100+.5)/100 end
       if caught then
       local variantId,variant=Catches.choose(random,s.lastVariant); s.lastVariant=variantId
       local started=workspace:GetServerTimeNow()
       npc:SetAttribute("FishingCatchVariant",variantId)
       npc:SetAttribute("FishingCatchT",started)
       once(variant.clip); Face.Set(npc,"Surprised")   -- клюёт! (спящего будит рывком)
       local function untilMarker(t)
        while workspace:GetServerTimeNow()-started<t do
         waitFor(math.min(.03,t-(workspace:GetServerTimeNow()-started)))
        end
       end
       untilMarker(variant.bite); npc:SetAttribute("FishingBiteT",started+variant.bite)
       untilMarker(variant.fight); npc:SetAttribute("FishingFightT",started+variant.fight)
       untilMarker(variant.launch)
       local flying,flyRoot=makeFish(fishDef,"HookedFish",true)
       -- заякорена, к плоту не приварена (см. follow); полёт рисует клиент (FishingMotion)
       local start=s.bobberRel.Position
       local fw={C0=CFrame.new(start)}; follow[flyRoot]=fw.C0
       task.delay(.1,function() follow[flyRoot]=nil end)   -- поставить у поплавка и отдать клиенту
       npc:SetAttribute("HookFlightT",started+variant.launch)
       while workspace:GetServerTimeNow()-started<variant.catch do
        local dt=Run.Heartbeat:Wait(); if not alive() then error("Fishing cancelled",0) end
        local u=math.clamp((workspace:GetServerTimeNow()-started-variant.launch)/(variant.catch-variant.launch),0,1)
        local hand,offset=Rig.grip(npc,"Left",true)
        local finish=primary.CFrame:PointToObjectSpace((hand.CFrame*offset).Position)
        local x,y=Catches.flightOffset(variant,u,scale)
        fw.C0=CFrame.new(start:Lerp(finish,u)+relative:VectorToWorldSpace(Vector3.new(x,y,0)))
       end
       flying:Destroy()
       fishHeld=showFish(fishDef); Face.Set(npc,"Happy")
       npc:SetAttribute("FishHeldT",started+variant.catch)
       untilMarker(variant.finish); clip("Wait")
      else Face.Set(npc,"Sad"); once("Miss"); waitFor(duration("Miss")) end
      if beam then beam:Destroy(); beam=nil end; if bobber then bobber:Destroy(); bobber=nil end
      if caught then
       standUp()
       clip("CarryWalk"); move(-2.8,3,-1.65)
       clip("CarryWalk"); move(-2,3,1.8,point(-3,1,2.8))
       clip("Idle"); once("PutFish"); waitFor(C.Events.PutFish); hideFish(); fill(1); waitFor(.65)
       -- No client request can mint money. Keep the fish until a valid owner/API exists.
       local paid=false
       repeat
        local player=options.Owner or owner(spot)
        if player and player.Parent and typeof(_G.AddPirate)=="function" then
         --[[ Цена дробная (0.5…15), а баланс — целые пираты: дробный остаток
              копится на игроке (PirateFraction) и доплачивается, когда наберётся. ]]
         local acc=(player:GetAttribute("PirateFraction") or 0)+price
         local whole=math.floor(acc+1e-6)
         local worked,result=true,0
         if whole>0 then worked,result=pcall(_G.AddPirate,player,whole) end
         if worked then player:SetAttribute("PirateFraction",acc-whole) end
         if worked and type(result)=="number" then
          paid=true; fill(0); spot:SetAttribute("SoldFish",(spot:GetAttribute("SoldFish") or 0)+1)
          spot:SetAttribute("LastFishWeightKg",weightKg); spot:SetAttribute("LastFish",fishDef.id)
          -- попап держится над ящиком улова (деталь едет вместе с плотом)
          event:FireAllClients(part(spot,"raft_fishing_catch_1"),point(-3,1.5,2.8),price,weightKg,fishDef.id)
          print("[Fishing] SOLD",fishDef.id,weightKg,"kg",price,"cycle",s.count)
         elseif not worked then error("Currency API failed; sale stopped to prevent duplicate payment: "..tostring(result)) end
        end
        if not paid then spot:SetAttribute("FishingState","WaitingForOwner"); waitFor(1) end
       until paid
       waitFor(duration("PutFish")-C.Events.PutFish-.65); clip("CarryWalk"); move(-2.8,3,-1.65); move(-.8,3,-1.4,grip.Position)
       once("ReturnRod"); waitFor(C.Events.ReturnRod); releaseRod(); waitFor(duration("ReturnRod")-C.Events.ReturnRod)
       clip("Idle"); once("Celebrate"); waitFor(duration("Celebrate"))
       break
      else
       fill(0); print("[Fishing] MISS; Fish=0; no payment",s.count)
      end
     until not alive() or spot:GetAttribute("FishingPaused")
     if rodInHand then
      standUp(); clip("CarryWalk"); move(-.8,3,-1.4,grip.Position)
      once("ReturnRod"); waitFor(C.Events.ReturnRod); releaseRod(); waitFor(duration("ReturnRod")-C.Events.ReturnRod); clip("Idle")
     end
    end
   end
  end,debug.traceback)
  cleanup()
  if not ok and not string.find(tostring(err),"Fishing cancelled",1,true) then warn(err) end
 end)
 return s
end
-- активная станция (или nil): по ней выжившие меняют рыбака (RaftFishing)
function Service.get(spot) return active[spot] end
return Service
