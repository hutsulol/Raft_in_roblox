local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
-- QuestEntryButton.client.lua
-- Left-side HUD button that opens the Quest menu. Builds incrementally
-- across A1 → A10 so each commit is testable on its own.
--
-- A1 scope: folder + script + ScreenGui host. Nothing rendered yet.
-- The ScreenGui sits at DisplayOrder 90 — below the phone menu (200)
-- so the phone UI overlaps us when it opens, and below the quest
-- tracker card (Phase H, DisplayOrder 5..something) doesn't matter
-- here. IgnoreGuiInset = false so the button respects Roblox's
-- top-bar inset just like the onboarding tooltip does.
--
-- Public API exposed across A1 → A10 (final shape):
--   _G.SetQuestBadgeCount(n)   -- A7: bumps the red-dot count
--   _G.OpenQuestMenu()         -- A8: stub-warns until Phase B lands
--   J keypress                 -- A10: also fires _G.OpenQuestMenu()

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local SCREENGUI_DISPLAY_ORDER = 90

-- ─── Wood-darkest is reused for the hover label pill (A10) — every
-- other wood/paper colour the original chrome used was deleted along
-- with the chrome itself when we switched to the bare icon asset.
local COLOR_WOOD_DARKEST = Color3.fromRGB( 61,  40,  23)
local COLOR_PAPER_LIGHT  = Color3.fromRGB(243, 230, 204)

-- The icon asset already ships its own wood-frame + paper background,
-- so the click-target is a plain ImageButton — no UICorner / UIStroke
-- / paper fill / inner highlight on our side. Larger than the original
-- 56-px chrome'd version so the baked-in frame reads at HUD distance.
-- ⚠️ РАЗМЕРЫ ПРОПУСКАЕМ ЧЕРЕЗ HudScale.
-- Числа подбирались на мониторе. На телефоне экран у́же в два-три раза, а кнопки
-- оставались прежними — левый столбец занимал пол-экрана и налезал на трекер
-- квеста. Коэффициент один на весь HUD, живёт в HudScale; свой множитель здесь
-- заводить нельзя, иначе кнопки разъедутся между собой.
-- ⚠️ Именно через размер, а НЕ через UIScale на кнопке: UIScale здесь уже занят
-- наведением и нажатием (см. ниже), второй бы с ним спорил.
local Hud = require(game:GetService("ReplicatedStorage"):WaitForChild("HudScale"))

local BTN_SIZE      = Hud.px(78)
-- ЛЕВЫЙ край, НАД иконкой инвентаря (тот же столбик слева-по-центру). Инвентарь
-- (InventoryUI bpHolder) стоит по вертикали в центре экрана; квесты — над ним, с
-- подписью «Квесты» под иконкой, ровно как «Инвентарь» под рюкзаком. Иконку 78px
-- центрируем по оси инвентаря (её иконка центрируется на ~58px от левого края).
-- Отступы масштабируются вместе с иконкой: иначе на телефоне кнопка сжимается, а
-- расстояния между ней и соседями остаются прежними, и столбик рассыпается.
local BTN_MARGIN_X  = Hud.gap(19)     -- левый отступ: воздух, режем сильнее
local BTN_ANCHOR_Y  = 0.5             -- scale; середина экрана по вертикали
-- ⚠️ ШАГ ВНИЗ — ЧЕРЕЗ step(), А НЕ gap(): иначе иконка с подписью станет выше
-- отведённого ей шага и кнопки наедут друг на друга (см. HudScale.step).
local BTN_OFFSET_Y  = -Hud.step(128)  -- выше центра: стоит НАД холдером инвентаря

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "QuestEntryGui"
screenGui.ResetOnSpawn = false
--[[ ⚠️ ЗДЕСЬ false, И ТРОГАТЬ ЭТО НЕЛЬЗЯ.
     Я менял на true, чтобы весь столбик считал высоту от одной точки: у
     Инвентаря, Карты и Настроек стоит true, и «половина высоты» у соседей
     расходится на высоту топбара. Но флаг действует на ВСЕ платформы, и на
     компьютере он сдвинул выверенную раскладку — кнопки поехали вверх и
     наложились там, где раньше всё стояло ровно.
     Разницу в системе отсчёта надо лечить смещениями на телефоне, а не сменой
     флага у половины столбика. ]]
screenGui.IgnoreGuiInset = false
screenGui.DisplayOrder = SCREENGUI_DISPLAY_ORDER
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

-- ─── Quest entry button (just the icon) ─────────────────────────────
-- The supplied asset is a self-contained icon (wood frame + scroll +
-- emerald are baked in), so we render it as a plain ImageButton with
-- no surrounding chrome. Hover / press feel comes from UIScale + Y
-- offset only — there's no fill colour to brighten anymore.
local QUEST_ICON_ASSET = "rbxassetid://119074861532109"

local button = Instance.new("ImageButton")
button.Name = "QuestButton"
button.AnchorPoint = Vector2.new(0, 0.5)
button.Position = UDim2.new(0, BTN_MARGIN_X, BTN_ANCHOR_Y, BTN_OFFSET_Y)
button.Size = UDim2.fromOffset(BTN_SIZE, BTN_SIZE)
button.BackgroundTransparency = 1
button.BorderSizePixel = 0
button.AutoButtonColor = false
button.Image = QUEST_ICON_ASSET
button.ScaleType = Enum.ScaleType.Fit
button.ZIndex = 1
button.Parent = screenGui

-- ─── Hover / pressed state animation (A5 + A6) ──────────────────────
-- UIScale drives the bounce; UIScale composes cleanly with the
-- Position offset added in the press path so the two states don't
-- fight over the same property. (TweenService уже взят наверху файла.)

local btnScale = Instance.new("UIScale")
btnScale.Scale = 1
btnScale.Parent = button

local HOVER_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function setHover(isHover)
	-- Hover scales up slightly so the button reads as interactive.
	-- No more "brighten fill" tween — there's no fill anymore now
	-- that the wood frame moved into the asset itself.
	TweenService:Create(btnScale, HOVER_INFO, {
		Scale = isHover and 1.05 or 1.0,
	}):Play()
end

button.MouseEnter:Connect(function()
	setHover(true)
end)
button.MouseLeave:Connect(function()
	setHover(false)
end)

-- A6: pressed state. Scale to 0.96 + nudge the button 1 px down so
-- it reads as physically depressed (the same trick the mockup's
-- .btn:active uses with translateY(2px)). MouseButton1Up restores
-- the resting state — including a stale press-leave fallback for
-- the case where the mouse leaves the button while held down.
local restingPosition = button.Position
local pressedPosition = restingPosition + UDim2.fromOffset(0, 1)
local PRESS_INFO = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function setPressed(isPressed)
	TweenService:Create(btnScale, PRESS_INFO, {
		Scale = isPressed and 0.96 or 1.03, -- 1.03 because we're still inside the hover
	}):Play()
	TweenService:Create(button, PRESS_INFO, {
		Position = isPressed and pressedPosition or restingPosition,
	}):Play()
end

button.MouseButton1Down:Connect(function()
	setPressed(true)
end)
button.MouseButton1Up:Connect(function()
	setPressed(false)
end)
-- If the player drags off the button while still holding the mouse
-- down, MouseButton1Up never fires here — MouseLeave does. Reset.
button.MouseLeave:Connect(function()
	setPressed(false)
end)

-- ─── Notification badge (A7) ────────────────────────────────────────
-- Red dot in the top-right of the button, with an optional count
-- label inside it for >1 claimable rewards. Driven by the global
-- _G.SetQuestBadgeCount(n) setter so the Phase C server flow can
-- bump it without reaching into this file. n=0 hides the badge.
-- ⚠️ ВОСКЛИЦАТЕЛЬНЫЙ ЗНАК — ТЕПЕРЬ КАРТИНКА, А НЕ КРУЖОК С БУКВОЙ.
-- Раньше значок собирался кодом: красный Frame, скругление, белая обводка и
-- TextLabel «!» поверх. Смысл тот же — «есть что-то новое, загляни», — но вид
-- задавался пятью объектами и тремя цветами прямо здесь, мимо рисованного стиля
-- остального HUD. Один ImageLabel заменяет всё это, и правка вида больше не
-- требует лезть в код.
-- Размер чуть больше прежнего: у рисованного знака есть собственные поля внутри
-- картинки, и в 22 пикселя он выглядел мельче старого кружка.
local BADGE_SIZE  = Hud.gap(28)   -- значок «!» — не кнопка, палец сюда не нужен
local BADGE_INSET = Hud.gap(4)

local badge = Instance.new("ImageLabel")
badge.Name = "Badge"
-- ⚠️ ЯКОРЬ В ЦЕНТРЕ, ИНАЧЕ ПУЛЬСАЦИЯ РАСТЁТ ВБОК.
-- Значок висел на якоре (1, 0) — за свой верхний правый угол. UIScale ниже
-- увеличивает РАЗМЕР, а точка якоря при этом остаётся прибитой: значок разбухал
-- влево-вниз, наползая на иконку квестов, вместо того чтобы дышать вокруг себя.
-- Ставим якорь в центр и на столько же сдвигаем позицию — стоит там же, где
-- стоял, но растёт теперь во все стороны одинаково.
badge.AnchorPoint = Vector2.new(0.5, 0.5)
badge.Position = UDim2.new(1, BADGE_INSET - BADGE_SIZE / 2, 0, BADGE_SIZE / 2 - BADGE_INSET)
badge.Size = UDim2.fromOffset(BADGE_SIZE, BADGE_SIZE)
badge.BackgroundTransparency = 1
badge.BorderSizePixel = 0
badge.Image = "rbxassetid://127581807351214"
badge.ScaleType = Enum.ScaleType.Fit
badge.Visible = false
badge.ZIndex = 5
badge.Parent = button

-- лёгкая пульсация: значок должен ловить взгляд, но не мигать назойливо
local badgeScale = Instance.new("UIScale")
badgeScale.Parent = badge
local badgePulse = TweenService:Create(badgeScale,
	TweenInfo.new(0.85, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
	{ Scale = 1.18 })

local function setBadge(on)
	if badge.Visible == on then return end
	badge.Visible = on
	if on then
		badgeScale.Scale = 1
		badgePulse:Play()
	else
		badgePulse:Cancel()
		badgeScale.Scale = 1
	end
end

-- Совместимость: прежняя ручка осталась, но теперь это просто «показать/скрыть».
_G.SetQuestBadgeCount = function(n)
	setBadge((tonumber(n) or 0) > 0)
end

-- ─── Что считается «новым» ──────────────────────────────────────────
-- ⚠️ ДВА РАЗНЫХ ПОВОДА, И ГАСНУТ ОНИ ПО-РАЗНОМУ.
--   • НАГРАДА ЖДЁТ (rewardPending) — горит, пока её не заберут. Открыть меню и
--     не забрать не должно гасить значок: награда-то на месте.
--   • НОВЫЙ КВЕСТ — тот, чей id игрок ещё не видел в меню. Гаснет, как только
--     меню открыли: он его увидел, дальше напоминать не о чем.
-- Отсюда и два отдельных флага вместо одного «есть что-то».
local seenQuests = {}      -- [id] = true, если игрок уже открывал меню при нём
local rewardWaiting = false
local unseenQuest = false
local lastQuests = {}      -- последний снимок: по нему помечаем «увидел»

local function refreshBadge()
	setBadge(rewardWaiting or unseenQuest)
end

local questStateEvent = ReplicatedStorage:WaitForChild("QuestState", 30)
if questStateEvent then
	questStateEvent.OnClientEvent:Connect(function(action, payload)
		if action ~= "state" or type(payload) ~= "table" then return end
		lastQuests = payload.quests or {}
		rewardWaiting, unseenQuest = false, false
		for _, q in ipairs(lastQuests) do
			if q.rewardPending then rewardWaiting = true end
			-- выполненный и закрытый квест новым не считается
			if not seenQuests[q.id] and not q.completed then unseenQuest = true end
		end
		refreshBadge()
	end)
end

-- Меню открыли — всё, что в нём сейчас лежит, считается увиденным.
local function markSeen()
	for _, q in ipairs(lastQuests) do
		seenQuests[q.id] = true
	end
	unseenQuest = false
	refreshBadge()
end

-- ─── Click: open the quest menu (A8) ────────────────────────────────
-- Phase B installs _G.OpenQuestMenu; until then we warn-stub so the
-- click is wired up + reviewable in advance and the integration is a
-- one-liner when the menu lands. The keybind in A10 routes through
-- the same opener for parity.
local function openQuestMenu()
	if typeof(_G.OpenQuestMenu) == "function" then
		_G.OpenQuestMenu()
	else
		warn("[QuestEntryButton] _G.OpenQuestMenu is not yet defined — Phase B lands the menu")
	end
end

button.MouseButton1Click:Connect(openQuestMenu)

-- ─── Hide while the phone menu is open (A9) ─────────────────────────
-- The phone covers most of the screen and has its own quest log
-- inside it; leaving the entry button on top of the phone UI would
-- read as a stray duplicate. PhoneMenu.client.lua publishes the
-- ScreenGui at _G.PhoneScreenGui and toggles .Enabled on open/close
-- (same handshake the inventory tooltip uses). Listen for that
-- changed event so we sync within a frame of the phone state.
local RunService = game:GetService("RunService")

local function isOverlayOpen()
	-- Phone menu hides us because it's a full-screen overlay with
	-- its own quest log inside; quest menu hides us because it's
	-- the destination this button leads to (no point in showing
	-- the entry once the menu is open); the building UI hides us
	-- because its category strip lives at the bottom-left and the
	-- entry would overlap it (T9). Each publishes its ScreenGui to
	-- _G so we can listen on the same handshake.
	for _, key in ipairs({ "PhoneScreenGui", "QuestMenuScreenGui", "BuildingScreenGui" }) do
		local gui = _G[key]
		if gui and gui:IsA("ScreenGui") and gui.Enabled then
			return true
		end
	end
	return false
end

local function syncVisibility()
	screenGui.Enabled = not isOverlayOpen()
end

-- Both PhoneScreenGui (PhoneMenu builds it lazily on first open) and
-- QuestMenuScreenGui (QuestMenu builds it lazily too) may not exist
-- yet when this script first runs. Poll briefly until each appears,
-- then bind to its Enabled-changed signal so we react immediately
-- without further polling.
local function bindGuiHandshake(globalKey)
	task.spawn(function()
		local deadline = os.clock() + 30
		while os.clock() < deadline do
			local gui = _G[globalKey]
			if gui and gui:IsA("ScreenGui") then
				gui:GetPropertyChangedSignal("Enabled"):Connect(function()
					syncVisibility()
					-- меню квестов открыли — квесты в нём считаются увиденными
					if globalKey == "QuestMenuScreenGui" and gui.Enabled then
						markSeen()
					end
				end)
				syncVisibility()
				return
			end
			task.wait(0.5)
		end
	end)
end

bindGuiHandshake("PhoneScreenGui")
bindGuiHandshake("QuestMenuScreenGui")

-- Heartbeat fallback catches the case where _G.PhoneScreenGui /
-- QuestMenuScreenGui swap reference at runtime (re-spawn, hot
-- reload, etc.) or where the polling deadline expires before the
-- gui has been built (game shipped without one of the menus).
RunService.Heartbeat:Connect(syncVisibility)

syncVisibility()

-- ─── Hover tooltip + J hotkey (A10) ─────────────────────────────────
-- Small "Quests (J)" label that pops next to the button on hover so
-- new players know what the icon does + that there's a keyboard
-- shortcut. The J key opens the menu via the same opener used by
-- click — gameProcessed-aware so typing 'j' in chat doesn't trip it.
local UserInputService = game:GetService("UserInputService")

-- ПОСТОЯННАЯ подпись «Квесты» ПОД иконкой — 1-в-1 стиль подписи «Инвентарь»
-- (InventoryUI: GothamBold 16, белый, обводка 0.3, наезжает на низ иконки).
local labelText = Instance.new("TextLabel")
labelText.Name = "CaptionLabel"
labelText.AnchorPoint = Vector2.new(0.5, 0.5)
labelText.Position = UDim2.new(0.5, 0, 1, -6) -- наезжает на низ иконки, как у рюкзака
-- ⚠️ Подпись тоже сжимается: сырые 120×20 на телефоне шире самой кнопки в
-- два с половиной раза и наезжают на соседний столбец.
labelText.Size = UDim2.new(1, Hud.px(6), 0, Hud.px(20))
labelText.TextScaled = true
Instance.new("UITextSizeConstraint", labelText).MaxTextSize = Hud.text(16)
--[[ ⚠️ ПОДПИСЬ НЕ ДОЛЖНА БЫТЬ ШИРЕ ШАГА МЕЖДУ КНОПКАМИ.
     120 пикселей задумывались под монитор, где иконки крупные и стоят просторно.
     На телефоне иконка ужимается сильно (px), а зазор между колонками — ещё
     сильнее (gap, это воздух), и подпись оказывалась заметно шире собственной
     кнопки: «Квесты» налезали на «Магазин», «Инвентарь» на «Карту».
     Привязываем ширину к самой кнопке и разрешаем шрифту ужиматься: слово
     останется целым, а за свою колонку не вылезет. ]]
labelText.BackgroundTransparency = 1
labelText.BorderSizePixel = 0
labelText.Font = Enum.Font.GothamBold
labelText.TextSize = Hud.text(16)
labelText.TextColor3 = Color3.new(1, 1, 1)
labelText.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
labelText.TextStrokeTransparency = 0.3
labelText.Text = "Квесты"
labelText.AutoLocalize = true
labelText.ZIndex = 4
labelText.Parent = button

-- N keybind. Skip when the input was already consumed (chat, text
-- box) and when the entry button is hidden — typically because the
-- phone menu has its own menu open and N shouldn't ALSO open the
-- quest UI on top.
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode ~= Enum.KeyCode.N then return end
	if not screenGui.Enabled then return end
	openQuestMenu()
end)