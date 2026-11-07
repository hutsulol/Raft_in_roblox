--[[ ⚠️ СЕТКОМЁТ (пакет test/NetCapture_Import): авторский модуль, перенесён в
     Rojo как есть. Модели (Assets: Sheep, FlightNet, WrappedNet и Tool
     Pirate_Net_Launcher) живут в Studio внутри ReplicatedStorage/NetCapture —
     Rojo их не трогает (init.meta.json). Наши правки помечены «-- НАШЕ:». ]]
local C={Order={'Sheep_Idle','Sheep_Walk','Sheep_Look','Sheep_Bleat','Sheep_Graze','Sheep_Eat','Sheep_Drink','Sheep_LieDown','Sheep_Rest','Sheep_StandUp','Sheep_PetReaction','Sheep_ShearIdle','Sheep_Startled','Sheep_TurnLeft','Sheep_TurnRight','Sheep_Trot'}}
local durations={4,1,2,1.3,4,2.5,2.5,1.4,5,1.4,2.5,3.5,.8,1.2,1.2,.7}
local loops={true,true,false,false,true,true,true,false,true,false,false,true,false,false,false,true}
for i,name in C.Order do C[name]={AnimationId='',Duration=durations[i],Looped=loops[i],Priority=(name=='Sheep_Walk' or name=='Sheep_Trot') and 'Movement' or 'Action',FadeTime=.25} end
C.Sheep_Idle.Priority='Idle'
C.Sheep_Bleat.Markers={{Time=.32,Name='Bleat',Value=''}}
C.Sheep_Walk.ReferenceSpeed=4;C.Sheep_Trot.ReferenceSpeed=7
C.Sheep_Graze.FadeTime=1.3
return C
