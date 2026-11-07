--[[ ⚠️ СЕТКОМЁТ (пакет test/NetCapture_Import): авторский модуль, перенесён в
     Rojo как есть. Модели (Assets: Sheep, FlightNet, WrappedNet и Tool
     Pirate_Net_Launcher) живут в Studio внутри ReplicatedStorage/NetCapture —
     Rojo их не трогает (init.meta.json). Наши правки помечены «-- НАШЕ:». ]]
local A={}
local function r(x,y,z)return CFrame.Angles(math.rad(x),math.rad(y),math.rad(z))end
local function smooth(a,b,t)local v=math.clamp((t-a)/(b-a),0,1);return v*v*(3-2*v)end
function A.pose(state,t)
 local p={};local step=math.sin(t*7);local walking=state=='Walk'
 p.Torso=CFrame.new(0,walking and .025*math.cos(t*14) or .015*math.sin(t*2),0)*r(0,0,walking and step*1.2 or 0)
 p.Head=r(2*math.sin(t*1.3),state=='Look' and 18*math.sin(t) or 3*math.sin(t*.7),0)
 p.Jaw=r(-(state=='Bleat' and 17*math.max(0,math.sin(t*5)) or 0),0,0)
 for _,side in {'Left','Right'} do
  local sign=side=='Left' and -1 or 1
  p[side..'Ear']=r(4*math.sin(t*2+sign),0,sign*(4*math.sin(t*1.8)+12*math.exp(-((t%5-1.4)/.16)^2)))
  local blink=math.exp(-((t%3.8-1.7)/.075)^2)
  p[side..'Lid']=CFrame.new(0,-.31*blink,-.095*blink)
  p[side..'Eye']=CFrame.new(.018*math.sin(t*.7),0,0)
 end
 p.Tail=r(0,12*math.sin(t*3),5*math.sin(t*2))
 for _,leg in {'LF','RF','LB','RB'} do
  local phase=(leg=='LF' or leg=='RB') and 0 or math.pi
  local wave=math.sin(t*7+phase);local lift=math.max(0,wave)
  p['UpperLeg'..leg]=r(walking and wave*22 or 0,0,0)
  p['LowerLeg'..leg]=r(walking and -lift*26 or 0,0,0)
  p['Hoof'..leg]=r(walking and lift*10 or 0,0,0)
 end
 if state=='Graze' then
  -- Lower the chest while keeping the hindquarters high; fold front shins back.
  local kneel=smooth(0,1.3,t);local chew=smooth(1.3,1.9,t)
  p.Torso=CFrame.new(0,-.48*kneel,0)*r(-24*kneel,0,0)
  p.Head=r((-48+1.2*math.sin(t*3))*kneel,2*math.sin(t*.8)*chew,0)
  p.Jaw=CFrame.new(.018*math.sin(t*8)*chew,0,0)*r(-(7+5*math.sin(t*8))*chew,0,0)
  for _,leg in {'LF','RF'} do
   p['UpperLeg'..leg]=r(96*kneel,0,0)
   p['LowerLeg'..leg]=r(-162*kneel,0,0)
   p['Hoof'..leg]=CFrame.identity
  end
  for _,leg in {'LB','RB'} do
   p['UpperLeg'..leg]=r(42*kneel,0,0)
   p['LowerLeg'..leg]=r(-34*kneel,0,0)
   p['Hoof'..leg]=r(16*kneel,0,0)
  end
 elseif state=='Shear' then
  -- One reaction: startle, tense fidgets during clipping, then relax.
  local startle=math.exp(-((t-.30)/.16)^2)
  local tense=smooth(.45,.9,t)*(1-smooth(3.5,4.8,t))
  local shake=math.sin(t*25)*math.exp(-((t-3.85)/.28)^2)
  p.Torso=CFrame.new(0,-.065*tense+.035*startle,0)*r(2*startle,0,1.8*math.sin(t*8)*tense+2*shake)
  p.Head=r(13*startle+3*tense,16*math.sin(t*2.8)*tense+8*shake,-4*startle)
  p.Jaw=r(-11*startle-3*math.max(0,math.sin(t*9))*tense,0,0)
  for _,side in {'Left','Right'} do
   local sign=side=='Left' and -1 or 1
   p[side..'Ear']=r(-18*tense,sign*12*tense,sign*(24*startle+8*math.sin(t*12)*tense))
   local squint=.8*startle+.35*tense
   p[side..'Lid']=CFrame.new(0,-.31*squint,-.095*squint)
  end
  for _,leg in {'LF','RF','LB','RB'} do
   p['UpperLeg'..leg]=r(12*tense,0,0);p['LowerLeg'..leg]=r(-24*tense,0,0);p['Hoof'..leg]=r(12*tense,0,0)
  end
  p.Tail=r(-20*tense,20*shake,0)
 end
 return p
end
function A.step(motors,state,t,dt)
 local pose=A.pose(state,t)
 local alpha=dt and (1-math.exp(-14*dt)) or 1
 for name,motor in pairs(motors) do motor.Transform=motor.Transform:Lerp(pose[name] or CFrame.identity,alpha) end
end
return A
