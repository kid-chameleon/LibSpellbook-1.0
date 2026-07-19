local _, ns = ...
ns = ns['__LibSpellbook-1.0']

local lib = ns.lib
if not lib then return end

local FoundSpell = ns.FoundSpell
local CleanUp    = ns.CleanUp

local supportedBookTypes = {
	pet      = true,
	pvp      = true,
	spell    = true,
	talent   = true,
}

local function ScanFlyout(flyoutId, bookType)
	local _, _, numSlots, isKnown = GetFlyoutInfo(flyoutId)

	if not isKnown or numSlots < 1 then return end

	local changed = false
	for i = 1, numSlots do
		local _, id, isKnown, name = GetFlyoutSlotInfo(flyoutId, i)

		if isKnown then
			changed = FoundSpell(id, name, bookType) or changed
		end
	end

	return changed
end

-- The classic clients (era and anniversary alike) only ship the legacy
-- spellbook API: their own SpellBookFrame uses GetNumSpellTabs and
-- GetSpellBookItemInfo, and C_SpellBook holds none of the retail scan
-- functions (no GetNumSpellBookSkillLines/GetSpellBookItemInfo).
local function ScanSpellbook(bookType, numSpells, offset)
	local changed = false
	offset = offset or 0

	for i = offset + 1, offset + numSpells do
		local spellType, actionId = GetSpellBookItemInfo(i, bookType)
		if spellType == 'SPELL' then
			local name, _, spellId = GetSpellBookItemName(i, bookType)
			changed = FoundSpell(spellId, name, bookType) or changed

			-- ranked spells link to the highest known rank
			local link = GetSpellLink(i, bookType)
			if link then
				local id, n = link:match('spell:(%d+):%d+\124h%[(.+)%]')
				id = tonumber(id)
				if id and id ~= spellId then
					changed = FoundSpell(id, n, bookType) or changed
				end
			end
		elseif spellType == 'FLYOUT' then
			changed = ScanFlyout(actionId, bookType)
		elseif spellType == 'PETACTION' then
			local name, _, spellId = GetSpellBookItemName(i, bookType)
			changed = FoundSpell(spellId, name, bookType) or changed
		elseif not spellType or spellType == 'FUTURESPELL' then
			break
		end
	end

	return changed
end

local function ScanSpells(event)
	local changed = false
	ns.generation = ns.generation + 1

	for tab = 1, GetNumSpellTabs() do
		local _, _, offset, numSpells = GetSpellTabInfo(tab)
		changed = ScanSpellbook('spell', numSpells, offset) or changed
	end

	local numPetSpells = HasPetSpells()
	if numPetSpells then
		changed = ScanSpellbook('pet', numPetSpells) or changed
	end

	local inCombat = InCombatLockdown()

	local current = ns.generation
	for id, generation in next, ns.spells.lastSeen do
		if generation < current then
			local bookType = ns.spells.book[id]
			if supportedBookTypes[bookType] and (not inCombat or bookType ~= 'talent') then
				CleanUp(id)
				changed = true
			end
		end
	end

	if changed then
		lib.callbacks:Fire('LibSpellbook_Spells_Changed')
	end

	if event == 'PLAYER_ENTERING_WORLD' then
		lib:UnregisterEvent(event, ScanSpells)
	end
end

lib:RegisterEvent('PLAYER_ENTERING_WORLD', ScanSpells)
lib:RegisterEvent('SPELLS_CHANGED', ScanSpells)
