--[[ ⚠️ КОПИЯ МОДУЛЯ ИЗ ПАКЕТА Farmers_Island_Transfer (последняя версия из
     test/Farmers_Game_Water/Gameplay). Модель острова в Studio Rojo не правит,
     поэтому клиентские эффекты (позы и удар мутанта, свечение сундуков) читают
     модули отсюда — см. StarterPlayerScripts/FarmersIslandClient. ]]
-- Authored vector VFX. No external sprite IDs or per-frame server traffic.
local Run = game:GetService("RunService")
local FX = {}
local function smooth(x) x=math.clamp(x,0,1); return x*x*(3-2*x) end
function FX.attach(chest)
 local body=chest:WaitForChild("Chest_Body",10); if not body then return end
 local hinge=body:WaitForChild("LidHinge",10); if not hinge then return end
 local sea=chest:GetAttribute("SeaChest")==true; local closed=hinge:GetAttribute("ClosedC0"); local scale=chest:GetAttribute("GlowScale") or 1
 local folder=Instance.new("Folder");folder.Name="ChestGlow_Local";folder.Parent=chest
 local anchor=Instance.new("Part");anchor.Name="GlowAnchor";anchor.Size=Vector3.one*.1;anchor.Transparency=1;anchor.Anchored=true;anchor.CanCollide=false;anchor.CanQuery=false;anchor.CanTouch=false;anchor.Parent=folder
 local light=Instance.new("PointLight");light.Name="WarmInterior";light.Color=Color3.fromRGB(70,190,255);light.Range=13*scale;light.Brightness=0;light.Shadows=true;light.Parent=anchor
 local rays={}
 for i=1,7 do
  local a=Instance.new("Attachment");a.Name="RayOrigin_"..i;a.Parent=anchor
  local b=Instance.new("Attachment");b.Name="RayTip_"..i;b.Parent=anchor
  local layers={}
  for layer=1,3 do
   local beam=Instance.new("Beam");beam.Name="GoldRay";beam.Attachment0=a;beam.Attachment1=b;beam.FaceCamera=true;beam.Segments=8;beam.LightEmission=1;beam.LightInfluence=0;beam.Color=ColorSequence.new(Color3.fromRGB(180,240,255),Color3.fromRGB(35,150,255));beam.Width0=(.18+layer*.15)*scale;beam.Width1=(.35+layer*.30)*scale;beam.Enabled=false;beam.Parent=folder;layers[layer]=beam
  end
  rays[i]={a=a,b=b,layers=layers}
 end
 local sparks={}
 for i=1,16 do
  local at=Instance.new("Attachment");at.Parent=anchor
  local gui=Instance.new("BillboardGui");gui.Name="AuthoredSpark";gui.Adornee=at;gui.Size=UDim2.fromScale(.10*scale,.10*scale);gui.LightInfluence=0;gui.AlwaysOnTop=false;gui.Enabled=false;gui.Parent=folder
  local star=Instance.new("Frame");star.AnchorPoint=Vector2.new(.5,.5);star.Position=UDim2.fromScale(.5,.5);star.Size=UDim2.fromScale(1,1);star.Rotation=45;star.BorderSizePixel=0;star.BackgroundColor3=Color3.fromRGB(160,225,255);star.Parent=gui
  sparks[i]={at=at,gui=gui,star=star,phase=(i*.6180339)%1}
 end
 local floor=Instance.new("Part");floor.Name="InteriorGlow";floor.Anchored=true;floor.Size=Vector3.new(6.2,.035,sea and 2.5 or 3.4)*scale;floor.Material=Enum.Material.Neon;floor.Color=Color3.fromRGB(85,195,255);floor.Transparency=1;floor.CanCollide=false;floor.CanQuery=false;floor.CanTouch=false;floor.CastShadow=false;floor.Parent=folder
 local amount=0;local observed=-1;local from=0;local age=0;local fade=1;local closingFade=1;local connection
 local function off()
  light.Brightness=0;floor.Transparency=1
  for _,r in rays do for _,b in r.layers do b.Enabled=false end end
  for _,p in sparks do p.gui.Enabled=false end
 end
 connection=Run.RenderStepped:Connect(function(dt)
  if not chest:IsDescendantOf(workspace) then connection:Disconnect();folder:Destroy();return end
  local stamp=chest:GetAttribute("GlowStarted") or 0;local target=chest:GetAttribute("TargetOpen")==true
  if stamp~=observed then observed=stamp;from=amount;closingFade=fade end
  local duration=target and 1.2 or .933333
  local t=(workspace:GetServerTimeNow()-stamp)/duration
  amount=from+((target and 1 or 0)-from)*smooth(t)
  local openedAt=chest:GetAttribute("GlowOpenedAt") or (stamp+1.2)
  fade=target and (1-smooth((workspace:GetServerTimeNow()-openedAt-4)/1.5)) or closingFade
  local strength=smooth((amount-.18)/.68)*fade
  local frame=body.CFrame*closed;anchor.CFrame=frame*CFrame.new(0,(sea and -.45 or -.80)*scale,(sea and 1.80 or 2.10)*scale);floor.CFrame=frame*CFrame.new(0,(sea and -1.90 or -2.25)*scale,(sea and 1.80 or 2.10)*scale)
  local camera=workspace.CurrentCamera
  if strength<.002 or not camera or (camera.CFrame.Position-anchor.Position).Magnitude>100*scale then off();folder:SetAttribute("Intensity",0);return end
  age+=dt;local pulse=1+.075*math.sin(age*2.1)+.035*math.sin(age*4.7)
  light.Brightness=5.4*strength*pulse;floor.Transparency=1-.58*strength
  for i,r in rays do
   local x=(i-4)*.67+math.sin(age*1.15+i*1.4)*.30;local sway=math.sin(age*1.3+i*1.4)*.48
   r.a.Position=Vector3.new(x,-.8,math.sin(i*2)*.65)*scale
   r.b.Position=Vector3.new(x*1.4+sway,2.5+math.sin(age*1.4+i*1.7)*.65,math.cos(age*.9+i*2.7)*.65)*scale
   for layer,b in r.layers do
    local opacity=strength*(.42/layer)*pulse
    b.Width0=(.18+layer*.15)*scale*(1+.15*math.sin(age*1.6+i));b.Width1=(.35+layer*.30)*scale*(1+.18*math.sin(age*1.6+i));b.Enabled=true;b.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1-opacity*.4),NumberSequenceKeypoint.new(.16,1-opacity),NumberSequenceKeypoint.new(.65,1-opacity*.42),NumberSequenceKeypoint.new(1,1)})
   end
  end
  for i,p in sparks do
   local life=(age*.28+p.phase)%1;local alpha=math.sin(life*math.pi)^1.6*strength
   p.at.Position=Vector3.new(math.sin(i*12.7)*2.45+math.sin(age+i)*.15,-.8+life*4.2,math.cos(i*7.9)*1.2)*scale
   p.gui.Enabled=true;p.star.BackgroundTransparency=1-alpha*.92;p.star.Rotation=45+age*18+i*27
  end
  folder:SetAttribute("Intensity",strength)
 end)
 return {folder=folder,destroy=function() connection:Disconnect();folder:Destroy() end}
end
return FX
