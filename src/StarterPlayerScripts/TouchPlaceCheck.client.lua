local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
-- TouchPlaceCheck.client.lua
-- ЕСЛИ МОДУЛЬ УСТАНОВКИ НЕ ДОЕХАЛ — ГОВОРИМ ОБ ЭТОМ НА ЭКРАНЕ, А НЕ В КОНСОЛЬ.
--
-- ⚠️ ЗАЧЕМ ОТДЕЛЬНЫЙ СТОРОЖ.
-- Одиннадцать ставилок ждут ReplicatedStorage.TouchPlace с таймаутом и, не
-- дождавшись, работают по-старому: тап ставит предмет там, где палец. На
-- компьютере это ровно прежнее поведение и никого не смущает, а на телефоне
-- выглядит как «баг вернулся»: кнопок нет, предмет ставится куда попало.
-- Отличить «модуль не доехал» от «модуль есть, но не работает» с телефона
-- нельзя: консоль F9 там открывают единицы. Поэтому один раз при входе
-- проверяем сами и, если модуля нет, пишем прямо в кадр — с готовым ответом,
-- что делать (перезапустить синхронизацию: сессия, поднятая до появления
-- нового файла, его не подхватывает).
--
-- Проверка стоит один FindFirstChild и живёт пять секунд. Когда всё на месте,
-- игрок не видит ничего.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")

local player = Players.LocalPlayer

-- на компьютере отсутствие модуля ничего не меняет: там и раньше ставили мышью
local isPhone = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
if not isPhone then return end

task.spawn(function()
	-- тот же таймаут, что у самих ставилок: раньше него жаловаться не на что
	--[[ Спрашиваем HudScale, а не отдельный файл: механика живёт в нём, и он в
	     плейсе давно. Новый файл мог просто не доехать — это и проверяем. ]]
	local hud = ReplicatedStorage:FindFirstChild("HudScale")
		or ReplicatedStorage:WaitForChild("HudScale", 6)
	local ok, mod = pcall(require, hud)
	if ok and type(mod) == "table" and type(mod.Place) == "table" then
		print("[Установка] механика постановки на месте — тап целится, кнопка ставит")
		return
	end

	warn("[Установка] механика постановки НЕ доехала до клиента — кнопок не будет")

	local gui = Instance.new("ScreenGui")
	gui.Name = "TouchPlaceMissing"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 200
	gui.Parent = player:WaitForChild("PlayerGui")

	local plate = Instance.new("TextLabel")
	plate.AnchorPoint = Vector2.new(0.5, 0)
	plate.Position = UDim2.new(0.5, 0, 0.22, 0)
	plate.Size = UDim2.new(0, 0, 0, 44)
	plate.AutomaticSize = Enum.AutomaticSize.XY
	plate.BackgroundColor3 = Color3.fromRGB(150, 40, 40)
	plate.BackgroundTransparency = 0.1
	plate.BorderSizePixel = 0
	plate.Font = Enum.Font.GothamBold
	plate.TextSize = 16
	plate.TextWrapped = true
	plate.TextColor3 = Color3.new(1, 1, 1)
	plate.Text = "Модуль постановки не загрузился.\nПерезапусти синхронизацию Rojo и зайди снова."
	plate.Parent = gui

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 16)
	pad.PaddingRight = UDim.new(0, 16)
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.Parent = plate

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = plate

	local cap = Instance.new("UISizeConstraint")
	local cam = workspace.CurrentCamera
	cap.MaxSize = Vector2.new((cam and cam.ViewportSize.X or 1280) * 0.8, math.huge)
	cap.Parent = plate

	task.wait(12)
	gui:Destroy()
end)
