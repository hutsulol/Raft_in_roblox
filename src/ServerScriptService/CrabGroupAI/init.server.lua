-- One server controller for all tagged rigs. No client remote can request damage.
local Players = game:GetService('Players')
local Tags = game:GetService('CollectionService')
local Paths = game:GetService('PathfindingService')
local Run = game:GetService('RunService')
local Combat = require(script.CrabCombat)
local Loot = require(script.CrabLoot)
local Death = require(script.CrabDeath)
local Life = require(script.CrabLife)
local actors, ordered = {}, {}
local slots = setmetatable({}, {__mode='k'})
local defaults = {CrabHealth=60, CrabDamage=12, CrabDetectRadius=35,
 CrabAlertRadius=30, CrabLeashRadius=65, CrabSpeed=9, CrabAttackCooldown=2.1}
local serial, pendingPaths = 0, 0
local function flat(v) return Vector3.new(v.X,0,v.Z) end
local function animate(a, name, restart)
 if restart or a.model:GetAttribute('CrabAnimation') ~= name then
  a.model:SetAttribute('CrabAnimationT',workspace:GetServerTimeNow())
  a.model:SetAttribute('CrabAnimation',name)
 end
end
local function state(a, value) a.model:SetAttribute('CrabState',value) end
local function attr(a,n) return a.model:GetAttribute(n) or defaults[n] end
local function character(player)
 local c=player and player.Character
 local h=c and c:FindFirstChildOfClass('Humanoid')
 local r=c and c:FindFirstChild('HumanoidRootPart')
 if h and r and h.Health>0 then return c,h,r end
end
local function params()
 local p=RaycastParams.new();p.FilterType=Enum.RaycastFilterType.Exclude
 local excluded={}
 for _,a in ordered do table.insert(excluded,a.model) end
 for _,pl in Players:GetPlayers() do if pl.Character then table.insert(excluded,pl.Character) end end
 p.FilterDescendantsInstances=excluded;p.RespectCanCollide=true
 return p
end
local rays
local function visible(a,pos)
 local from=a.root.Position
 return workspace:Raycast(from,pos-from,rays)==nil
end
local function add(model)
 if actors[model] or not model:IsA('Model') or not model:IsDescendantOf(workspace) then return end
 local root=model:FindFirstChild('HumanoidRootPart')
 if not root or not model:GetAttribute('CrabRig') then return end
 serial+=1
 for n,v in defaults do if model:GetAttribute(n)==nil then model:SetAttribute(n,v) end end
 local a={model=model,root=root,home=root.Position,scale=model:GetAttribute('CrabRigScale') or 1,
  id=serial,nextAttack=0,nextPath=0,lastSeen=0,previousHealth=attr({model=model},'CrabHealth'),
  idleUntil=0,waypoint=1,token=0}
 a.habitat=Life.habitat(model)
 root.Anchored=true;actors[model]=a;table.insert(ordered,a);state(a,'Idle')
end
local function assign(a,player,now)
 Life.cancel(a)
 if a.target~=player then a.nextAttack=now+.25 end
 a.target=player;a.lastSeen=now;a.aggroOrigin=a.root.Position;a.path=nil;a.token+=1
 a.model:SetAttribute('CrabTargetUserId',player.UserId)
end
local function requestPath(a,goal,now)
 if a.computing or now<a.nextPath or pendingPaths>=3 then return end
 a.nextPath=now+.35;a.computing=true;pendingPaths+=1
 local token=a.token;local start=a.root.Position
 task.spawn(function()
  local path=Paths:CreatePath({AgentRadius=math.max(1,3*a.scale),AgentHeight=math.max(2,3*a.scale),
   AgentCanJump=false,AgentCanClimb=false,WaypointSpacing=3,Costs={Water=math.huge}})
  local ok=pcall(function()path:ComputeAsync(start,goal)end)
  if actors[a.model]==a and a.token==token and not a.dead
   and a.moveGoal and flat(a.moveGoal-goal).Magnitude<3*a.scale then
   if ok and path.Status==Enum.PathStatus.Success then a.path=path:GetWaypoints();a.waypoint=2;a.pathGoal=goal
   else a.path=nil end
  end
  path:Destroy();a.computing=false;pendingPaths-=1
 end)
end
local function face(a,direction,dt)
 local d=flat(direction)
 if d.Magnitude>.01 then
  a.root.CFrame=a.root.CFrame:Lerp(CFrame.lookAt(a.root.Position,a.root.Position+d),math.min(1,dt*12))
 end
end
local function move(a,goal,now,dt)
 local delta=flat(goal-a.root.Position)
 if delta.Magnitude<0.6 then animate(a,'Idle');return true end
 a.moveGoal=goal
 -- On open ground steer to the current goal every AI tick. Use waypoints only
 -- to go around obstacles, never to finish an obsolete player position.
 local radius=2.7*a.scale
 local blocked=workspace:Blockcast(CFrame.new(a.root.Position),Vector3.new(radius*2,.7*a.scale,radius*2),delta,rays)
 if not blocked then a.path=nil
 else
  if a.pathGoal and flat(goal-a.pathGoal).Magnitude>3*a.scale then a.path=nil end
  requestPath(a,goal,now)
 end
 local point=blocked and a.path and a.path[a.waypoint]
 if point and flat(point.Position-a.root.Position).Magnitude<1 then a.waypoint+=1;point=a.path[a.waypoint] end
 local dest=point and point.Position or goal
 local direction=flat(dest-a.root.Position)
 if direction.Magnitude<.05 then return false end
 direction=direction.Unit
 -- Steer around every living crab, including neutral ones.
 local avoid=Vector3.zero
 for _,b in ordered do
  if b~=a and not b.dead then
   local offset=flat(a.root.Position-b.root.Position);local gap=2.8*(a.scale+b.scale)
   if offset.Magnitude>.01 and offset.Magnitude<gap+3*a.scale then
    avoid+=offset.Unit*math.max(0,(gap+3*a.scale-offset.Magnitude)/(3*a.scale))
   end
  end
 end
 local steering=direction+avoid*1.5
 if steering.Magnitude>.01 then direction=steering.Unit end
 local nextPos=a.root.Position+direction*math.min(attr(a,'CrabSpeed')*(a.target and 1 or .45)*dt,flat(dest-a.root.Position).Magnitude)
 for _,b in ordered do
  if b~=a and not b.dead then
   local gap=2.8*(a.scale+b.scale)
   if flat(nextPos-b.root.Position).Magnitude<gap
    and flat(nextPos-b.root.Position).Magnitude<flat(a.root.Position-b.root.Position).Magnitude then
    animate(a,'Idle');return false
   end
  end
 end
 -- Swept volume catches walls even between path recomputations.
 local obstruction=workspace:Blockcast(CFrame.new(a.root.Position),Vector3.new(radius*2,.7*a.scale,radius*2),nextPos-a.root.Position,rays)
 local y,swimming=Life.surface(a,nextPos)
 if not a.habitat then
  local ground=workspace:Raycast(nextPos+Vector3.new(0,2*a.scale,0),Vector3.new(0,-(4*a.scale+1),0),rays)
  if ground and ground.Normal.Y>.65 and ground.Material~=Enum.Material.Water then y=ground.Position.Y+1.45*a.scale end
 end
 -- НАШЕ: почему шаг не сделан — для диагностики (CrabIsland печатает)
 if obstruction then a.block='стена: '..obstruction.Instance:GetFullName() elseif not y then a.block='нет поверхности' end
 if obstruction or not y then animate(a,'Idle');a.path=nil;return false end
 if math.abs(y-a.root.Position.Y)>math.max(1.1*a.scale,2.5) then a.block=('перепад %.1f (земля+отступ %.1f, корень %.1f)'):format(y-a.root.Position.Y,y,a.root.Position.Y);animate(a,'Idle');return false end
 a.block=nil;a.steps=(a.steps or 0)+1
 a.model:SetAttribute('CrabSwimming',swimming or false)
 -- Use the same forward axis for locomotion and attacks.
 local position=Vector3.new(nextPos.X,y,nextPos.Z)
 local rotation=a.root.CFrame.Rotation:Lerp(CFrame.lookAt(Vector3.zero,direction),1-math.exp(-12*dt))
 a.root.CFrame=CFrame.new(position)*rotation
 animate(a,swimming and 'Swim' or a.target and 'Run' or 'Walk');return false
end
local function update(a,now,dt)
 local hp=attr(a,'CrabHealth')
 if hp<=0 then
  if not a.dead then
   a.dead=true;a.token+=1;a.attack=nil;a.target=nil;state(a,'Dead');Death.start(a.model)
   task.delay(1.2,function()
    if a.model:IsDescendantOf(workspace) then Loot.drop(a.model);Death.remove(a.model) end
   end)
  end
  return
 end
 if a.dead then return end
 if a.model:GetAttribute('CrabAIEnabled')==false then
  if a.target then a.token+=1 end
  a.attack=nil;a.target=nil;a.path=nil;animate(a,'Idle');state(a,'Disabled');return
 end
 if hp<a.previousHealth then
  local attacker=Players:GetPlayerByUserId(a.model:GetAttribute('CrabLastAttacker') or 0)
  if character(attacker) then assign(a,attacker,now) end
  -- Repeated sword hits must not indefinitely postpone the crab's counterattack.
  if not a.attack then a.hurtUntil=now+.2;animate(a,'Hurt',true) end
 end
 a.previousHealth=hp
 if a.hurtUntil and now<a.hurtUntil then state(a,'Hurt');return end
 local c,h,r=character(a.target)
 local origin=a.aggroOrigin or a.home
 if r and flat(r.Position-origin).Magnitude<attr(a,'CrabLeashRadius') and flat(a.root.Position-origin).Magnitude<attr(a,'CrabLeashRadius') then
  if visible(a,r.Position) then a.lastSeen=now end
  if now-a.lastSeen>5 then r=nil end
 else r=nil end
 if not r then
  if a.target then a.token+=1;a.path=nil end
  a.target=nil;a.attack=nil;a.model:SetAttribute('CrabTargetUserId',nil)
 end
 if a.attack then
  face(a,r.Position-a.root.Position,dt)
  if now>=a.attack.hitAt and not a.attack.hit then
   a.attack.hit=true
   local delta=r.Position-a.root.Position
   local facing=delta.Magnitude<.01 and 1 or a.root.CFrame.LookVector:Dot(delta.Unit)
   if Combat.canHit(hp>0,h.Health>0,flat(delta).Magnitude,math.max(3.5,4.5*a.scale),visible(a,r.Position) and math.abs(delta.Y)<6,facing) then h:TakeDamage(attr(a,'CrabDamage')) end
  end
  if now>=a.attack.ends then a.attack=nil;animate(a,'Idle') end
  return
 end
 if not r then
  Life.update(a,now,dt,ordered,move,animate,state);return
 end
 local distance=flat(r.Position-a.root.Position).Magnitude
 if distance<=math.max(3,4*a.scale) and math.abs(r.Position.Y-a.root.Position.Y)<6 and visible(a,r.Position) then
  face(a,r.Position-a.root.Position,dt);animate(a,'Threat');state(a,'Threat')
  if now>=a.nextAttack and Combat.reserve(slots,a.target,now,.9) then
   a.nextAttack=now+attr(a,'CrabAttackCooldown');a.attack={hitAt=now+.4,ends=now+.8,hit=false}
   animate(a,a.id%2==0 and 'AttackLeft' or 'AttackRight',true);state(a,'Attack')
  end
 else
  local peers={}
  for _,b in ordered do if not b.dead and b.target==a.target then table.insert(peers,b) end end
  local index=table.find(peers,a) or 1
  local angle=(index-1)*math.pi*2/math.max(1,#peers)
  local radius=math.max(2,2.6*a.scale)
  local goal=r.Position+Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius)
  state(a,'Surround');move(a,goal,now,dt)
 end
end
-- НАШЕ: диагностика для CrabIsland — состояние каждого краба
_G.CrabDebug=function()
 local out={}
 for _,a in ordered do
  table.insert(out,('%s hp=%s state=%s act=%s anim=%s шагов=%d блок=%s цель=%s'):format(a.model.Name,tostring(a.model:GetAttribute('CrabHealth')),
   tostring(a.model:GetAttribute('CrabState')),tostring(a.model:GetAttribute('CrabActivity')),tostring(a.model:GetAttribute('CrabAnimation')),
   a.steps or 0,tostring(a.block),tostring(a.target and a.target.Name)))
 end
 return out
end
Tags:GetInstanceAddedSignal('CrabNPC'):Connect(add)
for _,m in Tags:GetTagged('CrabNPC') do add(m) end
local elapsed,scan=0,0
Run.Heartbeat:Connect(function(dt)
 elapsed+=dt;scan+=dt
 if elapsed<.1 then return end
 local step=math.min(elapsed,.2);elapsed=0
 if scan>=1 then scan=0;for _,m in Tags:GetTagged('CrabNPC') do add(m) end end
 for i=#ordered,1,-1 do local a=ordered[i]
  if not a.model:IsDescendantOf(workspace) or not Tags:HasTag(a.model,'CrabNPC') or not a.root.Parent then
   actors[a.model]=nil;a.token+=1;table.remove(ordered,i)
  end
 end
 rays=params();local now=workspace:GetServerTimeNow()
 for _,a in ordered do
  update(a,now,step)
  -- Clients smooth this authoritative pose every frame; combat stays on the server.
  if not a.dead then a.model:SetAttribute('CrabMotionTarget',a.root.CFrame) end
 end
end)
