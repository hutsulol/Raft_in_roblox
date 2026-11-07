--[[ GamepadInput — ОДНО МЕСТО, ГДЕ РЕШАЕТСЯ, ЧТО НА ГЕЙМПАДЕ СЧИТАТЬ КЛИКОМ И КЛАВИШЕЙ.

     До этого с геймпада нельзя было даже срубить дерево: тридцать с лишним
     клиентских скриптов слушают ЛКМ/тап и клавиши E/Q/R, каждый своей
     проверкой, и ни одна не знала про кнопки контроллера. Раскладка:

       ЛКМ / тап                 → R2 (правый курок)   — «действие»: удар, бросок, поставить
       E  (взять, открыть, войти) → X                   — как у штатных ProximityPrompt
       R  (повернуть постройку)   → Y
       Q  (назад / бросить)       → B
       1…8 (слот хотбара)         → L1 / R1 — предыдущий / следующий слот
       ВВЕРХ/ВНИЗ у лебёдки       → крестовина вверх / вниз
       курсор                     → прицел в центре экрана (см. GamepadAdapter)

     ⚠️ ПОЧЕМУ ЦЕНТР ЭКРАНА, А НЕ ВИРТУАЛЬНЫЙ КУРСОР.
     Все лучи в мир идут «от мыши»: mouse.Hit, mouse.Target, mouse.X/Y,
     GetMouseLocation. На геймпаде курсора нет. Если запереть его в центре
     (MouseBehavior = LockCenter), Roblox отчитывается центром экрана во всех
     этих свойствах — и каждый скрипт целится в прицел, не зная ни о каком
     геймпаде. Правый стик при этом крутит камеру штатно. Это и делает
     GamepadAdapter; здесь — только правила, чтобы проверки во всех файлах
     звучали одинаково.

     Файлы, которые упёрлись в предел локальных переменных Luau (BuildingSystem),
     модуль НЕ подключают: там кнопки дописаны прямо в списки BindAction. ]]

local UserInputService = game:GetService("UserInputService")

local GamepadInput = {}

-- какая кнопка контроллера заменяет клавишу
GamepadInput.KEY_FOR = {
	[Enum.KeyCode.E] = Enum.KeyCode.ButtonX,
	[Enum.KeyCode.R] = Enum.KeyCode.ButtonY,
	[Enum.KeyCode.Q] = Enum.KeyCode.ButtonB,
	[Enum.KeyCode.X] = Enum.KeyCode.ButtonB,   -- «отмена» у пушки
}

local function isGamepadType(t)
	return t == Enum.UserInputType.Gamepad1 or t == Enum.UserInputType.Gamepad2
		or t == Enum.UserInputType.Gamepad3 or t == Enum.UserInputType.Gamepad4
end
GamepadInput.isGamepadType = isGamepadType

--[[ Играют ли сейчас с геймпада: последний ввод пришёл с него. Мышь или
     касание сразу возвращают прежний режим — переключение бесшовное. ]]
function GamepadInput.active()
	return isGamepadType(UserInputService:GetLastInputType())
end

--[[ «Клик» в мир: ЛКМ, тап или правый курок. Одна проверка на все файлы,
     чтобы не было третьей копии условия с четвёртым вариантом. ]]
function GamepadInput.isPrimary(input)
	local t = input.UserInputType
	if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
		return true
	end
	return isGamepadType(t) and input.KeyCode == Enum.KeyCode.ButtonR2
end

--[[ Нажата ли клавиша key — или её кнопка на геймпаде. ]]
function GamepadInput.isKey(input, key)
	if input.KeyCode == key then return true end
	local pad = GamepadInput.KEY_FOR[key]
	return pad ~= nil and input.KeyCode == pad and isGamepadType(input.UserInputType)
end

--[[ Замена mouse.Button1Down:Connect(fn): тот же fn и на правый курок.
     ⚠️ Курок принимаем только «мимо интерфейса» (processed = false): когда
     открыто меню, R2 — это нажатие в меню, а не удар по дереву за ним. У
     Button1Down такого флага нет, там всё как было. ]]
function GamepadInput.onPrimary(mouse, fn)
	local c1 = mouse.Button1Down:Connect(fn)
	local c2 = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if isGamepadType(input.UserInputType) and input.KeyCode == Enum.KeyCode.ButtonR2 then
			fn()
		end
	end)
	return c1, c2
end

--[[ Список клавиш для ContextActionService:BindAction — с кнопками геймпада
     в хвосте. Пример: BindAction(name, fn, false, unpack(GamepadInput.keys(Enum.KeyCode.R))) ]]
function GamepadInput.keys(...)
	local out = {}
	for _, k in ipairs({ ... }) do
		table.insert(out, k)
		local pad = GamepadInput.KEY_FOR[k]
		if pad then table.insert(out, pad) end
	end
	return out
end

-- подпись для подсказок: «E» на клавиатуре, «X» на геймпаде
function GamepadInput.keyLabel(key)
	if GamepadInput.active() then
		local pad = GamepadInput.KEY_FOR[key]
		if pad == Enum.KeyCode.ButtonX then return "X" end
		if pad == Enum.KeyCode.ButtonY then return "Y" end
		if pad == Enum.KeyCode.ButtonB then return "B" end
		if pad == Enum.KeyCode.ButtonR2 then return "R2" end
	end
	return key.Name
end

return GamepadInput
