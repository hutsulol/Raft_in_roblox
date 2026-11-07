-- DiverPreview.lua (ReplicatedStorage ModuleScript)
-- A LIVE, animated 3D preview of the Diver_UI rig inside a ViewportFrame (via WorldModel), framed
-- from the FRONT. Shared by the monolith repair window and the diver shop so both show the same
-- diver. The animation is advanced manually each frame (Animator:StepAnimations) — that's what makes
-- a ViewportFrame character actually move rather than sit as a frozen screenshot.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local AssetFind         = require(ReplicatedStorage:WaitForChild("AssetFind"))

local UI_MODEL = "Diver_UI"          -- dedicated UI rig (falls back to "Diver")
local SHOW     = 0.70                 -- fraction of the model height shown from the top
local ANGLE    = math.rad(18)         -- slight 3/4 turn off dead-front
local BORDER   = Color3.fromRGB(28, 79, 143)

local M = {}

local function corner(i, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = i end

-- pick the rig's display animation: prefer idle/ui/show/pose, then swim/walk, else the first
local function pickAnim(model)
	local prefer = { "idle", "ui", "show", "pose", "swim", "walk" }
	local anims = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Animation") and d.AnimationId ~= "" then table.insert(anims, d) end
	end
	for _, pat in ipairs(prefer) do
		for _, a in ipairs(anims) do
			if a.Name:lower():find(pat) then return a end
		end
	end
	return anims[1]
end

-- build the preview holder (with the ViewportFrame) and parent it to `parent`; returns the holder
function M.mount(parent)
	local holder = Instance.new("Frame")
	holder.Name = "PreviewHolder"
	holder.AnchorPoint = Vector2.new(1, 0.5); holder.Position = UDim2.new(1, -18, 0.5, 12)
	holder.Size = UDim2.fromOffset(214, 300)
	holder.BackgroundTransparency = 1 -- no backdrop: the diver floats over the panel
	holder.ZIndex = 3
	holder.Parent = parent

	local vp = Instance.new("ViewportFrame")
	vp.Size = UDim2.fromScale(1, 1); vp.BackgroundTransparency = 1; vp.ZIndex = 4
	vp.Ambient = Color3.fromRGB(200, 212, 230); vp.LightColor = Color3.fromRGB(255, 255, 255)
	vp.LightDirection = Vector3.new(-0.3, -1, -0.55); vp.Parent = holder; corner(vp, 16)

	local cam = Instance.new("Camera"); cam.Parent = vp; vp.CurrentCamera = cam
	local world = Instance.new("WorldModel"); world.Parent = vp

	local template = AssetFind.find(UI_MODEL, "Diver")
	if not template then
		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1; lbl.Size = UDim2.fromScale(1, 1); lbl.Font = Enum.Font.GothamBold
		lbl.Text = UI_MODEL .. "\n(нет в ReplicatedStorage)"; lbl.TextColor3 = Color3.new(1, 1, 1)
		lbl.TextSize = 15; lbl.TextWrapped = true; lbl.ZIndex = 5; lbl.Parent = holder
		return holder
	end

	local model = template:Clone()
	local hrp
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.CanCollide = false
			if d.Name == "HumanoidRootPart" then hrp = d; d.Anchored = true else d.Anchored = false end
		end
	end
	model.Parent = world

	-- Animator for live playback
	local hum = model:FindFirstChildWhichIsA("Humanoid", true)
	local animator
	if hum then
		animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
	else
		local ac = Instance.new("AnimationController"); ac.Parent = model
		animator = Instance.new("Animator"); animator.Parent = ac
	end
	local anim = pickAnim(model)
	if anim then
		local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
		if ok and track then track.Looped = true; track:Play() end
	end
	-- advance the animation each frame (ViewportFrames don't auto-step Animators); pause when hidden.
	-- Animator:StepAnimations is now gated ("lacking capability Plugin") in many contexts — if it errors
	-- we disconnect and fall back to a STATIC posed bust (which is what the UI wants anyway) rather than
	-- spamming the Output every frame.
	local screen = parent:FindFirstAncestorWhichIsA("ScreenGui")
	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		if screen and not screen.Enabled then return end
		local ok = pcall(function() animator:StepAnimations(dt) end)
		if not ok and conn then conn:Disconnect(); conn = nil end
	end)

	-- frame the FRONT of the rig (top portion), using its own facing so we never look at its back
	local cf, size = model:GetBoundingBox()
	local center = cf.Position
	local root = hrp or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	local front = root and root.CFrame.LookVector or Vector3.new(0, 0, 1)
	front = Vector3.new(front.X, 0, front.Z)
	front = (front.Magnitude > 0.01) and front.Unit or Vector3.new(0, 0, 1)
	front = CFrame.Angles(0, ANGLE, 0) * front
	local FOV = 70; cam.FieldOfView = FOV
	local top = center.Y + size.Y * 0.5
	local dist = (SHOW * size.Y) / (2 * math.tan(math.rad(FOV / 2))) * 1.45 -- pulled back a bit
	local lookAt = Vector3.new(center.X, top - SHOW * size.Y * 0.5, center.Z)
	cam.CFrame = CFrame.lookAt(
		Vector3.new(lookAt.X + front.X * dist, lookAt.Y + size.Y * 0.02, lookAt.Z + front.Z * dist), lookAt)

	return holder
end

return M
