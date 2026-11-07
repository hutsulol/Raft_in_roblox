local TweenService = game:GetService("TweenService")

local hinge = script.Parent.Doorframe.Hinge
local prompt = script.Parent.Base.ProximityPrompt

local goalOpen = {}
goalOpen.CFrame = hinge.CFrame * CFrame.Angles(0, math.rad(90), 0)

local goalClose = {}
goalClose.CFrame = hinge.CFrame * CFrame.Angles(0, 0, 0)

local tweenInfo = TweenInfo.new(1)
local tweenOpen = TweenService:Create(hinge, tweenInfo, goalOpen)
local tweenClose = TweenService:Create(hinge, tweenInfo, goalClose)

prompt.Triggered:Connect(function()
	if prompt.ActionText == "Close" then
		tweenClose:Play()
		prompt.ActionText = "Открыть"
	else
		tweenOpen:Play()
		prompt.ActionText = "Закрыть"
	end
end)