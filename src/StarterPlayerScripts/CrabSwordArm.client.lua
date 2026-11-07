-- Evaluated on every client so modern AnimationConstraint and legacy Motor6D rigs agree.
local Run=game:GetService('RunService')
local Players=game:GetService('Players')
local applied={}
local rigs=setmetatable({},{__mode='k'})
Run.PreAnimation:Connect(function()
 for joint,base in applied do if joint.Parent then joint.Transform=base end end
 table.clear(applied)
end)
local function angles(x,y,z)return CFrame.Angles(math.rad(x),math.rad(y),math.rad(z)) end
local poses={
 RightShoulder={angles(65,-15,20),angles(-45,25,-10)},
 LeftShoulder={angles(8,-6,-9),angles(-10,8,-4)},
 Waist={angles(-3,-13,3),angles(6,17,-4)},
 Root={angles(-2,-8,2),angles(4,10,-3)},
 Neck={angles(2,6,-2),angles(-3,-7,2)},
 RightHip={angles(-3,0,2),angles(4,0,-2)},
 LeftHip={angles(2,0,-2),angles(-3,0,2)},
}
local aliases={['Right Shoulder']='RightShoulder',['Left Shoulder']='LeftShoulder',RootJoint='Root',['Right Hip']='RightHip',['Left Hip']='LeftHip'}
local function joints(c)
 if rigs[c] then return rigs[c] end
 local list={};local waist=false
 for _,j in c:GetDescendants() do
  if j:IsA('Motor6D') or j:IsA('AnimationConstraint') then
   local name=aliases[j.Name] or j.Name
   if poses[name] then list[j]=name;waist=waist or name=='Waist' end
  end
 end
 if waist then for j,n in list do if n=='Root' then list[j]=nil end end end
 -- Retry discovery if the character has not finished replicating.
 if next(list) and c:FindFirstChild('RightHand') or next(list) and c:FindFirstChild('Right Arm') then rigs[c]=list end
 return list
end
local function ease(t)return (1-math.cos(math.clamp(t,0,1)*math.pi))/2 end
Run.PreSimulation:Connect(function()
 for _,player in Players:GetPlayers() do
  local c=player.Character
  local start=c and c:GetAttribute('TestSwordSwing')
  if c and player==Players.LocalPlayer then
   local predicted=c:GetAttribute('LocalTestSwordSwing')
   if predicted and workspace:GetServerTimeNow()-predicted<.65 then start=predicted end
  end
  if not start or not c:FindFirstChildOfClass('Tool') then continue end
  local t=workspace:GetServerTimeNow()-start
  if t<0 or t>.53 then continue end
  local h=c:FindFirstChildOfClass('Humanoid')
  if not h or h.Health<=0 then continue end
  for j,name in joints(c) do
   if not j.Parent then rigs[c]=nil;continue end
   local pair=poses[name];local pose
   if t<.16 then pose=CFrame.identity:Lerp(pair[1],ease(t/.16))
   elseif t<.28 then pose=pair[1]:Lerp(pair[2],ease((t-.16)/.12))
   else pose=pair[2]:Lerp(CFrame.identity,ease((t-.30)/.22)) end
   -- Keep walking readable: leg accents are reduced while moving.
   if name:find('Hip') and h.MoveDirection.Magnitude>.1 then pose=CFrame.identity:Lerp(pose,.25) end
   applied[j]=j.Transform;j.Transform=pose*j.Transform
  end
 end
end)
