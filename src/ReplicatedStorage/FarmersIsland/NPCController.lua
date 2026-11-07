--[[ ⚠️ КОПИЯ МОДУЛЯ ИЗ ПАКЕТА Farmers_Island_Transfer С НАШИМИ ПРАВКАМИ.
     Оригинал лежит внутри модели острова (Gameplay/*), но модель живёт в Studio,
     а не в репозитории — править его Rojo не может. Поэтому серверная часть
     рантайма острова запускается ОТСЮДА (IslandCrews), а модули внутри модели
     остаются для клиентских скриптов (ToolsClient, MutantClient) как есть.
     Что изменено — помечено «-- НАШЕ:». Остальное — авторский код пакета. ]]
-- Portable Farmers garrison. One server controller per island clone, never Terrain/global coordinates.
-- Models live under Gameplay.NPCs rather than Enemies, avoiding the legacy PirateIslandAI driver.
local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")
local HttpService = game:GetService("HttpService")
local ToolsAnimations = require(script.Parent:WaitForChild("ToolsAnimations"))
local Controller = {}
local running = setmetatable({}, {__mode = "k"})
local EXPECTED = {Pirate=12, Guard=3, Scientist=2, Mutant=1, Worker=2}
local CONFIG = {
	Pirate={speed=10, health=110, damage=12, reach=5, cooldown=1.6},
	Guard={speed=11, health=180, damage=18, reach=5.5, cooldown=1.7},
	Scientist={speed=9, health=85}, Worker={speed=8, health=100},
	Mutant={speed=7, health=950, damage=32, reach=10, cooldown=2.8},
}
local function living(s)
	return s.model.Parent ~= nil and s.hum.Health > 0 and s.root.Parent ~= nil
end
local function arrived(s, point, radius)
	local d=s.root.Position-point
	-- Markers sit on the ground; Humanoid roots are several studs above it.
	return Vector2.new(d.X,d.Z).Magnitude<radius and math.abs(d.Y)<(s.role=="Mutant" and 13 or 7)
end
local function face(s,position)
	local target=Vector3.new(position.X,s.root.Position.Y,position.Z)
	if (target-s.root.Position).Magnitude>.05 then s.root.CFrame=CFrame.lookAt(s.root.Position,target) end
end
local function ordered(folder)
	local list = {}
	if folder then
		for _, p in ipairs(folder:GetChildren()) do if p:IsA("BasePart") then table.insert(list,p) end end
	end
	table.sort(list,function(a,b)
		local ai,bi=a:GetAttribute("Order") or tonumber(a.Name:match("%d+$")) or 0,b:GetAttribute("Order") or tonumber(b.Name:match("%d+$")) or 0
		return ai == bi and a.Name < b.Name or ai < bi
	end)
	return list
end

function Controller.Start(island, gameplay)
	assert(RunService:IsServer(), "NPCController.Start is server-only")
	if running[island] then return running[island] end
	gameplay = gameplay or island:WaitForChild("Gameplay")
	local npcs = gameplay:WaitForChild("NPCs")
	for _,name in ipairs({"FarmersNPC","FarmersBatchedDecor"}) do pcall(function() PhysicsService:RegisterCollisionGroup(name) end) end
	PhysicsService:CollisionGroupSetCollidable("FarmersNPC","FarmersBatchedDecor",false)
	PhysicsService:CollisionGroupSetCollidable("FarmersNPC","FarmersNPC",false)
	local supports={}
	for _,p in ipairs(island:GetDescendants()) do
		if p:IsA("BasePart") then
			if p.Name:find("Static_Batch",1,true) then p.CollisionGroup="FarmersBatchedDecor" end
			if p.Name:find("Ground_Detail",1,true) or p.Name:find("Harbor",1,true) or p.Name=="GH_Foundation" or p.Name=="GH_Entry_Step" or p:FindFirstAncestor("NavigationColliders") then table.insert(supports,p) end
		end
	end
	local routes = gameplay:FindFirstChild("Routes")
	local workstations = gameplay:FindFirstChild("Workstations")
	local states, connections, counts = {}, {}, {}
	local stopped, pathsInFlight = false, 0
	local service = {}
	running[island] = service
	local ownership=HttpService:GenerateGUID(false)
	island:SetAttribute("FarmersRuntimeId",ownership)
	island:SetAttribute("FarmersCleared",false)
	island:SetAttribute("FarmersWorkersFreed",0)
	local function ownsIsland() return island:GetAttribute("FarmersRuntimeId")==ownership end
	local random = Random.new(island:GetAttribute("SpawnSeed") or math.floor(workspace:GetServerTimeNow()*1000)%2147483647)
	local function home(s) return island:GetPivot():PointToWorldSpace(s.home) end
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = {npcs}
	local groundRay=RaycastParams.new()
	groundRay.FilterType=Enum.RaycastFilterType.Include
	groundRay.FilterDescendantsInstances=supports
	groundRay.RespectCanCollide=true
	groundRay.CollisionGroup="FarmersNPC"
	local obstacleRay=RaycastParams.new()
	obstacleRay.FilterType=Enum.RaycastFilterType.Exclude
	obstacleRay.FilterDescendantsInstances={npcs}
	obstacleRay.RespectCanCollide=true
	obstacleRay.CollisionGroup="FarmersNPC"
	local function safeStraight(s,origin,goal)
		local horizontal=Vector3.new(goal.X-origin.X,0,goal.Z-origin.Z)
		local distance=horizontal.Magnitude
		if distance<.1 or distance>65 then return nil,"SegmentTooLong" end
		local direction=horizontal.Unit
		local side=Vector3.new(-direction.Z,0,direction.X)
		local radius=s.agentRadius
		local height=s.agentHeight
		local rootAbove=s.hum.HipHeight+s.root.Size.Y/2+(s.hum.RigType==Enum.HumanoidRigType.R6 and 2 or 0)
		local previous=origin.Y-rootAbove
		local firstHeight=previous
		local points={}
		local steps=math.ceil(distance/2.5)
		for i=0,steps do
			local p=origin+horizontal*(i/steps)
			local centerHeight=nil
			for _,offset in ipairs({0,-radius,radius}) do
				local sample=p+side*offset
				local hit=workspace:Raycast(Vector3.new(sample.X,previous+2.5,sample.Z),Vector3.new(0,-5,0),groundRay)
				if not hit or not hit.Instance:IsDescendantOf(island) or hit.Normal.Y<.78 or math.abs(hit.Position.Y-previous)>1.8 then return nil,"UnsafeGround" end
				if offset==0 then centerHeight=hit.Position.Y end
			end
			previous=centerHeight
			if i==0 then firstHeight=centerHeight else table.insert(points,{Position=Vector3.new(p.X,centerHeight,p.Z),Action=Enum.PathWaypointAction.Walk}) end
		end
		if math.abs(previous-goal.Y)>rootAbove+3 then return nil,"DifferentLevel" end
		-- Sweep each short segment at its local ground height, preserving slope clearance.
		local start=Vector3.new(origin.X,firstHeight+height/2+.25,origin.Z)
		for _,point in ipairs(points) do
			local finish=point.Position+Vector3.new(0,height/2+.25,0)
			local block=workspace:Blockcast(CFrame.new(start),Vector3.new(radius*2,height-.5,radius*2),finish-start,obstacleRay)
			if block then return nil,"Obstructed" end
			start=finish
		end
		return points,"SafeDirect"
	end
	local function visible(from, targetModel, targetRoot)
		local delta = targetRoot.Position-from
		if delta.Magnitude < .05 then return true end
		local hit=workspace:Raycast(from,delta,rayParams)
		return not hit or hit.Instance:IsDescendantOf(targetModel)
	end
	local function setState(s,name)
		if s.state==name then return end
		s.state=name
		s.model:SetAttribute("FarmersState",name)
		s.animation:SetState(name)
	end
	local function halt(s)
		s.path=nil; s.goal=nil; s.generation+=1
		s.hum:Move(Vector3.zero)
		s.hum:MoveTo(s.root.Position)
	end
	local function navigate(s,goal,now)
		s.hum.AutoRotate=true
		s.model:SetAttribute("NavigationGoal",goal)
		if arrived(s,goal,2.5) then halt(s); return true end
		if not s.goal or (goal-s.goal).Magnitude > 4 then s.path=nil; s.generation+=1; s.goal=goal end
		if s.path and s.way<=#s.path then
			local waypoint=s.path[s.way]
			if arrived(s,waypoint.Position,3) then s.way+=1; waypoint=s.path[s.way] end
			if waypoint then
				if waypoint.Action==Enum.PathWaypointAction.Jump then s.hum.Jump=true end
				s.hum:MoveTo(waypoint.Position)
			else s.path=nil end
		end
		if now>=s.nextPath and not s.computing and pathsInFlight<2 then
			s.nextPath=now+1.8+random:NextNumber(0,.5); s.computing=true; pathsInFlight+=1
			local generation=s.generation
			local origin=s.root.Position
			task.spawn(function()
				local path=PathfindingService:CreatePath({AgentRadius=s.agentRadius,AgentHeight=s.agentHeight,AgentCanJump=s.role~="Mutant",WaypointSpacing=5})
				local ok=pcall(function() path:ComputeAsync(origin,goal) end)
				pathsInFlight-=1; s.computing=false
				if stopped or not ownsIsland() or not living(s) or generation~=s.generation then return end
				s.model:SetAttribute("NavigationStatus",ok and path.Status.Name or "ComputeError")
				if ok and path.Status==Enum.PathStatus.Success then s.path=path:GetWaypoints();s.way=2;s.model:SetAttribute("NavigationBlocked",false)
				else
					local fallback,reason=safeStraight(s,origin,goal)
					s.model:SetAttribute("NavigationStatus",reason)
					if fallback then s.path=fallback;s.way=1;s.model:SetAttribute("NavigationBlocked",false)
					else s.path=nil;s.model:SetAttribute("NavigationBlocked",true);s.hum:MoveTo(s.root.Position) end
				end
			end)
		end
		if (s.root.Position-s.lastPosition).Magnitude>1 then s.lastMoved=now;s.lastPosition=s.root.Position end
		if now-s.lastMoved>5 then s.path=nil;s.nextPath=now;s.lastMoved=now end
		setState(s,"Walk")
		return false
	end
	local function nearestPlayer(s)
		local best,distance=nil,46
		for _, player in ipairs(Players:GetPlayers()) do
			local ch=player.Character
			local hum=ch and ch:FindFirstChildOfClass("Humanoid")
			local root=ch and ch:FindFirstChild("HumanoidRootPart")
			if hum and root and hum.Health>0 and not ch:FindFirstChildOfClass("ForceField") then
				local d=(root.Position-s.root.Position).Magnitude
				local vertical=math.abs(root.Position.Y-s.root.Position.Y)
				if d<distance and vertical<(s.role=="Mutant" and 18 or 22) and (root.Position-home(s)).Magnitude<95 and visible(s.root.Position+Vector3.new(0,1,0),ch,root) then best={model=ch,hum=hum,root=root};distance=d end
			end
		end
		return best
	end
	-- НАШЕ: пираты острова — наши, лежат в папке Enemies (IslandCrews); для
	-- освобождения работников и «остров чист» они такие же бойцы, как охрана
	local function ourPirates()
		local list={}
		local enemies=island:FindFirstChild("Enemies")
		if enemies then
			for _, m in ipairs(enemies:GetChildren()) do
				local h=m:IsA("Model") and m:FindFirstChildWhichIsA("Humanoid")
				local r=m:FindFirstChild("HumanoidRootPart")
				if h and r and h.Health>0 then table.insert(list,r) end
			end
		end
		return list
	end
	local function fightersRemaining()
		local n=0
		for _, s in ipairs(states) do if CONFIG[s.role].damage and living(s) then n+=1 end end
		return n+#ourPirates()
	end
	local function rescueSafe(worker)
		for _, s in ipairs(states) do
			if CONFIG[s.role].damage and living(s) and (s.root.Position-worker.root.Position).Magnitude<32 then return false end
		end
		for _, r in ipairs(ourPirates()) do
			if (r.Position-worker.root.Position).Magnitude<32 then return false end
		end
		return true
	end
	function service.Rescue(worker,player)
		if stopped or not ownsIsland() then return false end
		local selected=nil
		for _, s in ipairs(states) do if s.model==worker then selected=s;break end end
		if not selected or selected.role~="Worker" or not living(selected) or selected.freed then return false end
		if player then
			local ch=player.Character;local root=ch and ch:FindFirstChild("HumanoidRootPart");local hum=ch and ch:FindFirstChildOfClass("Humanoid")
			if not root or not hum or hum.Health<=0 or (root.Position-selected.root.Position).Magnitude>12 or not rescueSafe(selected) or not visible(root.Position,selected.model,selected.root) then return false end
		elseif fightersRemaining()>0 then return false end
		selected.freed=true;selected.joyUntil=os.clock()+6;selected.busyUntil=0
		selected.hum.AutoRotate=true
		selected.model:SetAttribute("FarmersJoyUntil",workspace:GetServerTimeNow()+6)
		selected.model:SetAttribute("Freed",true);selected.model:SetAttribute("Prisoner",false)
		selected.model:SetAttribute("RoleDisplayName","Свободный житель")
		selected.hum.DisplayName="Свободный житель"
		local head=selected.model:FindFirstChild("Head")
		local decal=head and (head:FindFirstChild("face") or head:FindFirstChildWhichIsA("Decal"))
		local happyTexture=selected.model:GetAttribute("HappyFaceTexture")
		if decal and decal:IsA("Decal") and type(happyTexture)=="string" and happyTexture~="" then decal.Texture=happyTexture end
		selected.prompt.Enabled=false;halt(selected);selected.animation:Celebrate(6);selected.state="Joy"
		selected.model:SetAttribute("FarmersState","Joy")
		local tool=selected.model:FindFirstChildWhichIsA("Tool")
		if tool then tool.Parent=gameplay:FindFirstChild("ReturnedTools") or gameplay end
		local freedCount=0
		for _, s in ipairs(states) do if s.role=="Worker" and s.freed then freedCount+=1 end end
		island:SetAttribute("FarmersWorkersFreed",freedCount)
		local event=gameplay:FindFirstChild("WorkersFreed")
		if event and event:IsA("BindableEvent") then event:Fire(selected.model,player,freedCount) end
		return true
	end
	for _, model in ipairs(npcs:GetChildren()) do
		-- НАШЕ: мутанта ведёт MutantAI, здесь его нет
		if model:IsA("Model") and model:GetAttribute("FarmersRole")~="Mutant" then
			local role=model:GetAttribute("FarmersRole")
			if role=="Civilian" then role="Worker";model:SetAttribute("FarmersRole",role) end
			local config=CONFIG[role];local hum=model:FindFirstChildOfClass("Humanoid");local root=model:FindFirstChild("HumanoidRootPart")
			assert(config and hum and root,"Invalid Farmers NPC: "..model.Name)
			counts[role]=(counts[role] or 0)+1
			model:SetAttribute("FarmersNPC",true);model:SetAttribute("FarmersController","PortableV1")
			model:SetAttribute("Prisoner",role=="Worker")
			if role=="Worker" then model:SetAttribute("Freed",false);model:SetAttribute("Escaped",false);model:SetAttribute("FarmersJoyUntil",nil) end
			hum.MaxHealth=model:GetAttribute("MaxHealth") or config.health;hum.Health=hum.MaxHealth;hum.WalkSpeed=config.speed
			hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown,false)
			hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll,false)
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then d.Anchored=false;d.CollisionGroup="FarmersNPC";pcall(function() d:SetNetworkOwner(nil) end) end
				if d:IsA("ForceField") then d:Destroy() end
			end
			local s={model=model,hum=hum,root=root,role=role,home=island:GetPivot():PointToObjectSpace(root.Position),route=ordered(routes and routes:FindFirstChild(model:GetAttribute("Route") or model.Name)),routeIndex=1,nextPath=0,generation=0,lastMoved=os.clock(),lastPosition=root.Position,nextAttack=0,nextHeal=0,busyUntil=0,pauseUntil=0}
			local _,bounds=model:GetBoundingBox()
			s.agentHeight=role=="Mutant" and math.max(6,bounds.Y) or 5
			s.agentRadius=role=="Mutant" and math.max(2,root.Size.X*.75) or 1.25
			s.animation=ToolsAnimations.Attach(model,role)
			table.insert(states,s)
			if role=="Worker" then
				local oldPrompt=root:FindFirstChild("FreeWorker");if oldPrompt then oldPrompt:Destroy() end
				local prompt=Instance.new("ProximityPrompt");prompt.Name="FreeWorker";prompt.ActionText="Освободить";prompt.ObjectText="Пленный работник";prompt.HoldDuration=1.8;prompt.MaxActivationDistance=9;prompt.RequiresLineOfSight=true;prompt.Parent=root;s.prompt=prompt
				table.insert(connections,prompt.Triggered:Connect(function(player) service.Rescue(model,player) end))
			end
			table.insert(connections,hum.Died:Connect(function()
				hum.AutoRotate=true
				halt(s);s.animation:Destroy();if s.prompt then s.prompt.Enabled=false end
				model:SetAttribute("FarmersState","Dead")
			end))
		end
	end
	local mutant=nil
	for _, s in ipairs(states) do if s.role=="Mutant" then mutant=s end end
	local function patrol(s,now)
		if now<s.pauseUntil then setState(s,s.role=="Scientist" and "Inspect" or "Idle");return end
		local point=s.route[s.routeIndex]
		local goal=point and point.Position or home(s)
		if navigate(s,goal,now) then s.routeIndex=s.routeIndex%math.max(#s.route,1)+1;s.pauseUntil=now+random:NextNumber(2,5);setState(s,"Idle") end
	end
	local function tick(s,now)
		if not living(s) then return end
		if s.role=="Worker" then
			-- Replicated liberation is authoritative even during a runtime replacement.
			if s.model:GetAttribute("Freed") and not s.freed then
				s.freed=true;s.busyUntil=0;s.hum.AutoRotate=true
				s.joyUntil=now+math.max(0,(s.model:GetAttribute("FarmersJoyUntil") or 0)-workspace:GetServerTimeNow())
				halt(s)
			end
			s.prompt.Enabled=not s.freed and rescueSafe(s)
			if s.freed then
				if now<s.joyUntil then
					if s.model:GetAttribute("FarmersAction")~="Joy" then s.animation:SetState("Joy") end
					s.model:SetAttribute("FarmersState","Joy");s.state="Joy"
					return
				end
				local escape=ordered(routes and routes:FindFirstChild("Escape"))
				if #escape>0 and not s.escaped then
					s.escapeIndex=s.escapeIndex or 1
					if navigate(s,escape[s.escapeIndex].Position,now) then
						if s.escapeIndex==#escape then s.escaped=true;s.model:SetAttribute("Escaped",true);setState(s,"Idle") else s.escapeIndex+=1 end
					end
				else setState(s,"Idle") end
				return
			end
			if now<s.busyUntil then
				if s.waterFacing then s.hum.AutoRotate=false;face(s,s.root.Position+s.waterFacing) end
				return
			end
			local station=workstations and workstations:FindFirstChild(s.model:GetAttribute("Workstation") or s.model.Name)
			local point=s.route[s.routeIndex]
			local goal=point and point.Position or (station and station:IsA("BasePart") and station.Position) or home(s)
			if navigate(s,goal,now) then
				local facing=point or (station and station:IsA("BasePart") and station)
				s.hum.AutoRotate=false
				if facing then s.waterFacing=facing.CFrame.LookVector;face(s,s.root.Position+s.waterFacing) end
				s.busyUntil=now+5;s.routeIndex=s.routeIndex%math.max(#s.route,1)+1;s.animation:Water(5);s.state="Water";s.model:SetAttribute("FarmersState","Water")
			end
			return
		end
		if s.role=="Scientist" then
			if now<s.busyUntil then return end
			local patient,ratio=nil,.95
			for _, other in ipairs(states) do
				if CONFIG[other.role].damage and living(other) and other.hum.Health/other.hum.MaxHealth<ratio and (other.root.Position-s.root.Position).Magnitude<36 then patient=other;ratio=other.hum.Health/other.hum.MaxHealth end
			end
			if patient then
				if (patient.root.Position-s.root.Position).Magnitude>7 then navigate(s,patient.root.Position,now)
				elseif visible(s.root.Position,patient.model,patient.root) then halt(s);setState(s,"Heal");if now>=s.nextHeal then patient.hum.Health=math.min(patient.hum.MaxHealth,patient.hum.Health+12);s.nextHeal=now+2;s.busyUntil=now+1.2 end
				else navigate(s,patient.root.Position,now) end
			else patrol(s,now) end
			return
		end
		if now<s.busyUntil then return end
		if (s.root.Position-home(s)).Magnitude>110 then
			s.model:SetAttribute("Detected",false)
			if navigate(s,home(s),now) then setState(s,"Idle") end
			return
		end
		local target=nearestPlayer(s)
		local cfg=CONFIG[s.role]
		if target then
			s.model:SetAttribute("Detected",true)
			if (target.root.Position-s.root.Position).Magnitude<=cfg.reach then
				halt(s)
				face(s,target.root.Position)
				if now>=s.nextAttack then
					s.nextAttack=now+cfg.cooldown;s.busyUntil=now+(s.role=="Mutant" and 1.52 or .82)
					s.animation:Strike(target.hum)
					task.delay(s.role=="Mutant" and .676 or .28,function()
						if stopped or not ownsIsland() or not living(s) or target.hum.Health<=0 or not target.root.Parent or target.model:FindFirstChildOfClass("ForceField") then return end
						if (target.root.Position-s.root.Position).Magnitude<=cfg.reach+1 and visible(s.root.Position,target.model,target.root) then target.hum:TakeDamage(cfg.damage) end
					end)
				else setState(s,"Idle") end
			else navigate(s,target.root.Position,now) end
		elseif s.role=="Guard" and mutant and living(mutant) then
			s.model:SetAttribute("Detected",false)
			local slot=s.model:GetAttribute("EscortIndex") or 1
			local angle=(slot-1)*math.pi*2/3
			local offset=Vector3.new(math.cos(angle)*8,0,math.sin(angle)*8)
			if navigate(s,mutant.root.CFrame:PointToWorldSpace(offset),now) then setState(s,"Idle") end
		else s.model:SetAttribute("Detected",false);patrol(s,now) end
	end
	local elapsed=0
	table.insert(connections,RunService.Heartbeat:Connect(function(dt)
		elapsed+=dt;if elapsed<.2 then return end;elapsed=0
		if stopped then return end
		if not ownsIsland() then service.Stop(true);return end
		local now=os.clock()
		for _, s in ipairs(states) do tick(s,now) end
		local remaining=fightersRemaining();island:SetAttribute("FarmersHostilesRemaining",remaining)
		if remaining==0 and not island:GetAttribute("FarmersCleared") then
			island:SetAttribute("FarmersCleared",true)
			for _, s in ipairs(states) do if s.role=="Worker" then service.Rescue(s.model,nil) end end
		end
	end))
	function service.GetStatus()
		local result={total=#states,hostiles=fightersRemaining(),counts=table.clone(counts),workersFreed=0}
		for _, s in ipairs(states) do if s.freed then result.workersFreed+=1 end end
		return result
	end
	function service.Stop(preserveActors)
		if stopped then return end;stopped=true;running[island]=nil
		for _, c in ipairs(connections) do c:Disconnect() end
		if not preserveActors then
			for _, s in ipairs(states) do s.hum.AutoRotate=true;if s.root.Parent then halt(s) end;s.animation:Destroy();if s.prompt then s.prompt:Destroy() end end
		end
	end
	table.insert(connections,island.AncestryChanged:Connect(function() if not island:IsDescendantOf(workspace) then service.Stop() end end))
	return service
end
return Controller
