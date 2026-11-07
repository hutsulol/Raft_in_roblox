function waitForChild(instance, name)
	while not instance:FindFirstChild(name) do
		instance.ChildAdded:wait()
	end
end


local Tool = script.Parent

enabled = true
game:GetService("ContentProvider"):Preload("rbxasset://icons/delete_sel.png")

local cluster = nil

local selectionBox
local currentSelection
local currentSelectionColors = {}
local selectionLasso

local deleteDistance = 100
local player = nil
--local playerModel = nil
local playerModel = game.Workspace
local buildingPlate = nil

local highlight = false

local megaClusterSelectionBox = Instance.new("Part")
megaClusterSelectionBox.FormFactor = "Custom"
megaClusterSelectionBox.Size = Vector3.new(4, 4, 4) -- a little thicker than 4x4x4 unit clusterpart; just so selection box is more easily seen
megaClusterSelectionBox.Transparency = 1
megaClusterSelectionBox.Anchored = true
megaClusterSelectionBox.CanCollide = false
megaClusterSelectionBox.Parent = nil

waitForChild(Tool, "IsRestricted")
local isRestricted = Tool.IsRestricted.Value

waitForChild(Tool, "AutoWedgeClusterParts")
local autoWedgeClusterParts = Tool.AutoWedgeClusterParts.Value

function hint(label)

	-- Pass in a string, it shows a top hint.  (Replaces previous hint, if exists)
	_player = game.Players:GetPlayerFromCharacter(Tool.Parent)
	if(_player ~= nil and _player.PlayerGui:FindFirstChild("topHint")~=nil) then
		local topHint = _player.PlayerGui.topHint
		topHint.Add.Label.Value = label
		topHint.Add.Width.Value = 3 -- widest width
		topHint.Add.Time.Value = 5
		topHint.Add.Disabled = true
		topHint.Add.Disabled = false
	end

end

function canDeleteObject(part)
	-- let them delete anything that they created *or* anything on their baseplate
	return part and not (part.Locked) and part:IsA("BasePart") and (part.Position - Tool.Parent.Head.Position).Magnitude < deleteDistance and (isChildOfMyModel(part) or partInBounds(part))
end

-- For Restricting Stamper Tool (isRestricted)
function inBounds(part)

	if part == nil then return false end

	if part:IsA("Part") or part:IsA("WedgePart") or part:IsA("TrussPart") then
		if not partInBounds(part) then return false end
	elseif part:IsA("Model") then
		local primPart = object.PrimaryPart
		if not partInBounds(primPart) then return false end
	end

	return true

end

function partInBounds(part)

	local xOne = buildingPlate.Position.x + buildingPlate.Size.x/2
	local xTwo = buildingPlate.Position.x - buildingPlate.Size.x/2
	local zOne = buildingPlate.Position.z + buildingPlate.Size.z/2
	local zTwo = buildingPlate.Position.z - buildingPlate.Size.z/2

	if part.Position.x > xOne or part.Position.x < xTwo then return false end
	if part.Position.z > zOne or part.Position.z < zTwo then return false end

	return true

end


function findModel(part)
	while part ~= nil do
		if part.className == "Model" and part.Name ~= playerModel.Name and part.Name ~= "GarbageParts" then
			return part
		elseif part.Name == playerModel.Name or part.Name == "GarbageParts" then
			return nil
		end
		part = part.Parent
	end

	return nil
end

function cleanOrphanedModel(parent)
	if not parent then return end
	if parent.className == "Model" then
		local children = parent:GetChildren()
		if #children == 0 and parent.Name ~= "GarbageParts" then
			local oldParent = parent.Parent
			parent:Remove()
			cleanOrphanedModel(oldParent)
		end
	end
end

function isChildOfMyModel(part)
		if not playerModel then return true end
		if playerModel:IsAncestorOf(part) then
			return true
		else return false end
end


-- Cyrion's auto-wedge fcn:
--turns column going down from coordinate x, y, z in cluster c into a wedge if possible
function makeWedge(x, y, z, c)
	-- bounds-check the call first
	if x < 0 or y < 0 or z < 0 then return end
	local clusterMaxX, clusterMaxY, clusterMaxZ = c:GetTerrainSizeInCells()
	if x >= clusterMaxX or y >= clusterMaxY or z >= clusterMaxZ then return end


	materiala, wedgea, rotationa = c:GetCellFull(x, y, z)
	materialb, wedgeb, rotationb = c:GetCellFull(x, y + 1, z)
	if materiala > 0 and materialb == 0 then
		--wedges
		originalheight = y
		h = originalheight
		wedgetype = -1 --type of wedge used above this one
		material, wedge, rotation = c:GetCellFull(x, h, z)
		while (wedgetype ~= 0 or h >= originalheight - 1) and h >= 0 and material > 0 do
			sides = {} --array of 4 surrounding coordinates, sides[n] has value 1 if coordinate is same height, 0 if lower
			surroundingsides = 0
			
			--check heights of 4 side coordinates
			
			--sides
			material0s, wedge0s, rotation0s = c:GetCellFull(x, h, z + 1)
			if material0s > 0 then
				sides[0] = 1
				surroundingsides = surroundingsides + 1
			elseif material0s == 0 then
				sides[0] = 0
			end
			
			material1s, wedge1s, rotation1s = c:GetCellFull(x + 1, h, z)
			if material1s > 0 then
				sides[1] = 1
				surroundingsides = surroundingsides + 1
			elseif material1s == 0 then
				sides[1] = 0
			end
			
			material2s, wedge2s, rotation2s = c:GetCellFull(x, h, z - 1)
			if material2s > 0 then
				sides[2] = 1
				surroundingsides = surroundingsides + 1
			elseif material2s == 0 then
				sides[2] = 0
			end
			
			material3s, wedge3s, rotation3s = c:GetCellFull(x - 1, h, z)
			if material3s > 0 then
				sides[3] = 1
				surroundingsides = surroundingsides + 1
			elseif material3s == 0 then
				sides[3] = 0
			end
			
			--corners
			surroundingcorners = 0
			corners = {} --an array of 4 corner coordinates, corners[n] has value 1 if coordinate is same height, 0 if lower
			
			material0c, wedge0c, rotation0c = c:GetCellFull(x - 1, h, z - 1)
			if material0c > 0 then
				surroundingcorners = surroundingcorners + 1
				corners[0] = 1
			elseif material0c == 0 then
				corners[0] = 0
			end
		
			material1c, wedge1c, rotation1c = c:GetCellFull(x - 1, h, z + 1)
			if material1c > 0 then
				surroundingcorners = surroundingcorners + 1
				corners[1] = 1
			elseif material1c == 0 then
				corners[1] = 0
			end
		
			material2c, wedge2c, rotation2c = c:GetCellFull(x + 1, h, z + 1)
			if material2c > 0 then
				surroundingcorners = surroundingcorners + 1
				corners[2] = 1
			elseif material2c == 0 then
				corners[2] = 0
			end
		
			material3c, wedge3c, rotation3c = c:GetCellFull(x + 1, h, z - 1)
			if material3c > 0 then
				surroundingcorners = surroundingcorners + 1
				corners[3] = 1
			elseif material3c == 0 then
				corners[3] = 0
			end
		
			--put in wedges
			--print("sides0: "..sides[0])
			--print("sides1: "..sides[1])
			--print("sides2: "..sides[2])
			--print("sides3: "..sides[3])
			if surroundingsides == 0 then
				c:SetCellFull(x, h, z, 1, 0, 0)
				wedgetype = 0
			elseif surroundingsides == 1 then
				if wedgetype == -1 then
					for n = 0, 3 do
						if sides[n] >= 1 then
							c:SetCellFull(x, h, z, 1, 1, (n + 2) % 4)
							wedgetype = 1
						end
					end
				else
					c:SetCellFull(x, h, z, 1, 0, 0)
					wedgetype = 0
				end
			elseif surroundingsides == 2 then
				set = false
				for n = 0, 3 do
					if sides[n] == 0 then
						if sides[(n + 1) % 4] == 0 then
							set = true
							if wedgetype == -1 then
								if corners[n] >= 1 then
									c:SetCellFull(x, h, z, 1, 2, (n + 1) % 4)
									wedgetype = 2
									lastorientation = n
								else
									c:SetCellFull(x, h, z, 1, 4, (n + 1) % 4)
									wedgetype = 4
									lastorientation = n
								end
							elseif wedgetype == 2 or wedgetype == 4 then
								c:SetCellFull(x, h, z, 1, 4, (lastorientation + 1) % 4)
								wedgetype = 4
							else
								c:SetCellFull(x, h, z, 1, 0, 0)
								wedgetype = 0
							end
						end
					end
				end	
				if set == false then
					c:SetCellFull(x, h, z, 1, 0, 0)
					wedgetype = 0
				end
			elseif surroundingsides == 3 then
				for n = 0, 3 do
					if sides[n] == 0 then
						if wedgetype == -1 and corners[n] >= 1 and corners[(n + 3) % 4] >= 1 then
								c:SetCellFull(x, h, z, 1, 1, n)
								wedgetype = 1
						elseif wedgetype == 2 or wedgetype == 4 then
							c:SetCellFull(x, h, z, 1, 4, (lastorientation + 1) % 4)
							wedgetype = 4
						else
							c:SetCellFull(x, h, z, 1, 0, 0)
							wedgetype = 0
						end
					end
				end
			elseif surroundingsides == 4 then
				if (wedgetype == -1 or wedgetype == 2 or wedgetype == 4) and surroundingcorners == 3 then
					for n = 0, 3 do
						if corners[n] == 0 then
							c:SetCellFull(x, h, z, 1, 3, (n + 3) % 4)
							wedgetype = 3
						end
					end
				else
					c:SetCellFull(x, h, z, 1, 0, 0)
					wedgetype = 0
				end
			end
			h = h - 1
			if h >= 0 then
				material, wedge, rotation = c:GetCellFull(x, h, z)
			end
		end
	end
end


function on3dButton1Down(mouse)
	local part = mouse.Target

	if part == nil then 
		return
	elseif part:IsA("Cluster") then
		--local xCell, yCell, zCell = clusterTarget(Vector3.new(math.floor(mouse.Hit.X/4), math.floor(mouse.Hit.Y/4), math.floor(mouse.Hit.Z/4)), mouse.Hit - game.Workspace.CurrentCamera.CoordinateFrame.p, part)
		--if xCell ~= nil then
		local cellBox = getClusterAdjustedRaycast(mouse.Hit.p)
		if cellBox ~= nil then
			--part:SetCell(xCell, yCell, zCell, 0)
			--part:SetCell(math.floor(cellBox.p.X/4), math.floor(cellBox.p.Y/4), math.floor(cellBox.p.Z/4))
			
			--cluster:SetCellFull(cluster:WorldToCell(cellBox.p))
			local xCell, yCell, zCell = cluster:WorldToCell(cellBox.p)
			cluster:SetCellFull(xCell, yCell, zCell)
			if (autoWedgeClusterParts) then
				for xStep = -1, 1 do
					for zStep = -1, 1 do
						if xStep ~= 0 and zStep ~= 0 then
							makeWedge(xCell + xStep, yCell, zCell + zStep, cluster) 
						end
					end
				end
			end
			clearSelection()
		end
	elseif canDeleteObject(part) then
		local model = findModel(part)
		local oldParent
		if model then 
			if currentSelection == model then
				currentSelection = nil
				clearSelection()
			end
			oldParent = model.Parent
			model:Remove()
		else
			if currentSelection == part then
				currentSelection = nil
				clearSelection()
			end
			oldParent = part.Parent
			part:Remove()
		end
		cleanOrphanedModel(oldParent)
	end
end

function saveSelectionColor(instance)
	if instance:IsA("BasePart") then
		currentSelectionColors[instance] = instance.BrickColor
		if instance.BrickColor == BrickColor.Red() then
			instance.BrickColor = BrickColor.new("Really red")
		else
			instance.BrickColor = BrickColor.Red()
		end
	end
end
	
function setSelection(partOrModel)
	if partOrModel ~= currentSelection then
		clearSelection()
		currentSelection = partOrModel
		selectionBox.Adornee = currentSelection
	end
end

function clearSelection()
	if currentSelection ~= nil then
		for part, color in pairs(currentSelectionColors) do
			part.BrickColor = color
		end
		selectionBox.Adornee = nil
	end
	currentSelectionColors = {}
	if currentSelection then currentSelection = nil end
	if selectionBox then selectionBox.Adornee = nil end
	megaClusterSelectionBox.Parent = nil
end

-- ~~~~~ RAYCASTING FCNS COPIED FROM STAMPER TOOL ~~~~~ --
-- below function returns the intersection times of a ray having axis-component dir and axis-start-position p with axis coordinates k1, k2, and k3
function getRayAxisIntersectTimes(p, dir, k1, k2, k3)
	local t1, t2, t3
	if -.01 < dir and dir < .01 then
		if (k1 < p and p < k2) or (k1 > p and p > k2) then t1 = 0 t2 = math.huge t3 = math.huge
		elseif (k2 < p and p < k3) or (k2 > p and p > k3) then t1 = 0 t2 = 0 t3 = math.huge
		else t1 = math.huge t2 = math.huge t3 = math.huge end
	else
		t1 = (k1 - p) / dir
		t2 = (k2 - p) / dir
		t3 = (k3 - p) / dir
	end
	return t1, t2, t3
end

-- returns the hitPoint, given a ray (defined by point and direction) and a time of collision
function calcRay(point, direction, time)
	return (point + direction*time)
end

-- below function assumes that our cluster starts with llcorner at position 0,0,0
--function getClusterCell(point)
--	return game.Workspace:FindFirstChild("Cluster"):GetCell(math.floor((point.X)/4), math.floor((point.Y)/4), math.floor((point.Z)/4))
--end

function checkBox(x, y, z, xSlabs, ySlabs, zSlabs)
	-- need to see if cluster has a cube at the specified location
	local location = Vector3.new((xSlabs[x] + xSlabs[x+1])/2, (ySlabs[y] + ySlabs[y+1])/2, (zSlabs[z] + zSlabs[z+1])/2)
	if cluster:GetCellFull(cluster:WorldToCell(location)) > 0 then return true else return false end
	--if getClusterCell(location) > 0 then return true else return false end
end

function getRayAABBCollisions(p, dir, xSlabs, ySlabs, zSlabs)
	local x1, x2, x3 = getRayAxisIntersectTimes(p.X, dir.X, xSlabs[1], xSlabs[2], xSlabs[3])
	local y1, y2, y3 = getRayAxisIntersectTimes(p.Y, dir.Y, ySlabs[1], ySlabs[2], ySlabs[3])
	local z1, z2, z3 = getRayAxisIntersectTimes(p.Z, dir.Z, zSlabs[1], zSlabs[2], zSlabs[3])

	-- enforce ordering of t1 < t2 < t3 [assumed]
	--if x1 > x3 then temp = x1 x1 = x3 x3 = temp end
	--if y1 > y3 then temp = y1 y1 = y3 y3 = temp end
	--if z1 > z3 then temp = z1 z1 = z3 z3 = temp end

	-- set up xyz tables and indices
	local xtable = {x1, x2, x3}
	local ytable = {y1, y2, y3}
	local ztable = {z1, z2, z3}

	--print(xtable[1], xtable[2], xtable[3])
	--print(ytable[1], ytable[2], ytable[3])
	--print(ztable[1], ztable[2], ztable[3])

	local xIndex = 1
	local yIndex = 1
	local zIndex = 1

	-- loop:
	while xIndex < 3 and yIndex < 3 and zIndex < 3 do
		-- update pointers
		while xIndex < 3 and (xtable[xIndex+1] <= ytable[yIndex] or xtable[xIndex+1] <= ztable[zIndex]) do xIndex = xIndex + 1 end
		while yIndex < 3 and (ytable[yIndex+1] <= xtable[xIndex] or ytable[yIndex+1] <= ztable[zIndex]) do yIndex = yIndex + 1 end
		while zIndex < 3 and (ztable[zIndex+1] <= xtable[xIndex] or ztable[zIndex+1] <= ytable[yIndex]) do zIndex = zIndex + 1 end
		if xIndex < 3 and yIndex < 3 and zIndex < 3 then 
			if checkBox(xIndex, yIndex, zIndex, xSlabs, ySlabs, zSlabs) then  -- if there's a box in that gridsquare
				-- find the latest ray-entry time and return which axis that was on, as well as the hit-point of the ray

				local boxFrame = CFrame.new(Vector3.new((xSlabs[xIndex] + xSlabs[xIndex+1])/2, (ySlabs[yIndex] + ySlabs[yIndex+1])/2, (zSlabs[zIndex] + zSlabs[zIndex+1])/2))

				if xtable[xIndex] > ytable[yIndex] then
					if xtable[xIndex] > ztable[zIndex] then
						return boxFrame, calcRay(p, dir, xtable[xIndex]), 1
					else
						return boxFrame, calcRay(p, dir, ztable[zIndex]), 3
					end
				else
					if ytable[yIndex] > ztable[zIndex] then
						return boxFrame, calcRay(p, dir, ytable[yIndex]), 2
					else
						return boxFrame, calcRay(p, dir, ztable[zIndex]), 3
					end
				end
			end

			-- advance one pointer by one in direction of smallest next value
			if xtable[xIndex + 1] < ytable[yIndex + 1] then
				if xtable[xIndex + 1] < ztable[zIndex + 1] then
					xIndex = xIndex + 1
				else
					zIndex = zIndex + 1
				end
			else
				if ytable[yIndex + 1] < ztable[zIndex + 1] then
					yIndex = yIndex + 1
				else
					zIndex = zIndex + 1
				end
			end
		end
	end

	-- algorithm: can order all of these 9 values, and step through them in order, whenever we see an x2, y2, or z2, we move that direction in our grid of cubes to check
	--            only after we've seen all 1-values do we start checking cubes, and as soon as we see an x3 value we stop.  By "checking cubes" I mean that if that grid space
	--            doesn't have a cube, we continue, and if it does, then we return that cube and surface as our hit :).  (which axis was our the last value we saw [and direction of our ray] determines the surface we hit).

	--local latestStartTime = math.max(x1, y1, z1)
	return nil, nil, 0 -- no collisions
end

function getClusterAdjustedRaycast(mouseHitInWorld)
		-- Note: we assume cluster is positioned with center at <0,0,0>

		local mouseRay = mouseHitInWorld - game.Workspace.CurrentCamera.CoordinateFrame.p
		local clusterSize = cluster:GetTerrainSizeInStuds()

		mouseHitInWorld = mouseHitInWorld + clusterSize/2

		-- test after filling out slabs below
		local xSlabs = {}
		local ySlabs = {}
		local zSlabs = {}
		if mouseRay.X > 0 then
			xSlabs[1] = 4*math.floor(mouseHitInWorld.X/4) - 4 - clusterSize.X/2
			xSlabs[2] = xSlabs[1] + 4
			xSlabs[3] = xSlabs[1] + 8
		else
			xSlabs[1] = 4*math.ceil(mouseHitInWorld.X/4) + 4 - clusterSize.X/2
			xSlabs[2] = xSlabs[1] - 4
			xSlabs[3] = xSlabs[1] - 8
		end

		if mouseRay.Y > 0 then
			ySlabs[1] = 4*math.floor(mouseHitInWorld.Y/4) - 4 - clusterSize.Y/2
			ySlabs[2] = ySlabs[1] + 4
			ySlabs[3] = ySlabs[1] + 8
		else
			ySlabs[1] = 4*math.ceil(mouseHitInWorld.Y/4) + 4 - clusterSize.Y/2
			ySlabs[2] = ySlabs[1] - 4
			ySlabs[3] = ySlabs[1] - 8
		end

		if mouseRay.Z > 0 then
			zSlabs[1] = 4*math.floor(mouseHitInWorld.Z/4) - 4 - clusterSize.Z/2
			zSlabs[2] = zSlabs[1] + 4
			zSlabs[3] = zSlabs[1] + 8
		else
			zSlabs[1] = 4*math.ceil(mouseHitInWorld.Z/4) + 4 - clusterSize.Z/2
			zSlabs[2] = zSlabs[1] - 4
			zSlabs[3] = zSlabs[1] - 8
		end

		return getRayAABBCollisions(game.Workspace.CurrentCamera.CoordinateFrame.p, mouseRay.unit, xSlabs, ySlabs, zSlabs)
end


function on3dMouseMove(mouse) 
	if isRestricted then
		mouse.TargetFilter = game.Workspace.BaseplateBumpers
	else
		mouse.TargetFilter = megaClusterSelectionBox
	end
	local part = mouse.Target

	if not part then
		clearSelection() 
		return
	elseif part:IsA("Cluster") then
		if not cluster then cluster = game:GetService("TerrainService") end
		local cellBox = getClusterAdjustedRaycast(mouse.Hit.p)
		print(cellBox)
		if not cellBox then clearSelection() return end
		megaClusterSelectionBox.CFrame = cellBox

		if isRestricted then megaClusterSelectionBox.Parent = game.Workspace.BaseplateBumpers else megaClusterSelectionBox.Parent = game.Workspace end
		selectionBox.Adornee = megaClusterSelectionBox
	elseif canDeleteObject(part) then
		local model = findModel(part)
		if model then 		
			selectionBox.Color = BrickColor.Red()
			setSelection(model)
		else
			selectionBox.Color = BrickColor.Red()
			setSelection(part)
		end
	else
		clearSelection()
	end
end

local equipCount = 0
function onEquippedLocal(mouse)
	equipCount = equipCount + 1
	local val = equipCount

	if isRestricted then
		waitForChild(game.Workspace, "BuildingAreas")
		if val ~= equipCount then
			return
		end
	end

	local character = script.Parent.Parent
	player = game.Players:GetPlayerFromCharacter(character)
	
	if not player then return end

	if isRestricted then
		local takenAreas = game.Workspace.BuildingAreas:GetChildren()
		for i = 1, #takenAreas do
				if takenAreas[i]:FindFirstChild("Player") ~= nil then  -- Test if child exists (to fix current bug: "Player" child is omitted from 1 baseplate at random, when played online.)
					if takenAreas[i].Player.Value == Tool.Parent.Name then
						buildingPlate = takenAreas[i].PlayerArea.BasePlate
						break
					end
				end
		end
	end

   if buildingPlate then
		playerModel  = buildingPlate.Parent
	else
		--playerModel  = nil
		playerModel = game.Workspace
	end
	guiMain = Instance.new("ScreenGui")
	guiMain.Parent = player.PlayerGui

	mouse.Button1Down:connect(function() on3dButton1Down(mouse) end)
	mouse.Move:connect(function() on3dMouseMove(mouse) end)
	mouse.Icon ="rbxasset://textures\\HammerCursor.png"

	selectionBox = Instance.new("SelectionBox")
	selectionBox.Name = "Model Delete Selection"
	selectionBox.Color = BrickColor.Red()
	selectionBox.Adornee = nil
	selectionBox.Parent = player.PlayerGui

	selectionLasso = Instance.new("SelectionPartLasso")
	selectionLasso.Name = "Model Delete Lasso"
	selectionLasso.Humanoid = character.Humanoid
	selectionLasso.archivable = false
	selectionLasso.Visible = true
	selectionLasso.Parent = game.workspace
	selectionLasso.Color = BrickColor.Red()

	highlight = true
end

function onUnequippedLocal()
	highlight = false
	if selectionBox then
		clearSelection()
		selectionBox:Remove()
	end
	if selectionLasso then selectionLasso:Remove() end
end


Tool.Equipped:connect(onEquippedLocal)
Tool.Unequipped:connect(onUnequippedLocal)
