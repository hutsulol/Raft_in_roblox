-- SheepPlayAnimation.server.lua
-- Dev helper: put this Script under the sheep Model (or reference it
-- directly below) and it will play the Animation instance named
-- "Animation" that already exists inside the same model.

local model = script.Parent
if not model or not model:IsA("Model") then
	warn("[SheepAnim] Script must be parented to the sheep Model")
	return
end

local animObj = model:FindFirstChild("Animation")
if not animObj or not animObj:IsA("Animation") then
	warn("[SheepAnim] Animation object named 'Animation' not found in model: " .. model:GetFullName())
	return
end

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
	return
end

track.Looped = true
track:Play()

print("[SheepAnim] Playing animation on", model:GetFullName())
