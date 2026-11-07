-- Вставка в существующий клиентский скрипт окна торговца: выбор режима отображения.

local GiftCard = require(script.GiftCard)
local giftCard = GiftCard.new(offersContainer) -- Frame под шапкой «Предложения», где сейчас список строк

local function isGiftOnly(offers)
	return #offers == 1 and offers[1].isGift == true and (offers[1].price or 0) == 0
end

local function render(offers)
	if isGiftOnly(offers) then
		offersList.Visible = false        -- ваш ScrollingFrame со строками
		featuredCard.Visible = false      -- если есть «особое предложение»
		local offer = offers[1]
		giftCard:Set(offer, function()
			local ok = MerchantBuy:InvokeServer(offer.id)  -- сервер выдаёт подарок, проверяет «только 1 раз»
			if ok then
				giftCard:SetClaimed(true)
				-- дальше: индикатор подбора / попап «Новый персонаж», если подарок — персонаж
			end
		end)
		-- вкладки сайдбара: оставить одну активную «Подарок», остальные скрыть
		setTabs({ "Подарок" })
	else
		giftCard:Hide()
		offersList.Visible = true
		setTabs({ "Все", "Инструменты", "Ресурсы", "Редкое" })
		-- ...существующий рендер строк
	end
end
