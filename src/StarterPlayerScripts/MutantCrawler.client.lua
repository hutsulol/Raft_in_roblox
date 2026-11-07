local RS=game:GetService('ReplicatedStorage');local Run=game:GetService('RunService')
local Pack=RS:WaitForChild('MutantCrawlerPack');local A=require(Pack.CrawlerAnimator)
local Audio=require(Pack.CrawlerAudio);Audio.preload()
local Data=require(Pack.CrawlerRigData);local FX=require(Pack.CrawlerFX)
local live=workspace:WaitForChild('MutantCrawlers')
local effects=Instance.new('Folder');effects.Name='CrawlerLocalFX';effects.Parent=workspace
local tracked,shots={},{}
local function upright(cf)
 local look=Vector3.new(cf.LookVector.X,0,cf.LookVector.Z)
 if look.Magnitude<.001 then look=Vector3.new(0,0,-1) end
 return CFrame.lookAt(cf.Position,cf.Position+look.Unit)
end
local function discover(m)
 if not m:IsA('Model') then return end
 tracked[m]={retry=0,charge=0}
end
for _,m in ipairs(live:GetChildren()) do discover(m) end
live.ChildAdded:Connect(discover)
Audio.bind(Pack.CrawlerEvent,effects)
FX.bind(Pack.CrawlerEvent,effects,Pack:FindFirstChild('AcidSpit',true))
Run.PreSimulation:Connect(function(dt)
 local now=workspace:GetServerTimeNow()
 for m,s in pairs(tracked) do
  if not m:IsDescendantOf(live) then tracked[m]=nil;continue end
  if not s.anim and now>=s.retry then
   s.retry=now+.25;local motors={};local count=0
   for _,v in ipairs(m:GetDescendants()) do
    if v:IsA('Motor6D') and v.Part1 and Data[v.Part1.Name] then motors[v.Part1.Name]=v;count+=1 end
   end
   local expected=0;for _ in pairs(Data) do expected+=1 end
   if count==expected then
    -- EvaluateStateMachine is local: disable the NPC's client physics as well.
    local hum=m:FindFirstChildOfClass('Humanoid');if hum then
     hum.EvaluateStateMachine=false
     hum.DisplayDistanceType=Enum.HumanoidDisplayDistanceType.None
     hum.NameDisplayDistance=0
    end
    for _,p in m:GetDescendants() do
     if p:IsA('BasePart') then p.CanCollide=false;p.CanTouch=false end
    end
    s.anim=A.new(motors);s.visual=m.PrimaryPart.CFrame
   end
  end
  local state=m:GetAttribute('CrawlerState')
  if s.anim and state then
   local name,stamp=state:match('^(%w+)|(.+)$');local start=tonumber(stamp)
   if name and start then
    local elapsed=math.max(0,now-start);s.anim:step(name,elapsed,dt,state);Audio.step(m,s,name,elapsed,state,s.anim.events)
    -- Smooth replicated root steps visually without moving the authoritative hitbox.
    local root=m.PrimaryPart
    if (root.Position-s.visual.Position).Magnitude>12 then s.visual=root.CFrame end
    local latchId=m:GetAttribute('LatchTargetUserId');local offset=m:GetAttribute('LatchOffset')
    local player=latchId and game:GetService('Players'):GetPlayerByUserId(latchId)
    local target=player and player.Character and player.Character:FindFirstChild('HumanoidRootPart')
    if name=='Scratch' and target and offset then s.visual=upright(target.CFrame)*offset
    else s.visual=upright(s.visual):Lerp(upright(root.CFrame),1-math.exp(-dt*22)) end
    local motor=s.anim.motors.LowerTorso
    motor.Transform=motor.C0:Inverse()*root.CFrame:ToObjectSpace(s.visual)*motor.C0*motor.Transform
    local reaction,stamp=(m:GetAttribute('Reaction') or ''):match('^(%w+)|(.+)$')
    local recent=stamp and now-tonumber(stamp)<.9
    local angry=name=='Scratch' or name=='ScratchPounce' or name=='FrenzyRun' or recent and reaction=='Anger'
    local scared=recent and reaction=='Fear'
    local pain=recent and reaction=='Pain'
    s.faceAnger=(s.faceAnger or 0)+((angry and 1 or 0)-(s.faceAnger or 0))*(1-math.exp(-dt*18))
    s.faceFear=(s.faceFear or 0)+((scared and 1 or 0)-(s.faceFear or 0))*(1-math.exp(-dt*18))
    for _,side in ipairs({'Left','Right'}) do
     local sign=side=='Left' and -1 or 1
     local brow=s.anim.motors[side..'Brow'];local lid=s.anim.motors[side..'Lid']
     local rage=s.faceAnger;local fear=s.faceFear
     if brow then brow.Transform=brow.Transform*CFrame.new(0,-.065*rage+.055*fear,0)*CFrame.Angles(0,0,sign*math.rad(24*rage-18*fear)) end
     if lid then lid.Transform=lid.Transform*CFrame.new(0,-.055*rage+.025*fear-(pain and .065 or 0),0) end
     local pupil=m:FindFirstChild(side..'Pupil')
     if pupil then
      local scale=1-.25*rage+.55*fear+.035*math.sin(elapsed*9)
      local size=Data[side..'Pupil'].size;pupil.Size=Vector3.new(size[1]*scale,size[2]*scale,size[3])
     end
    end
    if (name=='Spit' or name=='SpitAlt' or name=='Attack') and elapsed<.65 and now>s.charge then
     s.charge=now+.13
     FX.charge(effects,A.mouth(m,s.anim.motors,name,elapsed))
    end
   end
  end
 end
end)
