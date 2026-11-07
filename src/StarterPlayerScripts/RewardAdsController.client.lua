local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
--[[
	НАГРАДА С РЕЙДА — клиент (хендофф raft-reward-ads, этапы P1+P2).

	Точка входа "boatman": табличка «Награда с рейда» над лодочником (UI/AdBillboard).
	Видна, когда:
	  • сервер прислал оффер (RewardAds_OfferChanged) и он не заблокирован
	    (бой, ночная волна, катсцена, смерть);
	  • мой лодочник подошёл (State = Delivered);
	  • игрок не закрыл её ✕ (до нового оффера или BillboardDismissSeconds).
	«Бесплатно» → RewardAds_Watch, «R$ N» → RewardAds_Buy. Клиент шлёт только
	placement: состав, цену и что именно покупается решает сервер.
	Рядом — полная табличка, дальше BillboardFullDistance — пилюля.
]]
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local player = Players.LocalPlayer
local pack = ReplicatedStorage:WaitForChild("RewardAds")
local Config = require(pack:WaitForChild("Config"))
local Icons = require(pack:WaitForChild("ResourceIcons"))
local AdBillboard = require(pack:WaitForChild("UI"):WaitForChild("AdBillboard"))
local CourierConfig = require(ReplicatedStorage:WaitForChild("RaidCourier"):WaitForChild("Config"))

local OfferChanged = ReplicatedStorage:WaitForChild("RewardAds_OfferChanged")
local Watch        = ReplicatedStorage:WaitForChild("RewardAds_Watch")
local Buy          = ReplicatedStorage:WaitForChild("RewardAds_Buy")
local Dismiss      = ReplicatedStorage:WaitForChild("RewardAds_Dismiss")
local Granted      = ReplicatedStorage:WaitForChild("RewardAds_Granted")

local LootBurstFX
pcall(function() LootBurstFX = require(ReplicatedStorage:WaitForChild("LootBurstFX", 5)) end)

local function now() return workspace:GetServerTimeNow() end

-- игровая иконка предмета важнее иконки пакета (§7 хендоффа)
local warnedIcon = {}
local function iconOf(id)
	local game_ = typeof(_G.GetItemIcon) == "function" and _G.GetItemIcon(id) or ""
	if type(game_) == "string" and game_ ~= "" then return game_ end
	local pkg = Icons.byItem[id]
	if pkg then return pkg end
	if not warnedIcon[id] then
		warnedIcon[id] = true
		warn("[Реклама/клиент] нет иконки для «" .. tostring(id) .. "»")
	end
	return ""
end

local offers = {}     -- [placement] = data от сервера
local dismissed = {}  -- [placement] = { id = offerId, at = os.clock() }
local dirty = true

OfferChanged.OnClientEvent:Connect(function(placement, data)
	offers[placement] = data
	dirty = true
end)

-- ═══════════ табличка лодочника ═══════════
local bb = AdBillboard.new(player:WaitForChild("PlayerGui"))
bb.gui.MaxDistance = Config.BillboardMaxDistance
bb:setBob(Config.BillboardBob ~= false)
local lastClick = 0
local function clickOk()
	if os.clock() - lastClick < 1 then return false end
	lastClick = os.clock()
	return true
end

bb.onFree = function() if clickOk() then Watch:FireServer("boatman") end end
bb.onBuy = function() if clickOk() then Buy:FireServer("boatman") end end
bb.onClose = function()
	local o = offers.boatman
	dismissed.boatman = { id = o and o.id, at = os.clock() }
	Dismiss:FireServer("boatman")
	bb:setVisible(false, true)
end

local function myCourierHead(includeReturning)
	local folder = workspace:FindFirstChild("RaidCouriers")
	if not folder then return nil end
	for _, m in ipairs(folder:GetChildren()) do
		if m:GetAttribute("RecipientUserId") == player.UserId and (m:GetAttribute("State") == "Delivered" or (includeReturning and m:GetAttribute("CargoGranted"))) then
			for _, n in ipairs(CourierConfig.RIG_NAMES) do
				local rig = m:FindFirstChild(n)
				local head = rig and rig:FindFirstChild("Head")
				if head then return head end
			end
		end
	end
	return nil
end

local mode = "full"
local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < 0.2 then return end
	acc = 0
	local o = offers.boatman
	local head = o and not o.blocked and myCourierHead()
	local d = dismissed.boatman
	local isDismissed = d and d.id == (o and o.id) and os.clock() - d.at < Config.BillboardDismissSeconds
	local anyButton = o and (o.freeEnabled or o.claimed or o.buyKind ~= nil)
	--[[ ДИАГНОСТИКА: почему таблички нет — печатаем при каждой смене причины
	     (табличка «не отобразилась», а в логе было пусто). ]]
	local why = nil
	if not o then why = "оффера нет"
	elseif o.blocked then why = "сервер блокирует: " .. tostring(o.blocked)
	elseif not head then
		local f = workspace:FindFirstChild("RaidCouriers")
		local list = {}
		for _, m in ipairs(f and f:GetChildren() or {}) do
			local rigs = {}
			for _, c in ipairs(m:GetChildren()) do table.insert(rigs, c.Name) end
			table.insert(list, ("%s(кому=%s, State=%s, внутри: %s)"):format(m.Name,
				tostring(m:GetAttribute("RecipientUserId")), tostring(m:GetAttribute("State")), table.concat(rigs, "/")))
		end
		why = "нет головы лодочника: " .. (f and (#list > 0 and table.concat(list, ", ") or "папка пуста") or "нет папки RaidCouriers")
	elseif isDismissed then why = "закрыта ✕"
	elseif not anyButton then
		why = ("нет кнопок: free=%d freeEnabled=%s buy=%s"):format(#(o.free or {}), tostring(o.freeEnabled), tostring(o.buyKind))
	end
	if why ~= _G.RewardAdsLastWhy then
		_G.RewardAdsLastWhy = why
		if o or why ~= "оффера нет" then print("[Реклама/клиент] табличка: " .. (why or "показана")) end
	end
	if why then
		bb:setVisible(false)
		return
	end
	local left = (o.freeReadyAt or 0) - now()
	bb:setCooldown(left > 0 and left or nil)
	if dirty then
		dirty = false
		bb:setOffer(o, iconOf)
	end
	bb:setAdornee(head)
	-- рядом / далеко с гистерезисом
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local dist = hrp and (hrp.Position - head.Position).Magnitude or math.huge
	local edge = Config.BillboardFullDistance
	if mode == "full" and dist > edge + Config.BillboardHysteresis then mode = "compact"
	elseif mode == "compact" and dist < edge - Config.BillboardHysteresis then mode = "full" end
	bb:setMode(mode)
	bb:setVisible(true)
end)

-- выдано: «салют» иконок над лодочником (табличку прячет сам сервер, закрывая оффер)
Granted.OnClientEvent:Connect(function(placement, list)
	if placement ~= "boatman" or type(list) ~= "table" then return end
	local head = myCourierHead(true)
	if LootBurstFX and head then
		local icons = {}
		for _, r in ipairs(list) do
			local id = iconOf(r.id)
			if id ~= "" then table.insert(icons, id) end
		end
		pcall(LootBurstFX.play, head, icons, { heightOffset = 2 })
	end
end)

print("[Реклама/клиент] готов: табличка «Награда с рейда» над лодочником")
