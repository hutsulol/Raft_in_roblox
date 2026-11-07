-- CannonControl's physical Bullet_Cannon projectiles against the small raider.
-- A single server sweep owns each impact/interception; air bursts never do damage.
local M = {}
local RS = game:GetService('RunService')
local Debris = game:GetService('Debris')
local W = workspace
local boats, shells = {}, {}
function M.getBoat(model) return boats[model] end
local function burst(pos, radius)
 local e=Instance.new('Explosion');e.Position=pos;e.BlastRadius=radius;e.BlastPressure=0;e.DestroyJointRadiusPercent=0;e.Parent=W
 local sounds=game.ReplicatedStorage:FindFirstChild('CombatSounds')
 if sounds then require(sounds).play('hit',pos) end
end
local function finish(ball, air)
 if not shells[ball] or ball:GetAttribute('Resolved') then return false end
 ball:SetAttribute('Resolved',true);ball:SetAttribute('Intercepted',air==true)
 shells[ball]=nil
 if air then burst(ball.Position,3);W:SetAttribute('RaiderInterceptions',(W:GetAttribute('RaiderInterceptions') or 0)+1) end
 ball:Destroy();return true
end
local function track(ball)
 if not ball:IsA('BasePart') or ball.Name~='Bullet_Cannon' then return end
 if shells[ball] then return end
 shells[ball]={last=ball.Position,age=0};ball:SetAttribute('InterceptorHP',2)
 pcall(function()ball:SetNetworkOwner(nil)end)
end
local function detach(b,e,pos)
 local p=e.part;if not p.Parent or e.detached then return end
 e.detached=true;p:SetAttribute('PartHP',0)
 if e.hullArea then
  b.damage.lostArea+=e.hullArea
  table.insert(b.damage.holes,{rel=e.rel.Position,half=e.half,frame=e.rel,area=e.hullArea,water=0})
 end
 p.Parent=W;p.Anchored=false;p.CanQuery=false;p.CanCollide=false
 for _,j in ipairs(p:GetDescendants())do if j:IsA('WeldConstraint') or j:IsA('Motor6D') or j:IsA('Weld')then j:Destroy()end end
 local d=p.Position-pos
 p.AssemblyLinearVelocity=(d.Magnitude>.05 and d.Unit or Vector3.yAxis)*12+Vector3.new(0,9,0)
 p.AssemblyAngularVelocity=Vector3.new(2,3,-2);Debris:AddItem(p,9)
 b.folder:SetAttribute('DetachedParts',(b.folder:GetAttribute('DetachedParts') or 0)+1)
end
function M.register(b)
 boats[b.folder]=b;b.damage={flood=0,depth=0,roll=0,pitch=0,holes={},lostArea=0,totalArea=0}
 for _,e in ipairs(b.parts)do
  local p=e.part
  if p.Transparency<.99 then
   if p.Name=='HullPanel' then
    local dims={p.Size.X,p.Size.Y,p.Size.Z};table.sort(dims)
    e.hullArea=dims[2]*dims[3];e.half=p.Size*.5
    b.damage.totalArea+=e.hullArea
   end
   e.hp=p.Name=='HullPanel' and 85 or 40;p:SetAttribute('PartHP',e.hp);p:SetAttribute('PartMaxHP',e.hp)
  end
 end
 b.folder:SetAttribute('Flood',0)
end
function M.impact(b,hit,pos,mult)
 if not b.folder.Parent then return end
 mult=math.clamp(mult or 1,.1,10)
 burst(pos,7);b:onAttacked()
 local localHit=b.originCF:PointToObjectSpace(pos)
 local destroyed=0
 for _,e in ipairs(b.parts)do
  local p=e.part
  if e.hp and not e.detached and p.Parent then
   local near=p.CFrame:PointToObjectSpace(pos)
   local delta=Vector3.new(math.max(0,math.abs(near.X)-p.Size.X/2),math.max(0,math.abs(near.Y)-p.Size.Y/2),math.max(0,math.abs(near.Z)-p.Size.Z/2))
   local dist=delta.Magnitude
   if p==hit or dist<5 then
    e.hp-=mult*(p==hit and 110 or 90*(1-dist/5));p:SetAttribute('PartHP',math.max(0,e.hp))
    if e.hp<=0 then
     detach(b,e,pos);destroyed+=1
    end
   end
  end
 end
 -- Tires, rails and deck fittings lose their support with the struck local section.
 if destroyed>0 then
  for _,e in ipairs(b.parts)do
   if e.hp and not e.detached and (e.rel.Position-localHit).Magnitude<3.5 then detach(b,e,pos)end
  end
 end
 for _,p in ipairs(b.crew)do
  if not p.dead and (p.rig.hrp.Position-pos).Magnitude<7 then p.hum:TakeDamage(55*mult)end
 end
 b.folder:SetAttribute('CannonHits',(b.folder:GetAttribute('CannonHits') or 0)+1)
 W:SetAttribute('RaiderImpacts',(W:GetAttribute('RaiderImpacts') or 0)+1)
end
--[[ ПУЛЯ (револьвер: Bullet_Cannon с NoExplode) — НЕ ЯДРО. Раньше по катеру она
     била как пушечное ядро: взрыв радиусом 7, урон всем деталям вокруг и экипажу.
     Теперь пуля ведёт себя как пуля:
       • в матроса — обычный урон пули (как ShipCombat по людям), без взрыва;
       • в корпус — одно из трёх: рикошет (искры, пуля отскакивает и летит
         дальше), вмятина (щепки, след на доске, пуля застревает) или пробитие
         (дырка, пуля проходит насквозь и летит дальше).
     Урон деталям маленький: пулей катер не разобрать, это дело пушек. ]]
local BULLET_HUM = 100                 -- = ShipCombat.HUMANOID_DAMAGE (× DmgMult пули)
local RICOCHET, PIERCE = .3, .25       -- остальное — вмятина
local function chips(pos, normal, color, n, speed)
 local p=Instance.new('Part');p.Anchored=true;p.CanCollide=false;p.CanQuery=false;p.CanTouch=false
 p.Transparency=1;p.Size=Vector3.new(.1,.1,.1);p.CFrame=CFrame.lookAt(pos,pos+normal);p.Parent=W
 local a=Instance.new('Attachment');a.Parent=p
 local e=Instance.new('ParticleEmitter');e.Color=ColorSequence.new(color);e.LightEmission=color==Color3.fromRGB(255,214,120) and 1 or 0
 e.Size=NumberSequence.new(.12,0);e.Lifetime=NumberRange.new(.15,.35);e.Speed=NumberRange.new(speed*.5,speed)
 e.SpreadAngle=Vector2.new(35,35);e.Drag=4;e.Acceleration=Vector3.new(0,-25,0);e.EmissionDirection=Enum.NormalId.Front
 e.Rate=0;e.Parent=a;e:Emit(n);Debris:AddItem(p,1)
end
local function mark(part, pos, normal, size, color)
 local m=Instance.new('Part');m.Name='BulletMark';m.Shape=Enum.PartType.Cylinder;m.Size=Vector3.new(.04,size,size)
 m.Color=color;m.Material=Enum.Material.SmoothPlastic;m.CanCollide=false;m.CanQuery=false;m.CanTouch=false;m.Massless=true
 m.CFrame=CFrame.lookAt(pos+normal*.01,pos+normal*2)*CFrame.Angles(0,math.rad(90),0)
 local w=Instance.new('WeldConstraint');w.Part0=part;w.Part1=m;w.Parent=m;m.Parent=part
 Debris:AddItem(m,45)
end
local function sound(name,pos)
 local sounds=game.ReplicatedStorage:FindFirstChild('CombatSounds')
 if sounds then pcall(function() require(sounds).play(name,pos) end) end
end
-- вернёт true, если пуля летит дальше (рикошет / пробитие)
function M.bulletImpact(b,ball,res,mult)
 if not b.folder.Parent then return false end
 local hit,pos,normal=res.Instance,res.Position,res.Normal
 b:onAttacked()
 for _,p in ipairs(b.crew)do
  if not p.dead and p.model and hit:IsDescendantOf(p.model) then
   p.hum:TakeDamage(BULLET_HUM*mult)
   chips(pos,normal,Color3.fromRGB(120,20,20),6,10)
   return false
  end
 end
 local entry
 for _,e in ipairs(b.parts)do if e.part==hit then entry=e break end end
 local dmgScale=mult/.2                -- револьвер DmgMult .2 → 1; усиленный — больше
 local r=math.random()
 if r<RICOCHET then
  -- рикошет: отражаем скорость от грани, теряет половину; второй рикошет — уже нет
  chips(pos,normal,Color3.fromRGB(255,214,120),8,22);sound('ricochet',pos)
  if ball:GetAttribute('Ricocheted') then return false end
  ball:SetAttribute('Ricocheted',true)
  local v=ball.AssemblyLinearVelocity
  local refl=v-2*v:Dot(normal)*normal
  ball.CFrame=CFrame.new(pos+normal*.3);ball.AssemblyLinearVelocity=refl*.5
  return true
 elseif r<RICOCHET+PIERCE then
  -- пробитие: дырка, пуля проходит насквозь
  chips(pos,normal,Color3.fromRGB(120,85,55),10,14);sound('bulletWood',pos)
  mark(hit,pos,normal,.22,Color3.fromRGB(25,18,12))
  if entry and entry.hp and not entry.detached then
   entry.hp-=10*dmgScale;hit:SetAttribute('PartHP',math.max(0,entry.hp))
   if entry.hp<=0 then detach(b,entry,pos)end
  end
  ball.CFrame=CFrame.new(pos-normal*.6)*ball.CFrame.Rotation
  return true, hit
 else
  -- вмятина: щепки и след, пуля застряла
  chips(pos,normal,Color3.fromRGB(150,110,70),6,9);sound('bulletWood',pos)
  mark(hit,pos,normal,.16,Color3.fromRGB(60,42,28))
  if entry and entry.hp and not entry.detached then
   entry.hp-=4*dmgScale;hit:SetAttribute('PartHP',math.max(0,entry.hp))
   if entry.hp<=0 then detach(b,entry,pos)end
  end
  return false
 end
end
function M.flood(b,dt)
 local d=b.damage;if not d then return 0,0,0,1 end
 local sx,sz,weight=0,0,0
 local lost=d.lostArea/math.max(d.totalArea,1)
 for _,h in ipairs(d.holes)do
  -- The opening starts at its lowest edge, not its centre above the water.
  local cf=b.originCF*h.frame
  local halfY=math.abs(cf.RightVector.Y)*h.half.X+math.abs(cf.UpVector.Y)*h.half.Y+math.abs(cf.LookVector.Y)*h.half.Z
  local pressure=math.clamp(b.waterY+.25-(cf.Position.Y-halfY),0,6)
  if pressure>0 then
   local flow=dt*(h.area/math.max(d.totalArea,1))*(.35+.32*pressure)
   h.water+=flow;d.flood=math.min(1.5,d.flood+flow)
  end
  local w=h.water+h.area/math.max(d.totalArea,1)*.15
  sx+=h.rel.X*w;sz+=h.rel.Z*w;weight+=w
 end
 -- Lost displacement produces initial settling, submerging open lower edges.
 local targetDepth=lost*5+d.flood*7+math.max(0,d.flood-.65)*20
 local a=1-math.exp(-dt*.65)
 d.depth+=(targetDepth-d.depth)*a
 local tilt=math.min(1,d.flood*1.7+lost)
 local targetRoll=weight>0 and -math.clamp(sx/weight/4,-1,1)*math.rad(40)*tilt or 0
 local targetPitch=weight>0 and math.clamp(sz/weight/12,-1,1)*math.rad(32)*tilt or 0
 d.roll+=(targetRoll-d.roll)*a;d.pitch+=(targetPitch-d.pitch)*a
 b.folder:SetAttribute('Flood',d.flood);b.folder:SetAttribute('SinkDepth',d.depth)
 b.folder:SetAttribute('HullLoss',lost)
 return d.depth,d.roll,d.pitch,math.clamp(1-d.flood-lost*.5,0,1)
end
function M.crewSupport(p,dt)
 local b=p.boat
 if p.fall then
  local f=p.fall;f.age+=dt
  f.velocity-=Vector3.yAxis*W.Gravity*dt
  f.position+=f.velocity*dt
  local surface=b.waterY-1
  if f.position.Y<=surface then
   f.position=Vector3.new(f.position.X,surface+math.sin(f.age*4)*.12,f.position.Z)
   f.velocity=Vector3.new(f.velocity.X*.96,0,f.velocity.Z*.96)
   f.wet=(f.wet or 0)+dt
  end
  p.rig:apply(CFrame.lookAt(f.position,f.position+f.look)*CFrame.Angles(0,0,math.sin(f.age*5)*.18),{})
  if (f.wet or 0)>3 then p.hum.Health=0 end
  return true
 end
 local decks={}
 for _,e in ipairs(b.parts)do
  if not e.detached and e.part.Parent and e.part.Name=='Deck' then table.insert(decks,e.part)end
 end
 local feet=b.originCF:PointToWorldSpace(p.localPos)
 local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances=decks
 local supported=false
 for _,x in ipairs({0,-.45,.45})do
  if W:Raycast(feet+b.originCF.RightVector*x+Vector3.yAxis, -Vector3.yAxis*4,params) then supported=true;break end
 end
 if supported and feet.Y>b.waterY-.4 then p.unsupported=0;return false end
 p.unsupported=(p.unsupported or 0)+dt
 if p.unsupported<.12 then return false end
 local cf=p:worldCF()
 p.fall={position=cf.Position,velocity=b.heading*(b.currentSpeed or 3),look=Vector3.new(cf.LookVector.X,0,cf.LookVector.Z).Unit,age=0}
 p.target=nil;p.model:SetAttribute('CombatPriority','OVERBOARD');p.model:SetAttribute('Overboard',true)
 return true
end

function M.threat(pirate)
 local b=pirate.boat
 if b.damage and b.damage.depth>5 then return nil end
 local best,bestT=nil,math.huge
 for ball,s in pairs(shells)do
  if ball.Parent and not ball:GetAttribute('Resolved') then
   local v=ball.AssemblyLinearVelocity
   local delta=b.originCF.Position+Vector3.new(0,4,0)-ball.Position
   local t=math.clamp(delta:Dot(v)/math.max(v:Dot(v),1),0,1.5)
   local future=ball.Position+v*t-Vector3.yAxis*(W.Gravity*.5*t*t)
   local miss=(future-(b.originCF.Position+Vector3.new(0,4,0))).Magnitude
   if delta.Magnitude<150 and t>.02 and miss<22 and t<bestT then best,bestT=ball,t end
  end
 end
 return best
end
function M.fireAtShell(p,ball)
 if not shells[ball] or not ball.Parent then return end
 local origin=p.muzzlePosition or p.rig.hrp.Position
 local v=ball.Position-origin;if v.Magnitude<.1 then return end
 local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.FilterDescendantsInstances={p.model};params.IgnoreWater=true
 local obstruction=W:Raycast(origin,v,params)
 if obstruction and obstruction.Instance~=ball then return end
 p.lastShotAt=os.clock();p.model:SetAttribute('InterceptionShots',(p.model:GetAttribute('InterceptionShots') or 0)+1)
 require(game.ReplicatedStorage.MuzzleFX).burst(origin,v.Unit,{scale=.3,smoke=false})
 require(game.ReplicatedStorage.CombatSounds).play(p.shotSound,origin)
 -- Bullet spread decides a real ray hit on the shell, not guaranteed proximity damage.
 local distance=v.Magnitude;local spread=.009*distance
 local aim=ball.Position+Vector3.new((math.random()-.5)*spread,(math.random()-.5)*spread,(math.random()-.5)*spread)
 local ray=W:Raycast(origin,(aim-origin).Unit*(distance+3),params)
 local endpoint=ray and ray.Position or aim
 local tracer=Instance.new('Part');tracer.Name='InterceptorTracer';tracer.Anchored=true;tracer.CanCollide=false;tracer.CanQuery=false;tracer.CanTouch=false;tracer.Material=Enum.Material.Neon;tracer.Color=Color3.fromRGB(255,213,117);tracer.Size=Vector3.new(.035,.035,(endpoint-origin).Magnitude);tracer.CFrame=CFrame.lookAt((origin+endpoint)/2,endpoint);tracer.Parent=W;Debris:AddItem(tracer,.06)
 if ray and ray.Instance==ball then
  local hp=(ball:GetAttribute('InterceptorHP') or 2)-1;ball:SetAttribute('InterceptorHP',hp)
  if hp<=0 then finish(ball,true)end
 end
end
W.DescendantAdded:Connect(track)
for _,d in ipairs(W:GetDescendants())do track(d)end
RS.Heartbeat:Connect(function(dt)
 for model in pairs(boats)do if not model.Parent then boats[model]=nil end end
 for ball,s in pairs(shells)do
  if not ball.Parent then shells[ball]=nil;continue end
  s.age+=dt
  local now=ball.Position;local delta=now-s.last
  if delta.Magnitude>.001 then
   local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
   local exclude={ball};local creator=ball:FindFirstChild('creator');local player=creator and creator.Value
   if player and player:IsA('Player') and player.Character then table.insert(exclude,player.Character)end
   if s.age<.15 and W:FindFirstChild('Raft')then table.insert(exclude,W.Raft)end
   for _,ig in ipairs(s.ignore or {})do table.insert(exclude,ig)end
   params.FilterDescendantsInstances=exclude;params.IgnoreWater=true
   local hit=W:Spherecast(s.last,math.max(.15,ball.Size.X*.4),delta,params)
   if hit then
    local node=hit.Instance;local b
    while node and node~=W do if boats[node]then b=boats[node];break end;node=node.Parent end
    if b then
     local mult=ball:GetAttribute('DmgMult') or 1
     if ball:GetAttribute('NoExplode') then
      -- пуля (револьвер): без взрыва — рикошет / вмятина / пробитие
      local goOn,through=M.bulletImpact(b,ball,hit,mult)
      if goOn then
       s.last=ball.Position
       if through then s.ignore=s.ignore or {};table.insert(s.ignore,through) end
       continue
      end
      finish(ball,false)
     elseif finish(ball,false)then M.impact(b,hit.Instance,hit.Position,mult)end
    end
   end
  end
  s.last=now
 end
end)
return M
