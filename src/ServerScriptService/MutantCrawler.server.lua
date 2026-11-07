local RS=game:GetService('ReplicatedStorage')
local Players=game:GetService('Players')
local Run=game:GetService('RunService')
local Debris=game:GetService('Debris')
local Pack=RS:WaitForChild('MutantCrawlerPack')
local Rig=require(Pack.CrawlerRig);local Anim=require(Pack.CrawlerAnimator);local C=require(Pack.CrawlerConfig)
local Leap=require(Pack.CrawlerLeap)
local Nav=require(Pack.CrawlerNavigation)
local Choice=require(Pack.CrawlerAttackChoice)
-- Production uses the configured attack probabilities.
local Event=Pack:WaitForChild('CrawlerEvent')
local live=Instance.new('Folder');live.Name='MutantCrawlers';live.Parent=workspace
require(Pack:WaitForChild('CrawlerMeshLoader')).prepare(Pack:WaitForChild('Template'))
local states,shots={},{};local serial=0
-- The kinematic root owns translation/yaw only; body pitch belongs to Motor6D poses.
local function upright(cf)
 local look=Vector3.new(cf.LookVector.X,0,cf.LookVector.Z)
 if look.Magnitude<.001 then look=Vector3.new(0,0,-1) end
 return CFrame.lookAt(cf.Position,cf.Position+look.Unit)
end
local function params(exclude)
 local p=RaycastParams.new();p.FilterType=Enum.RaycastFilterType.Exclude;p.FilterDescendantsInstances=exclude;return p
end
local function setClip(s,name,now)
 if s.clip==name then return end
 s.clip=name;s.since=now
 -- One atomic attribute prevents name/time races during replication.
 s.model:SetAttribute('CrawlerState',name..'|'..string.format('%.6f',now))
end
local function releaseLatch(s)
 local m=s.model
 m:SetAttribute('LatchTargetUserId',nil);m:SetAttribute('LatchOffset',nil)
 if s.frenzy and s.frenzy.phase=='scratch' then
  local rp=params({live,s.target and s.target.Parent});rp.RespectCanCollide=true
  local root=m.PrimaryPart;local ground=workspace:Raycast(root.Position+Vector3.yAxis*2,Vector3.new(0,-30,0),rp)
  local pos=ground and ground.Position+Vector3.yAxis or s.home
  root.CFrame=CFrame.new(pos)*upright(root.CFrame).Rotation
 end
end
local function fallFromLatch(s,now)
 local m=s.model;local root=m.PrimaryPart
 m:SetAttribute('LatchTargetUserId',nil);m:SetAttribute('LatchOffset',nil)
 local start=upright(root.CFrame)
 local exclude={live};for _,p in Players:GetPlayers() do if p.Character then table.insert(exclude,p.Character) end end
 local rp=params(exclude);rp.RespectCanCollide=true
 local move=-start.LookVector*.7
 if workspace:Blockcast(start,Vector3.new(1.6,.6,1.6),move,rp) then move=Vector3.zero end
 local ground=workspace:Raycast(start.Position+move+Vector3.yAxis*2,Vector3.new(0,-30,0),rp)
 local finish=ground and ground.Position+Vector3.yAxis or start.Position
 s.fall={start=start,finish=finish,born=now};s.frenzy=nil;s.attack=nil;s.leap=nil
 s.nextShot=now+.8+C.Cooldown
 setClip(s,'LatchFall',now)
end
local function die(s,now)
 if s.dead then return end
 s.dead=true
 local m=s.model
 m:SetAttribute('Dead',true);m:SetAttribute('Enemy',false);m:SetAttribute('TargetUserId',nil)
 s.attack=nil;s.hurtUntil=nil
 if s.fall or (s.frenzy and s.frenzy.phase=='scratch') then
  if not s.fall then fallFromLatch(s,now) end
 else
  releaseLatch(s);s.frenzy=nil;s.leap=nil
  setClip(s,'Death',now)
 end
 s.target=nil
 Debris:AddItem(m,C.CorpseLifetime)
end
local function spawn(marker)
 if not marker:IsA('BasePart') then return end
 local m=Pack.Template:Clone();m.Name='MutantCrawler';local motors=Rig.setup(m)
 m.ModelStreamingMode=Enum.ModelStreamingMode.Atomic
 -- Marker top is the floor reference; do not raycast through stacked island floors.
 local top=marker.Position+Vector3.yAxis*(marker.Size.Y*.5+1)
 m:PivotTo(CFrame.new(top)*upright(marker.CFrame).Rotation)
 m.Humanoid.MaxHealth=C.Health;m.Humanoid.Health=C.Health
 local s={home=m.PrimaryPart.Position,model=m,motors=motors,nextShot=0,nextLunge=0,clip='',since=0};states[m]=s
 m:SetAttribute('Enemy',true);setClip(s,'Idle',workspace:GetServerTimeNow());m:SetAttribute('CrawlerRig',true);m.Parent=live
 m.Humanoid.Died:Connect(function() die(s,workspace:GetServerTimeNow()) end)
 -- Death is driven by health because this rig disables EvaluateStateMachine.
 -- Keep the rig intact so the authored death/fall poses can finish.
 local hp=C.Health
 m.Humanoid.HealthChanged:Connect(function(v)
  if v<=0 then die(s,workspace:GetServerTimeNow());hp=v;return end
  if s.dead then return end
  if v<hp then
   local now=workspace:GetServerTimeNow()
   local mood=v/m.Humanoid.MaxHealth<=.35 and 'Fear' or (s.frenzy or s.attack) and 'Anger' or 'Pain'
   m:SetAttribute('Reaction',mood..'|'..string.format('%.6f',now))
   Event:FireAllClients('Wound',m,m.PrimaryPart.Position,mood)
  end
  if v<hp and v>0 then
   if s.fall then hp=v;return end
   if s.frenzy and s.frenzy.phase=='scratch' then
    fallFromLatch(s,workspace:GetServerTimeNow());hp=v;return
   end
   if s.leap then m.PrimaryPart.CFrame=CFrame.lookAt(s.leap.start,s.leap.start+s.leap.direction);s.leap=nil end
   releaseLatch(s);if s.frenzy and s.frenzy.plan then m.PrimaryPart.CFrame=CFrame.lookAt(s.frenzy.plan.start,s.frenzy.plan.start+s.frenzy.plan.direction) end;s.frenzy=nil;s.attack=nil;s.hurtUntil=workspace:GetServerTimeNow()+.4
   setClip(s,'Hurt',workspace:GetServerTimeNow())
  end
  hp=v
 end)
 return m
end
local function playerHit(part)
 local node=part
 while node and node~=workspace do
  if node:IsA('Model') and Players:GetPlayerFromCharacter(node) then return node:FindFirstChildOfClass('Humanoid') end
  node=node.Parent
 end
end
local function visible(s,root)
 local origin=s.model.PrimaryPart.Position+Vector3.yAxis
 local hit=workspace:Raycast(origin,root.Position-origin,params({live}))
 return not hit or hit.Instance:IsDescendantOf(root.Parent)
end
local function validTarget(root)
 local hum=root and root.Parent and root.Parent:FindFirstChildOfClass('Humanoid')
 return hum and hum.Health>0 and not root.Parent:FindFirstChildOfClass('ForceField')
end
local function nearest(s,now)
 local root=s.model.PrimaryPart
 if validTarget(s.target) and (s.target.Position-root.Position).Magnitude<C.NoticeRange and (root.Position-s.home).Magnitude<C.LeashRange then
  if visible(s,s.target) then s.lastSeen=now;s.lastKnown=s.target.Position;return s.target,(s.target.Position-root.Position).Magnitude,true end
  if now-(s.lastSeen or 0)<C.MemoryTime then return s.target,(s.target.Position-root.Position).Magnitude,false end
 end
 s.target=nil;s.lastKnown=nil;s.model:SetAttribute('TargetUserId',nil)
 if (root.Position-s.home).Magnitude>C.LeashRange then return end
 local target,dist=nil,C.NoticeRange
 for _,p in ipairs(Players:GetPlayers()) do
  local r=p.Character and p.Character:FindFirstChild('HumanoidRootPart')
  if validTarget(r) then
   local d=(r.Position-root.Position).Magnitude
   if d<dist and visible(s,r) then target=r;dist=d end
  end
 end
 if target then
  s.target=target;s.lastSeen=now;s.lastKnown=target.Position;s.reactUntil=now+C.ReactionTime
  s.model:SetAttribute('TargetUserId',Players:GetPlayerFromCharacter(target.Parent).UserId)
  setClip(s,'Surprise',now)
 else s.model:SetAttribute('TargetUserId',nil) end
 return target,dist,target~=nil
end
local function fire(s,now)
 if not validTarget(s.target) then return end
 local origin=Anim.mouth(s.model,s.motors,s.attack.clip,s.attack.windup)
 local delta=s.attack.aim-origin;if delta.Magnitude<.01 then return end
 serial+=1
 local shot={id=serial,pos=origin,velocity=delta.Unit*C.ProjectileSpeed,born=now,params=params({live})}
 shots[serial]=shot;Event:FireAllClients('Shot',serial,origin,shot.velocity,now)
 -- Bounds queries return the whole island mesh AABB, even over empty space.
 -- Use an exact spherical contact probe for real initial overlaps only.
 local overlap=OverlapParams.new();overlap.FilterType=Enum.RaycastFilterType.Exclude;overlap.FilterDescendantsInstances={live}
 local probe=Instance.new('Part');probe.Name='SalivaContactProbe'
 probe.Shape=Enum.PartType.Ball;probe.Size=Vector3.one*(C.ProjectileRadius*2)
 probe.CFrame=CFrame.new(origin);probe.Anchored=true;probe.Transparency=1
 probe.CanCollide=false;probe.CanTouch=false;probe.CanQuery=false;probe.Parent=live
 local contacts=workspace:GetPartsInPart(probe,overlap);probe:Destroy()
 for _,part in ipairs(contacts) do
  local h=playerHit(part)
  if h or part.CanCollide then
   if h and h.Health>0 then h:TakeDamage(C.Damage) end
   Event:FireAllClients('Impact',serial,origin,-delta.Unit);shots[serial]=nil;break
  end
 end
end
local function frenzyStep(s,now,step)
 local f=s.frenzy;local m=s.model;local root=m.PrimaryPart
 if not validTarget(s.target) or (root.Position-s.home).Magnitude>C.LeashRange then releaseLatch(s);s.frenzy=nil;setClip(s,'Idle',now);return end
 local delta=s.target.Position-root.Position;local flat=Vector3.new(delta.X,0,delta.Z)
 local distance=flat.Magnitude
 if f.phase=='pounce' then
  local elapsed=now-s.since
  if not Leap.step(root,f.plan,elapsed,f.rp) then s.frenzy=nil;setClip(s,'Idle',now);return end
  if elapsed>=.35 and distance<=3.6 and math.abs(delta.Y)<4 and visible(s,s.target) then
   local away=Vector3.new(root.Position.X-s.target.Position.X,0,root.Position.Z-s.target.Position.Z)
   if away.Magnitude<.01 then away=-s.target.CFrame.LookVector end
   local pos=s.target.Position+away.Unit*2.35-Vector3.yAxis*1.8
   local at=CFrame.lookAt(pos,Vector3.new(s.target.Position.X,pos.Y,s.target.Position.Z))
   f.phase='scratch';f.hit=1;f.offset=upright(s.target.CFrame):ToObjectSpace(at);f.lastTarget=s.target.Position
   root.CFrame=at;m:SetAttribute('LatchOffset',f.offset)
   m:SetAttribute('LatchTargetUserId',Players:GetPlayerFromCharacter(s.target.Parent).UserId)
   setClip(s,'Scratch',now)
  elseif elapsed>=f.plan.land then
   s.frenzy=nil;s.nextShot=now+C.Cooldown;setClip(s,'Idle',now)
  end
 elseif f.phase=='rush' then
  if distance<=18 then
   local exclude={live,workspace:FindFirstChild('CrawlerSpawns')}
   for _,player in Players:GetPlayers() do if player.Character then table.insert(exclude,player.Character) end end
   local rp=params(exclude);rp.RespectCanCollide=true
   local plan=Leap.plan(root,s.target.Position,rp,'ScratchPounce')
   if plan then f.phase='pounce';f.plan=plan;f.rp=rp;setClip(s,'ScratchPounce',now)
   else s.frenzy=nil;setClip(s,'Idle',now) end
  elseif now-f.started>C.FrenzyTimeout or not visible(s,s.target) then s.frenzy=nil;setClip(s,'Idle',now)
  elseif distance>.001 then
   local dir=flat.Unit;local move=dir*math.min(C.FrenzySpeed*step,math.max(0,distance-3.5))
   local exclude={live,workspace:FindFirstChild('CrawlerSpawns')}
   for _,player in Players:GetPlayers() do if player.Character then table.insert(exclude,player.Character) end end
   local rp=params(exclude);rp.RespectCanCollide=true
   local wall=workspace:Blockcast(root.CFrame,Vector3.new(3.3,1.1,3.5),move,rp)
   local ground=workspace:Raycast(root.Position+move+Vector3.yAxis,Vector3.new(0,-4,0),rp)
   if not wall and ground and ground.Normal.Y>.7 and ground.Material~=Enum.Material.Water and math.abs(ground.Position.Y-root.Position.Y+1)<.5 then
    local pos=Vector3.new(root.Position.X+move.X,ground.Position.Y+1,root.Position.Z+move.Z)
    root.CFrame=CFrame.lookAt(pos,pos+dir)
   else s.frenzy=nil;setClip(s,'Idle',now) end
  end
 else
  local at=upright(s.target.CFrame)*f.offset
  if (s.target.Position-f.lastTarget).Magnitude>12 or not visible(s,s.target) then releaseLatch(s);s.frenzy=nil;setClip(s,'Idle',now);return end
  local exclude={live}
  for _,player in Players:GetPlayers() do if player.Character then table.insert(exclude,player.Character) end end
  local rp=params(exclude);rp.RespectCanCollide=true
  local motion=at.Position-root.Position
  if motion.Magnitude>.001 and workspace:Blockcast(root.CFrame,Vector3.new(1.6,.6,1.6),motion,rp) then releaseLatch(s);s.frenzy=nil;setClip(s,'Idle',now);return end
  root.CFrame=at;f.lastTarget=s.target.Position
  delta=s.target.Position-root.Position;flat=Vector3.new(delta.X,0,delta.Z);distance=flat.Magnitude
  local elapsed=now-s.since;local times={}
  for lap=0,2 do for _,hit in ipairs({.22,.48,.74}) do table.insert(times,lap+hit/1.1) end end
  while f.hit<=#times and elapsed>=times[f.hit] do
   if distance<=C.ScratchRange and math.abs(delta.Y)<4 and (distance<.01 or root.CFrame.LookVector:Dot(flat.Unit)>.2) and visible(s,s.target) then
    s.target.Parent:FindFirstChildOfClass('Humanoid'):TakeDamage(C.ScratchDamage)
    Event:FireAllClients('Flesh',m,s.target.Position)
    m:SetAttribute('ScratchHits',(m:GetAttribute('ScratchHits') or 0)+1)
   end
   f.hit+=1
  end
  if elapsed>=Anim.length('Scratch') then releaseLatch(s);s.frenzy=nil;s.nextShot=now+C.Cooldown;setClip(s,'Idle',now) end
 end
end
local accumulator=0
Run.Heartbeat:Connect(function(dt)
 local now=workspace:GetServerTimeNow()
 for id,p in pairs(shots) do
  local delta=p.velocity*dt;local hit=workspace:Spherecast(p.pos,C.ProjectileRadius,delta,p.params)
  if hit then
   local h=playerHit(hit.Instance);if h and h.Health>0 then h:TakeDamage(C.Damage) end
   Event:FireAllClients('Impact',id,hit.Position,hit.Normal);shots[id]=nil
  elseif now-p.born>C.ProjectileLifetime then Event:FireAllClients('Remove',id);shots[id]=nil
  else p.pos+=delta end
 end
 accumulator+=dt;if accumulator<1/30 then return end
 local step=math.min(accumulator,.10);accumulator=0
 for m,s in pairs(states) do
  if not m.Parent then states[m]=nil;continue end
  if m.Humanoid.Health<=0 then die(s,now) end
  if s.fall then
   local f=s.fall;local elapsed=now-f.born;local u=math.clamp(elapsed/.43,0,1)
   m.PrimaryPart.CFrame=CFrame.new(f.start.Position:Lerp(f.finish,u*u))*f.start.Rotation
   if elapsed>=Anim.length('LatchFall') then
    s.fall=nil;setClip(s,m.Humanoid.Health<=0 and 'Death' or 'Idle',now)
   end
   continue
  end
  if m.Humanoid.Health<=0 then continue end
  if s.hurtUntil and now<s.hurtUntil then continue end
  if s.frenzy then frenzyStep(s,now,step);continue end
  if s.leap then
   local elapsed=now-s.since
   if not Leap.step(m.PrimaryPart,s.leap,elapsed,s.leapParams) or elapsed>=Anim.length('Lunge') then s.leap=nil;setClip(s,'Idle',now) end
   continue
  end
  if s.attack then
   if not s.attack.fired and now-s.since>=s.attack.windup then s.attack.fired=true;fire(s,now) end
   if now-s.since>=s.attack.duration then releaseLatch(s);if s.frenzy and s.frenzy.plan then m.PrimaryPart.CFrame=CFrame.lookAt(s.frenzy.plan.start,s.frenzy.plan.start+s.frenzy.plan.direction) end;s.frenzy=nil;s.attack=nil;setClip(s,'Idle',now) end
   continue
  end
  local target,d,seen=nearest(s,now)
  if target and s.reactUntil and now<s.reactUntil then continue end
  local goal=target and s.lastKnown or s.home
  if not target and (m.PrimaryPart.Position-s.home).Magnitude<2 then setClip(s,'Idle',now);continue end
  local root=m.PrimaryPart;root.CFrame=upright(root.CFrame)
  local flat=Vector3.new(goal.X-root.Position.X,0,goal.Z-root.Position.Z)
  if flat.Magnitude<.01 then setClip(s,'Idle',now);continue end
  local direction=flat.Unit
  local look=root.CFrame.LookVector
  local angle=math.atan2(look:Cross(direction).Y,look:Dot(direction))
  local turn=math.clamp(angle,-C.TurnSpeed*step,C.TurnSpeed*step)
  root.CFrame=root.CFrame*CFrame.Angles(0,turn,0)
  m:SetAttribute('TurnLean',math.clamp(angle,-1,1))
  if math.abs(angle)>math.rad(40) or (s.turnUntil and now<s.turnUntil) then
   if not s.turnUntil or now>=s.turnUntil then s.turnUntil=now+.6;s.turnName=angle>0 and 'TurnLeft' or 'TurnRight' end
   setClip(s,s.turnName,now);continue
  end
  local origin=Anim.mouth(m,s.motors,'Idle',now-s.since)
  local sight=target and workspace:Raycast(origin,target.Position-origin,params({live}))
  if not C.TestScratchAlways and target and seen and d>C.LungeRange and now>=s.nextLunge and (d>C.AttackRange or target.AssemblyLinearVelocity:Dot(direction)>1) then
   local excluded={live,workspace:FindFirstChild('CrawlerSpawns')}
   for _,player in ipairs(Players:GetPlayers()) do if player.Character then table.insert(excluded,player.Character) end end
   local rp=params(excluded);rp.RespectCanCollide=true
   local plan=Leap.plan(root,target.Position,rp,'Lunge')
   s.nextLunge=now+C.LungeCooldown
   if plan then s.leap=plan;s.leapParams=rp;setClip(s,'Lunge',now);continue end
  end
  if target and seen and d<=C.AttackRange and now>=s.nextShot and (not sight or sight.Instance:IsDescendantOf(target.Parent)) then
   local choice=Choice.pick(s,C);s.nextShot=now+C.Cooldown
   if choice=='FrenzyRun' then
    s.frenzy={phase='rush',started=now};m:SetAttribute('FrenzyUsed',true);setClip(s,'FrenzyRun',now)
   else
    s.attack={aim=target.Position,fired=false,clip=choice,windup=choice=='SpitAlt' and .82 or C.Windup,duration=Anim.length(choice)};setClip(s,choice,now)
   end
  elseif not target or not seen or d>C.AttackRange*.7 then
   direction=Nav.direction(s,goal,now) or direction
   local moveSpeed=target and C.Speed or C.ReturnSpeed
   local delta=direction*moveSpeed*step
   local obstacles={live,workspace:FindFirstChild('CrawlerSpawns')}
   for _,p in ipairs(Players:GetPlayers()) do if p.Character then table.insert(obstacles,p.Character) end end
   local rp=params(obstacles);rp.RespectCanCollide=true
   local wall=workspace:Blockcast(root.CFrame,Vector3.new(3.3,1.1,3.5),delta,rp)
   local ground=workspace:Raycast(root.Position+delta+Vector3.yAxis,Vector3.new(0,-4,0),rp)
   if not wall and ground and ground.Normal.Y>.7 and ground.Material~=Enum.Material.Water and math.abs(ground.Position.Y-(root.Position.Y-1))<.5 then
    local pos=Vector3.new(root.Position.X+delta.X,ground.Position.Y+1,root.Position.Z+delta.Z)
    root.CFrame=CFrame.new(pos)*root.CFrame.Rotation;setClip(s,target and 'Run' or 'Crawl',now)
   else s.waypoints=nil;setClip(s,'Idle',now) end
  else setClip(s,'Idle',now) end
 end
end)
-- One model per marker, including dynamically cloned islands.
local markers={}
local function removeMarker(part)
 local record=markers[part];if not record then return end
 markers[part]=nil
 if record.mob then record.mob:Destroy() end
end
local function addMarker(part)
 if not part:IsA('BasePart') or part.Name~='Mutant_1' or markers[part] then return end
 markers[part]={due=0}
 print('CRAWLER_MARKER_FOUND',part:GetFullName())
 -- Spawn markers are editor helpers, never physical obstacles.
 part.Transparency=1;part.CanCollide=false;part.CanTouch=false;part.CanQuery=false;part.Anchored=true
end
workspace.DescendantAdded:Connect(addMarker)
workspace.DescendantRemoving:Connect(function(part) if markers[part] then removeMarker(part) end end)
for _,part in workspace:GetDescendants() do addMarker(part) end
print('CRAWLER_SPAWNER_READY')
task.spawn(function()
 while true do
  for part,record in pairs(markers) do
   if not part:IsDescendantOf(workspace) or part.Name~='Mutant_1' then removeMarker(part)
   elseif record.mob and not record.mob.Parent then
    record.mob=nil
    local delay=part:GetAttribute('RespawnSeconds')
    record.due=type(delay)=='number' and delay>0 and os.clock()+delay or math.huge
   elseif not record.mob and os.clock()>=record.due and part:GetAttribute('SpawnEnabled')~=false then
    record.mob=spawn(part)
    record.due=os.clock()+2
   end
  end
  task.wait(.5)
 end
end)
