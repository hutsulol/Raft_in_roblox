-- SheepPlayAnimation.server.lua
-- Dev helper: run from anywhere (e.g. ServerScriptService or DevScripts).
-- It auto-finds sheep-like models in Workspace that contain an
-- Animation child named "Animation" and starts it on their
-- AnimationController/Animator.

local Workspace = game:GetService("Workspace")

local function playOnModel(model)
	local animObj = model:FindFirstChild("Animation")
	if not (animObj and animObj:IsA("Animation")) then return false end

	local controller = model:FindFirstChildOfClass("AnimationController")
	if not controller then
		controller = Instance.new("AnimationController")
		controller.Name = "AnimationController"
		controller.Parent = model
	end

	local animator = controller:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = controller
	end

	local ok, track = pcall(function()
		return animator:LoadAnimation(animObj)
	end)
	if not ok or not track then
		warn("[SheepAnim] Failed to load animation for " .. model:GetFullName())
		return false
	end

	track.Priority = Enum.AnimationPriority.Action
	track.Looped = true
	track:Play(0.1, 1, 1)
	print("[SheepAnim] Playing animation on", model:GetFullName())
	return true
end

local started = 0
for _, inst in Workspace:GetDescendants() do
	if inst:IsA("Model") and playOnModel(inst) then
		started += 1
	end
end
print(("[SheepAnim] started tracks: %d"):format(started))
