local Run=game:GetService('RunService')
local Players=game:GetService('Players')
local Tags=game:GetService('CollectionService')
local Audio=require(script:WaitForChild('CrabCombatAudio'))
Audio.preload()
local crabs={}
local swords=setmetatable({},{__mode='k'})
local predicted=setmetatable({},{__mode='k'})
local function add(c)
 if c:IsA('Model') and not crabs[c] then
  crabs[c]={hp=c:GetAttribute('CrabHealth'),step=0,nextStep=0}
  task.spawn(function()local root=c:WaitForChild('HumanoidRootPart',10);if root then Audio.prepare(root) end end)
 end
end
Tags:GetInstanceAddedSignal('CrabNPC'):Connect(add)
Tags:GetInstanceRemovedSignal('CrabNPC'):Connect(function(c)crabs[c]=nil end)
for _,c in Tags:GetTagged('CrabNPC') do add(c) end
local function trailFor(tool)
 local blade=tool:FindFirstChild('Blade')
 if not blade or not blade:IsA('BasePart') then return end
 local trail=blade:FindFirstChild('AirSlash')
 if trail then return trail end
 local a=Instance.new('Attachment');a.Name='AirSlashBase';a.Position=Vector3.new(0,-blade.Size.Y*.43,0);a.Parent=blade
 local b=Instance.new('Attachment');b.Name='AirSlashTip';b.Position=Vector3.new(0,blade.Size.Y*.53,0);b.Parent=blade
 trail=Instance.new('Trail');trail.Name='AirSlash';trail.Attachment0=a;trail.Attachment1=b
 trail.Enabled=false;trail.FaceCamera=true;trail.Lifetime=.14;trail.MinLength=.025
 trail.LightEmission=.85;trail.LightInfluence=0
 trail.Color=ColorSequence.new(Color3.fromRGB(225,248,255),Color3.fromRGB(155,216,240))
 trail.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.20),NumberSequenceKeypoint.new(.35,.48),NumberSequenceKeypoint.new(1,1)})
 trail.WidthScale=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(1,0)})
 trail.Parent=blade
 return trail
end
local bound=setmetatable({},{__mode='k'})
local nextLocalSwing=0
local function bindTool(tool)
 if not tool:IsA('Tool') or bound[tool] then return end
 bound[tool]=true
 task.spawn(function()
  local handle=tool:WaitForChild('Handle',5)
  if handle then Audio.prepare(handle,{'Sword'}) end
  trailFor(tool)
 end)
 tool.Activated:Connect(function()
  local c=Players.LocalPlayer.Character;local h=c and c:FindFirstChildOfClass('Humanoid')
  local now=workspace:GetServerTimeNow()
  if tool.Parent~=c or not h or h.Health<=0 or not tool:FindFirstChild('Blade') or now<nextLocalSwing then return end
  nextLocalSwing=now+.65
  predicted[c]=now;c:SetAttribute('LocalTestSwordSwing',now)
  Audio.play(tool:FindFirstChild('Handle'),'Sword')
 end)
 tool.Unequipped:Connect(function()
  local c=Players.LocalPlayer.Character
  if c then c:SetAttribute('LocalTestSwordSwing',nil);predicted[c]=nil end
 end)
end
local function watch(container)
 container.ChildAdded:Connect(bindTool)
 for _,t in container:GetChildren() do bindTool(t) end
end
local localPlayer=Players.LocalPlayer
task.spawn(function()watch(localPlayer:WaitForChild('Backpack'))end)
localPlayer.ChildAdded:Connect(function(v)if v:IsA('Backpack') then watch(v) end end)
localPlayer.CharacterAdded:Connect(watch)
if localPlayer.Character then watch(localPlayer.Character) end
Run.PreSimulation:Connect(function()
 local now=workspace:GetServerTimeNow()
 for _,player in Players:GetPlayers() do
  local c=player.Character;if not c then continue end
  local start=c:GetAttribute('TestSwordSwing')
  if player==localPlayer then
   local localStart=c:GetAttribute('LocalTestSwordSwing')
   if localStart and now-localStart<.65 then start=localStart end
  end
  local data=swords[c]
  local tool=c:FindFirstChildOfClass('Tool');local hum=c:FindFirstChildOfClass('Humanoid')
  if data and (not tool or tool~=data.tool or not hum or hum.Health<=0) then
   if data.trail then data.trail.Enabled=false end
   swords[c]=nil;data=nil
  end
  if start and tool and hum and hum.Health>0 and now-start<.6 then
   if not data or data.start~=start then
    data={start=start,tool=tool,trail=trailFor(tool),sounded=predicted[c]==start};swords[c]=data
   end
   local t=now-start
   if t>=0 and t<.35 and not data.sounded then
    data.sounded=true;Audio.play(tool:FindFirstChild('Handle'),'Sword')
   end
   if data.trail then data.trail.Enabled=t>=.14 and t<.32 end
  elseif data and data.trail then data.trail.Enabled=false end
 end
end)
Run.Heartbeat:Connect(function(dt)
 local now=workspace:GetServerTimeNow()
 for c,d in crabs do
  if not c:IsDescendantOf(workspace) then crabs[c]=nil;continue end
  local root=c:FindFirstChild('HumanoidRootPart');if not root then continue end
  Audio.prepare(root)
  if not d.dust then
   local at=Instance.new('Attachment');at.Name='CrabActivityFX';at.Position=Vector3.new(0,-.8,-1);at.Parent=root
   local e=Instance.new('ParticleEmitter');e.Name='SandAndWater';e.Texture='rbxasset://textures/particles/smoke_main.dds';e.Rate=0
   e.Lifetime=NumberRange.new(.25,.5);e.Speed=NumberRange.new(.5,1.2);e.SpreadAngle=Vector2.new(65,65)
   e.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.12),NumberSequenceKeypoint.new(1,.35)})
   e.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.55),NumberSequenceKeypoint.new(1,1)})
   e.Parent=at;d.dust=e
  end
  local activity=c:GetAttribute('CrabState');local swimming=c:GetAttribute('CrabSwimming')
  d.dust.Color=ColorSequence.new(swimming and Color3.fromRGB(195,227,232) or Color3.fromRGB(207,188,132))
  d.dust.Rate=(c:GetAttribute('CrabHealth') or 0)>0 and (activity=='Forage' and 5 or swimming and 3 or 0) or 0
  local hp=c:GetAttribute('CrabHealth') or 0;local scale=c:GetAttribute('CrabRigScale') or 1
  local name=c:GetAttribute('CrabAnimation') or 'Idle';local stamp=c:GetAttribute('CrabAnimationT')
  if hp<=0 or c:GetAttribute('CrabRagdoll') then
   if not d.dead then
    d.dead=true;Audio.play(root,'Death',scale)
   end
   continue
  end
  if d.hp and hp<d.hp then Audio.play(root,'Hurt',scale) end
  d.hp=hp
  local identity=name..tostring(stamp)
  if identity~=d.animation then
   d.animation=identity;d.clawed=false
   if name=='Threat' and now-(d.alert or -100)>4 then d.alert=now;Audio.play(root,'Alert',scale) end
  end
  if (name=='AttackLeft' or name=='AttackRight') and stamp and now-stamp>=.34 and now-stamp<.6 and not d.clawed then
   d.clawed=true;Audio.play(root,'Claw',scale)
  end
  local pos=root.Position
  if d.position and (name=='Run' or name=='Walk') then
   local delta=(pos-d.position).Magnitude
   if delta<6*scale then d.step+=delta end
   if d.step>=.9*scale and now>=d.nextStep then
    d.step=0;d.nextStep=now+.16;Audio.play(root,'Step',scale)
   end
  else d.step=0 end
  d.position=pos
 end
end)
