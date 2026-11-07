-- Island-relative habitat sampling; no Terrain edits or permanent world props.
local Life={}
local habitats=setmetatable({},{__mode='k'})
local rng=Random.new()
local function flat(v)return Vector3.new(v.X,0,v.Z)end
--[[ НАШЕ: СРЕДА — ОСТРОВ ЭТОГО КРАБА И НАСТОЯЩАЯ ВОДА ИГРЫ.
     В тестовом плейсе остров искался как workspace.Crab_Rock_Island, а вода —
     как workspace.TestOcean. У нас островов может быть несколько, они встают
     куда угодно (PivotTo), а уровень воды публикует InfiniteOcean в атрибут
     workspace.WaterY. Остров краба — ObjectValue CrabIsland (ставит
     CrabIsland.server). Кэш на экземпляр острова; сдвинули остров — пересчёт. ]]
function Life.habitat(model)
 local link=model:FindFirstChild('CrabIsland') or model:FindFirstChild('Island')
 local island=link and link.Value or workspace:FindFirstChild('Crab_Rock_Island')
 if not island then return end
 local pivot=island:GetPivot().Position
 local cached=habitats[island]
 if cached and (cached.pivot-pivot).Magnitude<1 then return cached end
 -- остров крабов — Crab_Island_Ground, песчаная отмель — Sand_Main
 local ground=island:FindFirstChild('Crab_Island_Ground',true) or island:FindFirstChild('Sand_Main',true)
 if not ground then return end
 local waterY=workspace:GetAttribute('WaterY')
 local h={ground=ground,dry={},wet={},rests={},water=type(waterY)=='number' and waterY or nil,pivot=pivot}
 local ray=RaycastParams.new();ray.FilterType=Enum.RaycastFilterType.Include;ray.FilterDescendantsInstances={ground}
 h.ray=ray;h.top=ground.Position.Y+ground.Size.Magnitude+10
 function h.floor(pos)
  return workspace:Raycast(Vector3.new(pos.X,h.top,pos.Z),Vector3.new(0,-ground.Size.Magnitude*2-40,0),ray)
 end
 local extent=ground.Size.Magnitude/2
 local pending={}
 for x=-extent,extent,5 do for z=-extent,extent,5 do
  local pos=ground.CFrame:PointToWorldSpace(Vector3.new(x,0,z))
  local hit=h.floor(pos)
  if hit and hit.Normal.Y>.8 and (not h.water or hit.Position.Y>h.water+.2) then
   table.insert(h.dry,hit.Position)
  elseif h.water then table.insert(pending,Vector3.new(pos.X,h.water,pos.Z)) end
 end end
 -- Only shallow water within eight studs of a surveyed beach is navigable.
 for _,pos in pending do
  local closest=math.huge
  for _,dry in h.dry do
   if dry.Y<h.water+2.5 then closest=math.min(closest,flat(pos-dry).Magnitude) end
  end
  if closest<=8 then table.insert(h.wet,pos) end
 end
 for _,v in island:GetDescendants() do
  if v:IsA('BasePart') and (v.Name:find('Resource_Stone') or v.Name:match('^Stone_')) then
   for _,dry in h.dry do
    local d=flat(dry-v.Position).Magnitude
    if d>v.Size.Magnitude*.3+3 and d<v.Size.Magnitude*.3+9 then table.insert(h.rests,dry) end
   end
  end
 end
 habitats[island]=h
 print(('[Крабы] среда острова %s: суша %d, вода %d, отдых %d (вода Y=%s)'):format(
  island.Name,#h.dry,#h.wet,#h.rests,tostring(h.water)))
 return h
end
function Life.surface(a,pos)
 local h=a.habitat;if not h then return end
 local hit=h.floor(pos)
 if hit and hit.Normal.Y>.65 and (not h.water or hit.Position.Y>h.water+.2) then
  return hit.Position.Y+1.45*a.scale,false
 end
 if h.water then
  for _,wet in h.wet do
   if flat(pos-wet).Magnitude<3.7 then return h.water+.35*a.scale,true end
  end
 end
end
function Life.cancel(a)
 a.activity=nil;a.path=nil;a.moveGoal=nil;a.token+=1
 a.model:SetAttribute('CrabActivity',nil)
end
function Life.update(a,now,dt,actors,move,animate,state)
 local h=a.habitat
 if not h then animate(a,'Idle');state(a,'Idle');return end
 local job=a.activity
 if not job then
  local kind=({'Wander','Forage','Rest','Swim'})[(a.lifeIndex or a.id)%4+1]
  a.lifeIndex=(a.lifeIndex or a.id)+1
  local pool=kind=='Swim' and h.wet or kind=='Rest' and h.rests or h.dry
  if #pool==0 then kind='Wander';pool=h.dry end
  local candidates={}
  for _,pos in pool do
   local distance=flat(pos-a.root.Position).Magnitude
   if distance>5 and distance<42 and flat(pos-a.home).Magnitude<55 then
    local free=true
    for _,b in actors do
     if b~=a and not b.dead then
      local other=b.activity and b.activity.goal or b.root.Position
      if flat(other-pos).Magnitude<3.2*(a.scale+b.scale) then free=false;break end
     end
    end
    if free then table.insert(candidates,pos) end
   end
  end
  if #candidates==0 then animate(a,'Idle');state(a,'Rest');a.activity={kind='Rest',goal=a.root.Position,untilTime=now+3,deadline=now+4};return end
  job={kind=kind,goal=candidates[rng:NextInteger(1,#candidates)],deadline=now+22,lastPos=a.root.Position,progress=now}
  a.activity=job;a.path=nil;a.token+=1;a.model:SetAttribute('CrabActivity',kind)
 end
 if now>job.deadline then Life.cancel(a);return end
 if job.untilTime then
  state(a,job.kind);animate(a,job.kind=='Forage' and 'Forage' or job.kind=='Swim' and 'Swim' or 'Rest')
  if now>=job.untilTime then Life.cancel(a) end
  return
 end
 state(a,job.kind=='Swim' and 'GoToWater' or 'Explore')
 if move(a,job.goal,now,dt) then job.untilTime=now+rng:NextNumber(3,7);job.deadline=job.untilTime+1 end
 if flat(a.root.Position-job.lastPos).Magnitude>1 then job.progress=now;job.lastPos=a.root.Position end
 if now-job.progress>3 then Life.cancel(a) end
end
return Life
