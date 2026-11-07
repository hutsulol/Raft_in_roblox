--[[ ⚠️ СЕТКОМЁТ (пакет test/NetCapture_Import): авторский модуль, перенесён в
     Rojo как есть. Модели (Assets: Sheep, FlightNet, WrappedNet и Tool
     Pirate_Net_Launcher) живут в Studio внутри ReplicatedStorage/NetCapture —
     Rojo их не трогает (init.meta.json). Наши правки помечены «-- НАШЕ:». ]]
local Players=game:GetService('Players')
local RunService=game:GetService('RunService')
local Pack=script.Parent
local Config=require(Pack.Config)
local Service={sheep={},shots={},carrying={},lastShot={},lastAim={},connections={},nextId=0}
local function now()return workspace:GetServerTimeNow()end
local function finite(v)
 return typeof(v)=='Vector3' and v.X==v.X and v.Y==v.Y and v.Z==v.Z and math.abs(v.X)<1e6 and math.abs(v.Y)<1e6 and math.abs(v.Z)<1e6
end
local function actor(player)
 local c=player.Character
 local h=c and c:FindFirstChildOfClass('Humanoid')
 local root=c and c:FindFirstChild('HumanoidRootPart')
 if not h or not root or h.Health<=0 then return end
 return c,h,root
end
local function rayParams(exclude)
 local p=RaycastParams.new();p.FilterType=Enum.RaycastFilterType.Exclude;p.FilterDescendantsInstances=exclude;p.IgnoreWater=false;return p
end
--[[ НАШЕ: ЖИЗНЬ СВОБОДНОЙ ОВЦЫ — КАК НА ФЕРМЕ (FarmSystem.stepSheep).
     Была одна статичная поза «пасётся» и после спавна, и после освобождения.
     Теперь сервер ведёт режимы idle / graze / look / bleat / wander / лечь-
     отдохнуть-встать, пугается игрока вплотную (Startled → отбегает рысью).
     Клиенту уходит только атрибут Clip (+ ClipSince) — клипы NetCapture/
     SheepAnimator, как ферма шлёт Clip своим овцам.
     ⚠️ ОВЦА МОЖЕТ СТОЯТЬ НА ПЛЫВУЩЕМ ПЛОТУ: корень заякорен, поэтому его поза
     хранится относительно детали под ногами (base/baseRel) и каждый кадр
     переносится вместе с ней. Иначе плот уплывал бы из-под овцы. ]]
local AI={WalkSpeed=4,TrotSpeed=7,TurnRate=3.2,Leash=14,ScareRadius=6,StepUp=1.2}
local function clip(s,name)
 if s.clip~=name then s.clip=name;s.model:SetAttribute('Clip',name);s.model:SetAttribute('ClipSince',now()) end
end
local function groundParams()
 local ex={Service.folder}
 for _,pl in Players:GetPlayers() do if pl.Character then table.insert(ex,pl.Character) end end
 return rayParams(ex)
end
local function ground(pos,params)
 local hit=workspace:Raycast(pos+Vector3.new(0,3,0),Vector3.new(0,-9,0),params)
 if hit and hit.Normal.Y>.7 and hit.Material~=Enum.Material.Water then return hit end
end
--[[ НАШЕ: ⚠️ ОВЦА ПРИВАРЕНА К ДЕТАЛИ ПОД НОГАМИ, А НЕ ПЕРЕСТАВЛЯЕТСЯ КАЖДЫЙ КАДР.
     Раньше корень был заякорен, и сервер на каждом Heartbeat ставил его в
     base.CFrame*baseRel. Позиция заякоренной детали доходит до клиента пакетами,
     а плот клиент двигает своей физикой с интерполяцией — два разных «времени»,
     и на плывущем плоту овцу трясло.
     Теперь корень держит Weld к опоре (C0 = поза относительно опоры): клиент
     видит овцу частью сборки плота и рисует их вместе, без рассинхрона. Ходьба
     меняет только C0. ⚠️ root.CFrame приваренной овцы НЕ ПИСАТЬ и PivotTo не
     звать — сдвинется весь плот; сначала unweld. Позу читать через pose(s). ]]
local function pose(s)
 if s.base and s.base.Parent and s.baseRel then return s.base.CFrame*s.baseRel end
 return s.root.CFrame
end
local function unweld(s)
 if s.baseWeld then s.baseWeld:Destroy();s.baseWeld=nil end
end
local function anchorTo(s,hit)
 local cf=pose(s)
 s.base=hit and hit.Instance or nil
 s.baseRel=s.base and s.base.CFrame:ToObjectSpace(cf) or nil
end
local function follow(s)
 if s.carrier then return end
 if not (s.base and s.base.Parent and s.baseRel) then
  if s.baseWeld then unweld(s);s.root.Anchored=true end
  return
 end
 local w=s.baseWeld
 if not w or not w.Parent or w.Part0~=s.base then
  unweld(s)
  if s.root.Anchored then s.root.CFrame=s.base.CFrame*s.baseRel end
  w=Instance.new('Weld');w.Name='NetSheepBase';w.Part0=s.base;w.Part1=s.root;w.C0=s.baseRel;w.Parent=s.root
  s.baseWeld=w;s.root.Anchored=false
 elseif w.C0~=s.baseRel then w.C0=s.baseRel end
end
local function homePos(s)
 if s.homeBase and s.homeBase.Parent and s.homeRel then return (s.homeBase.CFrame*s.homeRel).Position end
 return s.root.Position
end
-- замер под ногами: высота корня над землёй, опора, «дом» для поводка
function Service.measure(s)
 local hit=ground(s.root.Position,groundParams())
 s.foot=hit and math.clamp(s.root.Position.Y-hit.Position.Y,0,3) or 0
 anchorTo(s,hit)
 s.homeBase=s.base;s.homeRel=s.baseRel
end
local function pickTarget(s,params,awayDir,far)
 local pos=pose(s).Position;local home=homePos(s)
 for _=1,8 do
  local dir
  if awayDir then dir=(CFrame.Angles(0,(math.random()-.5)*1.2,0):VectorToWorldSpace(awayDir)).Unit
  else local a=math.random()*math.pi*2;dir=Vector3.new(math.cos(a),0,math.sin(a)) end
  local target=pos+dir*(far or (4+math.random()*5))
  local flatHome=Vector3.new(target.X-home.X,0,target.Z-home.Z)
  if flatHome.Magnitude>AI.Leash and not awayDir then target=pos+Vector3.new(home.X-pos.X,0,home.Z-pos.Z).Unit*4 end
  local g=ground(target,params)
  if g and math.abs(g.Position.Y-(pos.Y-s.foot))<2.5 then
   local wall=workspace:Raycast(pos+Vector3.new(0,1.5,0),Vector3.new(target.X-pos.X,0,target.Z-pos.Z),params)
   if not (wall and wall.Instance.CanCollide) then return target end
  end
 end
end
--[[ НАШЕ: ⚠️ ЦЕЛЬ — ОТНОСИТЕЛЬНО ОПОРЫ ПОД НЕЙ, А НЕ МИРА. Плот плывёт
     8 студ/с: мировая точка прогулки за секунду-две оставалась позади, и овца
     на ходу пятилась к корме (та же ошибка была у фермера на ферме). ]]
local function setTarget(s,pos,params)
 local g=ground(pos,params)
 s.target=pos
 if g then s.tgtBase=g.Instance;s.tgtRel=g.Instance.CFrame:PointToObjectSpace(pos) else s.tgtBase=nil end
end
local function targetPos(s)
 if s.tgtBase and s.tgtBase.Parent and s.tgtRel then return s.tgtBase.CFrame*s.tgtRel end
 return s.target
end
-- шаг к цели; true — дошла или упёрлась
local function moveStep(s,dt,speed,params)
 local cur=pose(s);local pos=cur.Position
 local tp=targetPos(s)
 local to=Vector3.new(tp.X-pos.X,0,tp.Z-pos.Z)
 if to.Magnitude<.6 then return true end
 local want=to.Unit
 local look=Vector3.new(cur.LookVector.X,0,cur.LookVector.Z)
 look=look.Magnitude>.01 and look.Unit or want
 local ang=math.acos(math.clamp(look:Dot(want),-1,1))
 local dir=look
 if ang>.001 then local st=math.min(ang,AI.TurnRate*dt);dir=CFrame.Angles(0,look:Cross(want).Y>=0 and st or -st,0):VectorToWorldSpace(look).Unit end
 local adv=math.min(speed*dt,to.Magnitude)
 if ang>math.rad(70) then adv=adv*.25 end
 local nextPos=pos+dir*adv
 local g=ground(nextPos,params)
 local wall=workspace:Raycast(pos+Vector3.new(0,1.2,0),dir*(adv+1.4),params)
 if not g or math.abs(g.Position.Y-(pos.Y-s.foot))>AI.StepUp or (wall and wall.Instance.CanCollide) then
  clip(s,'Idle');return true
 end
 clip(s,adv>speed*dt*.4 and (speed>AI.WalkSpeed and 'Trot' or 'Walk') or 'Idle')
 local p=Vector3.new(nextPos.X,g.Position.Y+s.foot,nextPos.Z)
 local cf=CFrame.lookAt(p,p+dir)
 -- поза — относительно новой опоры; сварку подтянет follow (НАШЕ, см. pose)
 s.base=g.Instance;s.baseRel=g.Instance.CFrame:ToObjectSpace(cf)
 if not s.baseWeld then s.root.CFrame=cf end
 return false
end
local function idle(s,t) s.mode='idle';s.timer=t or (1.5+math.random()*2.5);clip(s,'Idle') end
function Service.ai(s,dt)
 local params=groundParams()
 s.timer=(s.timer or 0)-dt
 s.scareCd=math.max(0,(s.scareCd or 0)-dt)
 local pos=pose(s).Position
 -- испуг: игрок вплотную — вздрогнула и отбежала рысью
 if s.scareCd<=0 and s.mode~='startled' and s.mode~='flee' then
  local best,away=AI.ScareRadius,nil
  for _,pl in Players:GetPlayers() do
   local hrp=pl.Character and pl.Character:FindFirstChild('HumanoidRootPart')
   if hrp then
    local d=Vector3.new(pos.X-hrp.Position.X,0,pos.Z-hrp.Position.Z)
    if d.Magnitude<best and d.Magnitude>.05 then best,away=d.Magnitude,d.Unit end
   end
  end
  if away then
   s.scareCd=7;s.away=away
   if s.mode=='lie' or s.mode=='rest' then s.mode='standup';s.timer=1.4;clip(s,'StandUp');s.fleeAfter=true
   else s.mode='startled';s.timer=.8;clip(s,'Startled') end
   return
  end
 end
 local m=s.mode
 s.waterCheck=(s.waterCheck or 0)-dt
 if m=='idle' then
  clip(s,'Idle')
  --[[ НАШЕ: ЖАЖДА. Ферма на плоту (RaftFarmService) говорит, куда встать у
       корыта, если овце пора пить и в корыте есть вода. ]]
  if s.waterCheck<=0 and typeof(_G.SheepWantsWater)=='function' then
   s.waterCheck=2
   local ok,spot,look=pcall(_G.SheepWantsWater,s.model)
   if ok and spot then
    setTarget(s,spot,params)
    s.drinkLookRel=s.tgtBase and s.tgtBase.CFrame:PointToObjectSpace(look) or nil;s.drinkLook=look
    s.mode='toDrink';return
   end
  end
  if s.timer>0 then return end
  local r=math.random()
  if r<.4 then
   local t=pickTarget(s,params)
   if t then setTarget(s,t,params);s.mode='wander' else idle(s,1) end
  elseif r<.7 then s.mode='graze';s.timer=4+math.random()*5;clip(s,'Graze')
  elseif r<.8 then s.mode='look';s.timer=2;clip(s,'Look')
  elseif r<.88 then s.mode='bleat';s.timer=1.3;clip(s,'Bleat')
  elseif r<.95 then s.mode='lie';s.timer=1.4;clip(s,'LieDown')
  else idle(s) end
 elseif m=='graze' or m=='look' or m=='bleat' then
  if s.timer<=0 then idle(s,1+math.random()*2) end
 elseif m=='lie' then
  if s.timer<=0 then s.mode='rest';s.timer=10+math.random()*12;clip(s,'Rest') end
 elseif m=='rest' then
  if s.timer<=0 then s.mode='standup';s.timer=1.4;clip(s,'StandUp') end
 elseif m=='standup' then
  if s.timer<=0 then
   if s.fleeAfter then s.fleeAfter=nil;s.mode='startled';s.timer=.4;clip(s,'Startled') else idle(s,1) end
  end
 elseif m=='startled' then
  if s.timer<=0 then
   local t=s.away and pickTarget(s,params,s.away,7)
   if t then setTarget(s,t,params);s.mode='flee' else idle(s,1) end
  end
 elseif m=='toDrink' then
  if moveStep(s,dt,AI.WalkSpeed,params) then
   local tp=targetPos(s);local p=pose(s).Position
   if Vector3.new(tp.X-p.X,0,tp.Z-p.Z).Magnitude<2.4 then
    -- встала у борта: мордой к воде
    local look=(s.tgtBase and s.drinkLookRel and s.tgtBase.CFrame*s.drinkLookRel) or s.drinkLook
    local d=Vector3.new(look.X-p.X,0,look.Z-p.Z)
    if d.Magnitude>.05 then
     local cf=CFrame.lookAt(p,p+d.Unit)
     if s.base and s.base.Parent then s.baseRel=s.base.CFrame:ToObjectSpace(cf) elseif not s.baseWeld then s.root.CFrame=cf end
    end
    s.mode='drink';s.timer=3.5;clip(s,'Drink')
   else idle(s,1) end
  end
 elseif m=='drink' then
  clip(s,'Drink')
  if s.timer<=0 then
   if typeof(_G.SheepDrank)=='function' then pcall(_G.SheepDrank,s.model) end
   s.waterCheck=4;idle(s,1+math.random())
  end
 elseif m=='wander' or m=='flee' then
  if moveStep(s,dt,m=='flee' and AI.TrotSpeed or AI.WalkSpeed,params) then idle(s,1+math.random()*2) end
 else idle(s) end
end
function Service.setState(s,state)
 s.state=state;s.since=now()
 if state=='Free' then s.clip=nil;idle(s,1+math.random()*2) end
 s.model:SetAttribute('NetState',state);s.model:SetAttribute('NetStateSince',s.since)
 s.prompt.Enabled=state=='Captured'
 s.hitbox.CanQuery=state=='Free' or state=='Released'
end
function Service.spawn(position)
 local m=Pack.Assets.Sheep:Clone();m.Name='Sheep'
 local root=m:FindFirstChild('HumanoidRootPart',true);assert(root,'Sheep rig needs root');m.PrimaryPart=root
 for _,v in m:GetDescendants() do
  if v:IsA('BasePart') then v.Anchored=v==root;v.CanCollide=false;v.CanTouch=false;v.CanQuery=false;v.Massless=true end
 end
 m.Parent=Service.folder;m:PivotTo(CFrame.new(position))
 local hit=Instance.new('Part');hit.Name='CaptureHitbox';hit.Size=Vector3.new(2.5,3.25,3.9);hit.Transparency=1;hit.Anchored=false;hit.Massless=true;hit.CanCollide=false;hit.CanTouch=false;hit.CFrame=root.CFrame*CFrame.new(0,1.6,-.1);hit.Parent=m
 local hitWeld=Instance.new('WeldConstraint');hitWeld.Part0=root;hitWeld.Part1=hit;hitWeld.Parent=hit
 local attachment=Instance.new('Attachment');attachment.Position=Vector3.new(0,1,0);attachment.Parent=root
 local prompt=Instance.new('ProximityPrompt');prompt.Name='PickupSheep';prompt.ActionText='Поднять овцу';prompt.ObjectText='Овца в сети';prompt.KeyboardKeyCode=Enum.KeyCode.E;prompt.GamepadKeyCode=Enum.KeyCode.ButtonX;prompt.HoldDuration=.35;prompt.MaxActivationDistance=Config.PickupRange;prompt.RequiresLineOfSight=false;prompt.Parent=attachment
 local s={model=m,root=root,hitbox=hit,prompt=prompt,lastSafe=CFrame.new(position)}
 Service.sheep[m]=s;Service.measure(s);Service.setState(s,'Free')   -- НАШЕ: measure — опора и «дом»
 s.promptConnection=prompt.Triggered:Connect(function(player)Service.pickup(player,m)end)
 return s
end
function Service.capture(s)
 if s.state~='Free' then return false end
 Service.setState(s,'Catching');s.lastSafe=s.root.CFrame;s.target=nil
 Service.folder:SetAttribute('CaptureCount',(Service.folder:GetAttribute('CaptureCount') or 0)+1)
 return true
end
function Service.pickup(player,model)
 local s=Service.sheep[model];local c,h,root=actor(player)
 if not s or not c or s.state~='Captured' or Service.carrying[player] then return false end
 if (root.Position-s.root.Position).Magnitude>Config.PickupRange then return false end
 local result=workspace:Raycast(root.Position,s.root.Position+Vector3.yAxis-root.Position,rayParams({c,s.model}))
 if result then return false end
 Service.carrying[player]=s;s.carrier=player;s.oldSpeed=h.WalkSpeed;s.humanoid=h
 h:UnequipTools();h.WalkSpeed=math.min(h.WalkSpeed,Config.CarrySpeed)
 -- One physical assembly follows the character's locally predicted movement.
 -- Never move a carried sheep using replicated server Heartbeat teleports.
 unweld(s);s.base=nil;s.baseRel=nil   -- НАШЕ: снять с палубы, иначе PivotTo потащит плот
 s.model:PivotTo(root.CFrame*Config.CarryOffset)
 s.root.Anchored=false
 local joint=Instance.new('Weld');joint.Name='NetSheepCarry';joint.Part0=root; joint.Part1=s.root;joint.C0=Config.CarryOffset;joint.Parent=root;s.carryJoint=joint
 player:SetAttribute('NetCarrying',true);c:SetAttribute('NetCarrying',true)
 Service.setState(s,'Carried');s.model:SetAttribute('CarrierUserId',player.UserId)
 return true
end
--[[ НАШЕ: ПОИСК МЕСТА ДЛЯ ОВЦЫ — МЯГЧЕ АВТОРСКОГО. На плоту выходило
     «Здесь тесно» почти везде:
       • луч «пола» стартовал на 4 studs выше головы и упирался в нависающую
         скалу / навес, а не в палубу;
       • коробка свободного места начиналась у самого пола и цепляла выступы
         брёвен настила — любой бугор палубы считался стеной;
       • было всего 6 направлений на одной дистанции.
     Теперь пол ищем с уровня корня игрока вниз, коробка поднята над палубой
     на 0.9 studs, направлений 8 × 3 дистанции. Почему отказ — в Output. ]]
function Service.findRelease(s,character,root)
 local p=rayParams({character,s.model})
 local overlap=OverlapParams.new();overlap.FilterType=Enum.RaycastFilterType.Exclude;overlap.FilterDescendantsInstances={character,s.model}
 local why="нет пола"
 for _,dist in {4.2,3.2,5.5} do
  for _,angle in {0,math.pi/4,-math.pi/4,math.pi/2,-math.pi/2,math.pi*.75,-math.pi*.75,math.pi} do
   local forward=(root.CFrame*CFrame.Angles(0,angle,0)).LookVector
   forward=Vector3.new(forward.X,0,forward.Z).Unit
   local wall=workspace:Raycast(root.Position,forward*dist,p)
   if wall and wall.Instance.CanCollide then why="стена: "..wall.Instance:GetFullName()
   else
    local candidate=root.Position+forward*dist
    local floor=workspace:Raycast(candidate+Vector3.new(0,.5,0),Vector3.new(0,-7,0),p)
    if not floor then why="нет пола"
    elseif floor.Normal.Y<=.7 then why="пол наклонный"
    elseif floor.Material==Enum.Material.Water then why="вода"
    else
     local cf=CFrame.new(floor.Position+Vector3.new(0,.04,0))*CFrame.lookAt(Vector3.zero,forward).Rotation
     local blocker=nil
     for _,part in workspace:GetPartBoundsInBox(cf*CFrame.new(0,2.1,-.1),Vector3.new(2.6,2.4,3.9),overlap) do
      if part.CanCollide then blocker=part;break end
     end
     if not blocker then return cf end
     why="занято: "..blocker:GetFullName()
    end
   end
  end
 end
 warn("[Сеткомёт] некуда поставить овцу — последняя причина: "..why)
end
function Service.release(player,forced)
 local s=Service.carrying[player];if not s then return false end
 local c,h,root=actor(player)
 local cf=root and Service.findRelease(s,c,root)
 if not cf and not forced then Service.remote:FireClient(player,'Notice','Здесь тесно. Отойди на свободное место.');return false end
 cf=cf or s.lastSafe
 Service.carrying[player]=nil;s.carrier=nil
 player:SetAttribute('NetCarrying',false)
 if player.Character then player.Character:SetAttribute('NetCarrying',false) end
 if s.humanoid and s.humanoid.Parent and s.humanoid.WalkSpeed==math.min(s.oldSpeed,Config.CarrySpeed) then s.humanoid.WalkSpeed=s.oldSpeed end
 s.model:SetAttribute('CarrierUserId',nil)
 if s.carryJoint then s.carryJoint:Destroy();s.carryJoint=nil end
 s.root.Anchored=true
 s.root.AssemblyLinearVelocity=Vector3.zero;s.root.AssemblyAngularVelocity=Vector3.zero
 s.model:PivotTo(cf);s.lastSafe=cf;Service.measure(s);Service.setState(s,'Released')   -- НАШЕ: measure — новое место = новый дом
 Service.folder:SetAttribute('ReleaseCount',(Service.folder:GetAttribute('ReleaseCount') or 0)+1)
 return true
end
function Service.fire(player,origin,target,sequence)
 if not finite(origin) or not finite(target) then return false end
 local c,h,root=actor(player);if not c or Service.carrying[player] then return false end
 local tool=c:FindFirstChild(Config.ToolName)
 if not tool or not tool:IsA('Tool') then return false end
 local muzzle=tool:FindFirstChild('Muzzle',true)
 if not muzzle or not muzzle:IsA('Attachment') then return false end
 if (origin-root.Position).Magnitude>Config.ThrowOriginLimit then return false end
 local params=rayParams({c})
 -- Client supplies only a nearby muzzle and aim point, never a target sheep or hit.
 if workspace:Raycast(root.Position,origin-root.Position,params) then return false end
 local delta=target-origin
 if delta.Magnitude<.1 or delta.Magnitude>100000 then return false end
 if now()-(Service.lastShot[player] or -1e6)<Config.Cooldown then return false end
 Service.lastShot[player]=now();Service.nextId+=1
 local shot={id=Service.nextId,owner=player,origin=origin,pos=origin,dir=delta.Unit,distance=0,params=params,started=now()}
 Service.shots[shot.id]=shot
 Service.remote:FireAllClients('Shot',shot.id,origin,shot.dir,shot.started,player.UserId,sequence)
 Service.folder:SetAttribute('ShotCount',(Service.folder:GetAttribute('ShotCount') or 0)+1)
 return true,shot.id
end
local function finish(shot,position,hit)
 Service.shots[shot.id]=nil
 local captured=false
 if hit then
  local ancestor=hit:FindFirstAncestorOfClass('Model');local s=ancestor and Service.sheep[ancestor]
  if s then captured=Service.capture(s) end
 end
 Service.remote:FireAllClients('Impact',shot.id,position,captured)
end
function Service.step(dt)
 for id,shot in Service.shots do
  if not actor(shot.owner) or not shot.owner.Parent then finish(shot,shot.pos,nil);continue end
  local length=math.min(Config.Speed*dt,Config.Range-shot.distance)
  local displacement=shot.dir*length
  -- Spherecast prevents tunneling; overlap handles a sheep already touching the muzzle.
  local overlap=OverlapParams.new();overlap.FilterType=Enum.RaycastFilterType.Exclude;overlap.FilterDescendantsInstances={shot.owner.Character}
  local touching=nil
  for _,part in workspace:GetPartBoundsInRadius(shot.pos,Config.Radius,overlap) do
   if part.Name=='CaptureHitbox' and part.CanQuery then touching=part;break end
  end
  local hit=not touching and workspace:Spherecast(shot.pos,Config.Radius,displacement,shot.params)
  if touching then finish(shot,shot.pos,touching)
  elseif hit then finish(shot,hit.Position,hit.Instance)
  else
   shot.pos+=displacement;shot.distance+=length
   if shot.distance>=Config.Range or now()-shot.started>4 then finish(shot,shot.pos,nil) end
  end
 end
 for model,s in Service.sheep do
  if not model.Parent then
   if s.carrier then Service.release(s.carrier,true) end
   if s.promptConnection then s.promptConnection:Disconnect() end
   Service.sheep[model]=nil;continue
  end
  if not s.carrier then follow(s) end   -- НАШЕ: едет вместе с плотом
  if s.state=='Free' and not s.carrier then Service.ai(s,dt) end   -- НАШЕ: жизнь как на ферме
  if s.state=='Catching' and now()-s.since>=Config.CatchDuration then Service.setState(s,'Captured') end
  if s.state=='Released' and now()-s.since>=Config.ReleaseDuration then Service.setState(s,'Free') end
  if s.carrier then
   local c,h,root=actor(s.carrier)
   if not root then Service.release(s.carrier,true)
   else
    if c:FindFirstChildOfClass('Tool') then h:UnequipTools() end
   end
  end
 end
end
function Service.start()
 if Service.started then return Service end;Service.started=true
 Service.remote=Pack:WaitForChild('Remote')
 local folder=Instance.new('Folder');folder.Name='NetCaptureSheep';folder.Parent=workspace;Service.folder=folder
 if Config.SpawnPosition then Service.spawn(Config.SpawnPosition) end   -- НАШЕ: без автоспавна
 Service.connections[#Service.connections+1]=RunService.Heartbeat:Connect(Service.step)
 Service.connections[#Service.connections+1]=Service.remote.OnServerEvent:Connect(function(player,action,a,b,sequence)
  if action=='Fire' then
   if sequence~=nil and (type(sequence)~='number' or sequence~=sequence or sequence<1 or sequence>1e9) then return end
   local ok=Service.fire(player,a,b,sequence)
   if not ok and sequence then Service.remote:FireClient(player,'Rejected',sequence) end
  elseif action=='Aim' and finite(a) and a.Magnitude>.5 and a.Magnitude<1.5 and now()-(Service.lastAim[player] or 0)>.09 then
   local c=actor(player)
   if c and c:FindFirstChild(Config.ToolName) then Service.lastAim[player]=now();c:SetAttribute('NetAim',a.Unit) end
  elseif action=='Release' then Service.release(player,false)
  -- НАШЕ: подъём тапом/кликом по овце (телефон). Все проверки — в Service.pickup
  elseif action=='Pickup' and typeof(a)=='Instance' then Service.pickup(player,a) end
 end)
 Service.connections[#Service.connections+1]=Players.PlayerRemoving:Connect(function(p)Service.release(p,true);Service.lastShot[p]=nil;Service.lastAim[p]=nil end)
 local function bind(player)
  player.CharacterRemoving:Connect(function()Service.release(player,true)end)
 end
 for _,p in Players:GetPlayers() do bind(p) end
 Service.connections[#Service.connections+1]=Players.PlayerAdded:Connect(bind)
 print('NET_CAPTURE_SERVER_READY')
 return Service
end
return Service
