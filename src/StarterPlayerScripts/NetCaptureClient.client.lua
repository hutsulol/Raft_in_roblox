local print, warn = (function() local RS = game:GetService("RunService") if RS:IsServer() then return print, warn end local P, W, Pl = print, warn, game:GetService("Players") local function ok() local p = Pl.LocalPlayer return p ~= nil and p:GetAttribute("DevLogs") == true end return function(...) if ok() then P(...) end end, function(...) if ok() then W(...) end end end)() -- DevLogs: клиентские логи видят только админы (флаг ставит DevLogFlag.server)
--[[ СЕТКОМЁТ — клиент (Client.client пакета NetCapture_Import), без правок:
     прицел по курсору, локальная сеть у дула, позы рук при переноске, F/B —
     освободить овцу. Подсказка внизу экрана — авторская. ]]
local Players=game:GetService('Players')
local RunService=game:GetService('RunService')
local Context=game:GetService('ContextActionService')
local UserInput=game:GetService('UserInputService')
local TweenService=game:GetService('TweenService')
local Pack=game.ReplicatedStorage:WaitForChild('NetCapture')
local Config=require(Pack.Config)
local Poses=require(Pack.CapturePoses)
local SheepAnim=require(Pack.SheepAnimator)   -- НАШЕ: клипы свободной овцы (атрибут Clip от сервера)
local remote=Pack:WaitForChild('Remote')
local player=Players.LocalPlayer
local mouse=player:GetMouse()
local testAimPoint=nil
local aimGrips=setmetatable({},{__mode='k'})
local spawnFlight
local shotSequence=0
local lastAimSent=0
local aimHumanoid=nil
local savedAutoRotate=nil
local sheepFolder=workspace:WaitForChild('NetCaptureSheep')
local fx=Instance.new('Folder');fx.Name='NetCapture_LocalFX';fx.Parent=workspace
local flying={};local sheep={};local hooked=setmetatable({},{__mode='k'});local poseCache=setmetatable({},{__mode='k'})
local lastFire=-1e6;local notice='';local noticeUntil=0
local gui=Instance.new('ScreenGui');gui.Name='NetCaptureHUD';gui.ResetOnSpawn=false;gui.IgnoreGuiInset=true;gui.DisplayOrder=50;gui.Parent=player:WaitForChild('PlayerGui')
--[[ НАШЕ: ПОДСКАЗКА — КАК У КРУЖКИ С ВОДОЙ (CupPurifier): чёрная плашка по
     тексту над хотбаром, HudDock держит её выше слотов и диалога. Авторская
     плашка стояла на 55 px от низа — прямо под хотбаром, текст не читался. ]]
local label=Instance.new('TextLabel');label.Name='Instructions';label.AnchorPoint=Vector2.new(.5,1);label.Position=UDim2.new(.5,0,.85,0);label.Size=UDim2.new(0,0,0,40);label.AutomaticSize=Enum.AutomaticSize.XY;label.BackgroundColor3=Color3.new(0,0,0);label.BackgroundTransparency=.4;label.TextColor3=Color3.new(1,1,1);label.TextSize=18;label.Font=Enum.Font.GothamBold;label.TextWrapped=true;label.Text='';label.Visible=false;label.Parent=gui
local corner=Instance.new('UICorner');corner.CornerRadius=UDim.new(0,8);corner.Parent=label
do local pad=Instance.new('UIPadding');pad.PaddingLeft=UDim.new(0,14);pad.PaddingRight=UDim.new(0,14);pad.PaddingTop=UDim.new(0,6);pad.PaddingBottom=UDim.new(0,6);pad.Parent=label end
do local cap=Instance.new('UISizeConstraint');cap.MinSize=Vector2.new(0,40);cap.Parent=label
 local function fit()local cam=workspace.CurrentCamera;local w=(cam and cam.ViewportSize.X>0) and cam.ViewportSize.X or 1280;cap.MaxSize=Vector2.new(math.max(w-40,220),math.huge) end
 fit();if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal('ViewportSize'):Connect(fit) end end
pcall(function() require(game.ReplicatedStorage:WaitForChild('HudDock')).keepAbove(label,12) end)
-- НАШЕ: телефон — нет клавиш, подсказки про E/F/ЛКМ ему бесполезны
local function isPhone()return UserInput.TouchEnabled and not UserInput.MouseEnabled end
local cross=Instance.new('TextLabel');cross.Name='Crosshair';cross.AnchorPoint=Vector2.new(.5,.5);cross.Size=UDim2.fromOffset(26,26);cross.Position=UDim2.fromScale(.5,.5);cross.BackgroundTransparency=1;cross.Text='+';cross.TextSize=29;cross.Font=Enum.Font.Gotham;cross.TextColor3=Color3.new(1,1,1);cross.TextStrokeTransparency=.25;cross.Visible=false;cross.Parent=gui
local function clock()return workspace:GetServerTimeNow()end
local function tool()
 return player.Character and player.Character:FindFirstChild(Config.ToolName)
end
-- НАШЕ: на телефоне выстрел идёт в точку тапа (Tool.Activated приходит сразу за касанием)
local lastTap=nil
UserInput.InputBegan:Connect(function(input,processed)
 if not processed and input.UserInputType==Enum.UserInputType.Touch then lastTap={x=input.Position.X,y=input.Position.Y,t=os.clock()} end
end)
local function aiming()
 local camera=workspace.CurrentCamera
 if not camera then return Vector3.zero,Vector3.new(0,0,-1) end
 local ray
 if testAimPoint then
  ray=camera:ViewportPointToRay(testAimPoint.X,testAimPoint.Y)
 elseif lastTap and os.clock()-lastTap.t<.5 then
  ray=camera:ViewportPointToRay(lastTap.x,lastTap.y)   -- НАШЕ: телефон — куда тапнули
 elseif UserInput.MouseEnabled and UserInput:GetLastInputType()~=Enum.UserInputType.Gamepad1 then
  ray=mouse.UnitRay
 else
  ray=camera:ViewportPointToRay(camera.ViewportSize.X/2,camera.ViewportSize.Y/2)
 end
 local p=RaycastParams.new();p.FilterType=Enum.RaycastFilterType.Exclude;p.FilterDescendantsInstances={player.Character,fx}
 local hit=workspace:Raycast(ray.Origin,ray.Direction*300,p)
 return hit and hit.Position or ray.Origin+ray.Direction*300,ray.Direction
end
local function aimWeapon(c,target)
 local t=c and c:FindFirstChild(Config.ToolName)
 local grip=c and c:FindFirstChild('RightGrip',true)
 if not t or not grip or not grip:IsA('JointInstance') or not grip.Part0 or not grip.Part1 then return end
 local original=aimGrips[grip]
 if not original then original=grip.C0;aimGrips[grip]=original end
 local anchor=grip.Part0.CFrame*original
 local muzzle=t:FindFirstChild('Muzzle',true)
 if not muzzle then return end
 local offset=grip.Part1.CFrame:ToObjectSpace(muzzle.WorldCFrame)
 if (target-anchor.Position).Magnitude<1 then return end
 local rot=CFrame.lookAt(Vector3.zero,target-anchor.Position).Rotation
 local handle
 -- Keep the hand's grip point fixed. Solve the barrel axis through the cursor
 -- including the muzzle's offset above the handle; never move it to the head.
 for _=1,5 do
  handle=CFrame.new(anchor.Position-rot:VectorToWorldSpace(grip.C1.Position))*rot
  local from=(handle*offset).Position
  if (target-from).Magnitude<.1 then return end
  rot=CFrame.lookAt(Vector3.zero,target-from).Rotation*offset.Rotation:Inverse()
 end
 handle=CFrame.new(anchor.Position-rot:VectorToWorldSpace(grip.C1.Position))*rot
 grip.C0=grip.Part0.CFrame:ToObjectSpace(handle)*grip.C1
 -- Weld C0 updates may be applied on the next physics tick. The shot uses
 -- exactly the solved muzzle transform displayed in this render frame.
 return handle*offset
end
local function fire()
 local t=tool();if not t or player:GetAttribute('NetCarrying') then return end
 if clock()-lastFire<Config.Cooldown then return end
 local muzzle=t:FindFirstChild('Muzzle',true);if not muzzle then return end
 --[[ НАШЕ: УПРАВЛЕНИЕ КАК У ОСТАЛЬНЫХ ТУЛОВ. Авторский клиент каждый кадр
      отключал AutoRotate, крутил тело за курсором и выворачивал оружие в руке —
      персонаж не слушался WASD/камеры. Теперь в руках обычный тул: только в
      момент выстрела тело разом доворачивается к цели, сеть летит из дула. ]]
 local target=aiming()
 local root=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
 if root then
  local flat=Vector3.new(target.X,root.Position.Y,target.Z)-root.Position
  if flat.Magnitude>.5 then root.CFrame=CFrame.lookAt(root.Position,root.Position+flat) end
 end
 local cf=muzzle.WorldCFrame
 local delta=target-cf.Position;if delta.Magnitude<.1 then return end
 lastFire=clock();shotSequence+=1
 local key='pending_'..shotSequence
 spawnFlight(key,cf.Position,delta.Unit,lastFire)
 if Pack:GetAttribute('SelfTest') and RunService:IsStudio() then
  assert((flying[key].model:GetPivot().Position-cf.Position).Magnitude<.001,'net must start at muzzle')
  print('NET_CURSOR_BARREL_AND_ORIGIN_PASS')
 end
 remote:FireServer('Fire',cf.Position,target,shotSequence)
end
local function hook(t)
 if not t:IsA('Tool') or t.Name~=Config.ToolName or hooked[t] then return end
 hooked[t]=t.Activated:Connect(fire)
end
local function bindCharacter(c)
 for _,v in c:GetChildren() do hook(v) end
 c.ChildAdded:Connect(hook)
end
if player.Character then bindCharacter(player.Character) end
player.CharacterAdded:Connect(bindCharacter)
local backpack=player:WaitForChild('Backpack');for _,v in backpack:GetChildren() do hook(v) end;backpack.ChildAdded:Connect(hook)
local function release(_,state)
 if state==Enum.UserInputState.Begin and player:GetAttribute('NetCarrying') then remote:FireServer('Release') end
 return player:GetAttribute('NetCarrying') and Enum.ContextActionResult.Sink or Enum.ContextActionResult.Pass
end
-- НАШЕ: клавиши F / B остаются; экранную кнопку CAS заменила своя (ниже) — та
-- пряталась в углу среди кнопок прыжка и её не находили
Context:BindAction('NetReleaseSheep',release,false,Enum.KeyCode.F,Enum.KeyCode.ButtonB)
--[[ НАШЕ: КНОПКА «ПОСТАВИТЬ ОВЦУ» НА ТЕЛЕФОНЕ — как «Выпить воду» у кружки:
     крупная, по центру над хотбаром. HudDock считает её препятствием, и
     подсказка встаёт над ней, а не поверх. ]]
local carryGui=Instance.new('ScreenGui');carryGui.Name='NetCarryActions';carryGui.ResetOnSpawn=false;carryGui.IgnoreGuiInset=true;carryGui.DisplayOrder=16;carryGui.Enabled=false;carryGui.Parent=player:WaitForChild('PlayerGui')
local putBtn=Instance.new('TextButton');putBtn.Name='PutSheep';putBtn.AnchorPoint=Vector2.new(.5,1);putBtn.Position=UDim2.new(.5,0,1,-112);putBtn.Size=UDim2.fromOffset(0,44);putBtn.AutomaticSize=Enum.AutomaticSize.X
putBtn.BackgroundColor3=Color3.fromRGB(58,150,70);putBtn.BorderSizePixel=0;putBtn.Font=Enum.Font.GothamBlack;putBtn.TextSize=18;putBtn.TextColor3=Color3.new(1,1,1);putBtn.Text='Поставить овцу';putBtn.AutoButtonColor=true;putBtn.Parent=carryGui
do local pad=Instance.new('UIPadding');pad.PaddingLeft=UDim.new(0,20);pad.PaddingRight=UDim.new(0,20);pad.Parent=putBtn
 local c=Instance.new('UICorner');c.CornerRadius=UDim.new(0,10);c.Parent=putBtn
 local st=Instance.new('UIStroke');st.Thickness=2;st.Color=Color3.new(0,0,0);st.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;st.Parent=putBtn end
putBtn.Activated:Connect(function() if player:GetAttribute('NetCarrying') then remote:FireServer('Release') end end)
pcall(function() local Dock=require(game.ReplicatedStorage:WaitForChild('HudDock'));Dock.keepAbove(putBtn,10);Dock.registerObstacle(putBtn) end)
local function cloneNet(name)
 local m=Pack.Assets[name]:Clone()
 for _,v in m:GetDescendants() do if v:IsA('BasePart') then v.Anchored=true;v.CanCollide=false;v.CanTouch=false;v.CanQuery=false end end
 m.Parent=fx;return m
end
spawnFlight=function(id,origin,direction,time)
 local model=cloneNet('FlightNet');model:ScaleTo(.22)
 model:PivotTo(CFrame.lookAt(origin,origin+direction))
 flying[id]={model=model,origin=origin,dir=direction,time=time}
end
local function fade(m,duration)
 for _,v in m:GetDescendants() do if v:IsA('BasePart') then TweenService:Create(v,TweenInfo.new(duration),{Transparency=1}):Play() end end
 task.delay(duration,function()m:Destroy()end)
end
remote.OnClientEvent:Connect(function(kind,a,b,c,d,owner,sequence)
 if kind=='Shot' then
  local key=owner==player.UserId and sequence and ('pending_'..sequence)
  if key and flying[key] then flying[a]=flying[key];flying[key]=nil
  else spawnFlight(a,b,c,d) end
 elseif kind=='Rejected' then
  local key='pending_'..tostring(a);local s=flying[key]
  if s then s.model:Destroy();flying[key]=nil end
 elseif kind=='Impact' then
  local shot=flying[a]
  if shot then
   flying[a]=nil
   if c then shot.model:Destroy()
   else shot.model:PivotTo(CFrame.lookAt(b,b+shot.dir));fade(shot.model,.5) end
  end
 elseif kind=='Notice' then notice=a;noticeUntil=clock()+3 end
end)
local function observe(model)
 if not model:IsA('Model') then return end
 task.spawn(function()
  local root=model:WaitForChild('HumanoidRootPart',10);if not root then return end
  local record={root=root,motors={},state='Free'}
  for _,v in model:GetDescendants() do if v:IsA('Motor6D') and v.Part1 then record.motors[v.Part1.Name]=v end end
  sheep[model]=record
 end)
end
for _,m in sheepFolder:GetChildren() do observe(m) end
sheepFolder.ChildAdded:Connect(observe)
sheepFolder.ChildRemoved:Connect(function(m)local r=sheep[m];if r and r.net then r.net:Destroy() end;sheep[m]=nil end)
--[[ НАШЕ: ПОЙМАННАЯ ОВЦА РЯДОМ — подсказка «как поднять» и подъём тапом/кликом
     по самой овце. ⚠️ Части овцы CanQuery = false (сетка не должна цеплять
     лучи), поэтому попадание считаем не лучом, а расстоянием от луча тапа до
     центра овцы. Сервер (Service.pickup) сам проверяет дальность и стены. ]]
local function capturedNear()
 local c=player.Character;local hrp=c and c:FindFirstChild('HumanoidRootPart')
 if not hrp or player:GetAttribute('NetCarrying') then return nil end
 local best,bestD=nil,Config.PickupRange
 for model,r in sheep do
  if model.Parent and r.root.Parent and model:GetAttribute('NetState')=='Captured' then
   local d=(r.root.Position-hrp.Position).Magnitude
   if d<=bestD then best,bestD=model,d end
  end
 end
 return best
end
local function sheepUnder(screenPos)
 local camera=workspace.CurrentCamera;if not camera then return nil end
 local ray=camera:ViewportPointToRay(screenPos.X,screenPos.Y)
 local best,bestD=nil,math.huge
 for model,r in sheep do
  if model.Parent and r.root.Parent and model:GetAttribute('NetState')=='Captured' then
   local center=r.root.Position+Vector3.new(0,1.6,0)
   local along=(center-ray.Origin):Dot(ray.Direction)
   if along>0 then
    local miss=(ray.Origin+ray.Direction*along-center).Magnitude
    if miss<2.6 and along<bestD then best,bestD=model,along end
   end
  end
 end
 return best
end
UserInput.InputBegan:Connect(function(input,processed)
 if processed or player:GetAttribute('NetCarrying') then return end
 local t=input.UserInputType
 if t~=Enum.UserInputType.Touch and t~=Enum.UserInputType.MouseButton1 then return end
 local model=sheepUnder(Vector2.new(input.Position.X,input.Position.Y))
 if model and model==capturedNear() then remote:FireServer('Pickup',model) end
end)
local function arm(motor,direction)
 if not motor or not motor.Part0 or not motor.Part1 then return end
 local world= motor.Part0.CFrame*motor.C0
 local desired=CFrame.lookAt(Vector3.zero,direction)*CFrame.Angles(math.pi/2,0,0)
 motor.Transform=world.Rotation:Inverse()*desired*motor.C1.Rotation
end
local function posePlayer(p)
 local c=p.Character;if not c then return end
 local carrying=c:GetAttribute('NetCarrying')
 local root=c:FindFirstChild('HumanoidRootPart');if not root then return end
 local cache=poseCache[c]
 if not cache then
  cache={right=c:FindFirstChild('Right Shoulder',true) or c:FindFirstChild('RightShoulder',true),left=c:FindFirstChild('Left Shoulder',true) or c:FindFirstChild('LeftShoulder',true),lower={},active=false}
  for _,name in {'RightElbow','LeftElbow','RightWrist','LeftWrist'} do local motor=c:FindFirstChild(name,true);if motor then table.insert(cache.lower,motor) end end
  poseCache[c]=cache
 end
 if carrying then
  arm(cache.right,(root.CFrame.LookVector+root.CFrame.RightVector*-.12+Vector3.new(0,-.12,0)).Unit)
  arm(cache.left,(root.CFrame.LookVector+root.CFrame.RightVector*.12+Vector3.new(0,-.12,0)).Unit)
  -- Walk animations also bend the elbows; override the whole arm chain.
  for _,motor in cache.lower do motor.Transform=CFrame.identity end
  cache.active=true
 else
  if cache.active then
   for _,m in {cache.right,cache.left} do if m then m.Transform=CFrame.identity end end
   for _,motor in cache.lower do motor.Transform=CFrame.identity end
  end
  cache.active=false
 end
end
RunService.PreSimulation:Connect(function(dt)
 local time=clock()
 for model,r in sheep do
  if not model.Parent then continue end
  local state=model:GetAttribute('NetState') or 'Free'
  local t=time-(model:GetAttribute('NetStateSince') or time)
  -- НАШЕ: свободная овца живёт как на ферме — клип задаёт сервер (Clip/ClipSince)
  local pose
  if state=='Free' then
   local ok,p=pcall(SheepAnim.pose,model:GetAttribute('Clip') or 'Idle',time-(model:GetAttribute('ClipSince') or time))
   pose=ok and p or Poses.pose(state,t)
  else pose=Poses.pose(state,t) end
  for name,motor in r.motors do motor.Transform=motor.Transform:Lerp(pose[name] or CFrame.identity,1-math.exp(-17*dt)) end
 end
 for _,p in Players:GetPlayers() do posePlayer(p) end
end)
RunService.RenderStepped:Connect(function(dt)
 local time=clock();local held=tool();local carrying=player:GetAttribute('NetCarrying')
 -- НАШЕ: «+» только у геймпада (там цель — центр экрана); мышь и палец целятся сами
 cross.Visible=held~=nil and not carrying and UserInput:GetLastInputType()==Enum.UserInputType.Gamepad1
 cross.Position=UDim2.fromScale(.5,.5)
 for joint,original in aimGrips do
  if not joint.Parent or not joint.Part1 or not joint.Part1:IsDescendantOf(joint.Parent.Parent) then
   if joint.Parent then joint.C0=original end
   aimGrips[joint]=nil
  end
 end
 local phone=isPhone()
 if time<noticeUntil then label.Text=notice
 elseif carrying then label.Text=phone and 'Неси овцу на свободное место и нажми «Поставить овцу»' or 'Неси овцу в другое место  •  F / B — освободить'
 elseif capturedNear() then label.Text=phone and 'Тапни по овце в сети, чтобы поднять' or 'Овца в сети  •  E или клик по овце — поднять'
 elseif held then
  local remaining=Config.Cooldown-(time-lastFire)
  label.Text=remaining>0 and ('Перезарядка: %.1f'):format(remaining) or (phone and 'Тапни по овце — выстрелить сетью' or 'Наведи на овцу  •  ЛКМ / RT — выстрелить сетью')
 else label.Text='' end
 -- НАШЕ: подсказка с сеткомётом в руках, у пойманной овцы, при переноске и для уведомлений; иначе плашки нет (владелец)
 label.Visible=label.Text~=''
 carryGui.Enabled=carrying==true and UserInput.TouchEnabled   -- НАШЕ: кнопка только на сенсорных экранах
 for id,s in flying do
  local elapsed=math.max(0,time-s.time)
  if elapsed>Config.Range/Config.Speed+.8 then s.model:Destroy();flying[id]=nil
  else
   local scale=.22+.78*math.clamp(elapsed/.24,0,1)
   s.model:ScaleTo(scale)
   local p=s.origin+s.dir*Config.Speed*elapsed
   s.model:PivotTo(CFrame.lookAt(p,p+s.dir))
  end
 end
 for model,r in sheep do
  if not r.root.Parent then continue end
  local state=model:GetAttribute('NetState') or 'Free'
  local elapsed=time-(model:GetAttribute('NetStateSince') or time)
  if state=='Catching' or state=='Captured' or state=='Carried' then
   if not r.net then r.net=cloneNet('WrappedNet') end
   local scale=state=='Catching' and (1+.4*(1-math.clamp(elapsed/.65,0,1))) or 1
   r.net:ScaleTo(scale);r.net:PivotTo(r.root.CFrame)
  elseif r.net then fade(r.net,.45);r.net=nil end
 end
end)
print('NET_CAPTURE_CLIENT_READY')
-- Studio-only integration client: uses the same Tool.Activated and RemoteEvent path.
if Pack:GetAttribute('SelfTest') and RunService:IsStudio() then
 task.spawn(function()
  repeat task.wait(.1) until sheepFolder:GetAttribute('ReadyForClientShot')
  local model=sheepFolder:FindFirstChild('Sheep');local root=model and model:FindFirstChild('HumanoidRootPart')
  if not root then return end
  local camera=workspace.CurrentCamera
  camera.CameraType=Enum.CameraType.Scriptable
  camera.CFrame=CFrame.lookAt(root.Position+Vector3.new(0,4,15),root.Position+Vector3.new(5,1.6,0))
  local projected=camera:WorldToViewportPoint(root.Position+Vector3.new(0,1.6,0))
  testAimPoint=Vector2.new(projected.X,projected.Y)
  task.wait(.6)
  local t=tool();if t then t:Activate() end
  task.wait(1.5)
  local net=nil
  for _,v in fx:GetChildren() do if v.Name=='WrappedNet' then net=v end end
  print('NET_CLIENT_SHOT_CHECK',model:GetAttribute('NetState'),net~=nil)
  camera.CameraType=Enum.CameraType.Custom
  testAimPoint=nil
  repeat task.wait(.05) until sheepFolder:GetAttribute('ReadyForCarryWalk')
  local controls=require(player.PlayerScripts:WaitForChild('PlayerModule')):GetControls()
  controls:Disable()
  local char=player.Character;local hum=char:FindFirstChildOfClass('Humanoid');local hrp=char.HumanoidRootPart
  hum:MoveTo(hrp.Position+hrp.CFrame.LookVector*12)
  task.wait(2.5)
  local elbow=char:FindFirstChild('RightElbow',true)
  print('NET_CARRY_ELBOW_STRAIGHT',elbow==nil or elbow.Transform:FuzzyEq(CFrame.identity,.001))
  controls:Enable()
 end)
end
