-- ModalUIUnlocker.client.lua
-- Releases the mouse cursor whenever a click-driven UI is open.
--
-- The default Roblox camera script keeps MouseBehavior = LockCenter while
-- in first-person mode, which makes click-based UIs unusable: the cursor
-- stays glued to the screen center, so the player cannot reach the close
-- button on the workbench, furnace, lobby dialogs, etc.
--
-- The documented Roblox fix is to put a GuiButton with Modal = true into
-- the open UI; the camera script honors this and releases the mouse. We
-- attach an invisible Modal button to every modal ScreenGui as it appears.
-- We also force MouseBehavior = Default each frame as a belt-and-braces
-- backup, in case some other script tries to re-lock the mouse.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Names of ScreenGuis that need a free cursor when open. HUDs (HotbarGui,
-- BuildingGui, health/hunger bars, etc.) are intentionally excluded — they
-- coexist with normal gameplay and must NOT unlock the mouse.
local MODAL_UI_NAMES = {
	WorkbenchGui = true,
	FurnaceGui = true,
	InventoryGui = true,
	LobbyCreateGui = true,
	LobbyWaitGui = true,
	LobbyJoinGui = true,
	ContinuePromptGui = true,
	NoSaveGui = true,
}

local activeModalGuis = {}

local function attachModal(screenGui)
	if screenGui:FindFirstChild("__ModalUnlock") then return end

	-- An invisible GuiButton with Modal = true is enough — the camera
	-- script checks for any visible Modal button in PlayerGui and
	-- releases the mouse when it finds one.
	local btn = Instance.new("TextButton")
	btn.Name = "__ModalUnlock"
	btn.Modal = true
	btn.Visible = true
	btn.Active = true
	btn.BackgroundTransparency = 1
	btn.TextTransparency = 1
	btn.Text = ""
	btn.AutoButtonColor = false
	btn.Size = UDim2.new(0, 1, 0, 1)
	btn.Position = UDim2.new(0, 0, 0, 0)
	btn.ZIndex = 1
	btn.Parent = screenGui

	activeModalGuis[screenGui] = true
	screenGui.AncestryChanged:Connect(function(_, parent)
		if not parent then
			activeModalGuis[screenGui] = nil
		end
	end)
end

local function checkChild(child)
	if child:IsA("ScreenGui") and MODAL_UI_NAMES[child.Name] then
		attachModal(child)
	end
end

for _, child in playerGui:GetChildren() do
	checkChild(child)
end

playerGui.ChildAdded:Connect(checkChild)

-- Backup: force unlock cursor each frame while a modal UI exists.
RunService.RenderStepped:Connect(function()
	for gui in pairs(activeModalGuis) do
		if gui.Parent then
			if UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
				UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			end
			return
		end
	end
end)
