local RunService=game:GetService('RunService')
local Debris=game:GetService('Debris')
local FX={}
local particles={}
local ticker
local random=Random.new()
local greens={Color3.fromRGB(111,157,35),Color3.fromRGB(145,185,49),Color3.fromRGB(81,130,28),Color3.fromRGB(174,199,67)}
local function carrier(parent,name,pos)
 local p=Instance.new('Part');p.Name=name;p.Size=Vector3.one*.03;p.Transparency=1
 p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.Position=pos;p.Parent=parent
 return p
end
local function update(dt)
 for p,s in pairs(particles) do
  s.age+=dt
  if not p.Parent or s.age>=s.life or (s.follow and not s.follow.Parent) then particles[p]=nil;p:Destroy()
  else
   local t=s.age/s.life
   if s.follow then
    p.CFrame=s.follow.CFrame*CFrame.new(s.offset)
    p.Size=s.base*(1+.055*math.sin(s.age*23+s.phase))
   elseif s.splat then
    p.CFrame=s.frame
    local spread=1+.9*math.min(t*4,1)
    p.Size=Vector3.new(s.base.X*spread,s.base.Y*spread,s.base.Z*(1-.65*t))
   else
    local pos=s.origin+s.velocity*s.age+Vector3.new(0,-s.gravity*s.age*s.age/2,0)
    local v=s.velocity-Vector3.yAxis*s.gravity*s.age
    p.CFrame=CFrame.lookAt(pos,pos+v)
    local shrink=1-.82*t*t
    p.Size=Vector3.new(s.base.X*shrink,s.base.Y*shrink,s.base.Z*shrink*(1+.7*(1-t)))
   end
   p.Transparency=s.alpha+(1-s.alpha)*math.clamp((t-.5)/.5,0,1)
  end
 end
 if not next(particles) and ticker then ticker:Disconnect();ticker=nil end
end
local function droplet(parent,pos,velocity,size,life,alpha,follow,offset)
 local p=carrier(parent,'GreenSalivaDrop',pos);p.Shape=Enum.PartType.Ball
 p.Material=Enum.Material.SmoothPlastic;p.Color=greens[random:NextInteger(1,#greens)];p.Reflectance=.06;p.Transparency=alpha
 local base=Vector3.new(size,size*.85,size*(follow and 1.7 or 1.1));p.Size=base
 particles[p]={origin=pos,velocity=velocity,base=base,life=life,age=0,alpha=alpha,gravity=18,follow=follow,offset=offset,phase=random:NextNumber(0,6)}
 if not ticker then ticker=RunService.RenderStepped:Connect(update) end
 return p
end
function FX.shot(parent,_template)
 local root=carrier(parent,'InfectedSpit',Vector3.zero)
 droplet(root,Vector3.zero,Vector3.zero,.62,4,.04,root,Vector3.zero)
 for i=1,3 do
  droplet(root,Vector3.zero,Vector3.zero,.20+i*.025,4,.08,root,Vector3.new(random:NextNumber(-.19,.19),random:NextNumber(-.13,.13),.15+i*.15))
 end
 Debris:AddItem(root,4);return root
end
function FX.burst(parent,pos,normal,count)
 normal=normal.Magnitude>.001 and normal.Unit or Vector3.yAxis
 local root=carrier(parent,'GreenSalivaSplash',pos)
 local axis=math.abs(normal.Y)<.9 and Vector3.yAxis or Vector3.xAxis
 local tangent=normal:Cross(axis).Unit;local bitangent=normal:Cross(tangent).Unit
 -- Individual drops fan across the hit plane, stretch, fall, shrink and fade.
 for i=1,count do
  local a=2*math.pi*i/count+random:NextNumber(-.16,.16)
  local v=(tangent*math.cos(a)+bitangent*math.sin(a))*random:NextNumber(3.3,7.3)+normal*random:NextNumber(1,3)
  droplet(root,pos+normal*.07,v,random:NextNumber(.10,.29),random:NextNumber(.32,.65),.08)
 end
 for i=1,5 do
  local offset=tangent*random:NextNumber(-.28,.28)+bitangent*random:NextNumber(-.28,.28)
  local p=droplet(root,pos+offset+normal*.05,Vector3.zero,random:NextNumber(.3,.55),.6,.16)
  local s=particles[p];s.splat=true;s.frame=CFrame.lookAt(pos+offset+normal*.05,pos+offset+normal);s.base=Vector3.new(s.base.X,s.base.Y,.035)
 end
 Debris:AddItem(root,.8);return root
end
function FX.impact(parent,pos,normal)return FX.burst(parent,pos,normal,22) end
function FX.charge(_parent,_pos)end
function FX.muzzle(parent,pos,direction)
 local root=carrier(parent,'GreenCoughSpray',pos)
 for _=1,7 do
  local v=direction*random:NextNumber(3,6)+Vector3.new(random:NextNumber(-1,1),random:NextNumber(-.2,1),random:NextNumber(-1,1))
  droplet(root,pos,v,random:NextNumber(.08,.18),.25,.12)
 end
 Debris:AddItem(root,.35);return root
end
function FX.bind(event,parent,template)
 local shots={}
 local connection=event.OnClientEvent:Connect(function(kind,id,pos,velocity,born)
  if kind=='Shot' then
   if shots[id] then shots[id].part:Destroy() end
   local p=FX.shot(parent,template);p.CFrame=CFrame.lookAt(pos,pos+velocity)
   shots[id]={part=p,pos=pos,velocity=velocity,born=born,drip=0};FX.muzzle(parent,pos,velocity.Unit)
  elseif kind=='Impact' or kind=='Remove' then
   local s=shots[id];if s then s.part:Destroy();shots[id]=nil end
   if kind=='Impact' then FX.impact(parent,pos,velocity) end
  end
 end)
 local motion=RunService.RenderStepped:Connect(function(dt)
  local now=workspace:GetServerTimeNow()
  for id,s in pairs(shots) do
   if now-s.born>4 or not s.part.Parent then s.part:Destroy();shots[id]=nil
   else
    local pos=s.pos+s.velocity*math.max(0,now-s.born);s.part.CFrame=CFrame.lookAt(pos,pos+s.velocity)
    s.drip+=dt
    if s.drip>=.045 then
     s.drip%=.045
     droplet(parent,pos,s.velocity*.12+Vector3.new(random:NextNumber(-.25,.25),-.3,0),.19,.28,.12)
    end
   end
  end
 end)
 return function()
  connection:Disconnect();motion:Disconnect()
  for _,s in pairs(shots) do s.part:Destroy() end
  for p in pairs(particles) do if p:IsDescendantOf(parent) then particles[p]=nil;p:Destroy() end end
 end
end
return FX
