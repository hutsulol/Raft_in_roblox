--[[ ⚠️ ВИРУСНЫЙ ВЗРЫВ ПРИ СМЕРТИ МУТАНТА — ОРИГИНАЛ ИЗ ЛАБОРАТОРНОГО ПЛЕЙСА
     (test/MutantBloater/GiantInfected/runtime/GiantEffects.lua). При упаковке
     острова его пропустили. deathPose и virusDeath — авторские; изменено только
     помеченное «НАШЕ»: признак смерти (FarmersState/DeathT вместо State/
     SpawnGeneration) и высота носителя по масштабу мутанта (1.6).
     Эффект чисто визуальный: ни урона, ни отброса, ни Explosion. ]]
local Debris=game:GetService('Debris')
local FX={}
local function part(size,cf,color,material)
 local p=Instance.new('Part');p.Size=size;p.CFrame=cf;p.Color=color;p.Material=material
 p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=false;p.Parent=workspace;return p
end
FX.deathBurstTime=.65
function FX.deathPose(t)
 local q=math.clamp(t/FX.deathBurstTime,0,1)
 local squeeze=math.sin(q*math.pi)
 local tremor=math.sin(t*75)*q*2
 local function r(x,y,z)return CFrame.Angles(math.rad(x),math.rad(y),math.rad(z)) end
 return {
  LowerTorso=CFrame.new(0,-.22*squeeze,0)*r(-5*squeeze,0,tremor*.4),
  UpperTorso=r(14*squeeze-12*q,tremor,0),Head=r(-18*q,tremor*1.5,0),
  LeftUpperArm=r(-18*q,0,-24*q),RightUpperArm=r(-18*q,0,24*q),
  LeftLowerArm=r(-32*squeeze,0,0),RightLowerArm=r(-32*squeeze,0,0),
  LeftUpperLeg=r(-10*squeeze,0,-3),RightUpperLeg=r(-10*squeeze,0,3),
  LeftLowerLeg=r(18*squeeze,0,0),RightLowerLeg=r(18*squeeze,0,0),Jaw=r(24*q,0,0),
 }
end
-- НАШЕ: тело, которое уже лопнуло (поздний заход при StreamingEnabled), просто прячем
local function hideBody(model)
 for _,v in model:GetDescendants() do
  if v:IsA('BasePart') then v.LocalTransparencyModifier=1
  elseif v:IsA('SurfaceGui') or v:IsA('BillboardGui') then v.Enabled=false end
 end
end
function FX.virusDeath(model,elapsed)
 if not model.PrimaryPart then return end
 if elapsed>1.1 then hideBody(model) return end
 -- НАШЕ: одна жизнь = один DeathT (ставит MutantAI); смерть — FarmersState=='Dead', а не State
 local deathId=model:GetAttribute('DeathT') or 0
 local scale=model:GetScale()
 local holder=part(Vector3.one,CFrame.new(model.PrimaryPart.Position+Vector3.new(0,3.6*scale,0)),Color3.new(1,0,0),Enum.Material.SmoothPlastic)
 holder.Name='ViralDeathGas';holder.Transparency=1;Debris:AddItem(holder,6)
 local function smoke(name,speed,life,size,color)
  local e=Instance.new('ParticleEmitter');e.Name=name;e.Texture='rbxasset://textures/particles/smoke_main.dds'
  e.Rate=0;e.Speed=speed;e.Lifetime=life;e.SpreadAngle=Vector2.new(180,180)
  e.Rotation=NumberRange.new(-180,180);e.RotSpeed=NumberRange.new(-55,55)
  e.Drag=3;e.Acceleration=Vector3.new(0,1.6,0);e.LightInfluence=.25;e.LightEmission=.08
  e.Color=color;e.Size=size;e.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.07,.15),NumberSequenceKeypoint.new(.5,.4),NumberSequenceKeypoint.new(1,1)})
  e.Parent=holder;return e
 end
 local red=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(195,20,36)),ColorSequenceKeypoint.new(.45,Color3.fromRGB(115,8,23)),ColorSequenceKeypoint.new(1,Color3.fromRGB(55,12,20))})
 local cloud=smoke('RedVirusCloud',NumberRange.new(10,24),NumberRange.new(2.3,3.7),NumberSequence.new({NumberSequenceKeypoint.new(0,2),NumberSequenceKeypoint.new(.25,5),NumberSequenceKeypoint.new(1,8)}),red)
 local jets=smoke('FastGasBurst',NumberRange.new(26,38),NumberRange.new(.45,.85),NumberSequence.new(1.2,4.5),red)
 local leak=smoke('PressureLeak',NumberRange.new(2,5),NumberRange.new(.3,.6),NumberSequence.new(.5,2),red)
 if elapsed<FX.deathBurstTime then leak:Emit(12) end
 task.delay(math.max(0,FX.deathBurstTime-elapsed),function()
  if not holder.Parent or not model.Parent or not model.PrimaryPart or (deathId~=0 and (model:GetAttribute('DeathT') or 0)~=deathId) or model:GetAttribute('FarmersState')~='Dead' then return end
  holder.Position=model.PrimaryPart.Position+Vector3.new(0,3.6*scale,0)
  cloud:Emit(70);jets:Emit(35)
  hideBody(model)
 end)
end
return FX
