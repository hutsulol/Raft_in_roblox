--[[ By: Brutez, 2/28/2015, 1:34 AM, (UTC-08:00) Pacific Time (US & Canada) ]]--
local PlayerSpawning=false; --[[ Change this to true if you want the NPC to spawn like a player, and change this to false if you want the NPC to spawn at it's current position. ]]--
local AdvancedRespawnScript=script;
repeat Wait(0)until script and script.Parent and script.Parent.ClassName=="Model";
local JeffTheKiller=AdvancedRespawnScript.Parent;
if AdvancedRespawnScript and JeffTheKiller and JeffTheKiller:FindFirstChild("Thumbnail")then
JeffTheKiller:FindFirstChild("Thumbnail"):Destroy();
end;
local GameDerbis=Game:GetService("Debris");
local JeffTheKillerHumanoid;
for _,Child in pairs(JeffTheKiller:GetChildren())do
if Child and Child.ClassName=="Humanoid"and Child.Health~=0 then
JeffTheKillerHumanoid=Child;
end;
end;
local Respawndant=JeffTheKiller:Clone();
if PlayerSpawning then --[[ LOOK AT LINE: 2. ]]--
coroutine.resume(coroutine.create(function()
if JeffTheKiller and JeffTheKillerHumanoid and JeffTheKillerHumanoid:FindFirstChild("Status")and not JeffTheKillerHumanoid:FindFirstChild("Status"):FindFirstChild("AvalibleSpawns")then
SpawnModel=Instance.new("Model");
SpawnModel.Parent=JeffTheKillerHumanoid.Status;
SpawnModel.Name="AvalibleSpawns";
else
SpawnModel=JeffTheKillerHumanoid:FindFirstChild("Status"):FindFirstChild("AvalibleSpawns");
end;
function FindSpawn(SearchValue)
local PartsArchivable=SearchValue:GetChildren();
for AreaSearch=1,#PartsArchivable do
if PartsArchivable[AreaSearch].className=="SpawnLocation"then
local PositionValue=Instance.new("Vector3Value",SpawnModel);
PositionValue.Value=PartsArchivable[AreaSearch].Position;
PositionValue.Name=PartsArchivable[AreaSearch].Duration;
end;
FindSpawn(PartsArchivable[AreaSearch]);
end;
end;
FindSpawn(Game:GetService("Workspace"));
local SpawnChilden=SpawnModel:GetChildren();
if#SpawnChilden>0 then
local SpawnItself=SpawnChilden[math.random(1,#SpawnChilden)];
local RespawningForceField=Instance.new("ForceField");
RespawningForceField.Parent=JeffTheKiller;
RespawningForceField.Name="SpawnForceField";
GameDerbis:AddItem(RespawningForceField,SpawnItself.Name);
JeffTheKiller:MoveTo(SpawnItself.Value+Vector3.new(0,3.5,0));
else
if JeffTheKiller:FindFirstChild("SpawnForceField")then
JeffTheKiller:FindFirstChild("SpawnForceField"):Destroy();
end;
JeffTheKiller:MoveTo(Vector3.new(0,115,0));
end;
end));
end;
function Respawn()
Wait(5);
Respawndant.Parent=JeffTheKiller.Parent;
Respawndant:makeJoints();
Respawndant:FindFirstChild("Head"):MakeJoints();
Respawndant:FindFirstChild("Torso"):MakeJoints();
JeffTheKiller:remove();
end;
if AdvancedRespawnScript and JeffTheKiller and JeffTheKillerHumanoid then
JeffTheKillerHumanoid.Died:connect(Respawn);
end;
--[[ By: Brutez, 2/28/2015, 1:34 AM, (UTC-08:00) Pacific Time (US & Canada) ]]--