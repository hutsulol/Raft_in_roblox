-- Isolated local test place, never deploy this harness with a production game.
local RunService = game:GetService("RunService")
assert(RunService:IsStudio(), "CodeLab is only for local Studio tests")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Http = game:GetService("HttpService")
local Config = require(game:GetService("ServerStorage"):WaitForChild("StudioConfig"))
local Codes = require(script.Parent:WaitForChild("RewardCodes"))
local action = Instance.new("RemoteFunction")
action.Name = "CodeLabAction"
action.Parent = RS
local state = {}
local latest
local pending
local checks = "Ещё не проверено"
local network = "Ожидание HTTP-запроса"
local nextAction = {}
local function call(method, path, data, apiKey)
	local response = Http:RequestAsync({ Url = Config.baseUrl .. path, Method = method,
		Headers = { ["Content-Type"] = "application/json", ["X-API-Key"] = apiKey or Config.apiKey },
		Body = data and Http:JSONEncode(data) or nil })
	return response.StatusCode, Http:JSONDecode(response.Body)
end
Codes.Start({
	baseUrl = Config.baseUrl, secretName = "unused-in-local-studio", studioTest = { apiKey = Config.apiKey },
	rewardIds = { pirate_card_1000 = true },
	onPending = function(_, why) network = "API недоступен; повтор через 5 секунд: " .. why end,
	onIssued = function(_, card)
		latest = card
		pending = nil
		network = "Roblox → HttpService → API → SQLite: OK"
		print("[CodeLab] CARD_RECEIVED amount=" .. tostring(card.amount) .. " drop=" .. card.dropId)
		task.spawn(function()
			local ok, err = pcall(function()
				local body = { universeId = 0, dropId = card.dropId, robloxUserId = 1, rewardId = card.rewardId }
				local status, again = call("POST", "/api/roblox/rewards/issue", body)
				assert(status == 200 and again.code == card.code and again.amount == card.amount, "duplicate issue mismatch")
				local denied = call("POST", "/api/roblox/rewards/issue", body, "invalid-key")
				assert(denied == 401, "invalid key not rejected")
				body.rewardId = "pirate_card_100"
				local conflict = call("POST", "/api/roblox/rewards/issue", body)
				assert(conflict == 409, "conflicting nominal not rejected")
				checks = "3/3: повтор кода, защита ключа, защита номинала"
				print("[CodeLab] HTTP_CHECKS_PASS 3/3")
			end)
			if not ok then checks = "Проверка не прошла: " .. tostring(err); warn("[CodeLab] CHECK_FAILED " .. tostring(err)) end
		end)
	end,
})
local function snapshot()
	return { card = latest, pending = pending ~= nil, network = network, checks = checks, redeemed = state.redeemed, balance = state.balance }
end
action.OnServerInvoke = function(player, name)
	if name == "state" then return snapshot() end
	if (nextAction[player] or 0) > os.clock() then return { error = "Подождите пару секунд" } end
	nextAction[player] = os.clock() + 2
	if name == "issue" then
		if not pending then pending = "studio-pack-" .. Http:GenerateGUID(false) end
		network = "Карточка ожидает выдачи…"
		state.redeemed = nil
		local ok, why = Codes.Queue(player, pending, "pirate_card_1000")
		if not ok then return { error = why } end
		return snapshot()
	elseif name == "redeem" then
		if not latest then return { error = "Сначала получите карточку" } end
		local ok, result = pcall(function()
			local status, first = call("POST", "/api/redeem", { code = latest.code })
			assert(status == 200, "redeem HTTP " .. tostring(status))
			local retryStatus, again = call("POST", "/api/redeem", { code = latest.code })
			assert(retryStatus == 200 and again.alreadyRedeemed and first.balance == again.balance, "double credit")
			return again
		end)
		if not ok then return { error = tostring(result) } end
		state.redeemed = "Код активирован; повтор не начислил награду"
		state.balance = result.balance
		latest.status = "redeemed"
		print("[CodeLab] REDEEM_AND_RETRY_PASS balance=" .. tostring(result.balance))
		return snapshot()
	elseif name == "history" then
		local history, err = Codes.List(player)
		if not history then return { error = err } end
		-- Page through all test cards to restore the most recently issued one.
		for _ = 1, 20 do
			if #history.cards > 0 then latest = history.cards[#history.cards] end
			if not history.nextCursor then break end
			history, err = Codes.List(player, history.nextCursor)
			if not history then return { error = err } end
		end
		network = "Карточки восстановлены из API после перезахода"
		print("[CodeLab] HISTORY_RESTORED")
		return snapshot()
	end
	return { error = "unknown_action" }
end
Players.PlayerRemoving:Connect(function(player) nextAction[player] = nil end)
print("[CodeLab] READY: real HTTP, real SQLite; local Studio outbox is in memory")
