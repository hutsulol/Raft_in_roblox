local Data = require(script.Parent.CrawlerRigData)
local Physics=game:GetService('PhysicsService')
local collisionGroup='CrawlerVisual'
local Rig = {}
function Rig.setup(model)
 if not Physics:IsCollisionGroupRegistered(collisionGroup) then Physics:RegisterCollisionGroup(collisionGroup) end
 for _,group in Physics:GetRegisteredCollisionGroups() do
  Physics:CollisionGroupSetCollidable(collisionGroup,group.name,false)
 end
 local parts = {}
 for name in pairs(Data) do
  local p = model:FindFirstChild(name, true)
  assert(p and p:IsA('BasePart'), 'Missing crawler part: '..name)
  parts[name] = p
 end
 -- Rebuild the authored pose as well as joints: safe on an animated clone.
 for _,v in ipairs(model:GetDescendants()) do
  if v:IsA('JointInstance') or v:IsA('WeldConstraint') or v:IsA('AnimationController') then v:Destroy()
  elseif v.Name == 'Animate' and v:IsA('BaseScript') then v.Disabled = true end
 end
 local root = model:FindFirstChild('HumanoidRootPart') or Instance.new('Part')
 root.Name='HumanoidRootPart';root.Size=Vector3.new(1.7,1,2.2)
 root.Transparency=1;root.Anchored=true;root.CanCollide=false;root.CanTouch=false;root.CanQuery=false
 root.CFrame=CFrame.new(0,1,0);root.Parent=model;parts.HumanoidRootPart=root
 for name,d in pairs(Data) do
  local p=parts[name]
  -- Studio's FBX importer bakes a 180-degree Y turn into this export's mesh vertices.
  p.Size=Vector3.new(unpack(d.size));p.CFrame=CFrame.new(unpack(d.center))*CFrame.Angles(0,math.pi,0)
  p.Anchored=false;p.CanCollide=false;p.CanTouch=false;p.CanQuery=true;p.Massless=true
 end
 local motors={}
 for name,d in pairs(Data) do
  local p=parts[name];local parent=parts[d.parent]
  local at=CFrame.new(Vector3.new(unpack(d.center))+Vector3.new(p.Size.X*d.attach[1],p.Size.Y*d.attach[2],p.Size.Z*d.attach[3]))
  local m=Instance.new('Motor6D');m.Name=d.joint;m.Part0=parent;m.Part1=p
  m.C0=parent.CFrame:ToObjectSpace(at);m.C1=p.CFrame:ToObjectSpace(at);m.Parent=parent;motors[name]=m
 end
 local old=parts.Head:FindFirstChild('Mouth');if old then old:Destroy() end
 local mouth=Instance.new('Attachment');mouth.Name='Mouth'
 mouth.CFrame=parts.Head.CFrame:ToObjectSpace(CFrame.new(0,1.65,-1.96));mouth.Parent=parts.Head
 local hum=model:FindFirstChildOfClass('Humanoid') or Instance.new('Humanoid')
 hum.Name='Humanoid';hum.RigType=Enum.HumanoidRigType.R15;hum.RequiresNeck=false;hum.BreakJointsOnDeath=false;hum.AutoRotate=false
 hum.MaxHealth=30;hum.Health=30;hum.WalkSpeed=0;hum.DisplayName='';hum.NameDisplayDistance=0;hum.Parent=model
 hum.DisplayDistanceType=Enum.HumanoidDisplayDistanceType.None
 -- This NPC is driven kinematically; no body or imported accessory may push avatars.
 hum.EvaluateStateMachine=false
 for _,p in model:GetDescendants() do
  if p:IsA('BasePart') then
   p.CanCollide=false;p.CanTouch=false;p.Massless=true;p.CollisionGroup=collisionGroup
  end
 end
 model.PrimaryPart=root
 return motors
end
return Rig
