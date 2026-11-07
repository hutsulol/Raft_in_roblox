--[[ ⚠️ КОПИЯ ChestSetup ИЗ ПАКЕТА Farmers_Island_Transfer (Scripts/Gameplay).
     Сундук FarmersWoodChestV1: шарнир крышки LidHinge по LidPivot/направляющим,
     подсказка ChestPrompt, атрибуты свечения. Зовёт CrabIsland.server для
     сундука песчаной отмели (та же модель). ]]
local Setup={}
function Setup.apply(chest)
 local body=assert(chest:FindFirstChild("Chest_Body",true),"Missing body")
 local lid=assert(chest:FindFirstChild("Chest_Lid",true),"Missing lid")
 local pivot=assert(chest:FindFirstChild("LidPivot",true),"Missing pivot")
 local right=assert(chest:FindFirstChild("LidRightGuide",true),"Missing right guide")
 local up=assert(chest:FindFirstChild("LidUpGuide",true),"Missing up guide")
 local axis=(right.Position-pivot.Position);local vertical=(up.Position-pivot.Position).Unit
 local joint=CFrame.fromMatrix(pivot.Position,axis.Unit,vertical,axis.Unit:Cross(vertical))
 for _,old in chest:GetDescendants() do if old.Name=="ChestController" and old:IsA("Script") then old.Enabled=false end end
 body.Anchored=true;lid.Anchored=false;lid.CanCollide=false;lid.Massless=true
 local emblem=chest:FindFirstChild("Chest_Emblem",true)
 if emblem then
  emblem.Anchored=false;emblem.Massless=true;emblem.CanCollide=false
  local w=emblem:FindFirstChild("BodyWeld") or Instance.new("WeldConstraint");w.Name="BodyWeld";w.Part0=body;w.Part1=emblem;w.Parent=emblem
 end
 for _,p in {pivot,right,up} do p.Anchored=true;p.Transparency=1;p.CanCollide=false;p.CanQuery=false;p.CanTouch=false;p.CastShadow=false end
 local motor=body:FindFirstChild("LidHinge") or Instance.new("Motor6D");motor.Name="LidHinge";motor.Part0=body;motor.Part1=lid;motor.C0=body.CFrame:ToObjectSpace(joint);motor.C1=lid.CFrame:ToObjectSpace(joint);motor:SetAttribute("ClosedC0",motor.C0);motor.Parent=body
 chest:SetAttribute("Consumed",false);chest:SetAttribute("DespawnAt",nil);chest.PrimaryPart=body;chest:SetAttribute("GlowScale",axis.Magnitude);chest:SetAttribute("TargetOpen",false);chest:SetAttribute("IsOpen",false);chest:SetAttribute("Busy",false);chest:SetAttribute("GlowStarted",workspace:GetServerTimeNow())
 local prompt=body:FindFirstChild("ChestPrompt") or Instance.new("ProximityPrompt");prompt.Name="ChestPrompt";prompt.Enabled=true;prompt.ActionText="Открыть";prompt.ObjectText="Пиратский сундук";prompt.MaxActivationDistance=12;prompt.KeyboardKeyCode=Enum.KeyCode.E;prompt.HoldDuration=.15;prompt.Parent=body
 game:GetService("CollectionService"):AddTag(chest,"PirateChestGlow")
 return chest
end
return Setup
