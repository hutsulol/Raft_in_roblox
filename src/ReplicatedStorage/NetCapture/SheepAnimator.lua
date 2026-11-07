--[[ ⚠️ СЕТКОМЁТ (пакет test/NetCapture_Import): авторский модуль, перенесён в
     Rojo как есть. Модели (Assets: Sheep, FlightNet, WrappedNet и Tool
     Pirate_Net_Launcher) живут в Studio внутри ReplicatedStorage/NetCapture —
     Rojo их не трогает (init.meta.json). Наши правки помечены «-- НАШЕ:». ]]
local Config=require(script.Parent.SheepAnimationConfig)
local Old=require(script.Parent.SheepLegacyPoses)
local A={}
local function r(x,y,z)return CFrame.Angles(math.rad(x),math.rad(y or 0),math.rad(z or 0))end
local function ease(v)v=math.clamp(v,0,1);return v*v*(3-2*v)end
local function rest(p,w)
 p.Torso=CFrame.new(0,-.94*w,0)
 p.Head=r(5*w,0,0)
 for _,leg in {'LF','RF','LB','RB'} do
  p['UpperLeg'..leg]=r(100*w);p['LowerLeg'..leg]=r(-190*w);p['Hoof'..leg]=r(0*w)
 end
end
function A.pose(name,t)
 name=name:match('^Sheep_') and name or 'Sheep_'..name
 local cfg=assert(Config[name],'Unknown sheep animation '..name)
 local u=cfg.Looped and (t%cfg.Duration)/cfg.Duration or math.clamp(t/cfg.Duration,0,1)
 local q=u*2*math.pi;local envelope=math.sin(math.pi*u)^2
 local p={Torso=CFrame.new(0,.008*math.sin(q),0),Head=r(1.5*math.sin(q)),Jaw=CFrame.identity,Tail=r(0,4*math.sin(q))}
 for _,side in {'Left','Right'} do
  local sign=side=='Left' and -1 or 1
  p[side..'Ear']=r(2*math.sin(q),0,sign*3*math.sin(q))
  local blink=math.max(0,1-math.abs(u-.64)/.035);blink=ease(blink)
  p[side..'Lid']=CFrame.new(0,-.31*blink,-.095*blink)
 end
 if name=='Sheep_Walk' or name=='Sheep_Trot' or name=='Sheep_TurnLeft' or name=='Sheep_TurnRight' then
  local turn=name:find('Turn')~=nil;local trot=name=='Sheep_Trot';local strength=turn and envelope or 1
  p.Torso=CFrame.new(0,(trot and .04 or .015)*(1-math.cos(q*2)),0)*r(0,0,math.sin(q)*strength)
  p.Head=r(-2*math.sin(q)*strength,turn and (name=='Sheep_TurnLeft' and 12 or -12)*envelope or 0)
  for _,leg in {'LF','RF','LB','RB'} do
   local phase
   if trot then phase=(leg=='LF' or leg=='RB') and 0 or math.pi else phase=({LF=0,LB=math.pi*.5,RF=math.pi,RB=math.pi*1.5})[leg] end
   local wave=math.sin(q+phase);local lift=math.max(0,wave)
   local amp=turn and 10 or trot and 30 or 21
   p['UpperLeg'..leg]=r(wave*amp*strength)
   p['LowerLeg'..leg]=r(-lift*28*strength)
   p['Hoof'..leg]=r(lift*12*strength)
  end
 elseif name=='Sheep_Graze' then
  p=Old.pose('Graze',2)
  p.Head=r(-48+math.sin(q*2),2*math.sin(q))
  p.Jaw=CFrame.new(.018*math.sin(q*5),0,0)*r(-7-5*math.sin(q*5))
  for _,side in {'Left','Right'} do p[side..'Ear']=r(2*math.sin(q));p[side..'Lid']=CFrame.identity end
 elseif name=='Sheep_Drink' then
  -- НАШЕ: голова опущена к воде (как на выпасе), челюсть лакает мелко и часто, уши прижаты
  p=Old.pose('Graze',2)
  p.Head=r(-44+1.5*math.sin(q*6),1.5*math.sin(q))
  p.Jaw=CFrame.new(0,0,-.01*math.max(0,math.sin(q*8)))*r(-4-6*math.max(0,math.sin(q*8)))
  for _,side in {'Left','Right'} do p[side..'Ear']=r(-6,0,(side=='Left' and -1 or 1)*4);p[side..'Lid']=CFrame.new(0,-.1,-.04) end
  p.Tail=r(0,5*math.sin(q*2))
 elseif name=='Sheep_Eat' or name=='Sheep_Drink' then
  local drink=name=='Sheep_Drink'
  p.Head=r((drink and -17 or -5)+math.sin(q*2),0,0)
  p.Jaw=CFrame.new(drink and 0 or .016*math.sin(q*4),0,0)*r(-(drink and 2 or 6)-(drink and 1 or 4)*math.sin(q*4))
 elseif name=='Sheep_LieDown' then rest(p,ease(u))
 elseif name=='Sheep_StandUp' then rest(p,1-ease(u))
 elseif name=='Sheep_Rest' then rest(p,1);p.Torso=p.Torso*CFrame.new(0,.007*math.sin(q),0);p.Head=r(5+math.sin(q))
 elseif name=='Sheep_Look' then p.Head=r(0,25*envelope,2*envelope)
 elseif name=='Sheep_Bleat' then p.Head=r(12*envelope);p.Jaw=r(-19*envelope)
 elseif name=='Sheep_PetReaction' then
  p.Head=CFrame.new(0,.035*envelope,-.10*envelope)*r(9*envelope,12*envelope,-5*envelope)
  for _,side in {'Left','Right'} do p[side..'Ear']=r(-7*envelope,0,4*math.sin(q)*envelope);p[side..'Lid']=CFrame.new(0,-.18*envelope,-.06*envelope) end
 elseif name=='Sheep_ShearIdle' then
  p.Torso=CFrame.identity;p.Head=r(.7*math.sin(q));p.Tail=r(0,2*math.sin(q))
 elseif name=='Sheep_Startled' then
  local v=math.sin(math.pi*ease(u))^2
  p.Torso=CFrame.identity;p.Head=r(17*v,0,-3*v);p.Jaw=r(-6*v)
  for _,side in {'Left','Right'} do p[side..'Ear']=r(-18*v,0,(side=='Left' and -1 or 1)*20*v) end
 end
 return p
end
function A.step(motors,state,t,dt)
 local p=A.pose(state,t);local alpha=dt and (1-math.exp(-14*dt)) or 1
 for name,motor in pairs(motors) do motor.Transform=motor.Transform:Lerp(p[name] or CFrame.identity,alpha) end
end
return A
