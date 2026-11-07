--[[ ⚠️ СЕТКОМЁТ (пакет test/NetCapture_Import): авторский модуль, перенесён в
     Rojo как есть. Модели (Assets: Sheep, FlightNet, WrappedNet и Tool
     Pirate_Net_Launcher) живут в Studio внутри ReplicatedStorage/NetCapture —
     Rojo их не трогает (init.meta.json). Наши правки помечены «-- НАШЕ:». ]]
local Base=require(script.Parent.SheepAnimator)
local P={}
local function r(x,y,z)return CFrame.Angles(math.rad(x or 0),math.rad(y or 0),math.rad(z or 0))end
local function ease(t)t=math.clamp(t,0,1);return t*t*(3-2*t)end
function P.pose(state,t)
 if state=='Free' then return Base.pose('Graze',t) end
 if state=='Released' then
  local w=1-ease(t/1.15);local p=P.pose('Captured',0)
  for k,v in p do p[k]=CFrame.identity:Lerp(v,w) end
  p.Head=p.Head*r(0,math.sin(t*19)*8*w,0)
  return p
 end
 local w=state=='Catching' and ease(t/.65) or 1
 local active=state=='Captured' and math.sin(t*1.35)>.1
 local kick=active and math.sin(t*12)*8 or 0
 local carry=state=='Carried'
 local p={Torso=CFrame.new(0,-.70*w,0)*r(0,0,(active and math.sin(t*8)*3 or 0)*w),
  Head=r(9*w,(carry and 5 or 11)*math.sin(t*(carry and 1.8 or 4))*w,2*math.sin(t*5)*w),
  Jaw=r(active and -9*math.max(0,math.sin(t*8)) or 0),Tail=r(0,math.sin(t*8)*9*w)}
 for k,leg in {'LF','RF','LB','RB'} do
  p['UpperLeg'..leg]=r((84+kick*(k%2==0 and -1 or 1))*w)
  p['LowerLeg'..leg]=r((-146+kick)*w)
  p['Hoof'..leg]=r(12*w)
 end
 for _,s in {'Left','Right'} do
  p[s..'Ear']=r(-12*w,0,(s=='Left' and -1 or 1)*(14+math.sin(t*10)*4)*w)
  p[s..'Lid']=CFrame.new(0,-.025*w,0)
 end
 return p
end
return P
