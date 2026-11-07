local Pathfinding=game:GetService('PathfindingService')
local Nav={}
function Nav.direction(s,goal,now)
 local root=s.model.PrimaryPart
 if not s.pathBusy and now>=(s.nextPath or 0) and (not s.pathGoal or (goal-s.pathGoal).Magnitude>4 or not s.waypoints) then
  s.pathBusy=true;s.nextPath=now+1.25;s.pathGoal=goal
  task.spawn(function()
   local path=Pathfinding:CreatePath({AgentRadius=1.9,AgentHeight=3,AgentCanJump=false,WaypointSpacing=3})
   local ok=pcall(function()path:ComputeAsync(root.Position,goal)end)
   if s.model.Parent and ok and path.Status==Enum.PathStatus.Success then s.waypoints=path:GetWaypoints();s.waypoint=2 else s.waypoints=nil end
   s.pathBusy=false
  end)
 end
 local point=goal
 if s.waypoints then
  local w=s.waypoints[s.waypoint]
  if w and (Vector3.new(w.Position.X,root.Position.Y,w.Position.Z)-root.Position).Magnitude<1.5 then s.waypoint+=1;w=s.waypoints[s.waypoint] end
  if w then point=w.Position else s.waypoints=nil;s.nextPath=now+1 end
 end
 local delta=Vector3.new(point.X-root.Position.X,0,point.Z-root.Position.Z)
 return delta.Magnitude>.01 and delta.Unit or nil
end
return Nav
