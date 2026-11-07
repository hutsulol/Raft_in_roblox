--//Pirate_Gun — GUIScript (client)
--//Displays ammo / reserve, like the AK kit. The ScreenGui lives at
--//Pirate_Gun > GUI > GUI (a folder named "GUI" holding the ScreenGui "GUI").

--//Variables\\--
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local tool = script.Parent.Parent
local configs = tool:WaitForChild("Configs")
local ammo = configs:WaitForChild("Ammo")
local reserveAmmo = configs:WaitForChild("ReserveAmmo")
local magSize = configs:WaitForChild("MagSize")

--//The ScreenGui you placed at Pirate_Gun > GUI > GUI
local guiFolder = tool:WaitForChild("GUI")
local gui = guiFolder:WaitForChild("GUI")
--//labels found recursively, so they work whether they sit directly under the
--//ScreenGui (like the AK kit) or inside a Frame
local ammoLabel = gui:FindFirstChild("Ammo", true)
local resAmmoLabel = gui:FindFirstChild("ReserveAmmo", true)
local nameLabel = gui:FindFirstChild("Name", true)

--//Functions\\--
local function update()
	--//Set texts
	if nameLabel then nameLabel.Text = tool.Name end
	if ammoLabel then ammoLabel.Text = tostring(ammo.Value) end
	if resAmmoLabel then resAmmoLabel.Text = tostring(reserveAmmo.Value) end

	--//Indicator checks (red when low — same rule as the AK kit)
	local low = math.floor(magSize.Value * 0.2)
	if ammoLabel then
		ammoLabel.TextColor3 = (ammo.Value < low) and Color3.fromRGB(255, 0, 0) or Color3.fromRGB(255, 255, 255)
	end
	if resAmmoLabel then
		resAmmoLabel.TextColor3 = (reserveAmmo.Value < low) and Color3.fromRGB(255, 0, 0) or Color3.fromRGB(255, 255, 255)
	end
end

--//Event listeners\\--
ammo.Changed:Connect(update)
reserveAmmo.Changed:Connect(update)

tool.Equipped:Connect(function()
	--// родной ammo-GUI больше НЕ показываем — патроны/имя рисует общий WeaponHUD
	gui.Enabled = false
	update()
end)

tool.Unequipped:Connect(function()
	gui.Parent = guiFolder
end)

--//Initialization\\--
update()
