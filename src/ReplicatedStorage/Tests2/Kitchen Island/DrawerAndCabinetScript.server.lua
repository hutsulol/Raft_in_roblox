--- Made by DocBalla ---
local TweenService = game:GetService("TweenService")
local KitchenIsland = script.Parent
--- Drawers ---
local LeftDrawer = KitchenIsland.LeftDrawer.LDrawer
local leftKnob = KitchenIsland.LeftDrawer.LKnob
local LDrawPosition = LeftDrawer.CFrame

local RightDrawer = KitchenIsland.RightDrawer.RDrawer
local rightKnob = KitchenIsland.RightDrawer.RKnob
local RDrawPosition = RightDrawer.CFrame


-- // Drawers Tweens // -- 
local goal1 = {}
goal1.CFrame = LeftDrawer.CFrame * CFrame.new(1.8, 0 , 0)
local goal2 = {}
goal2.CFrame = RightDrawer.CFrame * CFrame.new(1.8, 0 , 0)

local info = TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 0, false, 0)
local LeftDrawerTween = TweenService:Create(LeftDrawer,info,goal1)
local RightDrawerTween = TweenService:Create(RightDrawer,info,goal2)

leftKnob.ClickDetector.MouseClick:Connect(function()
	if LeftDrawer.Status.Value == false then
		LeftDrawerTween:Play()
		LeftDrawer.Status.Value = true
	else
		local LcloseDrawer = TweenService:Create(LeftDrawer,info, {CFrame = KitchenIsland.LeftDrawer.CloseDrawer.CFrame}):Play()
		LeftDrawer.Status.Value = false
	end
end)

rightKnob.ClickDetector.MouseClick:Connect(function()
	if RightDrawer.Status.Value == false then
		RightDrawerTween:Play()
		RightDrawer.Status.Value = true
	else
		local RcloseDrawer = TweenService:Create(RightDrawer,info, {CFrame = KitchenIsland.RightDrawer.CloseDrawer.CFrame}):Play()
		RightDrawer.Status.Value = false
	end
	
end)


---// Cabinets  \\ ---

-- // LeftbottomCabinet Variables \\ --
local LBC = KitchenIsland.LeftBottomCabinet
local LBH = LBC.Handle
local LBD = LBC.Door
local open = LBC.OpenDoor
local close = LBC.ClosedDoor
local Lstatus= LBC.Status

-- // LeftmiddleCabinet Variables \\ --
local LMC = KitchenIsland.LeftMiddleCabinet
local LMH = LMC.Handle
local LMD = LMC.LMiddleDoor
local openLM = LMC.OpenMiddle
local closeLM = LMC.CloseMiddle
local LMstatus = LMC.Status

-- // RightmiddleCabinet Variables\\ --
local RMC = KitchenIsland.RightMiddleCabinet
local RMH = RMC.Handle
local RMD = RMC.RMiddleDoor
local openRM = RMC.OpenDoor
local closeRM = RMC.ClosedDoor
local RMstatus = RMC.Status

-- // RightbottomCabinet Variables \\ --
local RBC = KitchenIsland.RightBottomCabinet
local RBH = RBC.Handle
local RBD = RBC.BottomRightDoor
local openRB = RBC.Open
local closeRB = RBC.Closed
local RBstatus = RBC.Status

local Ttime = 1.5

--LBottomCabinet--
LBH.ClickDetector.MouseClick:Connect(function()
	if Lstatus.Value == false then
		
		local DoorInfo = TweenInfo.new(Ttime, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, false, 0)
		local tweenOpen = TweenService:Create(LBD, DoorInfo, {CFrame = open.CFrame})
		tweenOpen:Play()
		Lstatus.Value = true
	else
		local DoorInfo = TweenInfo.new(Ttime, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, false, 0)
		local tweenClose = TweenService:Create(LBD, DoorInfo, {CFrame = close.CFrame})

		tweenClose:Play()
		Lstatus.Value = false
	end
end)

--LMiddleCabinet--
LMH.ClickDetector.MouseClick:Connect(function()
	if LMstatus.Value == false then

		local DoorInfo = TweenInfo.new(Ttime, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, false, 0)
		local tweenOpen = TweenService:Create(LMD, DoorInfo, {CFrame = openLM.CFrame})
		tweenOpen:Play()
		LMstatus.Value = true
	else
		local DoorInfo = TweenInfo.new(Ttime, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, false, 0)
		local tweenClose = TweenService:Create(LMD, DoorInfo, {CFrame = closeLM.CFrame})

		tweenClose:Play()
		LMstatus.Value = false
	end
end)

--RMiddleCabinet--
RMH.ClickDetector.MouseClick:Connect(function()
	if RMstatus.Value == false then

		local DoorInfo = TweenInfo.new(Ttime, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, false, 0)
		local tweenOpen = TweenService:Create(RMD, DoorInfo, {CFrame = openRM.CFrame})
		tweenOpen:Play()
		RMstatus.Value = true
	else
		local DoorInfo = TweenInfo.new(Ttime, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, false, 0)
		local tweenClose = TweenService:Create(RMD, DoorInfo, {CFrame = closeRM.CFrame})

		tweenClose:Play()
		RMstatus.Value = false
	end
end)

--RBottomCabinet--
RBH.ClickDetector.MouseClick:Connect(function()
	if RBstatus.Value == false then

		local DoorInfo = TweenInfo.new(Ttime, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, false, 0)
		local tweenOpen = TweenService:Create(RBD, DoorInfo, {CFrame = openRB.CFrame})
		tweenOpen:Play()
		RBstatus.Value = true
	else
		local DoorInfo = TweenInfo.new(Ttime, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, false, 0)
		local tweenClose = TweenService:Create(RBD, DoorInfo, {CFrame = closeRB.CFrame})

		tweenClose:Play()
		RBstatus.Value = false
	end
end)