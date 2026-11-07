-- Anatomical angles converted into official R6 joint bases; 30 Hz curved poses.
return function(clips)
 local rad=math.rad
 local bases={Torso=CFrame.Angles(-math.pi/2,0,math.pi),Head=CFrame.Angles(-math.pi/2,0,math.pi),R=CFrame.Angles(0,math.pi/2,0),L=CFrame.Angles(0,-math.pi/2,0)}
 local defaults={rx=8,ry=0,rz=4,lx=6,ly=0,lz=-5,hr=0,hy=0,hz=0,kr=0,kl=0,sr=0,sl=0,bx=0,by=0,bz=0,px=0,py=0,pz=0,lock=0}
 local function p(base,change)
  local out={}; for k,v in pairs(defaults) do out[k]=base and base[k] or v end
  for k,v in pairs(change or {}) do out[k]=v end; return out
 end
 local idle=p(nil,{})
 local carry=p(nil,{rx=57,ry=-10,rz=8,lx=48,ly=12,lz=-12,hy=-5})
 local seated=p(carry,{rx=56,lx=48,kr=82,kl=78,sr=5,sl=-6,bx=-3,hr=-6,lock=1})
 local function pack(v)
  local function tr(b,x,y,z,dx,dy,dz)
   local a=CFrame.new(dx or 0,dy or 0,dz or 0)*CFrame.Angles(rad(x),rad(y),rad(z))
   return {(b:Inverse()*a*b):GetComponents()}
  end
  local pose={Torso=tr(bases.Torso,v.bx,v.by,v.bz,v.px,v.py,v.pz),Head=tr(bases.Head,v.hr,v.hy,v.hz),
   ["Right Arm"]=tr(bases.R,v.rx,v.ry,v.rz),["Left Arm"]=tr(bases.L,v.lx,v.ly,v.lz),
   ["Right Leg"]=tr(bases.R,v.kr,0,v.sr),["Left Leg"]=tr(bases.L,v.kl,0,v.sl)}
  -- Keep the thighs supported by the cushion while the torso leans/twists.
  if v.lock>0 then
   local body=CFrame.new(v.px,v.py,v.pz)*CFrame.Angles(rad(v.bx),rad(v.by),rad(v.bz))
   for _,side in ipairs({{"Right Leg",1,bases.R},{"Left Leg",-1,bases.L}}) do
    local hip=CFrame.new(side[2],-1,0)*side[3]
    local original=CFrame.new(table.unpack(pose[side[1]]))
    local supported=hip:Inverse()*body:Inverse()*hip*original
    pose[side[1]]={original:Lerp(supported,math.clamp(v.lock,0,1)):GetComponents()}
   end
  end
  return pose
 end
 local function bake(name,loop,rows)
  local length=rows[#rows][1]; local keys={}
  local function sample(t)
   local i=1; while i<#rows-1 and rows[i+1][1]<t do i=i+1 end
   local a,b=rows[i],rows[i+1]; local prev=rows[math.max(1,i-1)]; local nxt=rows[math.min(#rows,i+2)]
   local span=b[1]-a[1]; local u=math.clamp((t-a[1])/span,0,1); local v={}
   for k in pairs(defaults) do
    local va,vb=a[2][k],b[2][k]
    local ma=(vb-prev[2][k])/math.max(.001,b[1]-prev[1]); local mb=(nxt[2][k]-va)/math.max(.001,nxt[1]-a[1])
    if i==1 or (va-prev[2][k])*(vb-va)<=0 then ma=0 end
    if i==#rows-1 or (vb-va)*(nxt[2][k]-vb)<=0 then mb=0 end
    v[k]=(2*u^3-3*u^2+1)*va+(u^3-2*u^2+u)*span*ma+(-2*u^3+3*u^2)*vb+(u^3-u^2)*span*mb
   end
   return pack(v),v
  end
  local frames=math.ceil(length*30)
  for i=0,frames do local t=i==frames and length or length*i/frames; local pose,anatomy=sample(t); keys[#keys+1]={t=t,p=pose,a=anatomy} end
  clips["Fish_"..name]={loop=loop,length=length,keys=keys}
 end
 bake("Idle",true,{{0,idle},{1.3,p(idle,{bx=-1.5,hy=9,rx=10,py=.018})},{2.8,p(idle,{hy=-6,bz=1.2,lx=9})},{4,idle}})
 local function walk(name,held)
  local rows={}; local base=held and carry or idle
  for i=0,8 do local phase=i*math.pi/4; local swing=math.cos(phase)
   rows[#rows+1]={i*.1,p(base,{kr=25*swing,kl=-25*swing,rx=held and 57+3*swing or -22*swing,lx=held and 48-4*swing or 22*swing,
    bx=-3,by=3*swing,bz=2.5*math.sin(phase),hy=-2*swing,py=.035*(1-math.cos(phase*2))})}
  end
  bake(name,true,rows)
 end
 walk("Walk",false); walk("CarryWalk",true)
 bake("TakeRod",false,{{0,idle},{.25,p(idle,{hy=18,hr=-12,by=6})},{.62,p(idle,{rx=48,ry=-15,bx=-13,by=12,lx=16,hr=-18})},
  {.95,p(carry,{rx=70,ry=-18,bx=-15,by=14,hr=-20,lx=26})},{1.2,p(carry,{rx=79,bx=3,by=-5,lx=40})},{1.65,carry}})
 bake("Sit",false,{{0,carry},{.25,p(carry,{bx=-15,hr=-14,kr=9,kl=6})},{.58,p(carry,{bx=-11,kr=62,kl=55,rx=67,lx=36})},
  {.95,p(seated,{bx=-8,kr=87,kl=84,rx=64})},{1.32,p(seated,{bx=3,hr=2,rx=52,lx=53})},{1.72,seated}})
 bake("Wait",true,{{0,seated},{1.2,p(seated,{rx=57,lx=50,bx=-2,hr=-4,py=.012})},
  {2.6,p(seated,{hy=13,hz=-3,kl=73,lx=45,by=2})},{3.7,p(seated,{hy=2,hr=-9,rx=58})},{5,seated}})
 bake("CheckLine",false,{{0,seated},{.45,p(seated,{hy=22,hr=-18,rx=61,lx=36,by=5})},
  {.95,p(seated,{lx=64,ly=20,rx=62,bx=-7,hr=-13})},{1.5,p(seated,{hy=-9,hz=3,lx=50})},{2.1,seated}})
 bake("Cast",false,{{0,seated},{.25,p(seated,{hr=5,bx=3,lx=58,rx=65})},
  {.6,p(seated,{rx=117,lx=83,bx=12,by=-12,hr=14,ry=-18,rz=13})},{.76,p(seated,{rx=123,lx=91,bx=8,by=-8,hr=10})},
  {.94,p(seated,{rx=38,lx=60,bx=-15,by=7,hr=-12,ry=4})},{1.14,p(seated,{rx=35,lx=54,bx=-12,by=5,hr=-8})},
  {1.48,p(seated,{rx=61,lx=48,bx=1,hr=0})},{1.9,seated}})
 bake("Bite",false,{{0,seated},{.15,p(seated,{rx=45,lx=45,bx=-10,hr=-16})},{.32,p(seated,{rx=44,lx=57,bx=-12,hr=-18,hy=3})},
  {.55,p(seated,{rx=88,lx=74,bx=12,hr=4,kr=75,kl=84})},{.76,p(seated,{rx=94,lx=78,bx=15,hr=6})},{1.05,p(seated,{rx=77,lx=65,bx=4,hr=-6})}})
 local sleepy=p(seated,{rx=48,lx=27,ry=-7,hr=-28,hy=-8,hz=6,bx=-9,by=2,bz=3})
 bake("DozeOff",false,{{0,seated},{.55,p(seated,{lx=62,hr=8,hy=-10,bx=3})},
  {1.05,p(seated,{lx=70,ly=25,lz=-21,hr=11,hz=-5})},{1.6,p(sleepy,{hr=-15,lx=40})},{2.4,sleepy}})
 bake("Sleep",true,{{0,sleepy},{2.5,p(sleepy,{bx=-7,hr=-25,rx=49,py=.018})},
  {5.5,p(sleepy,{bx=-10,hr=-34,hz=9,lx=24})},{6.3,p(sleepy,{hr=-18,bx=-6,hz=2,rx=53})},
  {7.8,p(sleepy,{hr=-30,bx=-10})},{10,p(sleepy,{hy=3,hz=-3,rx=47})},{12,sleepy}})
 bake("WakeBite",false,{{0,sleepy},{.18,p(sleepy,{rx=40,bx=-14,hr=-34})},
  {.38,p(seated,{rx=73,lx=63,hr=16,hz=-8,bx=8,hy=12})},
  {.72,p(seated,{rx=67,lx=59,hr=-13,hy=-15,bx=-6})},{1.12,p(seated,{rx=68,lx=61,hy=4,hr=-10})},{1.55,seated}})
 bake("WakeCalm",false,{{0,sleepy},{.5,p(seated,{rx=51,lx=61,ly=20,hr=-13,bx=-5})},
  {1,p(seated,{lx=67,ly=23,hr=7,hy=-10,bx=3})},{1.8,seated}})
 local brace=p(seated,{rx=78,lx=64,bx=4,hr=-8})
 bake("Reel",true,{{0,brace},{.28,p(brace,{lx=74,ly=23,lz=-18,rx=80,bx=6,by=-3})},{.52,p(brace,{lx=62,ly=10,lz=-24,rx=74,bx=1,hr=-11})},
  {.8,p(brace,{lx=51,ly=-4,lz=-10,rx=72,bx=-3,by=2})},{1.08,p(brace,{lx=60,ly=1,lz=-3,rx=77,bx=3})},{1.35,brace}})
 for _,side in ipairs({-1,1}) do
  bake(side==-1 and "TugLeft" or "TugRight",false,{{0,brace},{.3,p(brace,{rx=57,lx=55,bx=-12,by=side*16,bz=side*9,hy=side*18,hr=-17})},
   {.55,p(brace,{rx=53,lx=57,bx=-15,by=side*20,bz=side*12,hy=side*22})},{1.02,p(brace,{rx=98,lx=83,bx=16,by=-side*7,bz=-side*5,hr=7,hy=-side*4})},
   {1.32,p(brace,{rx=103,lx=85,bx=18,hr=9})},{1.9,brace}})
 end
 bake("Lift",false,{{0,brace},{.32,p(brace,{rx=66,lx=53,bx=-9,hr=-17})},{.66,p(brace,{rx=110,lx=70,bx=12,hr=13})},
  {.92,p(brace,{rx=122,lx=85,bx=9,hr=8,hy=-12})},{1.23,p(brace,{rx=105,lx=77,ly=18,bx=-3,hy=-17,hr=-13})},
  {1.62,p(seated,{rx=72,lx=58,hy=-12,hr=-13})},{1.95,p(seated,{rx=66,lx=52,hr=-8})}})
 bake("Miss",false,{{0,seated},{.35,p(seated,{rx=89,lx=62,bx=7,hr=9})},{.72,p(seated,{rx=94,lx=30,bx=9,hy=-17,hz=8,hr=1})},
  {1.2,p(seated,{rx=64,lx=22,bx=-7,hr=-20,hy=14})},{1.8,p(seated,{hy=-10,hz=-4,bx=-5,hr=-13})},{2.4,seated}})
 bake("Stand",false,{{0,seated},{.32,p(seated,{bx=-13,hr=-13,rx=69,lx=54})},{.7,p(carry,{kr=72,kl=68,bx=-12,hr=-8})},
  {1.08,p(carry,{kr=25,kl=20,bx=-10})},{1.38,p(carry,{kr=2,kl=-2,bx=-5})},{1.7,carry}})
 bake("PutFish",false,{{0,carry},{.3,p(carry,{hy=-20,hr=-18,by=-9})},{.72,p(carry,{lx=69,ly=18,bx=-17,by=-14,rx=69,hr=-23})},
  {1.02,p(carry,{lx=86,ly=12,bx=-23,by=-11,rx=75,hr=-26})},{1.3,p(carry,{lx=82,ly=8,bx=-18,by=-10,hr=-21})},
  {1.75,p(carry,{lx=14,hr=-6})},{2.1,p(carry,{lx=8})}})
 bake("ReturnRod",false,{{0,p(carry,{lx=8})},{.4,p(carry,{hy=15,hr=-14,bx=-9,by=8,lx=12})},
  {.95,p(carry,{rx=73,ry=-17,bx=-17,by=12,hr=-23,lx=16})},{1.15,p(carry,{rx=68,bx=-15,hr=-20,lx=12})},{1.8,idle}})
 bake("Celebrate",false,{{0,idle},{.25,p(idle,{hr=-6,hy=-14,lx=18})},{.7,p(idle,{lx=68,ly=22,lz=-20,hr=8,bx=3,by=-8})},
  {1.05,p(idle,{lx=54,hy=-12,hz=-5,bx=1})},{1.5,idle}})

 -- Three complete seated catches. All begin/end in Wait; event times live in FishingCatches.
 bake("CatchCalm",false,{{0,seated},
  {.35,p(seated,{hr=-16,rx=48,bx=-7,lx=44})},
  {.72,p(seated,{rx=83,lx=65,bx=7,hr=-2})},
  {1.12,p(seated,{rx=74,lx=55,ly=16,bx=2,hy=-4})},
  {1.65,p(seated,{rx=86,lx=73,ly=23,bx=6,hr=-7})},
  {2.1,p(seated,{rx=71,lx=49,ly=-5,bx=-4,hr=-12})},
  {2.65,p(seated,{rx=95,lx=64,bx=8,hr=1})},
  {3.05,p(seated,{rx=116,lx=72,bx=9,hy=-12,hr=7})},
  {3.55,p(seated,{rx=103,lx=82,ly=20,bx=-3,hy=-18,hr=-13})},
  {3.9,p(seated,{rx=81,lx=58,ly=10,hy=-15,hr=-16})},
  {4.35,p(seated,{rx=61,lx=50,hy=-8})},{4.8,seated}})
 bake("CatchStruggle",false,{{0,seated},
  {.22,p(seated,{rx=39,lx=46,bx=-14,hr=-20,by=7})},
  {.64,p(seated,{rx=99,lx=82,bx=16,hr=5,kr=77,kl=84})},
  {1.05,p(seated,{rx=84,lx=65,bx=8,hr=-9})},
  {1.5,p(seated,{rx=57,lx=58,bx=-12,by=-18,bz=-9,hy=-23})},
  {2.02,p(seated,{rx=99,lx=81,bx=15,by=8,bz=4,hr=5})},
  {2.65,p(seated,{rx=64,lx=56,bx=-10,by=20,bz=10,hy=24,hr=-16})},
  {3.25,p(seated,{rx=106,lx=84,bx=17,by=-6,bz=-4,hr=8})},
  {3.8,p(seated,{rx=86,lx=62,bx=3,hr=-13})},
  {4.15,p(seated,{rx=68,lx=55,bx=-8,hr=-18})},
  {4.65,p(seated,{rx=122,lx=79,bx=12,hr=12,hy=-10})},
  {5.25,p(seated,{rx=106,lx=86,ly=20,bx=-3,hy=-20,hr=-12})},
  {5.6,p(seated,{rx=80,lx=59,ly=10,bx=-6,hr=-18,hy=-15})},
  {6.05,p(seated,{rx=63,lx=51,bx=1,hr=-4})},{6.5,seated}})
 bake("CatchSurprise",false,{{0,seated},
  {.38,p(seated,{hy=36,hz=5,lx=24,by=7,hr=3})},
  {.62,p(seated,{rx=37,bx=-12,hy=17,hr=-18,lx=32})},
  {.88,p(seated,{rx=70,lx=72,ly=17,bx=-4,hy=-4,hr=9})},
  {1.12,p(seated,{rx=109,lx=85,bx=14,hr=12,hy=-5})},
  {1.65,p(seated,{rx=82,lx=61,ly=23,bx=1,hr=-12})},
  {2.2,p(seated,{rx=66,lx=48,bx=-8,hy=10,hr=-17})},
  {2.75,p(seated,{rx=117,lx=75,bx=12,hr=15,hy=-12})},
  {3.05,p(seated,{rx=116,lx=94,ly=30,lz=-20,bx=-4,hy=-25,hr=7})},
  {3.38,p(seated,{rx=102,lx=63,ly=-8,lz=-6,bx=3,hy=-9,hr=-5})},
  {3.85,p(seated,{rx=98,lx=88,ly=20,lz=-13,bx=-7,hy=-20,hr=-17})},
  {4.15,p(seated,{rx=77,lx=58,ly=10,hy=-18,hr=-18})},
  {4.65,p(seated,{rx=61,lx=51,hr=-5,hz=-4})},{5.2,seated}})
end
