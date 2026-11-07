--[[ ⚠️ КОПИЯ МОДУЛЯ ИЗ ПАКЕТА Farmers_Island_Transfer С НАШИМИ ПРАВКАМИ.
     Оригинал внутри модели острова в Studio — Rojo его не правит. Серверная
     часть запускается отсюда (IslandCrews). Изменения помечены «-- НАШЕ:». ]]
-- Ten lightweight logical spots; only two resident chest meshes per live island.
local ServerStorage=game:GetService('ServerStorage')
local TweenService=game:GetService('TweenService')
local M={}
local active=setmetatable({},{__mode='k'})
local TEMPLATE_KEY='FarmersWoodChestV1'
local function prepare(gameplay)
 local spots=gameplay:WaitForChild('ChestSpots')
 local reference=gameplay:FindFirstChild('ChestTemplate')
 if not reference then reference=Instance.new('ObjectValue');reference.Name='ChestTemplate';reference.Parent=gameplay end
 local library=ServerStorage:FindFirstChild('FarmersChestTemplates')
 if not library then library=Instance.new('Folder');library.Name='FarmersChestTemplates';library.Parent=ServerStorage end
 -- НАШЕ: пакет лежит в ReplicatedStorage, а не в ServerStorage — ищем шаблон по имени
 local AssetFind=require(game:GetService('ReplicatedStorage'):WaitForChild('AssetFind'))
 local template=reference.Value or library:FindFirstChild(TEMPLATE_KEY) or AssetFind.find(TEMPLATE_KEY)
 if not template then
  local source=spots:FindFirstChildWhichIsA('Model')
  assert(source,'No chest template; preserve ServerStorage.FarmersChestTemplates when saving the place')
  template=source:Clone();template.Name=TEMPLATE_KEY;template:SetAttribute('ActiveChest',false);template.Parent=library
 end
 reference.Value=template
 for _,chest in ipairs(spots:GetChildren()) do
  if chest:IsA('Model') then
   local marker=Instance.new('Part');marker.Name=chest.Name;marker.Size=Vector3.new(.3,.3,.3)
   marker.CFrame=chest:GetPivot();marker.Transparency=1;marker.Anchored=true
   marker.CanCollide=false;marker.CanTouch=false;marker.CanQuery=false;marker.CastShadow=false
   marker:SetAttribute('SpotDescription',chest:GetAttribute('SpotDescription'))
   marker:SetAttribute('ChestSpot',true);marker.Parent=spots;chest:Destroy()
  end
 end
 local list={}
 for _,marker in ipairs(spots:GetChildren()) do if marker:IsA('BasePart') then table.insert(list,marker) end end
 assert(#list==10,'Expected ten authored chest spots')
 return list,template
end
function M.Start(island,gameplay)
 if active[island] then return active[island] end
 local spots,template=prepare(gameplay)
 table.sort(spots,function(a,b)return a.Name<b.Name end)
 local rng=Random.new();for j=#spots,2,-1 do local k=rng:NextInteger(1,j);spots[j],spots[k]=spots[k],spots[j] end
 local residents=gameplay:FindFirstChild('ActiveChests')
 if not residents then residents=Instance.new('Folder');residents.Name='ActiveChests';residents.Parent=gameplay end
 -- A live island clone includes two source chests; re-select from all ten markers.
 residents:ClearAllChildren()
 local chosen,connections,tweens={},{},{}
 local setup=require(gameplay.ChestSetup)
 for index,marker in ipairs(spots) do
  local enabled=index<=2;marker:SetAttribute('ActiveChest',enabled);marker:SetAttribute('Consumed',false)
  if enabled then
   local chest=template:Clone();chest.Name=marker.Name
   chest:SetAttribute('ActiveChest',true);chest:SetAttribute('Consumed',false)
   chest:SetAttribute('SpotDescription',marker:GetAttribute('SpotDescription'));chest:PivotTo(marker.CFrame)
   for _,p in ipairs(chest:GetDescendants()) do
    if p:IsA('BasePart') then
     local authored=p:GetAttribute('AuthoredTransparency') or 0
     p.Transparency=authored;p.CanCollide=p:GetAttribute('AuthoredCollide')==true;p.CanTouch=false;p.CanQuery=authored<1
    elseif p:IsA('ProximityPrompt') then p.Enabled=false end
   end
   setup.apply(chest);chest.Parent=residents;table.insert(chosen,chest.Name)
   local body=assert(chest:FindFirstChild('Chest_Body',true));local prompt=body:FindFirstChild('ChestPrompt');local hinge=body:FindFirstChild('LidHinge')
   local consumed=false
   table.insert(connections,prompt.Triggered:Connect(function(player)
    local root=player.Character and player.Character:FindFirstChild('HumanoidRootPart');local hum=player.Character and player.Character:FindFirstChildOfClass('Humanoid')
    if consumed or not chest:IsDescendantOf(workspace) or not root or not hum or hum.Health<=0 or (root.Position-body.Position).Magnitude>14 then return end
    local ray=RaycastParams.new();ray.FilterType=Enum.RaycastFilterType.Exclude;ray.FilterDescendantsInstances={player.Character};ray.RespectCanCollide=true
    local obstruction=workspace:Raycast(root.Position,body.Position-root.Position,ray)
    if obstruction and not obstruction.Instance:IsDescendantOf(chest) then return end
    consumed=true;prompt.Enabled=false;marker:SetAttribute('Consumed',true);chest:SetAttribute('Consumed',true);chest:SetAttribute('OpenedBy',player.UserId)
    local stamp=workspace:GetServerTimeNow();chest:SetAttribute('TargetOpen',true);chest:SetAttribute('GlowStarted',stamp)
    local tween=TweenService:Create(hinge,TweenInfo.new(.9,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{C0=hinge:GetAttribute('ClosedC0')*CFrame.Angles(math.rad(-100),0,0)})
    table.insert(tweens,tween);tween:Play();chest:SetAttribute('IsOpen',true);chest:SetAttribute('GlowOpenedAt',stamp+.9)
    local event=gameplay:FindFirstChild('ChestOpened');if event and event:IsA('BindableEvent') then event:Fire(player,chest) end
   end))
  end
 end
 island:SetAttribute('ActiveChestCount',2);island:SetAttribute('ActiveChestSpots',table.concat(chosen,','));island:SetAttribute('LogicalChestSpots',10)
 local result={chosen=chosen};active[island]=result;local stopped=false
 function result.Stop()
  if stopped then return end;stopped=true
  for _,c in ipairs(connections) do c:Disconnect() end
  for _,t in ipairs(tweens) do t:Cancel() end
  residents:ClearAllChildren();active[island]=nil
  for _,marker in ipairs(spots) do if marker.Parent then marker:SetAttribute('ActiveChest',false) end end
  island:SetAttribute('ActiveChestCount',0)
 end
 table.insert(connections,island.AncestryChanged:Connect(function()if not island:IsDescendantOf(workspace) then result.Stop() end end))
 return result
end
return M
