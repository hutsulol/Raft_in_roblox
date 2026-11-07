local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
--[[
	Адаптация HUD под телефон.

	⚠️ ЭТО НЕ «УМЕНЬШИТЬ ВСЁ В N РАЗ».
	Первая версия так и делала — один коэффициент на всё, — и вышло плохо сразу с двух
	сторон: на компьютере HUD съёжился (см. ниже про ViewportSize), а на телефоне
	иконки стали мелкими для пальца, хотя занимали места всё равно много: сжимались и
	кнопки, и промежутки между ними в одинаковой пропорции.

	Правильно — сжимать РАЗНОЕ ПО-РАЗНОМУ:
	    px(n)   — кнопки и иконки. Сжимаются слабо и никогда не мельче пальца.
	    gap(n)  — отступы, промежутки, смещения. Сжимаются сильно: именно они и едят
	              экран, а на них пальцем не попадают.
	    factor() — для целой готовой панели одним UIScale (МЕНЮ во весь экран).
	    cardFactor() — для карточки HUD (трекер квеста, уведомление, баннер подсказки):
	              она и так компактная, её нельзя жать как меню.
	    text(n)  — размер шрифта. Сжимается почти незаметно и не опускается ниже
	              порога читаемости.
	Место на узком экране освобождается за счёт воздуха, а не за счёт того, во что надо
	попадать.

	⚠️ ТЕЛЕФОН ОПРЕДЕЛЯЕМ ПО ОТСУТСТВИЮ МЫШИ, А НЕ ПО ШИРИНЕ ЭКРАНА.
	Ширина ненадёжна ровно там, где это больнее всего: HUD собирается в первые кадры,
	а workspace.CurrentCamera.ViewportSize к этому моменту ещё не окончательный. Из-за
	этого интерфейс сжимался НА КОМПЬЮТЕРЕ — числа успевали посчитаться от временного
	маленького размера. TouchEnabled в одиночку тоже не годится: он правдив на ноутбуке
	с сенсорным экраном. Работает связка «касание есть, мыши нет» — она известна сразу
	и не меняется по ходу игры.

		local Hud = require(ReplicatedStorage.HudScale)
		btn.Size = UDim2.fromOffset(Hud.px(78), Hud.px(78))
		btn.Position = UDim2.new(0, Hud.gap(19), 0.5, -Hud.gap(128))
		Hud.applyScaleLive(panel)          -- целую панель проще одним UIScale
]]

local UserInputService = game:GetService("UserInputService")

local HudScale = {}

-- Кнопки: сжимаем и держим не мельче пальца.
-- 0.7, а не 0.82: при 0.82 столбик Квесты/Карта подходил вплотную к трекеру квеста
-- и накрывал его. Заодно и шаг вниз считается от этого же числа (step), поэтому
-- уменьшение множителя ПОДТЯГИВАЕТ столбик к центру, освобождая место сверху.
--[[ ⚠️ 0.85, А НЕ 0.7. Прежнее число делало иконку 78 → 39 пикселей, и её
     спасал только пол MIN_TOUCH_PX: на экране стояли кнопки ровно в палец
     шириной, с подписью почти во всю иконку. Владелец так и сказал: «налазят
     друг на друга, сделай больше». 0.85 даёт 48 пикселей на низком экране и
     около 58 на высоком — палец попадает с запасом, подпись помещается. ]]
local TOUCH_FACTOR = 0.85
local MIN_TOUCH_PX = 44
-- Воздух: вот его и режем. Столбик из четырёх кнопок перестаёт занимать пол-экрана
-- именно за счёт промежутков.
local GAP_FACTOR   = 0.55
-- Целая панель одним UIScale. 0.55, а не 0.7: при 0.7 меню квестов и настроек всё
-- ещё занимали почти весь экран телефона — панели рисовались под 720px ширины.
local PANEL_FACTOR = 0.55

--[[ ⚠️ ШАГ В СТОЛБИКЕ СЧИТАЕТСЯ ОТ ИКОНКИ, А НЕ ОТ ВОЗДУХА.
     Кнопки Квесты / Карта / Инвентарь / Настройки стоят одна под другой, и каждая
     знает только своё смещение от центра экрана. Я прогнал эти смещения через gap()
     — и шаг сжался сильнее самих иконок: иконка с подписью стала ВЫШЕ отведённого ей
     шага, кнопки наехали друг на друга, а рюкзак вообще скрылся за соседями.

     ⚠️ НО И РОВНО КАК ИКОНКА — ТОЖЕ НЕВЕРНО, И ЭТО ВТОРАЯ ПОЛОВИНА ЖАЛОБЫ.
     Здесь стояло `return HudScale.px(n)`, то есть шаг сжимался тем же числом, что
     иконка. Пропорция столбика при этом сохраняется — но только пока всё внутри
     ряда сжимается одинаково. У подписи есть свой пол читаемости: она НЕ
     уменьшается вместе с иконкой, а значит ряд занимает больше, чем ему отвели, и
     подпись верхней кнопки ложится на иконку нижней. Ровно это на экране и видно.
     Поэтому у шага свой множитель, крупнее иконочного: воздуха между рядами
     становится больше, чем было бы при простом пропорциональном сжатии.
     Пола MIN_TOUCH_PX здесь нет намеренно — это расстояние, а не кнопка: пальцем
     по нему не попадают, и поднимать маленькие шаги до 44 пикселей значило бы
     растащить столбик на пол-экрана.

     ⚠️ САМА ФУНКЦИЯ ЖИВЁТ НИЖЕ, ПОСЛЕ heightK. Здесь ей не место: heightK —
     локальная функция, объявленная дальше по файлу, и обращение к ней отсюда
     ушло бы в глобальную область, где её нет. Скрипт падал бы на первом же
     вызове step() на телефоне, а на компьютере молчал бы. ]]
local STEP_FACTOR = 0.95

--[[ Телефон это или нет. Решается один раз и не зависит от кадра. ]]
function HudScale.isPhone()
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

--[[ ⚠️ ОДНОГО «ЭТО ТЕЛЕФОН» МАЛО — ВАЖНА ВЫСОТА ЭКРАНА.
     Множитель был постоянным, поэтому на вытянутом телефоне (широко, но низко)
     столбик кнопок занимал пол-экрана: пять рядов по 55 пикселей при высоте
     под 600 — это и есть «слишком большое UI». Досчитываем поправку от высоты
     окна относительно 720: на низком экране всё дополнительно ужимается, на
     планшете остаётся как было.

     Ниже 0.72 не опускаемся — дальше кнопки становятся мельче пальца, а
     MIN_TOUCH_PX это всё равно не даст. ]]
local REF_HEIGHT = 720

--[[ ⚠️ ПОЛ 0.72 — ПРОВЕРЕННЫЙ, НЕ ТРОГАТЬ БЕЗ ЦИФР С ТЕЛЕФОНА.
     Я опускал его до 0.45, чтобы столбик кнопок влез на низкий Android
     тестера, — и уменьшил кнопки у тех, у кого всё стояло ровно (iPhone
     16 Pro Max). Причина: на обоих телефонах при старом поле множитель был
     ОДИН И ТОТ ЖЕ, 0.72, а картинка разная — значит, дело у тестера не в
     высоте окна, и крутить общую формулу вслепую нельзя.
     Что именно у него — скажет строка [HudScale] в логе (ниже): экран,
     множитель и флаги TouchEnabled/MouseEnabled. Пока её нет, размер
     остаётся тем, что владелец видел как правильный. ]]
local HEIGHT_K_MIN = 0.72

local function heightK()
	local cam = workspace.CurrentCamera
	local h = cam and cam.ViewportSize.Y or 0
	if h <= 0 then return 1 end
	return math.clamp(h / REF_HEIGHT, HEIGHT_K_MIN, 1)
end

-- Минимум «под палец» постоянный: 44 пикселя, как и было до правки.
local function minTouchPx()
	return MIN_TOUCH_PX
end

--[[ Итоговый множитель для телефона: базовый × поправка на высоту. ]]
local function touchK()
	return TOUCH_FACTOR * heightK()
end

--[[ Размер кнопки/иконки. Никогда не мельче MIN_TOUCH_PX, если исходник был крупнее. ]]
function HudScale.px(n)
	if not HudScale.isPhone() then return n end
	local v = math.floor(n * touchK() + 0.5)
	local floorPx = minTouchPx()
	if n >= floorPx then v = math.max(v, floorPx) end
	return v
end

--[[ Отступ, промежуток, смещение. Сжимается сильнее кнопок — на них не нажимают. ]]
function HudScale.gap(n)
	if not HudScale.isPhone() then return n end
	return math.floor(n * GAP_FACTOR * heightK() + 0.5)
end

--[[ Шаг ряда в левом столбике. Объяснение множителя — у STEP_FACTOR выше. ]]
function HudScale.step(n)
	if not HudScale.isPhone() then return n end
	return math.floor(n * STEP_FACTOR * heightK() + 0.5)
end

--[[ Коэффициент для целой панели (UIScale). 1 на компьютере. ]]
-- ⚠️ У панелей свой пол 0.72 — тот, что раньше стоял в heightK. Их этот
-- пересчёт не касается: меню на низком экране и так ужимаются собственными
-- правилами (fitFactor у квестов и т. п.), а 0.55 × 0.45 = 0.25 — нечитаемо.
function HudScale.factor()
	return HudScale.isPhone() and (PANEL_FACTOR * math.max(heightK(), 0.72)) or 1
end

--[[ ⚠️ КОЭФФИЦИЕНТ ДЛЯ КНОПКИ, КОТОРУЮ СЖИМАЮТ ЦЕЛИКОМ ЧЕРЕЗ UIScale.
     Кнопки левого столбика сделаны по-разному: у Квестов и Карты размер задаётся
     числом (px), у Инвентаря и Настроек — целым холдером через applyScale. Пока
     вторые шли через factor() (панельный, 0.55), а первые через px() (0.82), иконки
     в одном столбике стали РАЗНОГО размера — это было видно сразу.
     Здесь тот же множитель, что у px, чтобы способ реализации не влиял на вид. ]]
function HudScale.iconFactor()
	return HudScale.isPhone() and touchK() or 1
end

--[[ Один раз на сессию: экран, множитель и ГЛАВНОЕ — флаги ввода.
     Печатаем на любом устройстве, не только на «телефоне по нашему
     определению»: если у тестера Android отчитывается MouseEnabled = true,
     isPhone() даёт false, интерфейс рисуется в размерах компьютера — и это
     как раз похоже на его скриншот. Без строки этого не отличить от
     «низкий экран». Размеры на чужих телефонах мы иначе не видим. ]]
task.defer(function()
	local cam = workspace.CurrentCamera
	for _ = 1, 50 do
		if cam and cam.ViewportSize.Y > 1 then break end
		task.wait(0.1)
		cam = workspace.CurrentCamera
	end
	local vp = cam and cam.ViewportSize or Vector2.new(0, 0)
	print(("[HudScale] экран %dx%d | touch=%s mouse=%s → телефон=%s | "
		.. "множитель кнопок %.2f, иконка 78 → %d, шаг 128 → %d"):format(
		vp.X, vp.Y, tostring(UserInputService.TouchEnabled),
		tostring(UserInputService.MouseEnabled), tostring(HudScale.isPhone()),
		HudScale.iconFactor(), HudScale.px(78), HudScale.step(128)))
end)
--[[ ⚠️ ТЕКСТ СЖИМАЕТСЯ ПОЧТИ НЕ СЖИМАЯСЬ, И У НЕГО СВОЙ ПОЛ.
     Подписи кнопок и цифры статусов шли сырыми числами (TextSize = 16) или через
     panel-множитель 0.55. На телефоне 0.55 × 0.72 = 0.4, то есть кегль 16
     превращался в 6 пикселей — читать нечего. У кнопок для этого есть
     MIN_TOUCH_PX, но он живёт внутри px() и до текста не достаёт.
     Здесь свой пол: ниже 14 пикселей текст на телефоне не читается. Если исходный
     кегль был мельче — оставляем как есть, поднимать чужую типографику не наше
     дело. ]]
local TEXT_FACTOR = 0.9
local MIN_TEXT_PX = 14

function HudScale.text(n)
	if not HudScale.isPhone() then return n end
	local v = math.floor(n * TEXT_FACTOR * heightK() + 0.5)
	return math.max(v, math.min(n, MIN_TEXT_PX))
end

--[[ ⚠️ КАРТОЧКА HUD — ЭТО НЕ МЕНЮ ВО ВЕСЬ ЭКРАН.
     Трекер квеста, баннеры подсказок и всплывающие уведомления сжимались тем же
     factor(), что и большие меню. Но меню есть куда жать — оно рисовалось под
     ширину 720 и на телефоне занимало весь экран; а карточка и так компактная,
     она состоит из текста, и 0.55 превращает её в нечитаемую полоску.
     Отдельный множитель: сжимаем мягко и не ниже своего пола. ]]
--[[ 1.0, а не 0.85: карточка квеста с полосой прогресса — то, на что игрок
     смотрит чаще всего, и на телефоне она читалась мельче остального HUD. ]]
local CARD_FACTOR = 1.0
local CARD_MIN    = 0.85

--[[ ⚠️ УВЕДОМЛЕНИЯ И ПОДСКАЗКИ НА ТЕЛЕФОНЕ ДОЛЖНЫ БЫТЬ КРУПНЫМИ, А НЕ МЕЛКИМИ.
     Карточка уведомления, всплывашка «+2 Дерево» и жёлтый баннер подсказки шли
     через factor() — панельный множитель 0.55, придуманный для МЕНЮ во весь
     экран. На телефоне он ещё умножается на долю высоты, и выходило около 0.45:
     текст, который игрок должен успеть прочитать за две секунды, становился
     вдвое мельче, чем на мониторе.
     Это разные задачи. Меню можно и нужно ужимать — оно и так во весь экран.
     Уведомление живёт секунды, читается на ходу и занимает угол: ему нужен
     размер, а не экономия места. Поэтому на телефоне оно НЕ мельче
     компьютерного, а на низком экране опускается лишь немного.
     На компьютере ровно 1 — десктоп этой правкой не задет вовсе. ]]
local NOTICE_FACTOR = 1.15
local NOTICE_MIN    = 0.95

function HudScale.noticeFactor()
	if not HudScale.isPhone() then return 1 end
	return math.max(NOTICE_FACTOR * heightK(), NOTICE_MIN)
end

--[[ ⚠️ ВСПЛЫВАЮЩЕЕ УВЕДОМЛЕНИЕ — НЕ ЖЁЛТАЯ ПОДСКАЗКА, ХОТЯ ОБА «КАРТОЧКИ».
     Сюда они ходили одной ручкой — noticeFactor, — и это склеило две разные
     задачи. Подсказка квеста стоит по центру сверху, читается вдумчиво, и её
     размер владельца устраивает. Уведомление же выезжает В УГОЛ поверх игры:
     340 пикселей ширины на экране в 852 — это больше трети, и вместе с тёмной
     рамкой оно читается как «пол-экрана потемнело». На мониторе те же 340 —
     шестая часть ширины, оттого разницы никто и не замечал.
     Мерить надо ДОЛЮ ЭКРАНА, а не компьютерные пиксели: 0.95 при нижней границе
     0.8 даёт около 270 — заметно, но угол остаётся углом.
     Тронув общий множитель, я бы заодно ужал подсказки, о которых сказано
     «размер норм». Поэтому ручка отдельная. ]]
local TOAST_FACTOR = 0.95
local TOAST_MIN    = 0.8

function HudScale.toastFactor()
	if not HudScale.isPhone() then return 1 end
	return math.max(TOAST_FACTOR * heightK(), TOAST_MIN)
end

--[[ ⚠️ КАРТОЧКА ДОБЫЧИ МЕНЬШЕ УВЕДОМЛЕНИЯ, И ЭТО НАМЕРЕННО.
     «+1 Дерево» всплывает на каждый подобранный предмет, десятками за минуту, и
     в размере уведомления о новом квесте загораживало пол-экрана. Уведомление
     редкое и важное, добыча частая и проходная — им нужен разный вес. ]]
--[[ ⚠️ НО НЕ НАСТОЛЬКО МЕНЬШЕ. 0.72 сжимало карточку добычи до двух третей
     компьютерной, и на телефоне награда за квест и содержимое рюкзака — то, ради
     чего игрок и лез, — читались мельче всего остального HUD. Владелец про это и
     написал: «не такая по размерам, как на ПК».
     Разница в весе между добычей и уведомлением остаётся, но берётся она теперь
     с другой стороны: уведомление ужато до 0.95 (см. выше), а добыча идёт вровень
     с компьютером. ]]
local PICKUP_FACTOR = 1.0
local PICKUP_MIN    = 0.9

function HudScale.pickupFactor()
	if not HudScale.isPhone() then return 1 end
	return math.max(PICKUP_FACTOR * heightK(), PICKUP_MIN)
end

function HudScale.cardFactor()
	if not HudScale.isPhone() then return 1 end
	return math.max(CARD_FACTOR * heightK(), CARD_MIN)
end

--[[ ⚠️ ТРЕКЕР КВЕСТА — ОТДЕЛЬНАЯ РУЧКА, И ЭТО ИСПРАВЛЕНИЕ СТАРОЙ ОШИБКИ.
     Карточка «что делать сейчас» с полосой прогресса сжималась ПАНЕЛЬНЫМ
     множителем — тем самым 0.55, придуманным для меню во весь экран. На
     телефоне он ещё умножается на долю высоты, и выходило около 0.4: карточка
     шириной сто двадцать пикселей с нечитаемой строкой. Владелец на неё
     показывал дважды.
     Просто поднять её до карточного множителя (0.85) нельзя: она стоит в
     левом верхнем углу, прямо НАД столбиком кнопок, и на низком экране
     упёрлась бы в «Квесты». Поэтому своё число — крупнее панельного почти
     вдвое, но с запасом до столбика: на экране 852×393 карточка занимает
     194×35 пикселей, а до верхней иконки остаётся сорок с лишним.
     ⚠️ ЭТО ЖЕ ЧИСЛО ЧИТАЕТ fitCenterBanner: подсказка по центру считает по нему
     свободную ширину. Меняешь здесь — там менять не нужно, оно уже общее. ]]
local TRACKER_FACTOR = 0.9
local TRACKER_MIN    = 0.6

function HudScale.trackerFactor()
	if not HudScale.isPhone() then return 1 end
	return math.max(TRACKER_FACTOR * heightK(), TRACKER_MIN)
end

--[[ ⚠️ ЦЕНТРАЛЬНАЯ ПОДСКАЗКА НЕ ДОЛЖНА ДОРАСТАТЬ ДО КАРТОЧКИ КВЕСТА.
     Баннеры подсказок стоят по центру сверху с AutomaticSize по ширине: строка
     растёт вместе с текстом и упирается только в край экрана. На мониторе это
     незаметно, а в окне поменьше длинная подсказка («Нужно дерево: 3 из 4 —
     вылавливай брёвна из океана») доезжает до карточки квеста слева и ложится
     поверх её полосы прогресса.
     Считаем свободную ширину между карточкой и её зеркальным отражением справа
     (баннер центрирован, значит мешает ему и левый край, и правый одинаково) и
     разрешаем переносить текст. Если и этого мало — узкое окно, телефон в
     портрете — уводим подсказку ПОД карточку, где ширина уже вся наша.

     Числа взяты из TrackerCard: ширина 300 и отступ 14. Дублировать их сюда
     неприятно, но альтернатива — тянуть сюда сам трекер и знать про его дерево,
     а это связь куда хуже двух констант. ]]
local TRACKER_RIGHT   = 314   -- TrackerCard: TRACKER_W (300) + MARGIN_X (14)
local TRACKER_HEIGHT  = 92    -- на столько опускаем подсказку, когда места нет
local BANNER_PAD      = 16    -- воздух между подсказкой и карточкой
local BANNER_MIN_W    = 320   -- уже этого по центру подсказка не помещается

--[[ ⚠️ НА ТЕЛЕФОНЕ ПОДСКАЗКУ СТАВИМ ДОЛЕЙ ВЫСОТЫ, А НЕ ПИКСЕЛЯМИ.
     Сначала я поставил ей 78 пикселей от верха — как на мониторе, только выше.
     На деле подсказка всё равно оказывалась посреди экрана: телефоны отдают
     ViewportSize в разных масштабах, и одно и то же число пикселей на одном
     аппарате «под строкой дня», а на другом — уже в середине обзора.
     Доля высоты от этого не зависит: 12% сверху — всегда сразу под «День N»,
     каким бы ни был экран. ]]
--[[ ⚠️ 0.12 И БЕЗ СДВИГА ВНИЗ.
     Владелец просил поднять подсказку дважды: она стояла заметно ниже строки
     «День N», между ними зиял пустой пояс. Девять процентов я попробовал —
     подсказка налезла на саму строку дня, и владелец попросил опустить.
     Двенадцать — это ровно под её нижним краем: ближе уже наезд.
     Сдвиг вниз на десятую долю высоты, который раньше включался, когда по бокам
     «мало места», убран совсем: ширину мы и так ограничиваем свободной полосой
     (см. ниже), поэтому наезжать подсказке не на что, а падать вниз тем более
     незачем. Это и была главная причина, почему она висела посреди экрана. ]]
local BANNER_TOP_PHONE_SCALE = 0.14

function HudScale.fitCenterBanner(label, topY)
	if not label then return end
	topY = topY or 92

	label.TextWrapped = true
	label.AutomaticSize = Enum.AutomaticSize.XY

	local cap = label:FindFirstChildOfClass("UISizeConstraint") or Instance.new("UISizeConstraint")
	-- нижняя граница по высоте: одну строку баннер держит прежней высоты
	cap.MinSize = Vector2.new(0, label.AbsoluteSize.Y > 0 and label.AbsoluteSize.Y or label.Size.Y.Offset)
	cap.Parent = label

	local function relayout()
		local cam = workspace.CurrentCamera
		local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
		--[[ Карточка квеста на телефоне сжата своим множителем, значит и занимает
		     меньше — считать её по компьютерной ширине значило бы зря отбирать у
		     подсказки место как раз там, где его и так мало.

		     ⚠️ И МНОЖИТЕЛЬ БЕРЁМ ТОТ, ПО КОТОРОМУ ТРЕКЕР СЖАТ НА САМОМ ДЕЛЕ.
		     Здесь стоял cardFactor (0.85) — я считал, что карточка квеста живёт
		     по нему. Она жила по панельному factor() ≈ 0.4, и разница была не
		     косметической: по завышенной ширине выходило, что места по бокам
		     нет, и подсказка уезжала вниз на десятую долю высоты экрана —
		     «туториал слишком низко».
		     Теперь у трекера своя ручка, и обе стороны читают ЕЁ: множитель
		     один, файла два, расходиться нечему. ]]
		local trackerRight = TRACKER_RIGHT * HudScale.trackerFactor()
		local free = vp.X - 2 * (trackerRight + BANNER_PAD)
		local phone = HudScale.isPhone()
		local tight = free < BANNER_MIN_W
		if tight then
			cap.MaxSize = Vector2.new(math.max(vp.X - 2 * BANNER_PAD, 200), math.huge)
		else
			cap.MaxSize = Vector2.new(free, math.huge)
		end

		if phone then
			--[[ ⚠️ ВНИЗ НЕ СДВИГАЕМ НИКОГДА. Раньше при «мало места по бокам»
			     добавлялась десятая доля высоты, и подсказка уезжала на середину
			     экрана — именно это и просили поднять. Ширину мы уже ограничили
			     свободной полосой выше, так что наезжать ей не на что. ]]
			label.Position = UDim2.new(0.5, 0, BANNER_TOP_PHONE_SCALE, 0)
		else
			local top = topY + (tight and TRACKER_HEIGHT or 0)
			label.Position = UDim2.new(0.5, 0, 0, top)
		end
	end

	relayout()
	local cam = workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(relayout)
	end
	--[[ ⚠️ ПЕРЕСЧИТЫВАЕМ ЕЩЁ И В ПЕРВЫЕ СЕКУНДЫ.
	     В первых кадрах ViewportSize ещё не окончательный — по нему подсказка
	     решала, что места по бокам нет, и уезжала вниз. Сигнал изменения потом
	     приходит не всегда (если размер «дорос» до реального без события), а
	     три дешёвых пересчёта закрывают весь этот отрезок. ]]
	task.spawn(function()
		for _ = 1, 3 do
			task.wait(1)
			relayout()
		end
	end)
	return relayout
end

--[[ Сжать готовый элемент целиком. Возвращает UIScale — вдруг понадобится крутить.
     ⚠️ Вешать на КОНТЕЙНЕР, а не на кнопку с наведением: у той UIScale уже занят. ]]
function HudScale.applyScale(container, factor)
	if not container then return nil end
	local s = container:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	s.Scale = factor or HudScale.factor()
	s.Parent = container
	return s
end

--[[ То же, но переживает поворот телефона: в портрете и ландшафте места разное.

     ⚠️ ВТОРЫМ АРГУМЕНТОМ МОЖНО ПЕРЕДАТЬ САМУ ФУНКЦИЮ, И ЭТО ЕДИНСТВЕННЫЙ
     СПОСОБ СДЕЛАТЬ МАСШТАБ ДЕЙСТВИТЕЛЬНО ЖИВЫМ.
     Раньше сюда приходило готовое ЧИСЛО — например, Hud.cardFactor(). Оно
     считалось один раз при запуске, и при повороте телефона строка ниже
     послушно присваивала то же самое число: «live» работал ровно для варианта
     по умолчанию, а для всех остальных был обманом. Множители зависят от высоты
     экрана (heightK), а она в портрете и ландшафте разная.
     Число по-прежнему принимается — старые вызовы не ломаются. ]]
function HudScale.applyScaleLive(container, factor)
	local function value()
		if type(factor) == "function" then return factor() end
		return factor or HudScale.factor()
	end

	local s = HudScale.applyScale(container, value())
	if not s then return nil end
	local cam = workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			s.Scale = value()
		end)
	end
	return s
end


--------------------------------------------------------------------
-- ПОСТАНОВКА ПРЕДМЕТОВ С РУК НА ТЕЛЕФОНЕ (HudScale.Place)
--
-- ⚠️ ПОЧЕМУ ЭТО ЖИВЁТ ЗДЕСЬ, А НЕ В СВОЁМ ФАЙЛЕ.
-- Реализация была отдельным модулем ReplicatedStorage/TouchPlace. Он и сейчас
-- есть — но НОВЫЙ файл до запущенной сессии Rojo доезжает не всегда: правки
-- существующих файлов синкаются, а новый инстанс в плейсе появляется только
-- после переподключения. На телефоне это выглядело как «ничего не изменилось»:
-- ставилки не находили модуль, честно откатывались на мышь, и тап по-прежнему
-- ставил предмет куда попало.
-- HudScale в плейсе давно и синкается штатно, а «как телефон ставит предметы» —
-- ровно та же телефонная адаптация, что и всё остальное здесь. Поэтому
-- реализация переехала сюда, а TouchPlace.lua остался тонкой обёрткой над ней:
-- кто нашёл его — получит то же самое.
--------------------------------------------------------------------
local Players = game:GetService("Players")

local player = Players.LocalPlayer

local TouchPlace = {}

function TouchPlace.isPhone()
	return HudScale.isPhone()
end

--------------------------------------------------------------------
-- Запомненная точка прицела
--------------------------------------------------------------------

-- Точка в осях плота (обычный случай) либо в мире (когда плота нет — остров).
local aimLocal = nil     -- CFrame относительно raft.PrimaryPart
local aimWorld = nil     -- Vector3, запасной вариант
local active   = false   -- идёт ли сеанс установки

local function raftPrimary()
	local raft = workspace:FindFirstChild("Raft")
	return raft and raft.PrimaryPart
end

--[[ Запомнить, куда игрок ткнул. Зовётся ставилкой сразу после удачного
     рейкаста — модуль не знает и не должен знать, что именно та считает
     допустимой поверхностью. ]]
function TouchPlace.setHit(worldPos)
	if not TouchPlace.isPhone() then return end
	if typeof(worldPos) ~= "Vector3" then return end
	local pp = raftPrimary()
	if pp then
		aimLocal = pp.CFrame:ToObjectSpace(CFrame.new(worldPos))
		aimWorld = nil
	else
		aimLocal = nil
		aimWorld = worldPos
	end
end

-- Где сейчас прицел в мире. nil — игрок ещё не тапал.
local function aimWorldPos()
	if aimLocal then
		local pp = raftPrimary()
		if pp then return (pp.CFrame * aimLocal).Position end
		return nil
	end
	return aimWorld
end

--[[ Луч прицела.
     ПК: ровно то, что было в каждом файле, — луч из курсора.
     Телефон до первого тапа: nil. Вызывающий обязан отнестись к этому как к
     промаху рейкаста (покрасить призрак и выйти) — показывать призрак в
     случайном месте до выбора нельзя, это и есть прежнее поведение.
     Телефон после тапа: луч ИЗ КАМЕРЫ В ЗАПОМНЕННУЮ ТОЧКУ. Рейкаст вызывающего
     упрётся в ту же поверхность, что и палец, но уже с поправкой на ход плота. ]]
function TouchPlace.ray(mouse)
	local camera = workspace.CurrentCamera
	if not camera then return nil end

	if not TouchPlace.isPhone() then
		if not mouse then return nil end
		return camera:ViewportPointToRay(mouse.X, mouse.Y)
	end

	--[[ ⚠️ ДО ПЕРВОГО ТАПА ЦЕЛИМСЯ В ЦЕНТР ЭКРАНА, А НЕ В НИКУДА.
	     Сначала здесь возвращался nil: мол, места ещё не выбрали — значит и
	     призрака быть не должно. На деле это читается как «предмет в руках, а
	     ставить нечем»: игрок не видит НИЧЕГО и не догадывается, что надо
	     тапнуть. Центр экрана — то место, куда человек и так смотрит: призрак
	     появляется сразу, а тап его двигает. Ровно так ведёт себя молоток. ]]
	local target = aimWorldPos()
	if not target then
		local vp = camera.ViewportSize
		return camera:ViewportPointToRay(vp.X * 0.5, vp.Y * 0.5)
	end

	--[[ ⚠️ ЛУЧ ИДЁТ СВЕРХУ ВНИЗ, А НЕ ИЗ КАМЕРЫ. ЭТО ГЛАВНОЕ МЕСТО ВО ВСЁМ МОДУЛЕ.
	     Сначала луч шёл из камеры в запомненную точку — казалось, что этого
	     достаточно: точка-то запомнена в осях плота и никуда не уползает. Но
	     упирается такой луч в ПЕРВОЕ, что встретит по дороге. Игрок шагнул,
	     камера поехала — и между ней и точкой оказался якорь или бочка. Призрак
	     прыгал НА эту бочку, менял место при каждом шаге, а игрок подтверждал
	     установку туда, куда не целился. Отсюда обе жалобы разом: «ставится в
	     другой объект» и «когда хожу, предпросмотр уезжает».
	     Вертикальный зонд от точки вниз этой болезнью не страдает вовсе: он
	     всегда находит поверхность РОВНО под выбранным местом, и результат не
	     зависит ни от камеры, ни от того, где стоит персонаж. Начинаем чуть
	     выше точки, чтобы не оказаться уже внутри детали. ]]
	return Ray.new(target + Vector3.new(0, 6, 0), Vector3.new(0, -1, 0))
end

--[[ Экранные координаты прицела — для тех, кому нужен не луч, а точка.
     Второе значение говорит, экранные они (с полосой Roblox) или видовые. ]]
function TouchPlace.point(mouse)
	if not TouchPlace.isPhone() then
		return mouse and mouse.X or 0, mouse and mouse.Y or 0, false
	end
	local camera = workspace.CurrentCamera
	local target = aimWorldPos()
	if not (camera and target) then return nil, nil, true end
	local v, onScreen = camera:WorldToScreenPoint(target)
	if not onScreen then return nil, nil, true end
	return v.X, v.Y, true
end

--------------------------------------------------------------------
-- Кнопки на телефоне
--------------------------------------------------------------------

local gui, confirmBtn, rotateBtn
local hooks = {}      -- { confirm = fn, rotate = fn }
local tapConn, tapBeganConn

--[[ ⚠️ У СЕАНСА ЕСТЬ ХОЗЯИН, И ЧУЖОЙ finish ЕГО НЕ ЗАКРЫВАЕТ.
     Вот на чём всё три раза и ломалось. Ставилок одиннадцать, и КАЖДАЯ следит за
     тем, что игрок держит в руках. Берёшь грядку — своя ставилка открывает сеанс
     (кнопки на экран), а следом просыпаются остальные десять, видят «это не мой
     предмет» и по-честному прибирают за собой: гасят свой призрак и зовут
     finish. Модуль-то один на всех — и гасил ТОЛЬКО ЧТО открытый сеанс.
     Со стороны это выглядело именно так, как в отладке: модуль есть, кнопка
     создана и даже помечена видимой, а окно выключено и сеанса нет.
     Хозяина определяем по вызывающему скрипту — debug.info отдаёт его источник,
     и это ровно та мера, которая нужна: «закрыть может тот, кто открыл». Правки
     в одиннадцати файлах при этом не нужны ни одной. ]]
local owner = nil

local function callerId()
	local ok, src = pcall(debug.info, 3, "s")
	return (ok and src) or "?"
end

local function ensureGui()
	if gui and gui.Parent then return end
	local pg = player:WaitForChild("PlayerGui")

	gui = Instance.new("ScreenGui")
	gui.Name = "TouchPlaceUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	-- выше стройки (20) и хотбара, но ниже меню: кнопка обязана быть доступна,
	-- пока открыт мир, и не спорить с окнами
	gui.DisplayOrder = 30
	gui.Enabled = false
	gui.Parent = pg

	--[[ ⚠️ МЕСТО ВЫБРАНО ПО КНОПКЕ СТРОЙКИ, А НЕ НА ГЛАЗ.
	     У молотка кнопка стоит в правом нижнем углу над прыжком (см.
	     BuildingSystem). Ставим свою туда же: это одно и то же действие
	     «подтвердить постановку», и рука должна тянуться в одно место. ]]
	--[[ Круглая форма. Белое кольцо — отдельным аргументом: у стройки оно есть
	     только на кнопке-заглушке без картинки, а поверх готовой иконки читается
	     как лишняя рамка. Владелец попросил его убрать — с молотка убираем, у
	     поворота оставляем: там нет картинки, и без кольца тёмный круг теряется
	     на фоне воды. ]]
	local function round(btn, ring)
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = btn
		if not ring then return end
		local s = Instance.new("UIStroke")
		s.Thickness = 3
		s.Color = Color3.new(1, 1, 1)
		s.Transparency = 0.25
		s.Parent = btn
	end

	--[[ ⚠️ КНОПКА — ТА ЖЕ, ЧТО У МОЛОТКА, И ЭТО ГЛАВНОЕ В НЕЙ.
	     Своя зелёная плашка выглядела иначе и читалась как другой механизм. А
	     действие ровно то же самое: «поставить то, что висит призраком». Игрок
	     уже знает эту круглую кнопку по стройке — берём её целиком: тот же
	     ассет, тот же размер, то же место в углу, та же полупрозрачная заливка
	     со светлой обводкой (см. BuildingSystem, BUILD_ICON). ]]
	local BUILD_ICON = "rbxassetid://116668456372183"

	confirmBtn = Instance.new("ImageButton")
	confirmBtn.Name = "ConfirmPlace"
	confirmBtn.AnchorPoint = Vector2.new(1, 1)
	confirmBtn.Position = UDim2.new(1, -184, 1, -190)   -- как кнопка стройки (BuildSlot)
	confirmBtn.Size = UDim2.fromOffset(132, 132)
	confirmBtn.BackgroundColor3 = Color3.new(0, 0, 0)
	confirmBtn.BackgroundTransparency = 0.35
	confirmBtn.BorderSizePixel = 0
	confirmBtn.AutoButtonColor = false
	confirmBtn.Image = BUILD_ICON
	confirmBtn.ImageTransparency = 0.25
	confirmBtn.ScaleType = Enum.ScaleType.Fit
	confirmBtn.Parent = gui
	round(confirmBtn, false)   -- без белого кольца: на иконке молотка оно лишнее

	-- подпись поверх иконки: у стройки она тоже есть, и без неё круг читается
	-- как «ещё одна кнопка прыжка»
	local confirmText = Instance.new("TextLabel")
	confirmText.Size = UDim2.fromScale(1, 1)
	confirmText.BackgroundTransparency = 1
	confirmText.Font = Enum.Font.GothamBlack
	confirmText.Text = ""   -- владелец просил без надписи: иконка молотка говорит сама
	confirmText.TextSize = 15
	confirmText.TextColor3 = Color3.new(1, 1, 1)
	confirmText.TextStrokeTransparency = 0.4
	confirmText.ZIndex = 3
	confirmText.Parent = confirmBtn

	--[[ Иконка поворота — своя, от владельца. Раньше стоял символ ↻: он есть не
	     во всех шрифтах и на части телефонов рисовался пустым квадратом (это
	     видно на скриншотах — «▯ — поворот»). Картинка от такого не зависит. ]]
	-- id продублирован в UITheme.Icons.rotate — там общий справочник иконок;
	-- здесь литерал намеренно: HudScale не должен зависеть от UITheme (он
	-- поднимается раньше и нужен даже без тем)
	local ICON_ROTATE = "rbxassetid://108864632671430"

	rotateBtn = Instance.new("ImageButton")
	rotateBtn.Name = "RotatePlace"
	rotateBtn.AnchorPoint = Vector2.new(1, 1)
	-- левее подтверждения, размером поменьше: поворот нажимают реже
	rotateBtn.Position = UDim2.new(1, -334, 1, -208)   -- левее подтверждения, по центру его высоты
	rotateBtn.Size = UDim2.fromOffset(96, 96)
	rotateBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	rotateBtn.BackgroundTransparency = 0.35
	rotateBtn.BorderSizePixel = 0
	rotateBtn.AutoButtonColor = false
	rotateBtn.Image = ICON_ROTATE
	rotateBtn.ImageTransparency = 0.1
	rotateBtn.ScaleType = Enum.ScaleType.Fit
	rotateBtn.Parent = gui
	round(rotateBtn, true)

	--[[ ⚠️ Activated, А НЕ MouseButton1Click.
	     На телефоне клик мышью кнопке не приходит вовсе — то же самое уже
	     наступало у кнопки стройки. Activated ловит и палец, и мышь. ]]
	confirmBtn.Activated:Connect(function()
		if hooks.confirm then hooks.confirm() end
	end)
	rotateBtn.Activated:Connect(function()
		if hooks.rotate then hooks.rotate() end
	end)

	--[[ ⚠️ МАСШТАБ БЕРЁМ ТОТ ЖЕ, ЧТО У КНОПКИ СТРОЙКИ, А НЕ СВОЙ.
	     Владелец просил «кнопку из молотка, в той же позиции и того же размера».
	     Позиция и размер в пикселях у нас уже совпадают (132 в углу), но меню
	     стройки целиком сжимается инвентарным масштабом (_G.AttachInventoryUIScale,
	     см. BuildingSystem), а не иконочным. Возьми мы свой множитель — кнопка
	     вышла бы заметно крупнее соседней при тех же числах.
	     Инвентарный масштаб пересчитывается сам при смене размера окна, поэтому
	     отдельный applyScaleLive здесь не нужен. Если инвентарь ещё не поднялся,
	     откатываемся на иконочный — лучше немного другой размер, чем никакого. ]]
	if typeof(_G.AttachInventoryUIScale) == "function" then
		_G.AttachInventoryUIScale(gui)
	else
		HudScale.applyScaleLive(gui, HudScale.iconFactor)
	end
end

--[[ ⚠️ ТАП ПО МИРУ ВЫБИРАЕТ МЕСТО И НИЧЕГО НЕ СТАВИТ.
     gameProcessedEvent отсеивает нажатия по интерфейсу — иначе тап по самой
     кнопке «ПОСТАВИТЬ» сначала перенёс бы прицел под палец, а потом поставил
     предмет туда, куда игрок и не целился. ]]
--[[ ⚠️ ПРИЦЕЛ ДВИГАЕТ ТОЛЬКО НАСТОЯЩИЙ ТАП, А НЕ ЛЮБОЕ КАСАНИЕ.
     Игрок ходит джойстиком и крутит камеру пальцем — это тоже касания экрана,
     и по ним прицел уезжал: «иду вперёд — грядка перескочила туда, куда я нажал
     для ходьбы». Отличаем тап от ведения по-честному: палец должен опуститься и
     подняться почти в той же точке и быстро. Сдвинулся больше чем на палец или
     держался дольше полусекунды — это управление, а не выбор места. ]]
local TAP_MOVE_MAX = 14   -- пикселей; больше — это ведение
local TAP_TIME_MAX = 0.45 -- секунд; дольше — это удержание
local touchStart = {}     -- [InputObject] = { pos = Vector2, t = number }

local function startTapCapture()
	if tapConn then return end

	local beganConn = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.UserInputType ~= Enum.UserInputType.Touch then return end
		if not active then return end
		touchStart[input] = { pos = Vector2.new(input.Position.X, input.Position.Y), t = os.clock() }
	end)

	tapConn = UserInputService.InputEnded:Connect(function(input, processed)
		local started = touchStart[input]
		touchStart[input] = nil
		if not started then return end
		if processed then return end
		if input.UserInputType ~= Enum.UserInputType.Touch then return end
		if not active then return end

		local endPos = Vector2.new(input.Position.X, input.Position.Y)
		if (endPos - started.pos).Magnitude > TAP_MOVE_MAX then return end
		if os.clock() - started.t > TAP_TIME_MAX then return end

		-- второй коннект держим рядом, чтобы снять его вместе с основным
		tapBeganConn = beganConn

		local camera = workspace.CurrentCamera
		if not camera then return end
		--[[ Точка касания — ЭКРАННАЯ, поэтому и луч экранный. Ставилка сама
		     решит, во что он упёрся: наше дело — отдать ей верное направление. ]]
		local ray = camera:ScreenPointToRay(input.Position.X, input.Position.Y)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		--[[ ⚠️ ПРИЗРАК ОБЯЗАН БЫТЬ В СПИСКЕ ИСКЛЮЧЕНИЙ.
		     Он стоит ровно там, куда целились в прошлый раз, и заслоняет собой
		     палубу. Не исключи его — луч упрётся в него самого, точка прицела
		     останется прежней, и призрак «прилипнет»: тапаешь в другое место, а
		     он не двигается. Инстанс призрака ставилка пересоздаёт, поэтому
		     спрашиваем его функцией, а не запоминаем ссылку. ]]
		local ignore = {}
		if player.Character then table.insert(ignore, player.Character) end
		if hooks.ignore then
			local extra = hooks.ignore()
			if typeof(extra) == "Instance" then
				table.insert(ignore, extra)
			elseif type(extra) == "table" then
				for _, inst in ipairs(extra) do
					if typeof(inst) == "Instance" then table.insert(ignore, inst) end
				end
			end
		end
		params.FilterDescendantsInstances = ignore

		local res = workspace:Raycast(ray.Origin, ray.Direction * 600, params)
		if res then TouchPlace.setHit(res.Position) end
	end)
end

local function stopTapCapture()
	if tapConn then
		tapConn:Disconnect()
		tapConn = nil
	end
	if tapBeganConn then
		tapBeganConn:Disconnect()
		tapBeganConn = nil
	end
	table.clear(touchStart)
end

--------------------------------------------------------------------
-- Сеанс установки
--------------------------------------------------------------------

--[[ Начать сеанс. На компьютере не делает НИЧЕГО и сразу возвращается — там
     всё работает мышью, и лишний интерфейс на экране не нужен.
     opts.confirm — та же функция, что вызывается по клику мышью;
     opts.rotate  — та же, что по клавише R (необязательна);
     opts.label   — надпись на кнопке, если «ПОСТАВИТЬ» не подходит. ]]
function TouchPlace.begin(opts)
	if not TouchPlace.isPhone() then return end
	opts = opts or {}
	hooks.confirm = opts.confirm
	hooks.rotate  = opts.rotate
	hooks.ignore  = opts.ignore
	aimLocal, aimWorld = nil, nil   -- новое место выбирают заново
	owner = callerId()   -- закрыть сеанс сможет только он (см. выше)
	active = true

	ensureGui()
	rotateBtn.Visible = opts.rotate ~= nil
	-- надпись живёт на ярлыке поверх иконки, а не на самой ImageButton
	local cap = confirmBtn:FindFirstChildOfClass("TextLabel")
	if cap then cap.Text = opts.label or "" end
	gui.Enabled = true
	startTapCapture()
end

-- Закончить сеанс: убрать кнопки и забыть точку.
function TouchPlace.finish()
	if not TouchPlace.isPhone() then return end
	--[[ Прибирает за собой каждая ставилка, а сеанс сейчас чужой — не трогаем:
	     иначе только что открытые кнопки гаснут от соседа. ]]
	if active and owner and callerId() ~= owner then return end
	owner = nil
	active = false
	hooks.confirm, hooks.rotate, hooks.ignore = nil, nil, nil
	aimLocal, aimWorld = nil, nil
	stopTapCapture()
	if gui then
		gui.Enabled = false
		local cap = confirmBtn and confirmBtn:FindFirstChildOfClass("TextLabel")
		if cap then cap.Text = "" end
	end
end

-- Идёт ли сеанс (нужно ставилкам, чтобы не подтверждать дважды).
function TouchPlace.active()
	return active
end


HudScale.Place = TouchPlace

return HudScale
