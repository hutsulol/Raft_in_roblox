--[[ ⚠️ КОПИЯ МОДУЛЯ ИЗ ПАКЕТА Farmers_Island_Transfer С НАШИМИ ПРАВКАМИ.
     Оригинал лежит внутри модели острова (Gameplay/*), но модель живёт в Studio,
     а не в репозитории — править его Rojo не может. Поэтому серверная часть
     рантайма острова запускается ОТСЮДА (IslandCrews), а модули внутри модели
     остаются для клиентских скриптов (ToolsClient, MutantClient) как есть.
     Что изменено — помечено «-- НАШЕ:». Остальное — авторский код пакета. ]]
-- Portable island tools and R6 animation. Combat damage belongs to NPCController.
-- Server: Attach(npc, role). Client: StartClient(island). No uploaded animation IDs.
local RunService = game:GetService('RunService')
local M = {}
local controllers = setmetatable({}, {__mode = 'k'})
local aliases = {Examine='Inspect', Celebrate='Joy'}
local function now() return workspace:GetServerTimeNow() end
local function part(tool, name, size, cf, color, material, shape)
 local p=Instance.new('Part'); p.Name=name; p.Size=size; p.CFrame=cf
 p.Color=color; p.Material=material or Enum.Material.SmoothPlastic
 p.CanCollide=false; p.CanTouch=false; p.CanQuery=false; p.Massless=true
 p.CastShadow=true; p.TopSurface=Enum.SurfaceType.Smooth; p.BottomSurface=Enum.SurfaceType.Smooth
 if shape then p.Shape=shape end
 p.Parent=tool
 return p
end
local function weld(a,b)
 local w=Instance.new('WeldConstraint'); w.Part0=a; w.Part1=b; w.Parent=b
end
local metal=Color3.fromRGB(63,72,77)
local function makeBaton()
 local t=Instance.new('Tool'); t.Name='Guard_Baton'; t.RequiresHandle=true; t.CanBeDropped=false
 t.ToolTip='Дубинка охранника'; t:SetAttribute('FarmersTool',true)
 local h=part(t,'Handle',Vector3.new(.22,.75,.22),CFrame.new(),Color3.fromRGB(37,29,23),Enum.Material.Wood)
 local shaft=part(t,'Baton',Vector3.new(.32,1.65,.32),CFrame.new(0,1.04,0),Color3.fromRGB(83,53,31),Enum.Material.Wood)
 local cap=part(t,'IronCap',Vector3.new(.37,.20,.37),CFrame.new(0,1.90,0),metal,Enum.Material.Metal)
 local guard=part(t,'Guard',Vector3.new(.48,.10,.48),CFrame.new(0,.39,0),metal,Enum.Material.Metal)
 for _,p in ipairs({shaft,cap,guard}) do weld(h,p) end
 t.Grip=CFrame.new(0,-.22,0)*CFrame.Angles(math.rad(90),0,0)
 return t
end
local function makeCan()
 local t=Instance.new('Tool'); t.Name='Watering_Can'; t.RequiresHandle=true; t.CanBeDropped=false
 t.ToolTip='Лейка'; t:SetAttribute('FarmersTool',true)
 local h=part(t,'Handle',Vector3.new(.15,.16,.78),CFrame.new(),metal,Enum.Material.Metal)
 local body=part(t,'Can',Vector3.new(.90,1.0,.90),CFrame.new(0,-.66,0),Color3.fromRGB(59,105,93),Enum.Material.Metal)
 local lid=part(t,'Lid',Vector3.new(.96,.08,.96),CFrame.new(0,-.13,0),metal,Enum.Material.Metal)
 local spout=part(t,'Spout',Vector3.new(.18,.18,1.02),CFrame.new(0,-.58,-.79)*CFrame.Angles(math.rad(-20),0,0),metal,Enum.Material.Metal)
 local rose=part(t,'Rose',Vector3.new(.42,.31,.12),CFrame.new(0,-.39,-1.26)*CFrame.Angles(math.rad(-20),0,0),metal,Enum.Material.Metal)
 for _,p in ipairs({body,lid,spout,rose}) do weld(h,p) end
 for _,z in ipairs({-.36,.36}) do
  local side=part(t,'HandleSide',Vector3.new(.13,.33,.13),CFrame.new(0,-.13,z),metal,Enum.Material.Metal); weld(h,side)
 end
 local outlet=Instance.new('Attachment'); outlet.Name='WaterOutlet'; outlet.Position=Vector3.new(0,0,-.09); outlet.Parent=rose
 t.Grip=CFrame.new(0,-.85,0)*CFrame.Angles(math.rad(90),0,0)
 t:SetAttribute('Pouring',false)
 return t
end
function M.Equip(character,role)
 local hum=character:FindFirstChildOfClass('Humanoid'); if not hum then return nil end
 local desired=role=='Guard' and 'Guard_Baton' or role=='Worker' and 'Watering_Can' or nil
 if not desired then return nil end
 local existing=character:FindFirstChild(desired)
 if existing and existing:IsA('Tool') then hum:EquipTool(existing); return existing end
 local t=role=='Guard' and makeBaton() or makeCan(); t.Parent=character; hum:EquipTool(t)
 return t
end
function M.SetPouring(character,on)
 local t=character:FindFirstChild('Watering_Can')
 if t then t:SetAttribute('Pouring',on==true) end
end
function M.Attach(character,role)
 if controllers[character] then return controllers[character] end
 local c={Character=character, Role=role, Tool=M.Equip(character,role), dead=false, strikeAt=-math.huge, sequence=0}
 character:SetAttribute('FarmersRole',role)
 local function state(name)
  if c.dead or not character.Parent then return end
  name=aliases[name] or name
  if character:GetAttribute('FarmersAction')~=name then
   character:SetAttribute('FarmersAction',name); character:SetAttribute('FarmersActionT',now())
  end
  M.SetPouring(character,name=='Water')
 end
 function c:SetState(name) self.sequence+=1; state(name) end
 function c:Strike(_targetHumanoid)
  if self.dead or now()-self.strikeAt<1.1 then return false end
  self.strikeAt=now(); self.sequence+=1; local ticket=self.sequence
  local action=role=='Guard' and 'BatonStrike' or role=='Mutant' and 'MutantSlam' or 'Slash'
  character:SetAttribute('FarmersActionT',now()); state(action)
  task.delay(role=='Mutant' and 1.52 or .82,function() if not self.dead and self.sequence==ticket then state('Idle') end end)
  return true -- Animation only: server combat controller validates and applies damage.
 end
 function c:Water(duration)
  self.sequence+=1; local ticket=self.sequence; state('Water')
  if duration then task.delay(duration,function() if not self.dead and self.sequence==ticket then state('Idle') end end) end
 end
 function c:Celebrate(duration)
  self.sequence+=1; local ticket=self.sequence; state('Joy')
  if duration then task.delay(duration,function() if not self.dead and self.sequence==ticket then state('Idle') end end) end
 end
 function c:Destroy()
  if self.dead then return end
  self.dead=true; self.sequence+=1; M.SetPouring(character,false); controllers[character]=nil
  if self.Tool and self.Tool.Parent then self.Tool:Destroy() end
 end
 controllers[character]=c; state('Idle'); return c
end

-- Use local Transform only: it is not replicated. Every client derives the same
-- pose from replicated action/time attributes, including late joins and clones.
local activeIslands=setmetatable({}, {__mode='k'})
local rad=math.rad
local function rotation(x,y,z) return CFrame.Angles(rad(x or 0),rad(y or 0),rad(z or 0)) end
local function joint(model,name)
 local j=model:FindFirstChild(name,true); return j and j:IsA('Motor6D') and j or nil
end
function M.StartClient(island)
 assert(RunService:IsClient(),'StartClient must run on a client')
 if activeIslands[island] then return activeIslands[island] end
 local rigs={}; local connections={}; local alive=true; local elapsed=0
 local effects=Instance.new('Folder'); effects.Name='_LocalFarmWaterDrops'; effects.Parent=island
 local function add(model)
  if rigs[model] or not model:IsA('Model') or not model:GetAttribute('FarmersRole') then return end
  local hum=model:FindFirstChildOfClass('Humanoid')
  if not hum or hum.Health<=0 or hum.RigType~=Enum.HumanoidRigType.R6 then return end
  local joints={RS=joint(model,'Right Shoulder'),LS=joint(model,'Left Shoulder'),RH=joint(model,'Right Hip'),LH=joint(model,'Left Hip'),N=joint(model,'Neck'),Root=joint(model,'RootJoint')}
  if not joints.RS or not joints.LS then return end
  local animate=model:FindFirstChild('Animate'); local wasDisabled=nil
  if animate and (animate:IsA('Script') or animate:IsA('LocalScript')) then wasDisabled=animate.Disabled; animate.Disabled=true end
  local animator=hum:FindFirstChildOfClass('Animator')
  if animator then for _,track in ipairs(animator:GetPlayingAnimationTracks()) do track:Stop(.1) end end
  rigs[model]={hum=hum,joints=joints,animate=animate,wasDisabled=wasDisabled,drops={},can=nil,canGrip=nil,handGrip=nil,originalGripC1=nil}
 end
 local function restoreCan(r)
  if r.can and r.can.Parent and r.canGrip then r.can.Grip=r.canGrip end
  if r.handGrip and r.handGrip.Parent and r.originalGripC1 then r.handGrip.C1=r.originalGripC1 end
 end
 local function remove(model,r)
  for _,j in pairs(r.joints) do if j.Parent then j.Transform=CFrame.identity end end
  for _,p in ipairs(r.drops) do p:Destroy() end
  restoreCan(r)
  if r.animate and r.animate.Parent and r.wasDisabled~=nil then r.animate.Disabled=r.wasDisabled end
  rigs[model]=nil
 end
 local function discover()
  for _,d in ipairs(island:GetDescendants()) do if d:IsA('Model') and d:GetAttribute('FarmersRole') then add(d) end end
 end
 discover()
 local function drops(r,model,t)
  local can=model:FindFirstChild('Watering_Can'); local outlet=can and can:FindFirstChild('WaterOutlet',true)
  local pouring=can and can:GetAttribute('Pouring') and outlet
  if can~=r.can then
   restoreCan(r);r.can=can;r.canGrip=can and can.Grip or nil;r.handGrip=nil;r.originalGripC1=nil
  end
  if can and r.canGrip then
   local grip=model:FindFirstChild('RightGrip',true)
   local bodyRoot=r.hum.RootPart
   local validGrip=grip and grip:IsA('JointInstance') and grip.Part0 and grip.Part1==can:FindFirstChild('Handle')
   if validGrip and r.handGrip~=grip then
    if r.handGrip and r.handGrip.Parent and r.originalGripC1 then r.handGrip.C1=r.originalGripC1 end
    r.handGrip=grip;r.originalGripC1=grip.C1
   end
   if pouring and validGrip and bodyRoot then
    -- Solve the hand weld instead of assuming Roblox's R6 RightGrip basis.
    -- Keep the handle in the palm; face the spout toward the bed, 25° down.
    local hand=grip.Part0.CFrame*grip.C0
    local forward=bodyRoot.CFrame.LookVector*Vector3.new(1,0,1)
    if forward.Magnitude>.01 then
     local outletLocal=can.Handle.CFrame:ToObjectSpace(outlet.WorldCFrame)
     local outletRotation=CFrame.lookAt(Vector3.zero,forward.Unit)*rotation(-25,0,0)
     local desired=CFrame.new(hand.Position)*outletRotation*outletLocal.Rotation:Inverse()
     local target=desired:ToObjectSpace(hand)
     local pose=grip.C1:Lerp(target,.2)
     can.Grip=pose
     -- Tool.Grip does not reliably refresh an already-created NPC RightGrip.
     -- The weld equation is Part0*C0 = Part1*C1, hence C1=desired^-1*hand.
     -- Explicit local C1 also works for Weld (the ordinary R6 Tool joint).
     grip.C1=pose
    end
   else
    restoreCan(r)
   end
  end
  if pouring and #r.drops==0 then
   for i=1,6 do
    -- Tiny elongated blocks read as falling droplets without sphere tessellation.
    -- Two workers together use only 12 blocks / 144 triangles for this effect.
    local p=Instance.new('Part'); p.Name='WaterDrop'; p.Size=Vector3.new(.055,.17,.055)
    p.Anchored=true; p.CanCollide=false; p.CanTouch=false; p.CanQuery=false; p.CastShadow=false
    p.Color=Color3.fromRGB(119,206,235); p.Material=Enum.Material.Glass; p.Transparency=.25; p.Parent=effects
    table.insert(r.drops,p)
   end
  end
  for i,p in ipairs(r.drops) do
   p.Transparency=pouring and .25 or 1
   if pouring then
    local phase=(t*1.9+i/6)%1
    local spread=Vector3.new(math.sin(i*2.4)*.14*phase,-phase*phase*2.4,math.cos(i*2.4)*.14*phase)
    p.CFrame=CFrame.new(outlet.WorldPosition+outlet.WorldCFrame.LookVector*phase*.35+spread)
   end
  end
 end
 connections[#connections+1]=RunService.PreSimulation:Connect(function(dt)
  elapsed+=dt
  if elapsed>1 then elapsed=0; discover() end
  local t=now()
  for model,r in pairs(rigs) do
   if not model:IsDescendantOf(island) or r.hum.Health<=0 then remove(model,r); continue end
   local action=model:GetAttribute('FarmersAction') or 'Idle'
   local age=math.max(0,t-(model:GetAttribute('FarmersActionT') or t))
   local rs,ls,rh,lh,neck,root=CFrame.identity,CFrame.identity,CFrame.identity,CFrame.identity,CFrame.identity,CFrame.identity
   local v=r.hum.RootPart and r.hum.RootPart.AssemblyLinearVelocity or Vector3.zero
   local speed=Vector3.new(v.X,0,v.Z).Magnitude
   local walking=(action=='Walk' or action=='Run' or speed>.8) and action~='Water' and action~='Joy'
   if walking then
    local swing=math.sin(t*(action=='Run' and 11 or 7))*math.min(35,speed*3)
    rs=rotation(swing,0,0); ls=rotation(-swing,0,0); rh=rotation(-swing*.75,0,0); lh=rotation(swing*.75,0,0)
    root=CFrame.new(0,math.abs(math.sin(t*7))*.05,0)
   else neck=rotation(math.sin(t*1.4)*1.8,0,0) end
   if model:GetAttribute('FarmersRole')=='Guard' then rs=rs*rotation(18,0,9) end
   if action=='Water' then
    rs=rotation(70+math.sin(age*1.9)*5,-10,24); ls=rotation(45,15,-28)
    root=rotation(0,0,-5); neck=rotation(-12,math.sin(age*.8)*8,0)
   elseif action=='Inspect' or action=='Heal' then
    rs=rotation(60+math.sin(age*3)*8,-20,10); ls=rotation(38,10,-20); neck=rotation(-17,math.sin(age)*12,0)
   elseif action=='Joy' then
    rs=rotation(-12,0,145+math.sin(age*5)*15); ls=rotation(-12,0,-145-math.sin(age*5)*15)
    root=CFrame.new(0,math.max(0,math.sin(age*6))*.17,0); neck=rotation(12,math.sin(age*4)*10,0)
   elseif action=='BatonStrike' or action=='Slash' then
    -- Impact at .28 s. Distinct overhead windup, fast cross-body strike, recovery.
    if age<.20 then rs=rotation(120*age/.20,15,35*age/.20)
    elseif age<.36 then local a=(age-.20)/.16; rs=rotation(120-160*a,15-45*a,35-55*a)
    else local a=math.clamp((age-.36)/.46,0,1); rs=rotation(-40*(1-a),-30*(1-a),-20*(1-a)) end
    ls=rotation(20,0,-18); root=rotation(0,math.sin(math.min(age/.82,1)*math.pi)*-18,0)
   end
   local poses={RS=rs,LS=ls,RH=rh,LH=lh,N=neck,Root=root}
   local alpha=1-math.exp(-18*dt)
   for key,j in pairs(r.joints) do
    if j.Parent then
     -- R6 shoulder/hip joint frames are rotated 90 degrees. Convert our
     -- torso-axis poses into each joint's basis instead of twisting the arms.
     local basis=j.C0.Rotation
     local target=basis:Inverse()*poses[key]*basis
     j.Transform=j.Transform:Lerp(target,alpha)
    end
   end
   drops(r,model,t)
  end
 end)
 local stop
 stop=function()
  if not alive then return end; alive=false
  for _,connection in ipairs(connections) do connection:Disconnect() end
  for model,r in pairs(rigs) do remove(model,r) end
  effects:Destroy(); activeIslands[island]=nil
 end
 connections[#connections+1]=island.AncestryChanged:Connect(function() if not island:IsDescendantOf(workspace) then stop() end end)
 activeIslands[island]=stop; return stop
end
return M
