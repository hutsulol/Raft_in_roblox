local Content=game:GetService('ContentProvider')
local Debris=game:GetService('Debris')
local Audio={};local ready={};local rng=Random.new();local voices=setmetatable({},{__mode='k'})
local sources={
 Swipe={id='rbxassetid://9126284289',fallback='rbxasset://sounds/action_jump.mp3',volume=.70,speed=1.65,life=.25},
 Splash={id='rbxassetid://9120591135',fallback='rbxasset://sounds/impact_water.mp3',volume=.62,speed=.87,life=.7},
 Spit={id='rbxassetid://9120591135',fallback='rbxasset://sounds/impact_water.mp3',volume=.38,speed=1.55,life=.3},
 Land={id='rbxasset://sounds/action_jump_land.mp3',volume=.42,speed=.82,life=.4},
 Step={id='rbxasset://sounds/action_footsteps_plastic.mp3',volume=.14,speed=.76,life=.12},
}
Audio.sources=sources
-- Original synthesized voice atlas, with independent segments (no borrowed vocal clips).
local voiceAsset=script:GetAttribute('VoiceAssetId') or 'rbxassetid://75803387404969'
local original={Breath={0,2.05,.22},Cough={2.37,.88,.55},CoughAlt={3.57,1.02,.55},Groan={4.91,1.1,.40},Strain={6.33,.42,.43},Pain={7.07,.67,.50},Death={8.06,1.8,.40}}
for name,v in pairs(original) do
 sources[name]={id=voiceAsset,start=v[1],life=v[2],volume=v[3],speed=1,voice=true,original=true}
end
sources.StrikeBreath=table.clone(sources.Strain)
sources.StrikeBreath.life=.19
sources.StrikeBreath.volume=.55
-- Combat recordings synthesized for this character.
sources.Whoosh1={id='rbxassetid://137806382070660',start=0.0,life=0.23,volume=0.7,speed=1,voice=false,original=true}
sources.Flesh1={id='rbxassetid://137806382070660',start=0.43,life=0.2,volume=0.58,speed=1,voice=false,original=true}
sources.Whoosh2={id='rbxassetid://137806382070660',start=0.83,life=0.23,volume=0.7,speed=1,voice=false,original=true}
sources.Flesh2={id='rbxassetid://137806382070660',start=1.26,life=0.2,volume=0.58,speed=1,voice=false,original=true}
sources.Whoosh3={id='rbxassetid://137806382070660',start=1.66,life=0.23,volume=0.7,speed=1,voice=false,original=true}
sources.Flesh3={id='rbxassetid://137806382070660',start=2.09,life=0.2,volume=0.58,speed=1,voice=false,original=true}
sources.Pain1={id='rbxassetid://137806382070660',start=2.49,life=0.5,volume=0.58,speed=1,voice=true,original=true}
sources.Pain2={id='rbxassetid://137806382070660',start=3.19,life=0.5,volume=0.58,speed=1,voice=true,original=true}
sources.Pain3={id='rbxassetid://137806382070660',start=3.89,life=0.5,volume=0.58,speed=1,voice=true,original=true}
sources.Fear1={id='rbxassetid://137806382070660',start=4.59,life=0.66,volume=0.58,speed=1,voice=true,original=true}
sources.Fear2={id='rbxassetid://137806382070660',start=5.45,life=0.66,volume=0.58,speed=1,voice=true,original=true}
sources.Fear3={id='rbxassetid://137806382070660',start=6.31,life=0.66,volume=0.58,speed=1,voice=true,original=true}
sources.Anger1={id='rbxassetid://137806382070660',start=7.17,life=0.54,volume=0.58,speed=1,voice=true,original=true}
sources.Anger2={id='rbxassetid://137806382070660',start=7.91,life=0.54,volume=0.58,speed=1,voice=true,original=true}
sources.Anger3={id='rbxassetid://137806382070660',start=8.65,life=0.54,volume=0.58,speed=1,voice=true,original=true}
sources.Effort1={id='rbxassetid://137806382070660',start=9.39,life=0.19,volume=0.58,speed=1,voice=true,original=true}
sources.Effort2={id='rbxassetid://137806382070660',start=9.78,life=0.19,volume=0.58,speed=1,voice=true,original=true}
sources.Effort3={id='rbxassetid://137806382070660',start=10.17,life=0.19,volume=0.58,speed=1,voice=true,original=true}
function Audio.preload()
 task.spawn(function()
  local used={}
  for _,d in pairs(sources) do
   if d.id~='' and not used[d.id] then
    used[d.id]=true
    local s=Instance.new('Sound');s.SoundId=d.id;s.Volume=0;s.Parent=game:GetService('SoundService')
    local status
    local ok=pcall(function()Content:PreloadAsync({s},function(_,result)status=result end)end)
    ready[d.id]=ok and status==Enum.AssetFetchStatus.Success
    print('CRAWLER_AUDIO_LOAD',d.id,ready[d.id],s.TimeLength);s:Destroy()
   end
  end
 end)
end
function Audio.play(parent,name,mult)
 local group=({Swipe='Whoosh',StrikeBreath='Effort',Pain='Pain',Fear='Fear',Anger='Anger',Flesh='Flesh'})[name]
 if group then
  local last=parent and parent:GetAttribute('LastAudio'..group) or 0
  local index=rng:NextInteger(1,2);if index>=last then index+=1 end
  if parent then parent:SetAttribute('LastAudio'..group,index) end
  name=group..index
 end
 local d=sources[name];if not d or not parent or not parent.Parent then return end
 if d.id=='' or (d.original and ready[d.id]==false) then return end
 if d.voice and voices[parent] then voices[parent]:Destroy() end
 local s=Instance.new('Sound');s.Name='Crawler_'..name
 s.SoundId=(ready[d.id]==false and d.fallback) or d.id
 s.Volume=d.volume*(mult or 1);s.PlaybackSpeed=d.speed*rng:NextNumber(.94,1.06)
 s.RollOffMode=Enum.RollOffMode.InverseTapered;s.RollOffMinDistance=5;s.RollOffMaxDistance=65
 s.Parent=parent
 if d.voice then
  voices[parent]=s
 end
 s:Play();if d.start then s.TimePosition=d.start end
 Debris:AddItem(s,d.life/s.PlaybackSpeed)
end
local schedules={
 Spit={{.16,'Cough'},{.65,'Spit'}},Attack={{.16,'Cough'},{.65,'Spit'}},
 SpitAlt={{.04,'CoughAlt'},{.82,'Spit'}},
 ScratchPounce={{.02,'Groan'},{.16,'Swipe'},{.65,'Land'}},
 Scratch={},
 LatchFall={{.43,'Land'}},
 Surprise={{.05,'Groan'}},Hurt={},Death={{.03,'Death'},{.72,'Land'}},
 Jump={{.26,'Swipe'},{.94,'Land'}},Lunge={{.02,'Groan'},{.22,'Swipe'},{.88,'Land'}},
}
-- Same contact times as the server damage; breath and whoosh lead each strike.
for lap=0,2 do
 for _,hit in ipairs({.22,.48,.74}) do
  local at=lap+hit/1.1
  table.insert(schedules.Scratch,{at-.07,'StrikeBreath'})
  table.insert(schedules.Scratch,{at-.05,'Swipe'})
 end
end
function Audio.step(m,s,name,t,key,events)
 local head=m:FindFirstChild('Head');if not head then return end
 if s.audioKey~=key then
  s.audioKey=key;s.audioPrevious=t<.2 and -.001 or t;s.nextBreath=t+1.2
  if voices[head] and name~='Hurt' and name~='LatchFall' then voices[head]:Destroy();voices[head]=nil end
 end
 local previous=s.audioPrevious or t
 for _,cue in ipairs(schedules[name] or {}) do
  if cue[1]>previous and cue[1]<=t and t-cue[1]<.18 then Audio.play(cue[2]=='Swipe' and m:FindFirstChild('RightHand') or head,cue[2]) end
 end
 s.audioPrevious=t
 for _,event in ipairs(events or {}) do
  if event=='LeftPlant' or event=='RightPlant' then Audio.play(m:FindFirstChild(event=='LeftPlant' and 'LeftHand' or 'RightHand'),'Step') end
 end
 if (name=='Idle' or name=='Run' or name=='Crawl' or name=='FrenzyRun') and t>=(s.nextBreath or 0) then
  Audio.play(head,'Breath');s.nextBreath=t+(name=='Idle' and rng:NextNumber(3,4.5) or 1.8)
 end
end
function Audio.bind(event,parent)
 return event.OnClientEvent:Connect(function(kind,model,pos,mood)
  if kind=='Wound' and model then
   Audio.play(model:FindFirstChild('Head'),mood);Audio.play(model:FindFirstChild('UpperTorso'),'Flesh');return
  end
  if kind~='Impact' and kind~='Flesh' then return end
  local p=Instance.new('Part');p.Name='SalivaImpactAudio';p.Size=Vector3.one*.02;p.Transparency=1
  p.Anchored=true;p.CanCollide=false;p.CanQuery=false;p.CanTouch=false;p.Position=pos;p.Parent=parent
  Audio.play(p,kind=='Flesh' and 'Flesh' or 'Splash');Debris:AddItem(p,1)
 end)
end
return Audio

