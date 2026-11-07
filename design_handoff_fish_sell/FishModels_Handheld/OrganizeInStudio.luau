-- Import FishModels_Handheld_ALL.fbx, select the imported collection, then
-- run this code in Studio's Command Bar (Edit mode).
local rows = {
 {'Fish_Sardine','Сардина',1.35}, {'Fish_Mackerel','Скумбрия',1.65},
 {'Fish_Seabass','Морской окунь',1.9}, {'Fish_Dorado','Дорадо',2.0},
 {'Fish_Bream','Морской лещ',1.7}, {'Fish_Barracuda','Барракуда',2.5},
 {'Fish_Tuna','Тунец',2.4}, {'Fish_Swordfish','Рыба-меч',2.8},
 {'Fish_GoldFugu','Золотая фугу',1.55}, {'Fish_Marlin','Синий марлин',3.0},
 {'Fish_GhostRay','Призрачный скат',2.5}, {'Fish_Krakenling','Кракенёнок',2.2},
 {'Fish_Leviathan','Левиафан',3.2},
}
local storage=game:GetService('ReplicatedStorage')
assert(not storage:FindFirstChild('FishModels'),'FishModels already exists; rename it first to preserve the previous collection')
local found={}
local wanted={}
for _,row in rows do wanted[row[1]]=true end
local seen={}
for _,root in game:GetService('Selection'):Get() do
 local objects=root:GetDescendants();table.insert(objects,root)
 for _,obj in objects do
  if obj:IsA('MeshPart') and wanted[obj.Name] and not seen[obj] then
   assert(not found[obj.Name],'Duplicate fish: '..obj.Name)
   found[obj.Name]=obj;seen[obj]=true
  end
 end
end
for _,row in rows do assert(found[row[1]],'Select imported collection; missing '..row[1]) end
local folder=Instance.new('Folder');folder.Name='FishModels'
for _,row in rows do
 local model=Instance.new('Model');model.Name=row[1]
 local mesh=found[row[1]]:Clone();mesh.Name='Handle'
 local scale=row[3]/math.max(mesh.Size.X,mesh.Size.Y,mesh.Size.Z)
 mesh.Size*=scale;mesh.CFrame=CFrame.identity
 mesh.Anchored=false;mesh.CanCollide=false;mesh.CanTouch=false;mesh.CanQuery=false;mesh.Massless=true
 mesh.Parent=model;model.PrimaryPart=mesh
 local grip=Instance.new('Attachment');grip.Name='GripAttachment'
 grip.Position=Vector3.new(0,-mesh.Size.Y*.3,0);grip.Parent=mesh
 model:SetAttribute('DisplayName',row[2]);model:SetAttribute('FishId',row[1])
 model:SetAttribute('MaxDimensionStuds',row[3]);model.Parent=folder
end
folder.Parent=storage
game:GetService('Selection'):Set({folder})
print('Created ReplicatedStorage.FishModels — 13 fish; originals preserved')
