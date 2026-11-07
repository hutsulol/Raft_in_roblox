--[[ ⚠️ КОПИЯ МОДУЛЯ ИЗ ПАКЕТА Farmers_Island_Transfer С НАШИМИ ПРАВКАМИ.
     Оригинал лежит внутри модели острова (Gameplay/*), но модель живёт в Studio,
     а не в репозитории — править его Rojo не может. Поэтому серверная часть
     рантайма острова запускается ОТСЮДА (IslandCrews), а модули внутри модели
     остаются для клиентских скриптов (ToolsClient, MutantClient) как есть.
     Что изменено — помечено «-- НАШЕ:». Остальное — авторский код пакета. ]]
-- Edit scene contains markers only. Spawn a fresh roster after the island enters Workspace.
local RunService=game:GetService('RunService')
local M={}
local active=setmetatable({},{__mode='k'})
local EXPECTED={Pirate=12,Guard=3,Scientist=2,Worker=2,Mutant=1}
local function reference(g,name)
 local value=g:FindFirstChild(name)
 return value and value:IsA('ObjectValue') and value.Value or nil
end
function M.Start(island,g)
 assert(RunService:IsServer(),'NPCSpawner is server-only')
 if active[island] then return active[island] end
 g=g or island:WaitForChild('Gameplay')
 local folder=assert(g:FindFirstChild('Spawns'),'NPC spawn platforms missing')
 local markers,counts={},{}
 for _,marker in ipairs(folder:GetChildren()) do
  if marker:IsA('BasePart') then
   local role=marker:GetAttribute('Role') or marker:GetAttribute('FarmersRole')
   -- НАШЕ: площадки пиратов и охраны пропускаем — там наши пираты (IslandCrews)
   if EXPECTED[role] and role~='Pirate' and role~='Guard' then counts[role]=(counts[role] or 0)+1;table.insert(markers,marker) end
  end
 end
 table.sort(markers,function(a,b)return a.Name<b.Name end)
 local factory=require(g:WaitForChild('CharacterFactory'))
 -- НАШЕ: ссылки-ObjectValue могли не пережить перенос — ищем по имени
 local AssetFind=require(game:GetService('ReplicatedStorage'):WaitForChild('AssetFind'))
 local assets=reference(g,'NPCAssets') or AssetFind.find('CharacterAssets')
 if assets then factory.ConfigureAssets(assets) end
 local head=reference(g,'NPCHeadLOD')
 if head and factory.ConfigureHead then factory.ConfigureHead(head) end
 local mutantTemplate=assert(reference(g,'MutantTemplate') or AssetFind.find('GiantInfected_Farmers'),'MutantTemplate server asset reference missing')
 local npcs=g:FindFirstChild('NPCs')
 if not npcs then npcs=Instance.new('Folder');npcs.Name='NPCs';npcs.Parent=g end
 -- A clone of a running island can carry the old runtime roster: replace it, never double it.
 npcs:ClearAllChildren()
 local spawned={}
 local ok,err=pcall(function()
  for _,marker in ipairs(markers) do
   local config=marker:GetAttributes()
   local role=config.Role or config.FarmersRole
   local index=config.Variant or tonumber(marker.Name:match('%d+$')) or 1
   local model=role=='Mutant' and mutantTemplate:Clone() or factory.Create(role,index,config)
   model.Name=marker.Name;model:SetAttribute('FarmersRole',role);model:SetAttribute('Variant',index)
   model:SetAttribute('FarmersNPC',true);model:SetAttribute('RuntimeNPC',true)
   -- НАШЕ: враги для зачистки (IslandClearSystem/IslandQuestSystem считают их вместе с нашими пиратами)
   if role=='Guard' or role=='Mutant' or role=='Scientist' then model:SetAttribute('Hostile',true) end
   for _,name in ipairs({'Route','Workstation','EscortIndex','MaxHealth','face','cloth','FaceTexture','ShirtTemplate','PantsTemplate','HappyFaceTexture'}) do
    if config[name]~=nil then model:SetAttribute(name,config[name]) end
   end
   model:SetAttribute('Freed',false);model:SetAttribute('Escaped',false)
   local root=assert(model:FindFirstChild('HumanoidRootPart'),'Spawn template root missing')
   local hum=assert(model:FindFirstChildOfClass('Humanoid'),'Spawn template Humanoid missing')
   hum.Health=hum.MaxHealth
   model.PrimaryPart=root
   for _,part in ipairs(model:GetDescendants()) do
    -- НАШЕ: CanTouch — пули (Bullet_Cannon, ShipCombat) бьют через Touched; у мутанта
    -- пакет выключал касание на всех деталях, и револьвер по нему не работал
    if part:IsA('BasePart') then part.Anchored=false;part.CanTouch=true end
    if part:IsA('LuaSourceContainer') then part:Destroy() end
   end
   local rootHeight=config.RootHeight or (role=='Mutant' and hum.HipHeight+root.Size.Y/2 or 3.05)
   model:PivotTo(marker.CFrame+marker.CFrame.UpVector*rootHeight)
   root.AssemblyLinearVelocity=Vector3.zero;root.AssemblyAngularVelocity=Vector3.zero
   table.insert(spawned,model);model.Parent=npcs
  end
 end)
 if not ok then for _,model in ipairs(spawned) do model:Destroy() end;error(err) end
 local service={models=spawned,count=#spawned};active[island]=service
 local connection;local stopped=false
 function service.Stop()
  if stopped then return end;stopped=true
  if connection then connection:Disconnect() end
  for _,model in ipairs(spawned) do model:Destroy() end
  active[island]=nil;island:SetAttribute('RuntimeNPCCount',0)
 end
 connection=island.AncestryChanged:Connect(function()if not island:IsDescendantOf(workspace) then service.Stop() end end)
 island:SetAttribute('RuntimeNPCCount',#spawned)
 return service
end
return M
