local rs = game:GetService("ReplicatedStorage")

local model = script.Parent
local part = model:FindFirstChildWhichIsA("BasePart", true)

local openWorkbenchEvent = rs:FindFirstChild("OpenWorkbench")
if not openWorkbenchEvent then
	openWorkbenchEvent = Instance.new("RemoteEvent")
	openWorkbenchEvent.Name = "OpenWorkbench"
	openWorkbenchEvent.Parent = rs
end

local prompt = Instance.new("ProximityPrompt")
prompt.ActionText = "Craft"
prompt.ObjectText = "WorkBench"
prompt.KeyboardKeyCode = Enum.KeyCode.E
prompt.HoldDuration = 0.5
prompt.MaxActivationDistance = 10
prompt.RequiresLineOfSight = true
prompt.Parent = part

prompt.Triggered:Connect(function(player)
	openWorkbenchEvent:FireClient(player)
end)
