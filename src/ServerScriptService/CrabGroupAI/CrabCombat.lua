-- Pure scheduling rules, shared by the server controller and offline tests.
local Combat = {}
function Combat.reserve(ledger, target, now, duration)
 if (ledger[target] or 0) > now then return false end
 ledger[target] = now + duration
 return true
end
function Combat.canHit(alive, targetAlive, distance, range, visible, facing)
 return alive and targetAlive and distance <= range and visible and facing >= 0.15
end
return Combat
