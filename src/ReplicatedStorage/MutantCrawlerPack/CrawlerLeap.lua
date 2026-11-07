-- Kinematic root motion, independent of the local Motor6D clip.
local L={}
function L.position(plan,t)
 local u=math.clamp((t-plan.takeoff)/(plan.land-plan.takeoff),0,1)
 return plan.start:Lerp(plan.finish,u)+Vector3.yAxis*(4*plan.height*u*(1-u))
end
function L.plan(root,target,rp,kind)
 local flat=Vector3.new(target.X-root.Position.X,0,target.Z-root.Position.Z)
 if flat.Magnitude<.1 then return end
 local scratch=kind=='ScratchPounce'
 local distance=scratch and math.min(15,math.max(.05,flat.Magnitude-3)) or (kind=='Jump' and 2 or math.min(9,math.max(0,flat.Magnitude-5)))
 if distance<1 and not scratch then return end
 local finish=root.Position+flat.Unit*distance
 local ground=workspace:Raycast(finish+Vector3.yAxis*4,Vector3.new(0,-9,0),rp)
 if not ground or ground.Normal.Y<.75 or ground.Material==Enum.Material.Water then return end
 finish=ground.Position+Vector3.yAxis
 if math.abs(finish.Y-root.Position.Y)>1.5 then return end
 local p={start=root.Position,finish=finish,height=scratch and 2.6 or (kind=='Jump' and 2.2 or 1.65),takeoff=scratch and .16 or (kind=='Jump' and .26 or .22),land=scratch and .65 or (kind=='Jump' and .94 or .88),direction=flat.Unit}
 local previous=p.start
 for i=1,16 do
  local at=L.position(p,p.takeoff+(p.land-p.takeoff)*i/16)
  local hit=workspace:Blockcast(CFrame.lookAt(previous,previous+p.direction),Vector3.new(2.7,1.2,2.7),at-previous,rp)
  if hit then return end
  previous=at
 end
 return p
end
function L.step(root,plan,t,rp)
 local position=L.position(plan,t);local delta=position-root.Position
 if delta.Magnitude>.001 and workspace:Blockcast(root.CFrame,Vector3.new(2.7,1.2,2.7),delta,rp) then
  -- Retreat to the previously validated safe starting ground if the arc gets blocked.
  root.CFrame=CFrame.lookAt(plan.start,plan.start+plan.direction);return false
 end
 root.CFrame=CFrame.lookAt(position,position+plan.direction);return true
end
return L
