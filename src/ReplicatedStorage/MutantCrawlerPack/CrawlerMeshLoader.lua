-- Geometry is supplied by Rojo; downloads must never block the spawner.
local Content=game:GetService('ContentProvider')
local Manifest=require(script.Parent.CrawlerMeshAssets)
local Loader={}
function Loader.prepare(template)
 local parts={}
 for name,asset in pairs(Manifest) do
  local part=template:FindFirstChild(name,true)
  if part and part:IsA('MeshPart') then
   part.TextureID=asset.texture
   table.insert(parts,part)
   if part.MeshId=='' then warn('Crawler empty mesh; reconnect Rojo before Play:',name) end
  else warn('Crawler missing MeshPart:',name) end
 end
 task.spawn(function()
  local ok,err=pcall(function()
   Content:PreloadAsync(parts,function(id,status)
    if status~=Enum.AssetFetchStatus.Success then warn('Crawler asset unavailable',id,status) end
   end)
  end)
  if not ok then warn('Crawler background preload:',err) end
 end)
 return #parts
end
return Loader
