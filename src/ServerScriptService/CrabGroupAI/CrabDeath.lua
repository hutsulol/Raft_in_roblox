local Tween=game:GetService('TweenService')
local Death={}
function Death.start(model)
 model:SetAttribute('CrabRagdoll',true)
 model:SetAttribute('CrabMotionTarget',nil)
 local root=model:FindFirstChild('HumanoidRootPart')
 local torso=model:FindFirstChild('Torso',true)
 if not root or not torso then return end
 -- Keep the shell and limbs connected, but let gravity/contacts move the body.
 -- The client stops procedural posing before the motor assembly is released.
 for _,m in model:GetDescendants() do
  if m:IsA('Motor6D') and m:GetAttribute('CrabJoint') then
   m.Transform=CFrame.identity
   local weld=Instance.new('WeldConstraint');weld.Part0=m.Part0;weld.Part1=m.Part1
   weld.Name='DeathWeld';weld.Parent=m.Part0;m.Enabled=false
  elseif m:IsA('BillboardGui') then m.Enabled=false end
 end
 for _,p in model:GetDescendants() do
  if p:IsA('BasePart') then p.Anchored=false;p.CanCollide=false end
 end
 torso.Massless=false;torso.CanCollide=true
 root.Anchored=false;root:SetNetworkOwner(nil)
 root.AssemblyLinearVelocity=Vector3.new(0,-2,0)
 root.AssemblyAngularVelocity=root.CFrame.RightVector*1.4
end
function Death.remove(model)
 for _,p in model:GetDescendants() do
  if p:IsA('BasePart') then Tween:Create(p,TweenInfo.new(.45),{Transparency=1}):Play() end
 end
 task.delay(.5,function()if model.Parent then model:Destroy() end end)
end
return Death
