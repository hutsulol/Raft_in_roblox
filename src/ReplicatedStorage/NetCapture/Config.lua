--[[ ⚠️ СЕТКОМЁТ (пакет test/NetCapture_Import): авторский модуль, перенесён в
     Rojo как есть. Модели (Assets: Sheep, FlightNet, WrappedNet и Tool
     Pirate_Net_Launcher) живут в Studio внутри ReplicatedStorage/NetCapture —
     Rojo их не трогает (init.meta.json). Наши правки помечены «-- НАШЕ:». ]]
return {
 ToolName='Pirate_Net_Launcher', Speed=46, Range=70, Radius=.7,
 Cooldown=1.45, CatchDuration=.65, ReleaseDuration=1.15,
 PickupRange=8, CarrySpeed=11, ThrowOriginLimit=8,
 CarryOffset=CFrame.new(0,-.9,-2.65)*CFrame.Angles(0,math.pi/2,0),
 -- НАШЕ: автоспавна нет — в океане нет фиксированной земли. Овцу для сети
 -- ставит админ-кнопка (SettingsMenu → _G.NetCaptureSpawn) или свой сценарий.
 SpawnPosition=nil,
}
