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

-- Меню, которым нужен свободный курсор. HUD'ы (хотбар, стройка, полоски, тосты)
-- сюда НЕ входят намеренно: они живут поверх обычной игры, и разблокировка мыши
-- отобрала бы у игрока обзор от первого лица.
--
-- ⚠️ СПИСОК БЫЛ НЕПОЛНЫМ, и это ровно то, из-за чего в меню монолита нельзя было
-- двигать курсором от первого лица: имени MonolithMenuGui здесь просто не было.
-- Ниже перечислены ВСЕ клик-меню проекта; для новых есть два способа не трогать
-- этот файл — атрибут ModalUI = true на ScreenGui или вызов _G.RegisterModalUI(gui).
local MODAL_UI_NAMES = {
	-- станки и хранилища
	WorkbenchGui = true,
	FurnaceGui = true,
	InventoryGui = true,
	ContainerGui = true,
	-- монолит: и починка, и апгрейды — это одно окно
	MonolithMenuGui = true,
	-- лобби и сейвы
	LobbyCreateGui = true,
	LobbyWaitGui = true,
	LobbyJoinGui = true,
	ContinuePromptGui = true,
	NoSaveGui = true,
	RaftGameOverGui = true,
	-- наёмники, квесты, телефон
	RecruitmentGui = true,
	MercInventory = true,
	MercCommandMenu = true,
	QuestMenuGui = true,
	BrainMazeGui = true,
	PhoneMenu = true,
	-- прочее с кнопками
	EggCaseGui = true,
	SettingsMenu = true,
	--[[ ⚠️ DialogueGui здесь НЕТ намеренно. Кнопка с Modal = true не только
	     отпускает курсор, но и запрещает вращать камеру правой кнопкой мыши —
	     а реплика висит подолгу, и игрок в это время хочет оглядываться
	     («не могу повернуть камеру ПКМ при диалоге»). Курсор в диалоге и так
	     свободен: плашка и кнопки ответов — обычные TextButton. ]]
	AnchorUI = true,
}

local MODAL_ATTRIBUTE = "ModalUI"

local UNLOCK_NAME = "__ModalUnlock"
local activeModalGuis = {}   -- [ScreenGui] = кнопка Modal

-- ОТКРЫТО ЛИ ОКНО. Проверять один только Enabled НЕЛЬЗЯ: половина меню проекта
-- (наёмники, вербовка, приказы, диалог) висит всегда включённой, а прячется через
-- Visible на своём корневом фрейме. Если считать такие меню открытыми, мышь
-- разблокируется навсегда и игрок теряет обзор от первого лица.
local function isOpen(gui)
	if not gui.Parent or not gui.Enabled then return false end
	for _, c in ipairs(gui:GetChildren()) do
		-- собственная кнопка-разблокировщик не в счёт, она видима всегда
		if c.Name ~= UNLOCK_NAME and c:IsA("GuiObject") and c.Visible then return true end
	end
	return false
end

local function attachModal(screenGui)
	if activeModalGuis[screenGui] then return end
	local existing = screenGui:FindFirstChild(UNLOCK_NAME)
	if existing then activeModalGuis[screenGui] = existing return end

	-- Невидимой кнопки с Modal = true достаточно: скрипт камеры ищет в PlayerGui
	-- любую видимую Modal-кнопку и отпускает мышь, найдя её. Само значение Modal
	-- держим в такт с открытостью окна — см. цикл ниже.
	local btn = Instance.new("TextButton")
	btn.Name = UNLOCK_NAME
	btn.Modal = false
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

	activeModalGuis[screenGui] = btn
	screenGui.AncestryChanged:Connect(function(_, parent)
		if not parent then activeModalGuis[screenGui] = nil end
	end)
end

local function isModal(gui)
	return MODAL_UI_NAMES[gui.Name] == true or gui:GetAttribute(MODAL_ATTRIBUTE) == true
end

local function checkChild(child)
	if not child:IsA("ScreenGui") then return end
	if isModal(child) then
		attachModal(child)
		return
	end
	-- Атрибут может проставиться уже после появления окна (окно строится лениво).
	child:GetAttributeChangedSignal(MODAL_ATTRIBUTE):Connect(function()
		if child:GetAttribute(MODAL_ATTRIBUTE) == true then attachModal(child) end
	end)
end

for _, child in playerGui:GetChildren() do
	checkChild(child)
end

playerGui.ChildAdded:Connect(checkChild)

-- Способ для нового меню не трогать этот файл: позвать отсюда свой ScreenGui.
-- Второй способ — атрибут ModalUI = true, он же работает и из Studio.
_G.RegisterModalUI = function(gui)
	if typeof(gui) == "Instance" and gui:IsA("ScreenGui") then attachModal(gui) end
end

-- ОДИН ЦИКЛ НА ВСЁ. Здесь и Modal у кнопок держится в такт с открытостью окон, и
-- страхуется сама мышь: если какой-то чужой скрипт снова запрёт её в центре, на
-- следующем кадре она освободится. Подписываться на Visible каждого фрейма меню
-- смысла нет — окон два десятка, а проверка стоит копейки.
RunService.RenderStepped:Connect(function()
	local anyOpen = false
	for gui, btn in pairs(activeModalGuis) do
		local open = isOpen(gui)
		if btn.Modal ~= open then btn.Modal = open end   -- пишем только на смене
		anyOpen = anyOpen or open
	end
	if anyOpen and UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
end)