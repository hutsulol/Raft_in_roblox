-- SERVER-ONLY ModuleScript. Require from ServerScriptService, never ReplicatedStorage.
-- No client-accessible issue RemoteEvent. Caller must persist the pack outcome/dropId
-- with the pack consumption BEFORE Queue(), and retry Queue() until it returns true.
local HttpService = game:GetService("HttpService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local M = {}
local config
local store
local active = {}
local pendingStoreName = "TelegramRewardOutbox_v1"
local function ownerId(player)
	return config.studioTest and 1 or player.UserId
end
local function key(userId) return "u_" .. tostring(userId) end
local function validId(id)
	return type(id) == "string" and #id >= 8 and #id <= 128 and id:match("^[%w:_%-]+$") ~= nil
end

local function request(method, path, body)
	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = config.baseUrl .. path,
			Method = method,
			Headers = {
				["Content-Type"] = "application/json",
				["X-API-Key"] = config.studioTest and config.studioTest.apiKey or HttpService:GetSecret(config.secretName),
			},
			Body = body and HttpService:JSONEncode(body) or nil,
		})
	end)
	if not ok then return nil, "network_or_secret_error" end
	if not response.Success then return nil, "http_" .. tostring(response.StatusCode) end
	local decoded, data = pcall(function() return HttpService:JSONDecode(response.Body) end)
	if not decoded or type(data) ~= "table" then return nil, "invalid_response" end
	return data
end

-- Returns backend-owned history (50 cards/page), only to the matching player.
function M.List(player, after)
	if not config then return nil, "not_configured" end
	after = after or 0
	if type(after) ~= "number" or after ~= math.floor(after) or after < 0 or after > 9007199254740991 then
		return nil, "invalid_cursor"
	end
	return request("GET", "/api/roblox/rewards?userId=" .. tostring(ownerId(player)) .. "&after=" .. tostring(after))
end

local function flush(player)
	local userId = ownerId(player)
	if active[userId] then return end
	active[userId] = true
	local ok, err = pcall(function()
		-- UpdateAsync reads the current queue; GetAsync caching can hide pending entries.
		local queue = store:UpdateAsync(key(userId), function(old) return old or {} end)
		for dropId, item in pairs(queue or {}) do
			if not player.Parent then break end
			local result, why = request("POST", "/api/roblox/rewards/issue", {
				dropId = dropId, robloxUserId = userId, rewardId = item.rewardId,
				universeId = config.studioTest and 0 or game.GameId,
			})
			if not result then
				-- Retain durable outbox on ALL errors, including misconfiguration.
				warn("[RewardCodes] delivery pending: " .. tostring(why))
				if config.onPending then pcall(config.onPending, player, why) end
				break
			end
			if result.dropId ~= dropId or result.robloxUserId ~= userId or result.rewardId ~= item.rewardId
				or type(result.code) ~= "string" or type(result.amount) ~= "number" or result.amount <= 0 then
				warn("[RewardCodes] invalid response; retained pending reward")
				break
			end
			-- Backend is now the permanent owner of the card. If this deletion fails,
			-- the next attempt returns the SAME code; no new reward is created.
			store:UpdateAsync(key(userId), function(old)
				old = old or {}
				if old[dropId] and old[dropId].rewardId == item.rewardId then old[dropId] = nil end
				return old
			end)
			if config.onIssued and player.Parent then
				local notified = pcall(config.onIssued, player, result)
				if not notified then warn("[RewardCodes] UI notification failed; card available via List") end
			end
			task.wait(0.3)
		end
	end)
	active[userId] = nil
	if not ok then warn("[RewardCodes] outbox unavailable; will retry") end
end

function M.Queue(player, dropId, rewardId)
	if not config then return false, "not_configured" end
	if not validId(dropId) or not config.rewardIds[rewardId] or ownerId(player) <= 0 then return false, "invalid_reward" end
	local accepted, reason
	local ok = pcall(function()
		store:UpdateAsync(key(ownerId(player)), function(old)
			accepted, reason = false, nil -- callback can run more than once
			old = old or {}
			if old[dropId] then
				if old[dropId].rewardId ~= rewardId then reason = "drop_conflict"; return nil end
				accepted = true; return old
			end
			local count = 0
			for _ in pairs(old) do count = count + 1 end
			if count >= 500 then reason = "queue_full"; return nil end
			old[dropId] = { rewardId = rewardId, createdAt = os.time() }
			accepted = true
			return old
		end)
	end)
	if not ok then return false, "storage_unavailable" end
	if not accepted then return false, reason end
	task.spawn(flush, player)
	return true, "pending"
end

function M.Start(options)
	assert(not config, "RewardCodes already started")
	if options.studioTest then
		assert(RunService:IsStudio(), "studioTest cannot run in a published game")
		assert(type(options.baseUrl) == "string" and options.baseUrl:match("^http://127%.0%.0%.1:%d+$"), "Studio test is loopback-only")
		assert(type(options.studioTest.apiKey) == "string" and #options.studioTest.apiKey >= 32, "Studio API key required")
	else
		assert(type(options.baseUrl) == "string" and options.baseUrl:match("^https://"), "HTTPS API URL required")
	end
	assert(type(options.secretName) == "string", "secretName required")
	assert(type(options.rewardIds) == "table", "rewardIds required")
	config = options
	config.baseUrl = config.baseUrl:gsub("/+$", "")
	if config.studioTest then
		-- Unpublished places cannot use DataStore. ONLY the outbox storage is in-memory
		-- in this explicit Studio harness. HTTP + code generation + backend SQLite are real.
		local records = {}
		store = { UpdateAsync = function(_, recordKey, transform)
			local old = records[recordKey] and HttpService:JSONDecode(HttpService:JSONEncode(records[recordKey])) or nil
			local updated = transform(old)
			if updated ~= nil then records[recordKey] = updated end
			return records[recordKey]
		end }
	else
		store = DataStoreService:GetDataStore(pendingStoreName)
	end
	Players.PlayerAdded:Connect(function(player) task.spawn(flush, player) end)
	for _, player in ipairs(Players:GetPlayers()) do task.spawn(flush, player) end
	task.spawn(function()
		while true do
			task.wait(config.studioTest and 5 or 30 + math.random(0, 10))
			for _, player in ipairs(Players:GetPlayers()) do task.spawn(flush, player) end
		end
	end)
end
return M
