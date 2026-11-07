--[[ ⚠️ КОПИЯ МОДУЛЯ ИЗ ПАКЕТА Farmers_Island_Transfer (последняя версия из
     test/Farmers_Game_Water/Gameplay). Модель острова в Studio Rojo не правит,
     поэтому клиентские эффекты (позы и удар мутанта, свечение сундуков) читают
     модули отсюда — см. StarterPlayerScripts/FarmersIslandClient. ]]
-- Local ground effects driven by the replicated attack clock; no terrain edits.
local Run=game:GetService('RunService')
local FX={}
function FX.new(island,gameplay)
 local folder=Instance.new('Folder');folder.Name='_MutantGroundImpact';folder.Parent=island
 local bursts={};local stopped=false
 local function part(size,cf,color,material)
  local p=Instance.new('Part');p.Name='GroundFragment';p.Size=size;p.CFrame=cf;p.Color=color;p.Material=material
  p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=false;p.Parent=folder;return p
 end
 local function params()
  local p=RaycastParams.new();p.FilterType=Enum.RaycastFilterType.Exclude;p.RespectCanCollide=true
  local excluded={folder,gameplay.NPCs}
  for _,player in game.Players:GetPlayers() do if player.Character then table.insert(excluded,player.Character) end end
  p.FilterDescendantsInstances=excluded;return p
 end
 local service={}
 function service.Impact(model)
  if stopped or not model.Parent then return false end
  local root=model:FindFirstChild('HumanoidRootPart');if not root then return false end
  local scale=model:GetScale();local ray=params()
  local target=root.Position+root.CFrame.LookVector*(3*scale)
  local hit=workspace:Raycast(target+Vector3.yAxis*5,Vector3.new(0,-30,0),ray)
  if not hit then return false end
  local pos,up=hit.Position,hit.Normal
  local color=hit.Instance:IsA('Terrain') and workspace.Terrain:GetMaterialColor(hit.Material) or hit.Instance.Color
  local axis=math.abs(up.Y)<.95 and Vector3.yAxis or Vector3.xAxis
  local x=axis:Cross(up).Unit;local z=x:Cross(up).Unit;local rng=Random.new()
  -- At most one burst per mutant: 21 cracks + 14 fragments = 420 triangles.
  local old=bursts[model];if old then for _,p in old.parts do p:Destroy() end end
  local burst={at=os.clock(),parts={},fragments={},cracks={}};bursts[model]=burst
  for branch=1,7 do
   local angle=branch*math.pi*2/7+rng:NextNumber(-.15,.15);local prev=pos+up*.035
   for segment=1,3 do
    local a=angle+rng:NextNumber(-.2,.2)
    local h=workspace:Raycast(pos+(x*math.cos(a)+z*math.sin(a))*(segment*.95*scale)+up*3,-up*6,ray)
    if h then
     local finish=h.Position+h.Normal*.035;local vector=finish-prev
     if vector.Magnitude>.1 then
      local p=part(Vector3.new((.07+(3-segment)*.025)*scale,.035,vector.Magnitude),CFrame.lookAt((prev+finish)*.5,finish,up),color:Lerp(Color3.new(.035,.03,.025),.8),Enum.Material.SmoothPlastic)
      p.Name='GroundCrack';table.insert(burst.parts,p);table.insert(burst.cracks,p)
     end;prev=finish
    end
   end
  end
  for _=1,14 do
   local a=rng:NextNumber(0,math.pi*2);local radial=x*math.cos(a)+z*math.sin(a)
   local p=part(Vector3.new(rng:NextNumber(.12,.43),rng:NextNumber(.12,.32),rng:NextNumber(.15,.48))*scale,CFrame.new(pos+up*.12+radial*.3),color:Lerp(Color3.fromRGB(68,51,31),.35),Enum.Material.Slate)
   table.insert(burst.parts,p);table.insert(burst.fragments,{p=p,origin=p.Position,v=(radial*rng:NextNumber(4,10)+up*rng:NextNumber(5,12))*scale,spin=Vector3.new(rng:NextNumber(-7,7),rng:NextNumber(-7,7),rng:NextNumber(-7,7))})
  end
  folder:SetAttribute('ImpactCount',(folder:GetAttribute('ImpactCount') or 0)+1)
  folder:SetAttribute('LastImpactPosition',pos)
  return true
 end
 local connection=Run.RenderStepped:Connect(function()
  for model,b in bursts do
   local t=os.clock()-b.at
   if t>=2.5 or not model:IsDescendantOf(island) then
    for _,p in b.parts do p:Destroy() end;bursts[model]=nil
   else
    for _,p in b.cracks do p.Transparency=math.clamp((t-1.6)/.9,0,1) end
    for _,f in b.fragments do
     if t<1.25 then f.p.CFrame=CFrame.new(f.origin+f.v*t+Vector3.new(0,-16*t*t,0))*CFrame.Angles(f.spin.X*t,f.spin.Y*t,f.spin.Z*t);f.p.Transparency=math.clamp((t-.65)/.6,0,1)
     else f.p.Transparency=1 end
    end
   end
  end
 end)
 function service.Stop()
  if stopped then return end;stopped=true;connection:Disconnect();folder:Destroy();table.clear(bursts)
 end
 return service
end
return FX
