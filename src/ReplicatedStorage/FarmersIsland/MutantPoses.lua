--[[ ⚠️ КОПИЯ МОДУЛЯ ИЗ ПАКЕТА Farmers_Island_Transfer (последняя версия из
     test/Farmers_Game_Water/Gameplay). Модель острова в Studio Rojo не правит,
     поэтому клиентские эффекты (позы и удар мутанта, свечение сундуков) читают
     модули отсюда — см. StarterPlayerScripts/FarmersIslandClient. ]]
local A={}
A.speed={Sweep=2.1,Backhand=2.1,Slam=1.85,Death=2.3,Alert=2.4,Hurt=1.8,Walk=1.55,Return=1.55,Idle=1.3}
local names={'LowerTorso','UpperTorso','Head','LeftUpperArm','LeftLowerArm','LeftHand','RightUpperArm','RightLowerArm','RightHand','LeftUpperLeg','LeftLowerLeg','LeftFoot','RightUpperLeg','RightLowerLeg','RightFoot'}
local function r(x,y,z)return CFrame.Angles(math.rad(x or 0),math.rad(y or 0),math.rad(z or 0))end
local function pose(d)
 local p={};for _,n in names do local a=d[n] or {};p[n]=CFrame.new(a[4] or 0,a[5] or 0,a[6] or 0)*r(a[1],a[2],a[3]) end;return p
end
local function key(t,d)return {t=t,p=pose(d)}end
-- Full-body authored phases; the dense clips are sampled at 60 Hz, not frame-stepped.
local clips={
 Sweep={
 key(0,{UpperTorso={-7},LeftUpperArm={9,0,-8},RightUpperArm={9,0,8}}),
 key(.20,{LowerTorso={-4,-9,3,0,-.07},UpperTorso={-3,-16,4},RightUpperArm={30,-28,27},RightLowerArm={65},LeftUpperArm={35,0,-16}}),
 key(.48,{LowerTorso={-6,-15,4,0,-.12},UpperTorso={4,-24,7},Head={-8,16},RightUpperArm={72,-58,52},RightLowerArm={85},LeftUpperArm={45,12,-16},LeftUpperLeg={12},RightUpperLeg={-10}}),
 key(.64,{LowerTorso={-8,-11,2,0,-.15},UpperTorso={0,-18,3},RightUpperArm={85,-38,48},RightLowerArm={57},LeftUpperArm={35,15,-20}}),
 key(.78,{LowerTorso={-9,16,-5,0,-.24,-.12},UpperTorso={-18,26,-9},Head={8,-13},RightUpperArm={88,52,-16},RightLowerArm={8},RightHand={-18},LeftUpperArm={5,25,-24},LeftUpperLeg={18},LeftLowerLeg={-8}}),
 key(.89,{LowerTorso={-8,21,-7,0,-.27,-.1},UpperTorso={-21,35,-10},RightUpperArm={80,76,-30},RightLowerArm={14},LeftUpperArm={-12,15,-24}}),
 key(1.05,{LowerTorso={-7,18,-4,0,-.23},UpperTorso={-17,27,-6},RightUpperArm={55,55,-15},RightLowerArm={25}}),
 key(1.28,{LowerTorso={-4,10,-2,0,-.14},UpperTorso={-12,15,-4},RightUpperArm={32,25,5},RightLowerArm={20}}),
 key(1.60,{LowerTorso={-2,3,0,0,-.04},UpperTorso={-8,5},RightUpperArm={15,8,8}}),
 key(1.85,{UpperTorso={-7},LeftUpperArm={9,0,-8},RightUpperArm={9,0,8}})},
 Backhand={
 key(0,{UpperTorso={-7}}),key(.24,{LowerTorso={-4,9,-3,0,-.06},UpperTorso={0,15,-5},LeftUpperArm={45,35,-20},LeftLowerArm={60},RightUpperArm={30,0,15}}),
 key(.55,{LowerTorso={-5,17,-5,0,-.16},UpperTorso={6,26,-9},Head={-6,-15},LeftUpperArm={85,65,-46},LeftLowerArm={87},RightUpperArm={45,-10,17}}),
 key(.72,{LowerTorso={-7,12,-3,0,-.2},UpperTorso={0,18},LeftUpperArm={95,45,-40},LeftLowerArm={44}}),
 key(.90,{LowerTorso={-10,-18,6,0,-.25,-.10},UpperTorso={-20,-30,10},LeftUpperArm={86,-58,18},LeftLowerArm={9},LeftHand={-20},RightUpperArm={0,-20,22},RightUpperLeg={20}}),
 key(1.04,{LowerTorso={-10,-24,7,0,-.28},UpperTorso={-23,-36,11},LeftUpperArm={69,-76,25},LeftLowerArm={16}}),
 key(1.26,{LowerTorso={-7,-17,5,0,-.22},UpperTorso={-16,-27,7},LeftUpperArm={48,-46,10},LeftLowerArm={30}}),
 key(1.6,{LowerTorso={-3,-6,2,0,-.1},UpperTorso={-11,-14},LeftUpperArm={20,-16,-5}}),
 key(1.92,{UpperTorso={-8,-3},LeftUpperArm={12,0,-8},RightUpperArm={9,0,8}}),key(2.15,{UpperTorso={-7},LeftUpperArm={9,0,-8},RightUpperArm={9,0,8}})},
 Slam={
 key(0,{UpperTorso={-7}}),
 key(.22,{LowerTorso={-7,0,0,0,-.16},UpperTorso={-10},LeftUpperLeg={-15},RightUpperLeg={-15},LeftLowerLeg={24},RightLowerLeg={24},LeftUpperArm={32,0,-16},RightUpperArm={32,0,16},LeftLowerArm={28},RightLowerArm={28}}),
 key(.52,{LowerTorso={-3,0,0,0,-.08},UpperTorso={4},Head={-15},LeftUpperArm={115,0,-20},RightUpperArm={115,0,20},LeftLowerArm={48},RightLowerArm={48}}),
 key(.82,{LowerTorso={5,0,0,0,.08},UpperTorso={10},Head={-16},LeftUpperArm={168,0,-10},RightUpperArm={168,0,10},LeftLowerArm={20},RightLowerArm={20}}),
 key(1.04,{LowerTorso={0,0,0,0,.02},UpperTorso={5},LeftUpperArm={170,0,-8},RightUpperArm={170,0,8},LeftLowerArm={12},RightLowerArm={12}}),
 key(1.15,{LowerTorso={-12,0,0,0,-.40,-.15},UpperTorso={-24},Head={15},LeftUpperArm={134,0,-12},RightUpperArm={134,0,12},LeftUpperLeg={-18},RightUpperLeg={-18},LeftLowerLeg={40},RightLowerLeg={40}}),
 key(1.25,{LowerTorso={-23,0,0,0,-.86,-.28},UpperTorso={-45},Head={24},LeftUpperArm={97,0,-13},RightUpperArm={97,0,13},LeftLowerArm={-4},RightLowerArm={-4},LeftUpperLeg={-28},RightUpperLeg={-28},LeftLowerLeg={57},RightLowerLeg={57},LeftFoot={-18},RightFoot={-18}}),
 key(1.34,{LowerTorso={-24,0,0,0,-.89,-.28},UpperTorso={-43},Head={25},LeftUpperArm={97,0,-13},RightUpperArm={97,0,13},LeftUpperLeg={-28},RightUpperLeg={-28},LeftLowerLeg={57},RightLowerLeg={57}}),
 key(1.50,{LowerTorso={-20,0,0,0,-.76,-.23},UpperTorso={-37},Head={20},LeftUpperArm={83,0,-18},RightUpperArm={83,0,18},LeftLowerArm={20},RightLowerArm={20},LeftUpperLeg={-24},RightUpperLeg={-24},LeftLowerLeg={47},RightLowerLeg={47}}),
 key(1.84,{LowerTorso={-14,0,0,0,-.50},UpperTorso={-25},Head={12},LeftUpperArm={45,0,-20},RightUpperArm={45,0,20},LeftUpperLeg={-16},RightUpperLeg={-16},LeftLowerLeg={32},RightLowerLeg={32}}),
 key(2.22,{LowerTorso={-6,0,0,0,-.20},UpperTorso={-15},LeftUpperArm={22,0,-12},RightUpperArm={22,0,12},LeftUpperLeg={-7},RightUpperLeg={-7},LeftLowerLeg={14},RightLowerLeg={14}}),
 key(2.8,{UpperTorso={-7},LeftUpperArm={9,0,-8},RightUpperArm={9,0,8}})},
}
A.timing={Sweep={duration=1.85,hit=.78,damage=24,range=5.8},Backhand={duration=2.15,hit=.90,damage=27,range=5.8},Slam={duration=2.8,hit=1.25,damage=35,range=7}}
for state,spec in pairs(A.timing) do spec.duration/=A.speed[state];spec.hit/=A.speed[state] end
clips.Death={
 key(0,{UpperTorso={-7},LeftUpperArm={9,0,-8},RightUpperArm={9,0,8}}),
 key(.18,{LowerTorso={4,0,-3,0,-.06},UpperTorso={12,-7,-5},Head={16,8},LeftUpperArm={30,12,-10},RightUpperArm={23,-12,18}}),
 key(.42,{LowerTorso={-4,4,-9,0,-.24},UpperTorso={-9,10,-6},Head={13,-9},LeftUpperArm={46,25,-20},LeftLowerArm={52},RightUpperArm={40,-25,24},RightLowerArm={46},LeftUpperLeg={24},LeftLowerLeg={-40},RightUpperLeg={17},RightLowerLeg={-28}}),
 key(.78,{LowerTorso={-10,7,-15,0,-.66},UpperTorso={-18,12,-10},Head={18,8},LeftUpperArm={52,45,-25},LeftLowerArm={80},RightUpperArm={57,-40,22},RightLowerArm={72},LeftUpperLeg={46},LeftLowerLeg={-87},RightUpperLeg={34},RightLowerLeg={-65},LeftFoot={30},RightFoot={25}}),
 key(1.10,{LowerTorso={-34.148,9.407,-21.037,-0.233,-1.351,-0.159},UpperTorso={-18.074,11.741,-8.444},Head={19.222,10.815,-7.037},LeftUpperArm={92.444,8.444,-22.222},LeftLowerArm={30.074},RightUpperArm={90.815,-33.778,1.111},RightLowerArm={74.0},LeftUpperLeg={49.556,0.0,-2.963},LeftLowerLeg={-89.259},RightUpperLeg={30.519,0.0,3.556},RightLowerLeg={-72.667},LeftFoot={35.407},RightFoot={35.222}}),
 key(1.46,{LowerTorso={-57.556,9.481,-26.963,-0.456,-1.752,-0.27},UpperTorso={-9.146,5.364,-2.924},Head={13.538,8.975,-3.314},LeftUpperArm={123.353,1.56,15.809},LeftLowerArm={40.458},RightUpperArm={112.934,-6.823,-22.047},RightLowerArm={68.06},LeftUpperLeg={34.815,0.0,-6.296},LeftLowerLeg={-67.037},RightUpperLeg={18.37,0.0,7.556},RightLowerLeg={-46.815},LeftFoot={25.741},RightFoot={25.333}}),
 key(1.72,{LowerTorso={-72.926,8.259,-22.037,-0.506,-1.895,-0.3},UpperTorso={-5.064,4.096,-0.263},Head={14.352,8.239,-0.478},LeftUpperArm={146.607,0.358,23.827},LeftLowerArm={40.526},RightUpperArm={133.647,-0.764,-23.995},RightLowerArm={59.223},LeftUpperLeg={24.926,0.0,-8.704},LeftLowerLeg={-48.815},RightUpperLeg={10.981,0.0,10.444},RightLowerLeg={-29.907},LeftFoot={18.5},RightFoot={16.407}}),
 key(1.86,{LowerTorso={-82.0,8.0,-14.0,-0.5,-1.9,-0.3},UpperTorso={-4.0,4.0,0.0},Head={15.0,8.0,0.0},LeftUpperArm={160.0,0.0,20.0},LeftLowerArm={35.0},RightUpperArm={145.0,0.0,-20.0},RightLowerArm={55.0},LeftUpperLeg={20.0,0,-10},LeftLowerLeg={-40.0},RightUpperLeg={8.0,0,12},RightLowerLeg={-22.0},LeftFoot={15.0},RightFoot={12.0}}),
}
local function sample(keys,t)
 if t<=keys[1].t then return keys[1].p end
 for i=2,#keys do if t<=keys[i].t then local a,b=keys[i-1],keys[i];local k=(t-a.t)/(b.t-a.t);k=k*k*(3-2*k);local p={};for _,n in names do p[n]=a.p[n]:Lerp(b.p[n],k) end;return p end end
 return keys[#keys].p
end
local function plantSlamFeet(p)
 local pelvis=CFrame.new(0,2.9,0)*p.LowerTorso
 local pitch=p.LowerTorso:ToOrientation()
 for _,side in {'Left','Right'} do
  local x=side=='Left' and -.61 or .61
  local hip=pelvis:PointToWorldSpace(Vector3.new(x,0,0))
  local delta=Vector3.new(x,.76,.03)-hip
  local l1,l2=1.22,.92
  local length=math.clamp(math.sqrt(delta.Y*delta.Y+delta.Z*delta.Z),.31,l1+l2-.001)
  local knee=-math.acos(math.clamp((length*length-l1*l1-l2*l2)/(2*l1*l2),-1,1))
  local thigh=math.atan2(-delta.Z,-delta.Y)-math.atan2(l2*math.sin(knee),l1+l2*math.cos(knee))
  p[side..'UpperLeg']=CFrame.Angles(thigh-pitch,0,0)
  p[side..'LowerLeg']=CFrame.Angles(knee,0,0)
  p[side..'Foot']=CFrame.Angles(-thigh-knee,0,0)
 end
 return p
end
local dense={}
for state,keys in pairs(clips) do local frames={};local duration=keys[#keys].t;for i=0,math.ceil(duration*60) do frames[i+1]=sample(keys,math.min(i/60,duration));if state=='Slam' then plantSlamFeet(frames[i+1]) end end;dense[state]=frames end
local function orientHands(p,state)
 local active=state=='Sweep' or state=='Backhand' or state=='Slam' or state=='Death'
 if active then p.LeftHand*=r(0,-90,0);p.RightHand*=r(0,90,0) end
 return p
end
-- Foot trajectories are measured in studs, not sinusoidal joint swings.
A.gaitStride={Walk=3.2,Return=3.2,Run=30.8}
-- One shared clock drives propulsion, weight transfer, arms and footstep audio.
A.runCycle=1.10
function A.runVelocity(t)
 local phase=t/A.runCycle
 return A.gaitStride.Run/A.runCycle*(1+.55*math.cos(4*math.pi*(phase-.40)))
end
-- Alternating contact / loading / push-off / recovery poses from the sprint reference.
local runLegKeys={
 {0,55,-30,0},{.16,43,-100,0},{.30,20,-70,0},
 {.42,-28,-28,-8},{.50,-38,-40,-12},{.64,0,-95,-7},
 {.76,60,-100,5},{.88,67,-60,4},{1,55,-30,0},
}
local function runLeg(f)
 for i=2,#runLegKeys do
  local a,b=runLegKeys[i-1],runLegKeys[i]
  if f<=b[1] then
   local k=(f-a[1])/(b[1]-a[1]);k=k*k*(3-2*k)
   return a[2]+(b[2]-a[2])*k,a[3]+(b[3]-a[3])*k,a[4]+(b[4]-a[4])*k
  end
 end
 return 55,-30,0
end
function A.referenceRun(phase)
 local f=phase%1;local twist=math.sin(f*math.pi*2)
 local load=math.cos(4*math.pi*(f-.10))
 local headLag=math.cos(4*math.pi*(f-.16))
 local p=pose({
  LowerTorso={-12-2*load,5*twist,2.2*twist,0,0,-.04},
  UpperTorso={-24-5*load,-12*twist,-3*twist},
  Head={24+4*headLag,7*math.sin((f-.04)*math.pi*2),1.5*twist},
 })
 local pelvis=CFrame.new(0,2.9,0)*p.LowerTorso
 local lowest=math.huge
 for _,side in {'Left','Right'} do
  local left=side=='Left';local legPhase=(f+(left and 0 or .5))%1
  local thigh,knee,ankle=runLeg(legPhase)
  p[side..'UpperLeg']=pelvis.Rotation:Inverse()*r(thigh,0,left and -1 or 1)
  p[side..'LowerLeg']=r(knee)
  p[side..'Foot']=(pelvis.Rotation*p[side..'UpperLeg']*p[side..'LowerLeg']):Inverse()*r(ankle)
  local cf=pelvis*CFrame.new(left and -.61 or .61,0,0)*p[side..'UpperLeg']*CFrame.new(0,-1.22,0)*p[side..'LowerLeg']*CFrame.new(0,-.92,0)*p[side..'Foot']
  for _,z in {-1.0,.42} do lowest=math.min(lowest,cf:PointToWorldSpace(Vector3.new(0,-.72,z)).Y) end
  -- Shoulder drives the fist from behind the hip to chest height; wrists stay straight.
  local drive=-math.cos((legPhase-.035)*math.pi*2)
  -- Hold each long reach; pass through the middle decisively after push-off.
  drive=math.sign(drive)*math.abs(drive)^.65
  p[side..'UpperArm']=r(5+57*drive,left and 4 or -4,left and -7 or 7)
  p[side..'LowerArm']=r(76+12*drive)
  p[side..'Hand']=r(0,0,0)
 end
 p.LowerTorso=CFrame.new(0,.008-lowest,0)*p.LowerTorso
 return p
end

function A.locomotion(state,phase)
 if state=='Run' then return A.referenceRun(phase) end
 local cycle=phase%1
 local stance=.68
 local stride=A.gaitStride[state];local reach=stride*stance*.5
 local wave=math.sin(cycle*math.pi*2)
 local settle=.5-.5*math.cos(4*math.pi*(cycle-.07))
 local lag=math.sin(2*math.pi*(cycle-.09))
 local ankleHeight=.725 -- flat boot sole sits .005 studs above the floor
 local feet={};local supportZ=0
 for _,side in {'Left','Right'} do
  local f=(cycle+(side=='Left' and 0 or .5))%1
  local z,lift
  if f<stance then
   z=-reach+stride*f;lift=0;supportZ=math.max(supportZ,math.abs(z))
  else
   local u=(f-stance)/(1-stance)
   local k=u*u*(3-2*u)
   z=reach*(1-2*k)
   -- Recover the heel behind the body, then extend low into the next contact.
   lift=(side=='Left' and .10 or .14)*math.sin(math.pi*u)^1.5
  end
  feet[side]={phase=f,z=z,lift=lift}
 end
 -- Soft knees and lateral weight transfer; foot IK keeps both soles grounded.
 local height=ankleHeight+math.sqrt(2.12^2-supportZ^2)-.13-.025*settle
 local yaw=2.5*wave
 local p=pose({
  LowerTorso={-8-1.2*settle,yaw,2*wave,-.075*wave,height-2.9},
  UpperTorso={-17-2*settle,-yaw*1.2,-1.5*lag},
  Head={7+1.8*math.sin(4*math.pi*(cycle-.12)),1.5*lag,1+1.2*lag},
 })
 local pelvis=CFrame.new(0,2.9,0)*p.LowerTorso
 for _,side in {'Left','Right'} do
  local left=side=='Left';local f=feet[side];local x=left and -.61 or .61
  local hip=pelvis:PointToWorldSpace(Vector3.new(x,0,0))
  local delta=pelvis:VectorToObjectSpace(Vector3.new(x,ankleHeight+f.lift,.03+f.z)-hip)
  local roll=math.atan2(delta.X,-delta.Y);local lateral=CFrame.Angles(0,0,roll)
  local localDelta=lateral:VectorToObjectSpace(delta)
  local l1,l2=1.22,.92
  local length=math.clamp(localDelta.Magnitude,.31,l1+l2-.00001)
  local knee=-math.acos(math.clamp((length^2-l1^2-l2^2)/(2*l1*l2),-1,1))
  local thigh=math.atan2(-localDelta.Z,-localDelta.Y)-math.atan2(l2*math.sin(knee),l1+l2*math.cos(knee))
  p[side..'UpperLeg']=lateral*CFrame.Angles(thigh,0,0)
  p[side..'LowerLeg']=CFrame.Angles(knee,0,0)
  p[side..'Foot']=(pelvis.Rotation*p[side..'UpperLeg']*p[side..'LowerLeg']):Inverse()
  -- Relaxed shoulders hang below the hunched chest. Unequal, delayed swings.
  local arm=-math.cos((f.phase-.08)*math.pi*2)
  p[side..'UpperArm']=CFrame.new(0,left and -.035 or -.06,0)*r(24+(left and 10 or 7)*arm,left and -3 or 2,left and -3 or 5)
  p[side..'LowerArm']=r((left and 17 or 24)-4*arm)
  p[side..'Hand']=r(-8-3*math.sin((f.phase-.15)*math.pi*2),0,left and -3 or 4)
 end
 return p
end

function A.pose(state,t,gaitPhase)
 if A.gaitStride[state] then return A.locomotion(state,gaitPhase or (state=='Run' and t/A.runCycle or t*2.8/A.gaitStride[state])) end
 t*=A.speed[state] or 1
 if dense[state] then local f=dense[state];local x=math.max(0,t)*60;local i=math.min(math.floor(x)+1,#f);local p={};for _,n in names do p[n]=f[i][n]:Lerp(f[math.min(i+1,#f)][n],x%1) end;return orientHands(p,state) end
 local b=math.sin(t*1.65);local d={LowerTorso={-2,0,.5*b,0,.012*b},UpperTorso={-7+b*.7},Head={4-b*.5},LeftUpperArm={9,0,-8},RightUpperArm={9,0,8}}
 if state=='Alert' then local k=math.sin(math.min(t/.8,1)*math.pi);d.UpperTorso={-7+9*k};d.Head={-12*k};d.LeftUpperArm={12,0,-17*k};d.RightUpperArm={12,0,17*k}
 elseif state=='Hurt' then d.UpperTorso={-7};d.LeftLowerArm={12};d.RightLowerArm={12}
 elseif state=='Death' then local k=math.clamp(t/1.5,0,1);k=k*k*(3-2*k);d.LowerTorso={0,0,-88*k,0,-1.65*k};d.UpperTorso={-10,0,-8*k};d.Head={15*k};d.LeftUpperArm={30*k};d.RightUpperArm={-25*k}
 end
 return pose(d)
end
-- Independent hit layer: stays visible during attacks and restarts on each damage event.
A.hurtDuration=.34
A.deathDuration=1.86/A.speed.Death
function A.hitPose(t,variant,strength)
 if t<0 or t>=A.hurtDuration then return {} end
 local k
 if t<.045 then k=1-(1-t/.045)^3
 elseif t<.085 then k=1
 else local x=(t-.085)/(A.hurtDuration-.085);k=1-x*x*(3-2*x) end
 k*=math.clamp(strength or 1,.65,1.35)
 local side=(variant or 1)%2==0 and -1 or 1
 local low=(variant or 1)%3==0
 return pose({
  LowerTorso={3*k,3*side*k,2*side*k,0,-.035*k,0},
  UpperTorso={(low and -19 or 17)*k,12*side*k,7*side*k},
  Head={(low and 16 or -23)*k,-15*side*k,-9*side*k},
  LeftUpperArm={(side==1 and 30 or 14)*k,-9*k,-13*k},
  RightUpperArm={(side==-1 and 30 or 14)*k,9*k,13*k},
  LeftLowerArm={23*k},RightLowerArm={27*k},
  LeftHand={-10*k},RightHand={-10*k},
 })
end
function A.face(state,t,hurt)
 t*=A.speed[state] or 1
 if state=='Death' then return 8 end
 if hurt or state=='Hurt' then return 6 end
 if state=='Slam' then return t<1.10 and 4 or (t<1.6 and 11 or 3) end
 if state=='Sweep' or state=='Backhand' then return t<.65 and 4 or (t<1.12 and 5 or 3) end
 if state=='Alert' then return 2 end
 if state=='Walk' or state=='Run' then return t%4.6<.1 and 1 or 3 end
 return t%4.8<.12 and 1 or 0
end
-- Jaw hinge shares the neck's coordinate system; negative pitch opens downward.
function A.jawAngle(state,t)
 if state=='Death' then return -22 end
 if state=='Hurt' then return -28 end
 if state=='Slam' or state=='Sweep' or state=='Backhand' then return -24-7*math.sin(math.min(t/.35,1)*math.pi) end
 if state=='Charge' or state=='Alert' or state=='ChargeWindup' then return -28 end
 if state=='Run' then return -18-3*math.sin(t*4*math.pi/A.runCycle) end
 if state=='Walk' or state=='Return' then return -11-2*math.sin(t*3.2) end
 return -7-2*math.sin(t*2)
end
return A
