-- Presentation only: server owns catch outcome and currency.
-- Resolve line/fish against rendered hands; FishingRig owns this NPC's poses.
local Run=game:GetService("RunService")
local Tween=game:GetService("TweenService")
local Debris=game:GetService("Debris")
local RS=game:GetService("ReplicatedStorage")
local Rig=require(RS:WaitForChild("FishingRig"))
local Catches=require(RS:WaitForChild("FishingCatches"))
local clips={}; require(RS:WaitForChild("FishingClips"))(clips)
local tracked={}
local function sample(c,t)
 if c.loop then t=t%c.length else t=math.clamp(t,0,c.length) end
 local keys=c.keys; local lo,hi=1,#keys
 while hi-lo>1 do local mid=math.floor((lo+hi)/2); if keys[mid].t<=t then lo=mid else hi=mid end end
 local a,b=keys[lo],keys[hi]; local u=math.clamp((t-a.t)/(b.t-a.t),0,1); local out={}
 for k,v in pairs(a.a) do out[k]=v+(b.a[k]-v)*u end
 return out
end
Run.PreSimulation:Connect(function(dt)
 local now=workspace:GetServerTimeNow()
 for m,s in pairs(tracked) do
  if not m.Parent then if s.rig then s.rig:restore() end; tracked[m]=nil
  elseif m:GetAttribute("FishingAdaptive") then
   if not s.rig then
    if m:FindFirstChild("Head") and Rig.hand(m,"Left") and Rig.hand(m,"Right") then s.rig=Rig.attach(m) end
   end
   if s.rig then
    local c=clips[m:GetAttribute("Clip")]; local t=now-(m:GetAttribute("ClipT") or now)
    local once=clips[m:GetAttribute("ClipOnce")]; local ot=now-(m:GetAttribute("ClipOnceT") or 0)
    if once and ot>=0 and ot<once.length then c=once; t=ot end
    if c then s.rig:apply(sample(c,t),dt) end
   end
  elseif s.rig then s.rig:restore(); s.rig=nil end
 end
end)
local function watch(m)
 if m:IsA("Model") and m.Name=="RaftFisherman" then tracked[m]={} end
end
workspace.ChildAdded:Connect(watch)
for _,m in ipairs(workspace:GetChildren()) do watch(m) end
local function splash(position,scale)
 for i=1,7 do
  local a=i*math.pi*2/7
  local p=Instance.new("Part"); p.Name="FishingSplash"; p.Shape=Enum.PartType.Ball
  p.Anchored=true; p.CanCollide=false; p.CanTouch=false; p.CanQuery=false
  p.Material=Enum.Material.Neon; p.Color=Color3.fromRGB(188,239,250)
  p.Size=Vector3.new(.09,.09,.09)*scale; p.Position=position; p.Parent=workspace
  Tween:Create(p,TweenInfo.new(.45,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{
   Position=position+Vector3.new(math.cos(a)*.7,.25+(i%3)*.12,math.sin(a)*.7)*scale,
   Transparency=1,Size=Vector3.new(.025,.025,.025)*scale}):Play(); Debris:AddItem(p,.5)
 end
end
Run.RenderStepped:Connect(function()
 local now=workspace:GetServerTimeNow()
 for m,s in pairs(tracked) do
  if not m.Parent then if s.rig then s.rig:restore() end; tracked[m]=nil else
   local head=m:FindFirstChild("Head")
   if m:GetAttribute("FishingSleeping") and head then
    if not s.zzz then
     local gui=Instance.new("BillboardGui"); gui.Name="FishingSleep"; gui.Size=UDim2.fromOffset(90,60)
     gui.StudsOffset=Vector3.new(.7,1.25,0); gui.AlwaysOnTop=true; gui.Adornee=head; gui.Parent=head
     local text=Instance.new("TextLabel"); text.Size=UDim2.fromScale(1,1); text.BackgroundTransparency=1
     text.Text="z Z z"; text.Font=Enum.Font.GothamBold; text.TextSize=23
     text.TextColor3=Color3.fromRGB(180,213,255); text.TextStrokeColor3=Color3.fromRGB(31,47,83); text.TextStrokeTransparency=.4; text.Parent=gui
     s.zzz=gui; s.zzzText=text
    end
    local u=(now%3)/3
    s.zzz.StudsOffset=Vector3.new(.7,1.1+u*.7,0)
    s.zzzText.TextTransparency=.2+.6*u; s.zzzText.Rotation=-8+math.sin(now)*5
   elseif s.zzz then s.zzz:Destroy(); s.zzz=nil; s.zzzText=nil end
   local root=m:FindFirstChild("HumanoidRootPart")
   local rw=root and root:FindFirstChild("RaftFishermanWeld")
   -- рыбак держится за плот AlignPosition (FishingService): плот — родитель вложения
   local primary=rw and (rw:IsA("JointInstance") and rw.Part0 or (rw.Attachment1 and rw.Attachment1.Parent))
   local relative=m:GetAttribute("FishingFrame")
   if primary and relative then
    local frame=primary.CFrame*relative; local scale=m:GetAttribute("FishingScale") or 1
    local function point(x,y,z) return frame*Vector3.new(x*scale,y*scale,z*scale) end
    local function place(p,cf)
     local align=p:GetAttribute("FishAlign")   -- рыба пака: длина к позе заглушки (FishingService)
     if typeof(align)=="CFrame" then cf=cf*align end
     if p:IsA("Model") then p:PivotTo(cf) return end   -- 3D-модель рыбы (FishData)
     local w=p:FindFirstChildOfClass("Weld")
     if w then w.C0=w.Part0.CFrame:ToObjectSpace(cf)*w.C1 end
     p.CFrame=cf
    end
    local rod=m:FindFirstChild("Heldraft_fishing_rod")
    local beam=rod and rod:FindFirstChildOfClass("Beam")
    local bobber=m:FindFirstChild("FishingBobber")
    local cast=m:GetAttribute("FishingCastT")
    if bobber and beam and cast then
     local t=now-cast
     if s.cast~=cast then
      s.cast=cast; s.castStart=primary.CFrame:PointToObjectSpace(beam.Attachment0.WorldPosition); s.landed=false; s.flight=nil; s.splash=0
     end
     local target=point(.6,-2.2,-8)
     local pos=target+frame.UpVector*(math.sin(t*3.2)*.035*scale)
     if t<.78 then
      local u=math.clamp(t/.78,0,1)
      pos=(primary.CFrame*s.castStart):Lerp(target,u)+frame.UpVector*(4*u*(1-u)*2.4*scale)
      beam.CurveSize0=(1-u)*.55*scale; beam.CurveSize1=-(1-u)*.55*scale
     else
      if not s.landed then s.landed=true; splash(target,scale) end
      local bite=m:GetAttribute("FishingBiteT")
      local fight=m:GetAttribute("FishingFightT")
      local variant=Catches[m:GetAttribute("FishingCatchVariant")] or Catches[1]
      if bite and not fight then
       local b=now-bite; pos=pos-frame.UpVector*(math.abs(math.sin(b*13))*.24*scale)
      elseif fight then
       local f=now-fight
       pos=pos+frame.RightVector*(math.sin(f*2.7)*variant.sway*scale)+frame.LookVector*(math.sin(f*4.1)*.23*scale)
       pos=pos-frame.UpVector*(.08*scale)
       if now-s.splash>.8 then s.splash=now; splash(pos,scale*.65) end
      end
      beam.CurveSize0=fight and 0 or .12*scale; beam.CurveSize1=fight and 0 or -.12*scale
     end
     local fish=m:FindFirstChild("HookedFish")
     local flight=m:GetAttribute("HookFlightT")
     local hand=Rig.hand(m,"Left")
     if fish and flight and hand then
      if s.flight~=flight then s.flight=flight; s.fishStart=primary.CFrame:PointToObjectSpace(pos); splash(pos,scale*1.4) end
      local variant=Catches[m:GetAttribute("FishingCatchVariant")] or Catches[1]
      local u=math.clamp((now-flight)/(variant.catch-variant.launch),0,1)
      local _,offset=Rig.grip(m,"Left",true)
      local grip=hand.CFrame*offset
      local x,y=Catches.flightOffset(variant,u,scale)
      local p=(primary.CFrame*s.fishStart):Lerp(grip.Position,u)+frame.UpVector*y+frame.RightVector*x
      local flutter=CFrame.Angles(math.sin(u*30)*variant.flutter*(1-u),u*5*(1-u),math.sin(u*43)*.35*(1-u))
      local cf=CFrame.new(p)*grip.Rotation*flutter
      place(fish,cf); pos=p
     end
     place(bobber,CFrame.new(pos)); bobber.LocalTransparencyModifier=fish and 1 or 0
    end
    local fish=m:FindFirstChild("HeldFishermanFish")
    if fish then
     local w=fish:FindFirstChild("HandWeld",true) or fish:FindFirstChildOfClass("Weld")
     local t=now-(m:GetAttribute("FishHeldT") or now)
     if w then
      local amp=.12*math.exp(-t*.35)+.025
      local _,offset=Rig.grip(m,"Left",true)
      w.C0=offset*CFrame.Angles(math.sin(t*18)*amp,0,math.sin(t*23)*amp)
     end
    end
   end
  end
 end
end)
