-- AxeClient.client.lua
-- Клиентская часть боевого топора (Tool "Axe"): анимации + отправка замаха на сервер.
--   • Экипировал → Holster (поза удержания, зациклена);
--   • Клик/тап → Attack (замах) + AxeSwing на сервер (урон считает AxeCombat.server).
-- Animation-объекты "Attack" и "Holster" лежат ВНУТРИ тула (авторские). Треки играются
-- на СВОЁМ персонаже локально — Roblox сам реплицирует их всем.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local swingRemote = ReplicatedStorage:WaitForChild("AxeSwing")

-- Локальный кулдаун (сервер дополнительно валидирует). 0.8 = AxeCombat.COOLDOWN:
-- при 0.55 быстрые клики перезапускали анимацию замаха, не дав ей доиграть.
local COOLDOWN = 0.8

local function hookAxe(tool)
	if not (tool:IsA("Tool") and tool.Name:match("^Axe")) then return end

	local holsterTrack, attackTrack
	local lastSwing = 0

	local function animator()
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum then return nil end
		local an = hum:FindFirstChildOfClass("Animator")
		if not an then
			an = Instance.new("Animator")
			an.Parent = hum
		end
		return an
	end

	tool.Equipped:Connect(function()
		local an = animator()
		if not an then return end
		local holsterAnim = tool:FindFirstChild("Holster")
		local attackAnim  = tool:FindFirstChild("Attack")
		if holsterAnim and holsterAnim:IsA("Animation") and holsterAnim.AnimationId ~= "" then
			local ok, tr = pcall(function() return an:LoadAnimation(holsterAnim) end)
			if ok and tr then
				holsterTrack = tr
				tr.Priority = Enum.AnimationPriority.Idle
				tr.Looped = true
				tr:Play(0.15)
			end
		end
		if attackAnim and attackAnim:IsA("Animation") and attackAnim.AnimationId ~= "" then
			local ok, tr = pcall(function() return an:LoadAnimation(attackAnim) end)
			if ok and tr then
				attackTrack = tr
				tr.Priority = Enum.AnimationPriority.Action
				tr.Looped = false
			end
		end
	end)

	tool.Unequipped:Connect(function()
		if holsterTrack then pcall(function() holsterTrack:Stop(0.15) end) holsterTrack = nil end
		if attackTrack then pcall(function() attackTrack:Stop(0.1) end) attackTrack = nil end
	end)

	tool.Activated:Connect(function()
		local now = os.clock()
		if now - lastSwing < COOLDOWN then return end
		lastSwing = now
		if attackTrack then
			pcall(function()
				attackTrack:Stop(0)
				attackTrack:Play(0.05)
			end)
		end
		swingRemote:FireServer()
	end)
end

-- ловим топор в руках и в рюкзаке (выдача в любой момент)
local function watch(container)
	if not container then return end
	for _, c in ipairs(container:GetChildren()) do hookAxe(c) end
	container.ChildAdded:Connect(hookAxe)
end

watch(player:FindFirstChildOfClass("Backpack"))
player.ChildAdded:Connect(function(c)
	if c:IsA("Backpack") then watch(c) end
end)
if player.Character then watch(player.Character) end
player.CharacterAdded:Connect(watch)
