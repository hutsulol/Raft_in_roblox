local Choice={}
function Choice.pick(state,config,roll)
 if config.TestScratchAlways then return 'FrenzyRun' end
 roll=roll or math.random
 if not state.frenzyUsed and roll()<config.FrenzyChance then
  state.frenzyUsed=true
  return 'FrenzyRun'
 end
 return roll()<config.AltSpitChance and 'SpitAlt' or 'Spit'
end
return Choice
