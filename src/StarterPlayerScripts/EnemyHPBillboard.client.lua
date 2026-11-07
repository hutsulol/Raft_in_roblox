-- EnemyHPBillboard.client.lua
-- Разворачивает HP-борды НПС/пиратов (SurfaceGui на партах, тег "EnemyHPBoard") лицом к
-- камере и держит их над головой. SurfaceGui сам масштабируется с расстоянием (как часть
-- мира) — издалека бар не раздувается, в отличие от экранного BillboardGui. Каждый клиент
-- крутит парты под свою камеру локально (сервер их не двигает — они заякорены и косметичны).

local RunService        = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local TAG = "EnemyHPBoard"

-- ⚠️ ПОСЛЕ плавного хода катеров (BoatRide: PirateBoatSmooth, приоритет First):
-- иначе табличка вставала над НЕсглаженной головой матроса и дрожала
RunService:BindToRenderStep("EnemyHPBoards", Enum.RenderPriority.First.Value + 1, function()
	local cam = workspace.CurrentCamera
	if not cam then return end
	local camPos = cam.CFrame.Position
	for _, board in ipairs(CollectionService:GetTagged(TAG)) do
		if board:IsA("BasePart") and board.Parent then
			local ref = board:FindFirstChild("HeadRef")
			local head = ref and ref.Value
			if head and head.Parent then
				local up = board:GetAttribute("UpStuds") or 2.4
				local pos = head.Position + Vector3.new(0, up, 0)
				-- лицом (Front = -Z) к камере, вертикаль — мировая
				board.CFrame = CFrame.lookAt(pos, camPos, Vector3.yAxis)
			end
		end
	end
end)
