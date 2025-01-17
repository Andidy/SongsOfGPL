local tabb = require "engine.table"
local ui = require "engine.ui"
local uit = require "game.ui-utils"

local pv = require "game.raws.values.political"

local RANKS = require "game.raws.ranks.character_ranks"

local tb = {}

local alerts_amount = 0

function tb.rect()
	return ui.rect(0, 0, uit.BASE_HEIGHT * 30 + alerts_amount * uit.BASE_HEIGHT * 2, uit.BASE_HEIGHT * 2)
end

---@return boolean
function tb.mask(gam)
	local tr = tb.rect()
	local character = WORLD.player_character
	if character and character.province and character.province.realm then
		return not ui.trigger(tr)
	else
		return true
	end
end


---@class TreasuryDisplayEffect
---@field reason EconomicReason
---@field amount number
---@field timer number

---@type TreasuryDisplayEffect[]
CURRENT_EFFECTS = {}
MAX_TREASURY_TIMER = 4.0
MIN_DELAY = 0.3


function HANDLE_EFFECTS()
	local counter = 0
	while WORLD.treasury_effects:length() > 0 do
		local temp = WORLD.treasury_effects:dequeue()
		---@type TreasuryDisplayEffect
		local new_effect = {
			reason = temp.reason,
			amount = temp.amount,
			timer = MAX_TREASURY_TIMER + counter * MIN_DELAY
		} 
		table.insert(CURRENT_EFFECTS, new_effect)
		WORLD.old_treasury_effects:enqueue(temp)
		while WORLD.old_treasury_effects:length() > OPTIONS['treasury_ledger'] do
			WORLD.old_treasury_effects:dequeue()
		end
		counter = counter + 1
	end
end

function DRAW_EFFECTS(parent_rect)
	local new_rect = parent_rect:copy()
	for _, effect in pairs(CURRENT_EFFECTS) do
		if (effect.timer < MAX_TREASURY_TIMER) then
			local r, g, b, a = love.graphics.getColor()
			if effect.amount > 0 then
				love.graphics.setColor(1, 1, 0, (effect.timer) / MAX_TREASURY_TIMER)
			else 
				love.graphics.setColor(1, 0, 0, (effect.timer) / MAX_TREASURY_TIMER)
			end

			new_rect.x = parent_rect.x
			new_rect.y = parent_rect.y + 2 * uit.BASE_HEIGHT * (1 + 4 * (MAX_TREASURY_TIMER - effect.timer) / MAX_TREASURY_TIMER)
			ui.right_text(uit.to_fixed_point2(effect.amount) .. MONEY_SYMBOL, new_rect)

			new_rect.x = parent_rect.x - parent_rect.width
			ui.left_text(effect.reason, new_rect)
			love.graphics.setColor(r, g, b, a)
		end
	end
end

---@param dt number
function tb.update(dt)
	EFFECTS_TO_REMOVE = {}
	for _, effect in pairs(CURRENT_EFFECTS) do
		effect.timer = effect.timer - dt
		if effect.timer < 0 then
			table.insert(EFFECTS_TO_REMOVE, _)
		end
	end

	for _, key in pairs(EFFECTS_TO_REMOVE) do
		table.remove(CURRENT_EFFECTS, key)
	end
end

---Draws the bar at the top of the screen (if a player realm has been selected...)
---@param gam table
function tb.draw(gam)
	local character = WORLD.player_character
	if character and character.province and character.province.realm then
		local tr = tb.rect()
		ui.panel(tr)

		if ui.trigger(tr) then
			gam.click_callback = function() return end
		end

		-- portrait
		local portrait_rect = tr:subrect(0, 0, uit.BASE_HEIGHT * 2, uit.BASE_HEIGHT * 2, "left", 'up'):shrink(5)
		if ui.invisible_button(portrait_rect) then
			gam.selected.character = WORLD.player_character
			gam.inspector = "character"
		end
		require "game.scenes.game.widgets.portrait"(portrait_rect, WORLD.player_character)
		ui.tooltip("Click the portrait to open character screen", portrait_rect)
		

		--- current character
		local layout = ui.layout_builder()
			:position(uit.BASE_HEIGHT * 2, uit.BASE_HEIGHT)
			:horizontal()
			:build()

		local name_rect = layout:next(7 * uit.BASE_HEIGHT, uit.BASE_HEIGHT)
		if uit.text_button(WORLD.player_character.name, name_rect) then
			gam.selected.character = WORLD.player_character
			gam.inspector = "character"
		end

		local rect = layout:next(uit.BASE_HEIGHT * 5, uit.BASE_HEIGHT)
		if uit.text_button("", rect) then
			gam.inspector = "treasury-ledger"
			(require "game.scenes.game.inspector-treasury-ledger").current_tab = 'Character'
		end
		
		uit.money_entry_icon(
			character.savings,
			rect,
			"My personal savings")
		layout:next(7 * uit.BASE_HEIGHT, uit.BASE_HEIGHT)

		uit.data_entry_icon(
			'duality-mask.png',
			uit.to_fixed_point2(pv.popularity(character, character.province.realm)),
			layout:next(uit.BASE_HEIGHT * 3, uit.BASE_HEIGHT),
			"My popularity")


		-- COA + name
		local layout = ui.layout_builder()
			:position(uit.BASE_HEIGHT * 2, 0)
			:horizontal()
			:build()

		require "game.scenes.game.widgets.realm-name"(
			gam, 
			character.province.realm, 
			uit.BASE_HEIGHT, 
			layout:next(
				uit.BASE_HEIGHT * 7, 
				uit.BASE_HEIGHT
			)
		)

		-- Treasury
		local trt = layout:next(uit.BASE_HEIGHT * 5, uit.BASE_HEIGHT)

		if uit.text_button("", trt) then
			gam.inspector = "treasury-ledger"
			(require "game.scenes.game.inspector-treasury-ledger").current_tab = 'Treasury'
		end

		uit.money_entry_icon(
			character.province.realm.budget.treasury,
			trt,
			"Realm treasury")

		HANDLE_EFFECTS()
		DRAW_EFFECTS(trt)

		-- Food
		local amount = character.province.realm.resources['food'] or 0
		uit.data_entry_icon(
			'noodles.png',
			uit.to_fixed_point2(amount),
			layout:next(uit.BASE_HEIGHT * 4, uit.BASE_HEIGHT),
			"Food")

		-- Technology
		local amount = character.province.realm:get_education_efficiency()
		local tr = layout:next(uit.BASE_HEIGHT * 3, uit.BASE_HEIGHT)
		local trs = "Current ability to research new technologies. When it's under 100%, technologies will be slowly forgotten, when above 100% they will be researched. Controlled largely through treasury spending on research and education but in most states the bulk of the contribution will come from POPs in the realm instead."
		uit.generic_number_field('erlenmeyer.png', amount, tr, trs, uit.NUMBER_MODE.PERCENTAGE, uit.NAME_MODE.ICON)

		-- Happiness
		local amount = character.province.realm:get_average_mood()
		local tr = layout:next(uit.BASE_HEIGHT * 3, uit.BASE_HEIGHT)
		local trs = "Average mood (happiness) of population in our realm. Happy pops contribute more voluntarily to our treasury, whereas unhappy ones contribute less."
		uit.data_entry_icon('duality-mask.png', uit.to_fixed_point2(amount), tr, trs)

		-- POP
		local amount = character.province.realm:get_total_population()
		local tr = layout:next(uit.BASE_HEIGHT * 3, uit.BASE_HEIGHT)
		local trs = "Current population of our realm."
		uit.data_entry_icon('minions.png', tostring(math.floor(amount)), tr, trs)

		-- Army size
		local amount = character.province.realm:get_realm_military()
		local target = character.province.realm:get_realm_military_target() + character.province.realm:get_realm_active_army_size()
		local tr = layout:next(uit.BASE_HEIGHT * 3, uit.BASE_HEIGHT)
		local trs = "Size of our realms armies."
		uit.data_entry_icon('barbute.png', tostring(math.floor(amount)) .. ' / ' .. tostring(math.floor(target)), tr, trs)
	

		-- ALERTS
		---@class Alert
		---@field icon string
		---@field tooltip string

		---@type Alert[]
		local alerts = {}

		if character.province:get_unemployment() > 5 then
			table.insert(alerts, {
				['icon'] = 'miner.png',
				['tooltip'] = "Unemployment is high. Consider construction of new buildings or investment into local economy.",
			})
		end

		if character.province.mood < 1 then
			table.insert(alerts, {
				['icon'] = 'despair.png',
				['tooltip'] = "Our people are unhappy. Gift money to your population or raid other realms.",
			})
		end

		if character.rank == RANKS.CHIEF then
			if character.province:get_infrastructure_efficiency() < 0.9 then
				table.insert(alerts, {
					['icon'] = 'horizon-road.png',
					['tooltip'] = "Infrastructure efficiency is low. It might be a temporary effect or a sign of a low infrastructure budget.",
				})
			end

			if character.realm:get_education_efficiency() < 0.9 then
				table.insert(alerts, {
					['icon'] = 'erlenmeyer.png',
					['tooltip'] = "Education efficiency is low. It might be a temporary effect or a sign of a low education budget.",
				})
			end
		end

		for _, alert in ipairs(alerts) do
			local rect = layout:next(uit.BASE_HEIGHT * 2, uit.BASE_HEIGHT * 2)

			local alert_rect = rect:copy():shrink(5)
			local old_style = ui.style.panel_outline
			ui.style.panel_outline = { ['r'] = 1, ['g'] = 0, ['b'] = 0, ['a'] = 1 }
			ui.panel(alert_rect, uit.BASE_HEIGHT)
			ui.style.panel_outline = old_style
			love.graphics.setColor(0.8, 0, 0, 1)
			alert_rect:shrink(4)
			ui.image(ASSETS.icons[alert.icon], alert_rect)
			love.graphics.setColor(1, 1, 1, 1)
			ui.tooltip(alert.tooltip, rect)
		end

		alerts_amount = #alerts
	end
end

return tb
