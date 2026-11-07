local Content=game:GetService('ContentProvider')
local Audio={}
local atlas='rbxassetid://137806382070660'
local step='rbxassetid://173656827' -- Sand Footsteps - Fixed (Creator Store)
local land='rbxasset://sounds/action_jump_land.mp3'
-- Gains measured from the loudest 30 ms, then mixed: steps -9 dB, hurt/death +4 dB.
-- Trim silent lead-ins: notably 380 ms in the classic sword recording.
local sources={
 Sword={id='rbxassetid://12222216',start=.376,fallback='rbxasset://sounds/action_jump.mp3',fallbackStart=.076,fallbackVolume=1.654,volume=.208,speed=1.05,life=.18},
 Step={id=step,start=0,volume=.1766,speed=1.15,life=.16},
 Claw={id='rbxassetid://12222216',start=.376,fallback='rbxasset://sounds/action_jump.mp3',fallbackStart=.076,fallbackVolume=.66,volume=.0832,speed=1.3,life=.14},
 Hurt={id=atlas,start=1.261,fallback=land,fallbackStart=.038,fallbackVolume=2.178,volume=.441,speed=1.2,life=.19},
 Alert={id=atlas,start=2.0905,fallback=land,fallbackStart=.038,fallbackVolume=1.374,volume=.338,speed=1.6,life=.19},
 Death={id=land,start=.038,volume=2.178,speed=.85,life=.22},
 Shell={id=atlas,start=2.0905,fallback=land,fallbackStart=.038,fallbackVolume=1.374,volume=.338,speed=.9,life=.19},
}
local ready={};local banks=setmetatable({},{__mode='k'});local rng=Random.new()
local group=Instance.new('SoundGroup');group.Name='CrabCombatSFX';group.Volume=1;group.Parent=game.SoundService
local limiter=Instance.new('CompressorSoundEffect');limiter.Name='PackLimiter';limiter.Threshold=-15;limiter.Ratio=6;limiter.Attack=.005;limiter.Release=.08;limiter.GainMakeup=0;limiter.Parent=group
Audio.sources=sources
function Audio.preload()
 local used={}
 for _,d in sources do
  for _,id in {d.id,d.fallback} do
   if id and not used[id] then
    used[id]=true
    task.spawn(function()
     local s=Instance.new('Sound');s.SoundId=id;s.Volume=0;s.Parent=game.SoundService
     local status
     local ok=pcall(function()Content:PreloadAsync({s},function(_,result)status=result end)end)
     ready[id]=ok and status==Enum.AssetFetchStatus.Success
     print('CRAB_AUDIO_READY',id,ready[id],s.TimeLength);s:Destroy()
    end)
   end
  end
 end
end
function Audio.prepare(parent,names)
 if not parent then return end
 local bank=banks[parent]
 if not bank then bank={};banks[parent]=bank end
 local preload={}
 for _,name in names or {'Step','Claw','Hurt','Alert','Death','Shell'} do
  if bank[name] then continue end
  local d=sources[name];local entry={token=0};bank[name]=entry
  for _,variant in {'main','fallback'} do
   local id=variant=='main' and d.id or d.fallback
   if not id then continue end
   local s=Instance.new('Sound');s.Name='CrabFX_'..name..(variant=='fallback' and '_Fallback' or '')
   s.SoundId=id;s.SoundGroup=group;s.Volume=variant=='main' and d.volume or d.fallbackVolume
   s.RollOffMode=Enum.RollOffMode.InverseTapered;s.RollOffMinDistance=12;s.RollOffMaxDistance=60
   if name=='Step' then
    s.RollOffMinDistance=3;s.RollOffMaxDistance=18
    local eq=Instance.new('EqualizerSoundEffect');eq.LowGain=-12;eq.MidGain=-5;eq.HighGain=-4;eq.Parent=s
   end
   if name=='Claw' then
    local eq=Instance.new('EqualizerSoundEffect');eq.LowGain=-3;eq.MidGain=-5;eq.HighGain=-16;eq.Parent=s
   end
   s.Parent=parent;entry[variant]=s;table.insert(preload,s)
  end
 end
 if #preload>0 then task.spawn(function()pcall(function()Content:PreloadAsync(preload)end)end) end
 return bank
end
function Audio.play(parent,name,scale)
 if not parent or not parent:IsDescendantOf(workspace) then return end
 local camera=workspace.CurrentCamera
 if camera and (camera.CFrame.Position-parent.Position).Magnitude>60 then return end
 local d=sources[name];if not d then return end
 local bank=banks[parent] or Audio.prepare(parent,{name})
 if not bank[name] then Audio.prepare(parent,{name}) end
 local entry=bank[name]
 local primary=entry.main.IsLoaded
 local s=primary and entry.main or entry.fallback
 -- Never queue a late sound or truncate one before loading; use the ready fallback.
 if not s or not s.IsLoaded then return end
 entry.token+=1;local token=entry.token
 s:Stop();s.Volume=primary and d.volume or d.fallbackVolume
 s.PlaybackSpeed=d.speed*rng:NextNumber(.98,1.02)/math.clamp((scale or 1)^.12,.9,1.1)
 s.TimePosition=primary and d.start or d.fallbackStart
 s:Play()
 task.delay(d.life/s.PlaybackSpeed,function()if entry.token==token and s.Parent then s:Stop()end end)
 return s
end
return Audio
