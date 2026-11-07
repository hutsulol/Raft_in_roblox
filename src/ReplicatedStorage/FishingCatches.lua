-- Shared timeline: server state and client presentation use the same markers.
local M={
 {name="Calm",clip="CatchCalm",bite=.35,fight=.72,launch=2.95,catch=3.9,finish=4.8,arc=1.35,sway=.28,flutter=.12},
 {name="Struggle",clip="CatchStruggle",bite=.12,fight=.64,launch=4.5,catch=5.6,finish=6.5,arc=1.9,sway=1.05,flutter=.32},
 {name="Surprise",clip="CatchSurprise",bite=.5,fight=1.12,launch=2.8,catch=4.15,finish=5.2,arc=2.3,sway=.6,flutter=.24},
}
-- Uniform among remaining variants, including the last entry (no reroll loop).
function M.choose(random,last)
 local n=random:NextInteger(1,last and #M-1 or #M)
 if last and n>=last then n=n+1 end
 return n,M[n]
end
function M.flightOffset(v,u,scale)
 local y=math.sin(u*math.pi)*v.arc*scale
 local x=0
 if v.name=="Surprise" then
  -- Fish slips past the first reach, then swings back into the second hand catch.
  x=math.sin(u*math.pi*2)*math.sin(u*math.pi)*.65*scale
  y=y+math.sin(u*math.pi)^2*math.sin(u*math.pi*3)*.25*scale
 end
 return x,y
end
return M
