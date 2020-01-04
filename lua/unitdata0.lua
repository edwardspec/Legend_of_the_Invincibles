--! #textdomain "wesnoth-loti"
--
-- Functions that manipulate unit inventories and advancements.
-- Note: parameter "unit" can accept both WML table and unit ID (string).
--

local helper = wesnoth.require "lua/helper.lua"

-- Helper function.
-- Analyze "unit" parameter, which can be WML table or unit ID.
-- Returns WML table.
local function normalize_unit_param(unit)
	if type(unit) == 'table' then
		-- WML table.
		return unit
	end

	-- Unit ID
	return wesnoth.get_unit(unit).__cfg
end

-- Helper function.
-- Construct iterator around some modifications of the unit.
-- Parameters:
-- tag - name of WML tag inside [modifications], e.g. "object" or "advancement".
-- filter (optional) - function that:
-- 1) receives one result (e.g. [object] WML table) as parameter,
-- 2) returns the value that should be returned by iterator, or false if this result must be skipped.
-- (if filter isn't specified, then all values are returned "as is", and nothing gets skipped)
-- Sample usage: for _, advancement in wml_modification_iterator(unit, "advancement")
local function wml_modification_iterator(unit, tag, filter)
	unit = normalize_unit_param(unit)

	local modifications = helper.get_child(unit, "modifications")
	local elements = helper.child_array(modifications, tag)

	local idx = 0
	return function()
		idx = idx + 1
		while elements[idx] do
			local result = elements[idx]
			if filter then
				-- Allow callback to modify the result
				-- (or return false, which would mean "skip this result")
				result = filter(result)
			end

			if result then
				return idx, result
			end

			-- Element didn't pass a filter function,
			-- e.g. [object] without "sort" key when listing items.
			-- Try the next element.
			idx = idx + 1
		end
	end
end

-- Implementation based on the fact that items, effects, etc. are stored
-- as modifications within the WML of the unit.
return {

	-- Get a list of numbers of items on a unit
	list_unit_item_numbers = function(unit)
		unit = normalize_unit_param(unit)

		local retval = {}
		local mods = helper.get_child(unit, "modifications")
		for i = 1,#mods do
			if mods[i][1] == "object" and mods[i][2].number then
				table.insert(retval, mods[i][2].number)
			end
		end
		return retval
	end,

	-- Returns iterator over items of this unit.
	items = function(unit)
		unit = normalize_unit_param(unit)

		local set_items = loti.unit.list_unit_item_numbers(unit)
		return wml_modification_iterator(unit, "object", function(elem)
			if elem.number then
				return loti.unit.item_with_set_effects(elem.number, set_items, elem.sort)
			end
		end)
	end,

	-- Returns iterator over advancements of this unit.
	advancements = function(unit)
		unit = normalize_unit_param(unit)
		return wml_modification_iterator(unit, "advancement", function(elem)
			return loti.util.get_type_advancement(unit.type, elem.id)
		end)
	end,

	-- Returns iterator over effects of this unit.
	effects = function(unit)
		unit = normalize_unit_param(unit)

		local idx = 0 -- Top-level index returned as key from effects() iterator
		local set_items = loti.unit.list_unit_item_numbers(unit)

		-- List of all modifications of this unit.
		-- Includes items, advancements, traits, etc.
		local modifications = helper.get_child(unit, "modifications")
		local modif_idx = 0

		-- Effects of only one modification (modification we are currently processing)
		local effects
		local effect_idx = 0

		return function()
			effect_idx = effect_idx + 1

			while not effects or not effects[effect_idx] do
				-- Since we have already returned everything from effects[] array
				-- (or when we just started using the iterator, when effects=nil),
				-- obtain the new effects[] array (if any) from the next modification.

				modif_idx = modif_idx + 1

				local modif_tag = modifications[modif_idx]
				if not modif_tag then
					return -- Already listed everything, nothing more to return
				end

				local modif_type = modif_tag[1] -- E.g. "object" or "advancement"
				local contents = modif_tag[2] -- WML table, e.g. one [object] tag.

				if modif_type == "object" and contents.number then
					-- This is an item, therefore we must add "item set" effects (if any).
					contents = loti.unit.item_with_set_effects(contents.number, set_items, contents.sort)
				elseif modif_type == "advancement" then
					contents = loti.util.get_type_advancement(unit.type, contents.id)
				end

				-- New effects[] array.
				-- Further calls to effects() iterator will return its values until this array is depleted.
				effects = helper.child_array(contents, "effect")
				effect_idx = 1
			end

			idx = idx + 1
			return idx, effects[effect_idx]
		end
	end,

	-- Returns iterator over containers containing effects of this unit
	effect_containers = function(unit)
		unit = normalize_unit_param(unit)

		local idx = 0 -- Top-level index returned as key from effects() iterator
		local set_items = loti.unit.list_unit_item_numbers(unit)

		-- List of all modifications of this unit.
		-- Includes items, advancements, traits, etc.
		local modifications = helper.get_child(unit, "modifications")
		local modif_idx = 0

		return function()
			modif_idx = modif_idx + 1

			local modif_tag = modifications[modif_idx]
			if not modif_tag then
				return -- Already listed everything, nothing more to return
			end

			local modif_type = modif_tag[1] -- E.g. "object" or "advancement"
			local contents = modif_tag[2] -- WML table, e.g. one [object] tag.

			if modif_type == "object" and contents.number then
				-- This is an item, therefore we must add "item set" effects (if any).
				contents = loti.unit.item_with_set_effects(contents.number, set_items, contents.sort)
			elseif modif_type == "advancement" then
				contents = loti.util.get_type_advancement(unit.type, contents.id)
			end

			idx = idx + 1
			return idx, contents
		end
	end,

	-- Add advancement to unit.
	add_advancement = function(unit, advancement_id)
		unit = normalize_unit_param(unit)
		local mods = helper.get_child(unit, "modifications")
		local advancement = loti.util.get_type_advancement(unit.type, advancement_id)

		if not advancement then
			helper.wml_error("Trying to add non-existent advancement \"" .. tostring(advancement_id) ..
				" to unit " .. unit.id)
		end

		table.insert(mods, { "advancement", advancement })

		-- Place updated unit back onto the map.
		loti.put_unit(unit)
	end,

	-- Remove advancement from unit.
	remove_advancement = function(unit, advancement_id)
		unit = normalize_unit_param(unit)
		local mods = helper.get_child(unit, "modifications")
		for i = 1,#mods do
			if mods[i][1] == "advancement" and mods[i][2].id == advancement_id then
				table.remove(mods, i)
				break
			end
		end

		-- Place updated unit back onto the map.
		loti.put_unit(unit)
	end,

	-- Remove all advancements from unit.
	remove_all_advancements = function(unit)
		unit = normalize_unit_param(unit)
		local mods = helper.get_child(unit, "modifications")
		for i = #mods,1,-1 do
			if mods[i][1] == "advancement" then
				table.remove(mods, i)
			end
		end

		-- Place updated unit back onto the map.
		loti.put_unit(unit)
	end,

	-- Add item to unit.
	add_item = function(unit, item_number, item_sort)
		unit = normalize_unit_param(unit)

		local item = wesnoth.deepcopy(loti.item.type[item_number])
		if item_sort then
			item.sort = item_sort
		end

		local on_equip = helper.get_child(item, "on_equip")
		if on_equip then
			local variable = on_equip.variable or "armed"
			wesnoth.set_variable(variable, unit)
			loti.execute(on_equip)
			unit = wesnoth.get_variable(variable)
			wesnoth.set_variable(variable, nil)
		end

		local modifications = helper.get_child(unit, "modifications")
		table.insert(modifications, wml.tag.object(item))

		-- Place updated unit back onto the map.
		loti.put_unit(unit)
	end,

	-- Remove item from unit.
	remove_item = function(unit, item_number, item_sort)
		unit = normalize_unit_param(unit)
		local mods = helper.get_child(unit, "modifications")
		for i = 1,#mods do
			if mods[i][1] == "object" and mods[i][2].number == item_number and (not item_sort or mods[i][2].sort == item_sort) then
				table.remove(mods, i)
				break
			end
		end

		-- Place updated unit back onto the map.
		loti.put_unit(unit)
	end,

	-- Remove all items from unit.
	-- Returns a Lua array of items that were removed.
	-- Optional parameter: filter_func - callback function. If set, then:
	--	each item is passed to this callback as a parameter,
	--	item is only removed if the callback returned true.
	remove_all_items = function(unit, filter_func)
		unit = normalize_unit_param(unit)

		local mods = helper.get_child(unit, "modifications")
		for i = #mods,1,-1 do
			if mods[i][1] == "object" then
				if not filter_func or filter_func(mods[i][2]) then
					table.remove(mods, i)
				end
			end
		end

		-- Place updated unit back onto the map.
		loti.put_unit(unit)
	end
}