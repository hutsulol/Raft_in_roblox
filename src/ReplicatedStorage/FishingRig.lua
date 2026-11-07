-- Anatomical poses retargeted against each rig's actual, unmodified bind joints.
local M={}
local function part(m,n) return m:FindFirstChild(n,true) end
function M.hand(m,side)
 return part(m,side.."Hand") or part(m,side.." Arm")
end
function M.grip(m,side,fish)
 local h=assert(M.hand(m,side),"Fishing rig has no "..side.." hand")
 local a=h:FindFirstChild(side.."GripAttachment")
 local pos=a and a.Position or Vector3.new(0,-h.Size.Y*.5,0)
 return h,CFrame.new(pos)*CFrame.Angles(fish and 0 or math.rad(-60),0,fish and math.pi/2 or 0)
end
function M.measure(m,scale)
 local root=assert(part(m,"HumanoidRootPart")); local torso=part(m,"LowerTorso") or part(m,"Torso")
 assert(torso,"Fishing requires an R6 or R15 torso")
 assert(M.hand(m,"Left") and M.hand(m,"Right"),"Fishing requires both hands")
 local leg=part(m,"LeftUpperLeg") or part(m,"Left Leg")
 assert(leg,"Fishing requires legs")
 local hip
 for _,d in ipairs(m:GetDescendants()) do
  if d:IsA("Motor6D") and d.Part1==leg then hip=d end
 end
 assert(hip,"Fishing requires a connected hip")
 local hipPos=root.CFrame:PointToObjectSpace(hip.Part0.CFrame*hip.C0.Position)
 local thickness=math.max(leg.Size.X,leg.Size.Z)*.5
 local hum=m:FindFirstChildOfClass("Humanoid")
 local ground=part(m,"LowerTorso") and (hum.HipHeight+root.Size.Y*.5) or (leg.Size.Y+torso.Size.Y*.5)
 return {ground=ground/scale,seat=2.66+(-hipPos.Y+thickness)/scale+.2,
  approach=.6-(1.16+math.max(torso.Size.Z,root.Size.Z)/scale*.5+.59)}
end
local rad=math.rad
local function rot(x,y,z) return CFrame.Angles(rad(x or 0),rad(y or 0),rad(z or 0)) end
function M.attach(model)
 local self={model=model,joints={},r15=part(model,"LowerTorso")~=nil}
 for _,j in ipairs(model:GetDescendants()) do
  if j:IsA("Motor6D") then self.joints[j.Name]={motor=j,c0=j.C0,c1=j.C1,original=j.Transform} end
 end
 local required=self.r15 and {"Root","Waist","Neck","LeftShoulder","RightShoulder","LeftHip","RightHip","LeftKnee","RightKnee","LeftElbow","RightElbow"}
  or {"RootJoint","Neck","Left Shoulder","Right Shoulder","Left Hip","Right Hip"}
 for _,name in ipairs(required) do if not self.joints[name] then return nil end end
 function self:restore()
  for _,j in pairs(self.joints) do if j.motor.Parent then j.motor.Transform=j.original end end
 end
 function self:apply(v,dt)
  local alpha=1-math.exp(-math.max(dt,0)*24)
  local scale=model:GetAttribute("FishingScale") or 1
  local body=CFrame.new(v.px*scale,v.py*scale,v.pz*scale)*rot(v.bx,v.by,v.bz)
  local function apply(name,a,locked)
   local j=self.joints[name]; if not j or not j.motor.Part0 or not j.motor.Part1 then return end
   -- A is expressed in the parent body axes; preserve arbitrary bind orientations.
   local basis=j.c0.Rotation
   local target=basis:Inverse()*a*basis
   if locked then
    local supported=j.c0:Inverse()*body:Inverse()*j.c0*target
    target=target:Lerp(supported,math.clamp(v.lock,0,1))
   end
   j.motor.Transform=j.motor.Transform:Lerp(target,alpha)
  end
  if not self.r15 then
   apply("RootJoint",body)
   apply("Neck",rot(v.hr,v.hy,v.hz))
   apply("Right Shoulder",rot(v.rx,v.ry,v.rz)); apply("Left Shoulder",rot(v.lx,v.ly,v.lz))
   apply("Right Hip",rot(v.kr,0,v.sr),true); apply("Left Hip",rot(v.kl,0,v.sl),true)
  else
   -- Root supplies full lean so actual hip compensation keeps the seat support.
   apply("Root",body)
   apply("Waist",rot(0,0,0))
   apply("Neck",rot(v.hr,v.hy,v.hz))
   for _,side in ipairs({"Right","Left"}) do
    local right=side=="Right"; local x=right and v.rx or v.lx
    local y=right and v.ry or v.ly; local z=right and v.rz or v.lz
    local bend=math.clamp(x*.28,0,32)
    apply(side.."Shoulder",rot(x-bend,y,z))
    apply(side.."Elbow",rot(bend,0,0)); apply(side.."Wrist",rot(0,0,0))
    local knee=math.clamp(v.lock,0,1)*80
    apply(side.."Hip",rot(right and v.kr or v.kl,0,right and v.sr or v.sl),true)
    apply(side.."Knee",rot(-knee,0,0)); apply(side.."Ankle",rot(knee*.12,0,0))
   end
  end
 end
 return self
end
return M
