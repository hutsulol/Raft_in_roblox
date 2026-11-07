local Data=require(script.Parent.CrawlerClips)
local Clips={}
for name,clip in pairs(Data) do
 local keys={}
 for _,k in ipairs(clip.keys) do
  local p={};for n,v in pairs(k.p) do
   local cf=CFrame.new(unpack(v))
   -- Keep the chin below the mouth cavity throughout the closing motion.
   if n=='Jaw' then local x,y,z=cf:ToOrientation();cf=CFrame.new(cf.Position)*CFrame.fromOrientation(x*.4,y,z) end
   p[n]=cf
  end
  table.insert(keys,{t=k.t,p=p})
 end
 Clips[name]={keys=keys,loop=clip.loop,length=keys[#keys].t,events=clip.events or {},holdLast=clip.holdLast}
end
-- Additional full-body Motor6D clips, sampled at the same 30 Hz as the base set.
local function extraClip(name,base,length,loop,pose,events)
 local keys={};local source=Clips[base]
 for i=0,math.floor(length*30+.5) do
  local t=i/30;local phase=t/length
  local k=source.keys[math.min(#source.keys,math.floor(phase*(#source.keys-1))+1)]
  local p=table.clone(k.p);pose(p,t,phase);table.insert(keys,{t=t,p=p})
 end
 if loop then keys[#keys].p=table.clone(keys[1].p) end
 Clips[name]={keys=keys,length=length,loop=loop,events=events or {}}
end
local function rot(x,y,z)return CFrame.Angles(math.rad(x),math.rad(y),math.rad(z))end
extraClip('FrenzyRun','Run',.3,true,function(p,t,u)
 p.UpperTorso=p.UpperTorso*rot(-10,0,math.sin(u*math.pi*2)*5)
 p.Head=p.Head*rot(8,0,0)
end)
extraClip('SpitAlt','Attack',1.5,false,function(p,t,u)
 local wind=math.sin(math.pi*math.clamp(t/.82,0,1))
 local cough=math.exp(-((t-.82)/.10)^2)
 p.UpperTorso=CFrame.new(0,.05*wind,0)*rot(-12*wind+17*cough,-17*wind,9*wind)
 p.Head=rot(14*wind-23*cough,12*wind,-12*wind)
 p.LeftUpperArm=p.LeftUpperArm*rot(-35*wind,12*wind,-22*wind)
 p.LeftLowerArm=p.LeftLowerArm*rot(48*wind,0,0)
 p.RightUpperArm=p.RightUpperArm*rot(8*wind,0,10*wind)
 p.LeftUpperLeg=p.LeftUpperLeg*rot(9*wind,0,0)
 p.RightLowerLeg=p.RightLowerLeg*rot(-12*wind,0,0)
 p.Jaw=rot(7*(1-cough),0,0)
 for _,side in ipairs({'Left','Right'}) do p[side..'Lid']=CFrame.new(0,-.10*cough,0) end
end,{{t=.82,name='Release'}})
-- Authored hand targets are solved with two-bone IK in the exported clips.
for name,clip in pairs(require(script.Parent.CrawlerClawClips)) do
 local keys={}
 for _,key in ipairs(clip.keys) do
  local pose={};for part,values in pairs(key.p) do pose[part]=CFrame.new(unpack(values)) end
  table.insert(keys,{t=key.t,p=pose})
 end
 Clips[name]={keys=keys,length=keys[#keys].t,loop=false,events=clip.events or {}}
end
local A={};A.__index=A
function A.sample(name,t)
 local c=assert(Clips[name],'Unknown crawler clip: '..tostring(name))
 t=c.loop and t%c.length or math.clamp(t,0,c.length)
 local i=math.min(math.floor(t*30)+1,#c.keys-1)
 local a,b=c.keys[i],c.keys[i+1];local u=math.clamp((t-a.t)/(b.t-a.t),0,1)
 local p={};for n,cf in pairs(a.p) do p[n]=cf:Lerp(b.p[n],u) end
 return p
end
function A.new(motors)return setmetatable({motors=motors,current={},from={},key='',fade=1,fadeTime=.12,finished=false,previousTime=-1,events={}},A) end
function A.length(name)return assert(Clips[name],'Unknown clip').length end
function A.isLoop(name)return assert(Clips[name],'Unknown clip').loop end
function A:play(name,fadeTime,speed)
 assert(Clips[name],'Unknown clip: '..tostring(name))
 self.name=name;self.time=0;self.speed=speed or 1;self.fadeTime=fadeTime or .12
 self.playId=(self.playId or 0)+1;self.finished=false
end
function A:update(dt)
 if not self.name then return end
 self.time+=dt*self.speed;self:step(self.name,self.time,dt,tostring(self.playId))
end
function A:stop()
 self.name=nil;self.finished=false;self.current={};self.from={};self.key='';self.previousTime=-1
 for _,m in pairs(self.motors) do m.Transform=CFrame.identity end
end
function A:step(name,t,dt,key)
 local clip=assert(Clips[name],'Unknown clip: '..tostring(name))
 if key~=self.key then self.from=table.clone(self.current);self.fade=0;self.key=key;self.previousTime=t<.25 and -.0001 or t end
 self.events={}
 local previous=self.previousTime
 if t>=previous then
  for _,event in ipairs(clip.events) do
   local cycle=clip.loop and math.max(0,math.floor(previous/clip.length)) or 0
   for lap=cycle,(clip.loop and math.floor(t/clip.length) or 0) do
    local at=lap*clip.length+event.t
    if at>previous and at<=t then table.insert(self.events,event.name) end
   end
  end
 end
 self.previousTime=t;self.finished=not clip.loop and t>=clip.length
 self.fade=self.fadeTime<=0 and 1 or math.min(1,self.fade+dt/self.fadeTime)
 local p=A.sample(name,t)
 for n,m in pairs(self.motors) do
  local cf=(self.from[n] or CFrame.identity):Lerp(p[n] or CFrame.identity,self.fade)
  m.Transform=cf;self.current[n]=cf
 end
end
-- Server forward kinematics: compute mouth without writing Motor6D.Transform.
function A.mouth(model,motors,name,t)
 local pose=A.sample(name,t);local cache={HumanoidRootPart=model.PrimaryPart.CFrame}
 local function world(n)
  if cache[n] then return cache[n] end
  local m=motors[n]
  local cf=world(m.Part0.Name)*m.C0*(pose[n] or CFrame.identity)*m.C1:Inverse()
  cache[n]=cf;return cf
 end
 return (world('Head')*model.Head.Mouth.CFrame).Position
end
return A
