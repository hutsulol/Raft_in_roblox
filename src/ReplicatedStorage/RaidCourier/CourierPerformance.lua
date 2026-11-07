--[[ ⚠️ КОПИЯ CourierPerformance из пакета test/Boat_Courier (процедурная гребля,
     подъём ящика, походка, мимика). Крутится на КЛИЕНТЕ (RaidCourierClient):
     лодочник ездит с плотом, и только клиент видит плот плавным. Правка одна —
     помечена «НАШЕ». ]]
-- R6 procedural performance: oar grips and cargo grips are the actual hand targets.
local Performance={}
local function smooth(x) x=math.clamp(x,0,1);return x*x*(3-2*x) end
local function pose(j,base,x,z) j.C0=CFrame.new(base.Position)*CFrame.Angles(x,0,z or 0)*base.Rotation end
function Performance.new(scene)
 local self={scene=scene,rig=scene:FindFirstChild('Raider') or scene.NormalDummy,time=0,phaseTime=0,gait=0,moveBlend=0,lastMode='',stroke=0}
 setmetatable(self,{__index=Performance})
 self.root=self.rig.HumanoidRootPart;self.torso=self.rig.Torso;self.head=self.rig.Head
 self.rj=self.root:FindFirstChild('RootJoint') or self.torso:FindFirstChild('RootJoint')
 self.rootBase=self.rj.C0;self.neck=self.torso.Neck;self.neckBase=self.neck.C0
 self.right=self.torso['Right Shoulder'];self.left=self.torso['Left Shoulder']
 self.r0=self.right:GetAttribute('OriginalC0') or self.right.C0;self.l0=self.left:GetAttribute('OriginalC0') or self.left.C0
 self.rh=self.torso['Right Hip'];self.lh=self.torso['Left Hip']
 self.rh0=self.rh:GetAttribute('StandingC0') or self.rh.C0;self.lh0=self.lh:GetAttribute('StandingC0') or self.lh.C0
 self.box=self.rig.Carried_Box;self.joint=self.torso.CarryBoxJoint;self.carry=self.joint.C0
 self.face=self.head.CourierExpressions
 self.faceName='Happy';self.blinkAt=3.2;self.blinkStart=-10
 return self
end
function Performance:body(offset)
 self.rj.C0=offset*self.rootBase
 return self.root.CFrame*self.rj.C0*self.rj.C1:Inverse()
end
function Performance:hand(motor,base,target,torsoCF)
 local shoulder=(torsoCF*CFrame.new(base.Position)).Position
 local up=(shoulder-target).Unit
 local right=torsoCF.LookVector:Cross(up).Unit
 local back=right:Cross(up).Unit
 local cf=CFrame.fromMatrix(target+up,right,up,back)
 motor.C0=torsoCF:ToObjectSpace(cf)*motor.C1
end
function Performance:faceUpdate(name)
 local now=self.time
 if now>self.blinkAt then self.blinkStart=now;self.blinkAt=now+3.2+math.random()*2 end
 local blink=now-self.blinkStart<.14
 for _,frame in self.face:GetChildren() do
  if frame:IsA('Frame') then
   frame.Visible=frame.Name==name
   if frame.Visible then
    for _,eyeName in {'EyeL','EyeR'} do
     local eye=frame:FindFirstChild(eyeName)
     if eye then
      local h=eye:GetAttribute('OpenHeight')
      eye.Size=UDim2.fromOffset(eye.Size.X.Offset,blink and 4 or h)
      eye.Glint.Visible=not blink
     end
    end
   end
  end
 end
 self.rig:SetAttribute('Expression',name)
end
function Performance:hold(torsoCF,offset)
 self.joint.C0=offset*self.carry
 local boxCF=torsoCF*self.joint.C0
 self:hand(self.right,self.r0,(boxCF*CFrame.new(1.4,-.3,.05)).Position,torsoCF)
 self:hand(self.left,self.l0,(boxCF*CFrame.new(-1.4,-.3,.05)).Position,torsoCF)
end
function Performance:Step(mode,dt,boatCF,pickup)
 self.time+=dt
 if self.lastMode~=mode then self.lastMode=mode;self.phaseTime=0 end
 self.phaseTime+=dt
 local t=self.time;local elapsed=self.phaseTime
 local face='Happy'
 if mode=='Waiting' or mode=='Rowing' or mode=='Docking' or mode=='OarsReady' then
  local rowing=mode=='Rowing'
  self.stroke+=dt*3.2*(rowing and 1 or .25)
  local strength=rowing and math.min(elapsed*2,1) or (mode=='Docking' and math.max(1-elapsed*1.4,0) or 0)
  local sweep=math.sin(self.stroke)*.42*strength
  local recovery=math.max(0,math.cos(self.stroke))
  local cf=boatCF*CFrame.new(0,math.sin(t*2)*.035,0)*CFrame.Angles(math.sin(self.stroke)*.015*strength,0,math.sin(t*1.7)*.008)
  self.scene.Rowboat:PivotTo(cf)
  self.root.CFrame=cf*CFrame.new(0,2.6,.8)
  local torsoCF=self:body(CFrame.new(0,.025*math.cos(self.stroke)*strength,0)*CFrame.Angles(math.sin(self.stroke)*.10*strength,0,0))
  self.box:PivotTo(cf*CFrame.new(0,1.45,-2.6))
  pose(self.rh,self.rh0,math.rad(78));pose(self.lh,self.lh0,math.rad(78))
  local maxError=0
  for _,side in {-1,1} do
   local oar=self.scene.Rowboat[side==-1 and 'LeftOar' or 'RightOar']
   local oarCF=cf*CFrame.new(side*2.4,1.95,.1)*CFrame.Angles(0,side*sweep,side*(-.14+recovery*.25*strength))
   oar:PivotTo(oarCF)
   local grip=(oarCF*CFrame.new(-side*1.1,0,0)).Position
   local motor=side==1 and self.right or self.left
   self:hand(motor,side==1 and self.r0 or self.l0,grip,torsoCF)
   local predicted=(torsoCF*motor.C0*motor.C1:Inverse()*CFrame.new(0,-1,0)).Position
   maxError=math.max(maxError,(predicted-grip).Magnitude)
  end
  self.scene:SetAttribute('OarGripError',maxError)
  self.neck.C0=CFrame.Angles(-math.sin(self.stroke)*.055*strength,math.sin(t*.8)*.035,0)*self.neckBase
  face=rowing and 'Focused' or 'Happy'
 elseif mode=='Sitting' then
  local p=pickup
  local step=smooth(p/.38)
  local lower=smooth((p-.30)/.42)
  local settle=smooth((p-.65)/.35)
  local reach=smooth((p-.70)/.30)
  -- НАШЕ: исходная поза корня уже в осях лодки (клиент снял её на входе в Sitting):
  -- мировой sitFrom из статичного демо на плывущем плоте устаревал бы каждый кадр
  local from=self.sitFromRel or boatCF:ToObjectSpace(self.sitFrom)
  local standing=Vector3.new(0,3.05,.8)
  local position=from.Position:Lerp(standing,step)+Vector3.new(0,-.45*lower,0)
  self.root.CFrame=boatCF*CFrame.new(position)*from.Rotation:Lerp(CFrame.identity,step)
  local lean=.13*math.sin(lower*math.pi)*(1-settle)
  local targetBody=CFrame.Angles(lean,0,0)*self.rootBase
  self.rj.C0=self.sitBody:Lerp(targetBody,smooth(p/.25))
  local torsoCF=self.root.CFrame*self.rj.C0*self.rj.C1:Inverse()
  -- Two short backward steps, then gradual hip flexion onto the bench.
  local stride=math.sin(step*math.pi*2)*.18*(1-lower)
  pose(self.rh,self.rh0,math.rad(78)*lower+stride)
  pose(self.lh,self.lh0,math.rad(78)*lower-stride)
  self.rh.C0=self.sitRH:Lerp(self.rh.C0,smooth(p/.15))
  self.lh.C0=self.sitLH:Lerp(self.lh.C0,smooth(p/.15))
  self.box:PivotTo(boatCF*CFrame.new(0,1.45,-2.6))
  for _,side in {-1,1} do
   local name=side==-1 and 'LeftOar' or 'RightOar'
   local oar=self.scene.Rowboat[name]
   local rest=CFrame.new(side*2.4,1.95,.1)*CFrame.Angles(0,0,-side*.14)
   local oarCF=boatCF*self.sitOars[name]:Lerp(rest,reach)
   oar:PivotTo(oarCF)
   local motor=side==1 and self.right or self.left
   local base=side==1 and self.r0 or self.l0
   local grip=(oarCF*CFrame.new(-side*1.1,0,0)).Position
   -- Hands first balance beside the hips, then close on both oar grips.
   local brace=(torsoCF*CFrame.new(side*1.5,-.8,.1)).Position
   self:hand(motor,base,brace:Lerp(grip,reach),torsoCF)
   motor.C0=(side==1 and self.sitRight or self.sitLeft):Lerp(motor.C0,smooth(p/.25))
  end
  self.neck.C0=self.sitNeck:Lerp(CFrame.Angles(-.10*math.sin(lower*math.pi),0,0)*self.neckBase,smooth(p/.3))
  self.stroke=0
  face='Focused'
 elseif mode=='Pickup' then
  local p=pickup
  local stand=smooth(p/.18)
  local bend=self.emptyHanded and 0 or smooth((p-.18)/.22)*(1-smooth((p-.53)/.33))
  local lift=smooth((p-.5)/.38)
  self.root.CFrame=boatCF*CFrame.new(0,2.6+.45*stand,-.55*stand+.8*(1-stand))
  local effort=math.sin(t*28)*.008*bend
  local torsoCF=self:body(CFrame.new(0,-.33*bend,0)*CFrame.Angles(-.32*bend+effort,0,0))
  pose(self.rh,self.rh0,math.rad(78)*(1-stand)+.18*bend)
  pose(self.lh,self.lh0,math.rad(78)*(1-stand)+.15*bend)
  local from=boatCF*CFrame.new(0,1.45,-2.6)
  local to=torsoCF*self.carry
  local boxCF=from:Lerp(to,lift)*CFrame.Angles(math.sin(lift*math.pi)*-.07,0,effort)
  self.box:PivotTo(boxCF)
  local reach=self.emptyHanded and 0 or smooth((p-.16)/.25)
  for _,side in {-1,1} do
   local base=side==1 and self.r0 or self.l0
   local rest=(torsoCF*CFrame.new(side*1.5,-1,0)).Position
   local grip=(boxCF*CFrame.new(side*1.4,-.3,.05)).Position
   self:hand(side==1 and self.right or self.left,base,rest:Lerp(grip,reach),torsoCF)
  end
  self.neck.C0=CFrame.Angles(-.22*bend,0,0)*self.neckBase
  face=p>.4 and p<.88 and 'Effort' or 'Focused'
 else
  -- НАШЕ: корень заякорен и ставится клиентом по плоту, скорость меряет RaidCourierClient
  local moving=mode=='Walking' and (self.walkSpeed or 0) or 0
  if mode=='Disembarking' then moving=5 end
  local wanted=math.clamp(moving/7,0,1)
  self.moveBlend+=(wanted-self.moveBlend)*(1-math.exp(-dt*9))
  self.gait+=dt*(3+moving*.85)
  local gait=self.gait;local strength=self.moveBlend
  local bob=(math.cos(gait*2)*.045-.025)*strength
  local sway=math.sin(gait)*.035*strength
  local greeting=mode=='Delivered' and math.sin(math.min(elapsed/1.8,1)*math.pi) or 0
  local torsoCF=self:body(CFrame.new(sway,bob+.015*math.sin(t*2),0)*CFrame.Angles(.045*strength-greeting*.035,0,math.sin(gait)*.026*strength))
  pose(self.rh,self.rh0,math.sin(gait)*.40*strength)
  pose(self.lh,self.lh0,-math.sin(gait)*.40*strength)
  -- All cargo motion is shared by both hands, so the box never floats away from the grip.
  local cargoOffset=CFrame.new(0,.018*math.sin(t*2)+greeting*.1,-greeting*.10)*CFrame.Angles(.018*math.cos(gait)*strength,0,math.sin(gait)*.014*strength)
  if self.emptyHanded then
   -- Relaxed counter-swing after handing over the cargo.
   pose(self.right,self.r0,-math.sin(gait)*.28*strength,.06)
   pose(self.left,self.l0,math.sin(gait)*.28*strength,-.06)
  else
   self:hold(torsoCF,cargoOffset)
  end
  local nod=mode=='Delivered' and math.sin(math.min(elapsed/1.5,1)*math.pi*2)*math.exp(-elapsed)*.12 or 0
  self.neck.C0=CFrame.Angles(nod-.015*strength,math.sin(t*.7)*.025,0)*self.neckBase
  face=mode=='Delivered' and 'Happy' or (math.sin(t*.9)>.88 and 'Effort' or 'Focused')
 end
 self:faceUpdate(face)
end
return Performance
