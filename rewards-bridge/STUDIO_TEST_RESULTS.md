# Проверка приёма кодов в Roblox Studio — 2 ноября 2026

Среда: Roblox Studio 0.745.0.7451137, локальный Play Test отдельного
`data/RewardCodesStudio.rbxl`; Node API `http://127.0.0.1:8787`; SQLite `data/demo/rewards.sqlite`.
Telegram не использовался. HTTP-запросы выполнял серверный Luau-скрипт внутри Studio.

| Проверка | Наблюдаемый результат |
|---|---|
| Нажать «Открыть тестовый пак» в Roblox | Получен созданный backend-код с amount=1000, отображён в игровом UI |
| Повтор POST issue с тем же dropId | Вернулся тот же код и сумма, дополнительной карточки нет |
| Неверный X-API-Key | HTTP 401 |
| Другой rewardId при том же dropId | HTTP 409 |
| Активировать код, полученный в Roblox | Тестовый баланс вырос с 1000 до 2000 |
| Сразу повторить активацию | alreadyRedeemed=true, баланс остался 2000 |
| Выключить Node API, запросить новую карточку | Roblox сообщил об ожидании и повторял доставку |
| Включить API, не нажимая выдачу повторно | Ожидающая карточка автоматически доставлена; новое выпадение не создавалось |
| Полностью закрыть тестовый плейс и снова открыть/запустить Play | «Восстановить карточку» вернуло тот же ранее полученный код из API |

Маркерные строки реального Studio Output (секреты и полные коды не логируются):

```text
[CodeLab] CARD_RECEIVED amount=1000 drop=studio-pack-e0d9c911-ed8c-437e-be6e-2d4e622ff4f4
[CodeLab] HTTP_CHECKS_PASS 3/3
[CodeLab] REDEEM_AND_RETRY_PASS balance=2000
[RewardCodes] delivery pending: network_or_secret_error
[CodeLab] CARD_RECEIVED amount=1000 drop=studio-pack-b0e41ee2-c0fd-45d8-a01c-08d3b6982b36
[CodeLab] HTTP_CHECKS_PASS 3/3
[CodeLab] HISTORY_RESTORED
```

Дополнительно: 9 серверных автотестов, мобильный браузерный тест,
luaparse для четырёх Lua-файлов и сборка отдельного тестового плейса Rojo.

## Что эта проверка не покрывает

- Публичный HTTPS endpoint, Creator Hub Secret и опубликованный Roblox-сервер.
- Персистентную очередь Roblox DataStore при аварии игрового сервера: в неопубликованном
  стенде очередь находится в памяти, хотя API-карточки/баланс сохраняются в SQLite.
- Подключение к конкретному production-паку, его оплате/расходу и шансам выпадения.

Готов production-адаптер `roblox/RewardCodes.lua`; тестовый CodeLab в основную игру
не встроен. Требования другой команде — `BACKEND_CONTRACT.md`.
