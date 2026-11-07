local M = {}
local C = Color3.fromRGB
local function new(class, props, parent)
 local o=Instance.new(class); for k,v in pairs(props) do o[k]=v end; o.Parent=parent; return o
end
local function round(o,r) new('UICorner',{CornerRadius=UDim.new(r or 1,0)},o) return o end
local function shape(parent,name,x,y,w,h,color,rot)
 return round(new('Frame',{Name=name,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),BackgroundColor3=color,BorderSizePixel=0,Rotation=rot or 0},parent))
end
function M.Face(head)
 for _,o in ipairs(head:GetChildren()) do if o:IsA('Decal') or o.Name=='RoseFace' then o:Destroy() end end
 local f=new('SurfaceGui',{Name='RoseFace',Face=Enum.NormalId.Front,CanvasSize=Vector2.new(600,300),LightInfluence=.25,AlwaysOnTop=false,ZOffset=.015},head)
 local ink=C(49,22,37)
 for i,x in ipairs({222,374}) do
  local s=i==1 and -1 or 1
  shape(f,'Blush'..i,x,203,61,17,C(194,113,92)).BackgroundTransparency=.56
  local eye=shape(f,'Eye'..i,x,140,94,49,ink,-s*7); eye.ClipsDescendants=true
  shape(eye,'White',47,27,89,43,C(255,237,202))
  shape(eye,'Iris',48,25,33,44,C(153,76,24))
  shape(eye,'Pupil',48,24,17,35,ink)
  shape(eye,'Glint',42,15,10,11,C(255,255,236))
  shape(f,'Lash'..i,x+s*45,123,28,7,ink,-s*26)
  shape(f,'Brow'..i,x,99,86,12,ink,s*11)
 end
 shape(f,'Nose',302,187,18,6,C(171,99,67),-12)
 shape(f,'Mouth',300,230,70,13,C(109,30,51),-8)
 shape(f,'Teeth',300,228,53,4,C(255,228,197),-8)
 shape(f,'Lip',300,239,49,5,C(174,55,73),-8)
 return f
end
M.Expressions={'Confident','Happy','Skeptical','Angry','Surprised','Sad','Wink','Laugh','Sleep'}
function M.Expression(f,emotion,t,talking)
 -- Sleep: глаза закрыты (без моргания), брови расслаблены, рот приоткрыт и медленно «дышит»
 local vals={Sleep={0,-6,0,9},Confident={.78,11,-8,13},Happy={.86,-8,0,24},Skeptical={.55,20,-13,7},Angry={.58,28,0,8},Surprised={1.2,-15,0,38},Sad={.76,-23,7,8},Wink={.84,5,-10,16},Laugh={.2,-9,0,44}}
 local v=vals[emotion] or vals.Confident
 local phase=t%4.7
 local blink=phase<.20 and (1-.96*math.sin(math.pi*phase/.20)^2) or 1
 if emotion=='Sleep' then blink=1 end
 for i=1,2 do
  local eye=f['Eye'..i]; local open=v[1]*blink
  if emotion=='Wink' and i==2 then open=.07 end
  -- Rotated GUI frames do not reliably clip their children. Keep a stable
  -- eye container, and anchor every layer to the same proportional center.
  local height=math.max(4,49*open)
  eye.Rotation=0
  eye.Position=UDim2.fromOffset(i==1 and 222 or 374,140)
  eye.Size=UDim2.fromOffset(94,height)
  eye.ClipsDescendants=true
  local closed=open<.24
  for _,n in ipairs({'White','Iris','Pupil','Glint'}) do eye[n].Visible=not closed end
  eye.White.Position=UDim2.fromScale(.5,.5)
  eye.White.Size=UDim2.fromScale(.94,.84)
  eye.Iris.Position=UDim2.fromScale(.5,.5)
  eye.Iris.Size=UDim2.fromScale(.35,.88)
  eye.Pupil.Position=UDim2.fromScale(.5,.5)
  eye.Pupil.Size=UDim2.fromScale(.18,.72)
  eye.Glint.Position=UDim2.fromScale(.445,.32)
  eye.Glint.Size=UDim2.fromScale(.10,.22)
  local side=i==1 and -1 or 1
  f['Lash'..i].Position=UDim2.fromOffset((i==1 and 222 or 374)+side*45,140-height*.34)
  f['Lash'..i].Rotation=closed and 0 or -side*22
  f['Brow'..i].Rotation=(i==1 and 1 or -1)*v[2]
  f['Brow'..i].Position=UDim2.fromOffset(i==1 and 222 or 374,emotion=='Surprised' and 81 or (emotion=='Skeptical' and i==2 and 83 or 99))
 end
 local h=v[4]; local w=emotion=='Surprised' and 34 or 70
 if talking then local syll=math.abs(math.sin(t*12)+.45*math.sin(t*21)); h=9+syll*25; w=48+19*math.sin(t*7)^2 end
 if emotion=='Sleep' and not talking then local breath=.5+.5*math.sin(t*1.4); h=7+breath*7; w=30+breath*8 end
 f.Mouth.Size=UDim2.fromOffset(w,h); f.Mouth.Rotation=v[3]
 f.Teeth.Size=UDim2.fromOffset(w*.73,math.min(6,h*.25)); f.Teeth.Position=UDim2.fromOffset(300,230-h*.31); f.Teeth.Rotation=v[3]
 f.Teeth.Visible=h>15 and emotion~='Surprised'
 f.Lip.Position=UDim2.fromOffset(300,232+h*.48); f.Lip.Rotation=v[3]
end
function M.Build()
 local model=workspace:FindFirstChild('Captain Rose'); assert(model,'Captain Rose missing')
 if model:GetAttribute('RoseReady') then return model end
 for _,o in ipairs(workspace:GetChildren()) do if o.Name=='Baseplate' or o:IsA('SpawnLocation') then o:Destroy() end end
 local root=model.HumanoidRootPart
 for _,o in ipairs(model:GetDescendants()) do
  if o:IsA('BasePart') then o.Anchored=false; o.CanCollide=false; o.Massless=true end
  if o:IsA('Motor6D') or o:IsA('Snap') or (o:IsA('Weld') and not o.Part1) or o:IsA('Script') or o:IsA('LocalScript') then o:Destroy() end
 end
 root.Anchored=true; root.CFrame=CFrame.new(0,3.7,0); root.Transparency=1
 local function joint(name,p0,p1,c0,c1)
  p1.CFrame=p0.CFrame*c0*c1:Inverse()
  return new('Motor6D',{Name=name,Part0=p0,Part1=p1,C0=c0,C1=c1},p0)
 end
 joint('RootJoint',root,model.Torso,CFrame.new(),CFrame.new())
 joint('Neck',model.Torso,model.Head,CFrame.new(0,1,0),CFrame.new(0,-.5,0))
 joint('Right Shoulder',model.Torso,model['Right Arm'],CFrame.new(1.5,.7,0),CFrame.new(0,.7,0))
 joint('Left Shoulder',model.Torso,model['Left Arm'],CFrame.new(-1.5,.7,0),CFrame.new(0,.7,0))
 joint('Right Hip',model.Torso,model['Right Leg'],CFrame.new(.5,-1,0),CFrame.new(0,1,0))
 joint('Left Hip',model.Torso,model['Left Leg'],CFrame.new(-.5,-1,0),CFrame.new(0,1,0))
 for _,o in ipairs(model:GetDescendants()) do if o:IsA('Weld') and o.Part0 and o.Part1 then o.Part1.CFrame=o.Part0.CFrame*o.C0*o.C1:Inverse() end end
 model.Humanoid.DisplayDistanceType=Enum.HumanoidDisplayDistanceType.None
 model.PrimaryPart=root; M.Face(model.Head)
 local stage=new('Model',{Name='Captain Rose • Portrait Stage'},workspace)
 local function part(n,size,cf,col,mat)
  return new('Part',{Name=n,Size=size,CFrame=cf,Color=col,Material=mat or Enum.Material.Wood,Anchored=true,TopSurface=Enum.SurfaceType.Smooth,BottomSurface=Enum.SurfaceType.Smooth},stage)
 end
 part('Dark sea',Vector3.new(600,1,600),CFrame.new(0,-2,0),C(13,45,57),Enum.Material.SmoothPlastic)
 for i=-8,8 do part('Deck plank',Vector3.new(1.18,.35,18),CFrame.new(i*1.2,.42,1),C(63+i%3*5,40+i%3*4,39)) end
 local pl=part('Portrait pedestal',Vector3.new(.28,7,7),CFrame.new(0,.68,0)*CFrame.Angles(0,0,math.pi/2),C(89,44,65),Enum.Material.Marble);pl.Shape=Enum.PartType.Cylinder
 for i=-5,5 do
  part('Gold deck inlay',Vector3.new(.035,.03,15),CFrame.new(i*1.8,.61,1),C(168,120,54),Enum.Material.Metal)
 end
 for _,x in ipairs({-8,8}) do
  for _,z in ipairs({-5,5}) do
   part('Rail pillar',Vector3.new(.35,3,.35),CFrame.new(x,1.9,z),C(55,32,37))
   part('Lantern',Vector3.new(.55,.65,.55),CFrame.new(x,3.6,z),C(255,173,77),Enum.Material.Neon)
  end
  part('Rail',Vector3.new(.24,.24,14),CFrame.new(x,2.9,0),C(124,79,43))
 end
 for _,x in ipairs({-5.5,5.5}) do
  part('Banner mast',Vector3.new(.15,8,.15),CFrame.new(x,4.6,5),C(174,127,53),Enum.Material.Metal)
  part('Captain banner',Vector3.new(2.5,4,.12),CFrame.new(x,6.4,5),C(58,19,53),Enum.Material.Fabric)
  part('Banner gold',Vector3.new(2.5,.13,.14),CFrame.new(x,4.4,5),C(217,161,57),Enum.Material.Metal)
 end
 local lighting=game:GetService('Lighting');lighting.ClockTime=17.8;lighting.Brightness=3;lighting.Ambient=C(138,114,144);lighting.OutdoorAmbient=C(123,139,156)
 local cam=workspace.CurrentCamera;cam.CFrame=CFrame.lookAt(Vector3.new(0,5.2,-15),Vector3.new(0,3.8,0));cam.FieldOfView=36
 model:SetAttribute('RoseReady',true)
 return model
end
M.Clips={{'Signature Idle',12,'Confident'},{'Hat Salute',4,'Wink'},{'Sword Flourish',5,'Confident'},{'Treasure Laugh',4,'Laugh'},{'Inspect Blade',6,'Skeptical'},{'Victory',4,'Happy'},{'Talk • Story',7,'Happy'},{'Talk • Command',5,'Angry'},{'Talk • Secret',6,'Skeptical'},{'Battle Ready',5,'Angry'},{'Surprise',3,'Surprised'},{'Courtly Bow',5,'Confident'}}
local function rot(x,y,z) return CFrame.Angles(math.rad(x),math.rad(y),math.rad(z)) end
local function pulse(t,a,b) if t<a or t>b then return 0 end return math.sin((t-a)/(b-a)*math.pi)^2 end
function M.Pose(name,t)
 local a={};local breath=math.sin(t*2.1)
 a.RootJoint=CFrame.new(0,.025*breath,0)*rot(0,2*math.sin(t*.7),-2)
 a.Neck=rot(-2+breath,4*math.sin(t*.8),3)
 a['Right Shoulder']=rot(-8,0,9);a['Left Shoulder']=rot(-12,0,-14)
 a['Right Hip']=rot(0,0,2);a['Left Hip']=rot(-3,0,-3)
 if name=='Signature Idle' then
  local salute=pulse(t,4,7);local blade=pulse(t,8,11)
  a['Left Shoulder']=rot(-18-132*salute,-15*salute,-17-13*salute)
  a['Right Shoulder']=rot(-12-45*blade,-38*blade,14+24*blade)
  a.Neck=rot(-2-10*salute,12*math.sin(t*.6)-20*blade,5-9*salute)
  a.RootJoint=CFrame.new(.035*math.sin(t*.6),.025*breath,0)*rot(0,5*math.sin(t*.6),-3+4*blade)
 elseif name=='Hat Salute' then local p=pulse(t,0,4); a['Left Shoulder']=rot(-155*p,-15*p,-25*p);a.Neck=rot(-13*p,9*p,6*p)
 elseif name=='Sword Flourish' then local p=pulse(t,0,5);a['Right Shoulder']=rot(-70*p,math.sin(t*3)*65*p,55*p);a.RootJoint=rot(0,25*math.sin(t*1.4)*p,-6*p);a['Left Shoulder']=rot(15*p,0,-30*p)
 elseif name=='Treasure Laugh' then local p=pulse(t,0,4);a.Neck=rot(-15*p+4*math.sin(t*12)*p,0,3);a.RootJoint=CFrame.new(0,.07*math.abs(math.sin(t*8))*p,0)*rot(6*p,0,-3);a['Left Shoulder']=rot(-55*p,-35*p,-20*p)
 elseif name=='Inspect Blade' then local p=pulse(t,0,6);a['Right Shoulder']=rot(-80*p,-38*p,15*p);a.Neck=rot(12*p,-32*p,-8*p);a['Left Shoulder']=rot(-10,0,-20)
 elseif name=='Victory' then local p=pulse(t,0,4);a['Right Shoulder']=rot(-165*p,0,22*p);a['Left Shoulder']=rot(-110*p,0,-45*p);a.Neck=rot(-15*p,0,-8*p)
 elseif string.find(name,'Talk') then
  local beat=math.sin(t*3.3);local p=.5+.5*math.sin(t*1.7)
  a.Neck=rot(3*beat,8*math.sin(t),3*math.sin(t*1.8))
  a['Left Shoulder']=rot(-40-35*p,-15,-25-10*beat)
  a['Right Shoulder']=rot(-10-12*p,6*beat,12)
  if name=='Talk • Command' then a['Left Shoulder']=rot(-80-18*p,0,-12);a.RootJoint=rot(8,0,-2) end
  if name=='Talk • Secret' then a['Left Shoulder']=rot(-130,-20,-20);a.RootJoint=rot(7,15,-6);a.Neck=rot(0,-16,8) end
 elseif name=='Battle Ready' then local p=pulse(t,0,5);a.RootJoint=rot(8*p,-25*p,0);a['Right Shoulder']=rot(-65*p,-40*p,30*p);a['Left Shoulder']=rot(-40*p,0,-30*p);a['Left Hip']=rot(-15*p,0,-8*p)
 elseif name=='Surprise' then local p=pulse(t,0,3);a.RootJoint=rot(-12*p,0,0);a['Left Shoulder']=rot(-65*p,0,-50*p);a['Right Shoulder']=rot(-30*p,0,38*p);a.Neck=rot(-8*p,0,0)
 elseif name=='Courtly Bow' then local p=pulse(t,0,5);a.RootJoint=rot(32*p,0,-3*p);a.Neck=rot(12*p,0,0);a['Left Shoulder']=rot(-65*p,-45*p,-35*p);a['Right Shoulder']=rot(15*p,0,30*p) end
 for _,n in ipairs({"Left Shoulder","Right Shoulder"}) do local x,y,z=a[n]:ToEulerAnglesXYZ();a[n]=CFrame.Angles(-x,y,z) end; return a end
function M.ExportClips(model)
 local old=game.ReplicatedStorage:FindFirstChild('Rose_Animation_Clips'); if old then old:Destroy() end
 local folder=new('Folder',{Name='Rose_Animation_Clips'},game.ReplicatedStorage)
 for _,clip in ipairs(M.Clips) do
  local seq=new('KeyframeSequence',{Name=clip[1],Loop=true,Priority=Enum.AnimationPriority.Action},folder)
  for index=0,clip[2]*12 do
   local t=index/12;local pose=M.Pose(clip[1],t);local k=new('Keyframe',{Time=t},seq)
   local root=new('Pose',{Name='HumanoidRootPart',CFrame=CFrame.new()},k)
   local torso=new('Pose',{Name='Torso',CFrame=pose.RootJoint},root)
   for motor,part in pairs({Neck='Head',['Left Shoulder']='Left Arm',['Right Shoulder']='Right Arm',['Left Hip']='Left Leg',['Right Hip']='Right Leg'}) do new('Pose',{Name=part,CFrame=pose[motor]},torso) end
  end
 end
end
return M
