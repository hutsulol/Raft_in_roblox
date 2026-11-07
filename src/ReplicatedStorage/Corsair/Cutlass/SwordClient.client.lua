--!strict

local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local Sword = script.Parent
local SwordServer = Sword.SwordServer
local CommandEvent = SwordServer.ClientCommand

local LocalPlayer = Players.LocalPlayer
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()

local MouseIcons = {
	Reloading = "rbxasset://textures/GunWaitCursor.png",
	Default = "rbxasset://textures/GunCursor.png",
}

local Actions: { [string]: { Enum.KeyCode } } = {
	SetElectric = { Enum.KeyCode.Q },
	JetBoots = { Enum.KeyCode.E },
	Throw = { Enum.KeyCode.F },
}

-------------------------------------------------------------------------------------------------------------------

local function updateIcon()
	if Sword.Parent ~= Character then
		return
	end
	
	UserInputService.MouseIcon = if Sword.Enabled
		then MouseIcons.Default
		else MouseIcons.Reloading
end

local function handleAction(name: string, state: Enum.UserInputState, input: InputObject)
	if state ~= Enum.UserInputState.Begin then
		return
	end

	if name == "Throw" then
		CommandEvent:FireServer(1)
	elseif name == "SetElectric" then
		CommandEvent:FireServer(2)
	elseif name == "JetBoots" then
		CommandEvent:FireServer(3)
	end
end

-------------------------------------------------------------------------------------------------------------------

local function onEquipped()
	for name, keys in Actions do
		ContextActionService:BindAction(name, handleAction, true, unpack(keys))
	end
	
	updateIcon()
end

local function onUnequipped()
	UserInputService.MouseIcon = ""
	for name, _ in Actions do
		ContextActionService:UnbindAction(name)
	end
end

-------------------------------------------------------------------------------------------------------------------

Sword:GetPropertyChangedSignal("Enabled"):Connect(updateIcon)
Sword.Unequipped:Connect(onUnequipped)
Sword.Equipped:Connect(onEquipped)
