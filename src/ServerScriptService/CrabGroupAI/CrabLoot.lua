--[[ Клешни с убитого краба. Геометрия — из LeftClaw/LeftFinger и RightClaw/
     RightFinger самого рига, отдельной модели лута нет.
     НАШЕ: подобранная клешня — РЕСУРС Crab_Claw основного инвентаря
     (_G.AddResourceToInventory), а не отдельный Tool: клешни складываются в
     один слот стаком, сохраняются и уходят в сундук как любой ресурс.
     Дроп лежит в папке CrabDrops своего острова — снесли остров, ушли и дропы. ]]
local Debris=game:GetService('Debris')
local Loot={}
Loot.ITEM='Crab_Claw'
local function clean(part)
 for _,v in part:GetDescendants() do
  if v:IsA('JointInstance') or v:IsA('WeldConstraint') or v:IsA('Script') then v:Destroy() end
 end
 part.Anchored=false;part.Massless=false;part.CanTouch=false;part.CanQuery=true;part.Transparency=0
end
local function dropFolder(model)
 local link=model:FindFirstChild('CrabIsland')
 local island=link and link.Value
 local parent=(island and island.Parent) and island or workspace
 local folder=parent:FindFirstChild('CrabDrops')
 if not folder then folder=Instance.new('Folder');folder.Name='CrabDrops';folder.Parent=parent end
 return folder
end
function Loot.drop(model)
 if model:GetAttribute('CrabLootDropped') then return end
 model:SetAttribute('CrabLootDropped',true)
 local folder=dropFolder(model)
 for _,side in {'Left','Right'} do
  local claw=model:FindFirstChild(side..'Claw',true)
  local finger=model:FindFirstChild(side..'Finger',true)
  if not claw or not finger then continue end
  local drop=Instance.new('Model');drop.Name='CrabClaw_'..side
  drop:SetAttribute('ItemId','CrabClaw');drop:SetAttribute('SourceCrab',model.Name)
  local handle=claw:Clone();clean(handle);handle.Name='Handle';handle.CanCollide=true;handle.Parent=drop
  local tip=finger:Clone();clean(tip);tip.Name='Finger';tip.CanCollide=false;tip.Massless=true;tip.Parent=drop
  local weld=Instance.new('WeldConstraint');weld.Part0=handle;weld.Part1=tip;weld.Parent=handle
  drop.PrimaryPart=handle;drop.Parent=folder
  drop:PivotTo(drop:GetPivot()+Vector3.new(0,1,0))
  handle:SetNetworkOwner(nil)
  handle.AssemblyLinearVelocity=Vector3.new(side=='Left' and -3 or 3,5,0)
  claw.Transparency=1;finger.Transparency=1
  local prompt=Instance.new('ProximityPrompt');prompt.ActionText='Подобрать';prompt.ObjectText='Клешня краба'
  prompt.KeyboardKeyCode=Enum.KeyCode.E;prompt.HoldDuration=.2;prompt.MaxActivationDistance=12
  -- НАШЕ: клешня лежит в песке — луч видимости упирался в землю, и подсказки не было
  prompt.RequiresLineOfSight=false;prompt.Parent=handle
  -- НАШЕ: улеглась — закрепить, чтобы не сползла в воду и не провалилась
  task.delay(1.5,function() if handle.Parent then handle.Anchored=true;tip.Anchored=true end end)
  local taken=false
  prompt.Triggered:Connect(function(player)
   local char=player.Character;local root=char and char:FindFirstChild('HumanoidRootPart')
   local hum=char and char:FindFirstChildOfClass('Humanoid')
   if taken or not root or not hum or hum.Health<=0 then return end
   local dist=(root.Position-handle.Position).Magnitude
   if dist>14 then print(('[Крабы] клешня: %s далеко (%.1f)'):format(player.Name,dist));return end
   if typeof(_G.AddResourceToInventory)~='function' then warn('[Крабы] нет _G.AddResourceToInventory — клешню некуда положить');return end
   taken=true
   local ok,added=pcall(_G.AddResourceToInventory,player,Loot.ITEM,1,nil)
   print(('[Крабы] клешня: %s подбирает → %s'):format(player.Name,tostring(ok and added or added)))
   if not ok or (added or 0)<1 then taken=false;return end -- рюкзак полон: клешня остаётся на земле
   if typeof(_G.SendInventory)=='function' then pcall(_G.SendInventory,player) end
   prompt:Destroy();drop:Destroy()
  end)
  print(('[Крабы] клешня %s упала: %s'):format(side,tostring(handle.Position)))
  Debris:AddItem(drop,120)
 end
end
return Loot
