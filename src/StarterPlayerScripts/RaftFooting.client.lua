-- Подписка на «плот тряхнуло»: держит персонажа на месте, когда сервер
-- перестраивает сборку плота. Вся логика в модуле RaftShake — здесь только
-- включение, чтобы у подписки был ровно один владелец.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RaftShake = require(ReplicatedStorage:WaitForChild("RaftShake"))

RaftShake.listen()

-- Наружу для скриптов, которые знают о перестройке РАНЬШЕ сервера: стройка зовёт
-- удержание в тот же кадр, что и отправку запроса, не дожидаясь ответа.
_G.KeepRaftFooting = RaftShake.hold
