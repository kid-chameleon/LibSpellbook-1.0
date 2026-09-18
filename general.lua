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

-- WoW: Forever (and retail) ship only the C_SpellBook scan API: skill lines
-- instead of tabs, and item info as a table.
local hasSkillLineAPI = C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookSkillLineInfo
	and C_SpellBook.GetSpellBookItemInfo and true or false

local function ScanSkillLineItems(bookType, bank, first, last)
	local changed = false
	local Spell, PetAction, Flyout = Enum.SpellBookItemType.Spell, Enum.SpellBookItemType.PetAction, Enum.SpellBookItemType.Flyout

	for i = first, last do
		local item = C_SpellBook.GetSpellBookItemInfo(i, bank)
		if not item then break end
		if item.itemType == Spell or item.itemType == PetAction then
			local spellId = item.spellID or item.actionID
			changed = FoundSpell(spellId, item.name, bookType) or changed
			if item.actionID and item.actionID ~= spellId then
				changed = FoundSpell(item.actionID, item.name, bookType) or changed
			end
		elseif item.itemType == Flyout and GetFlyoutInfo then
			changed = ScanFlyout(item.actionID, bookType) or changed
		end
	end

	return changed
end

local function ScanSkillLines()
	local changed = false
	local bank = Enum.SpellBookSpellBank.Player

	for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
		local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
		if info and not info.isGuild then
			local first = info.itemIndexOffset + 1
			changed = ScanSkillLineItems('spell', bank, first, first + info.numSpellBookItems - 1) or changed
		end
	end

	local numPetSpells = C_SpellBook.HasPetSpells()
	if numPetSpells then
		changed = ScanSkillLineItems('pet', Enum.SpellBookSpellBank.Pet, 1, numPetSpells) or changed
	end

	return changed
end

local function ScanSpells(event)
	local changed = false
	ns.generation = ns.generation + 1

	if hasSkillLineAPI then
		changed = ScanSkillLines() or changed
	else
		for tab = 1, GetNumSpellTabs() do
			local _, _, offset, numSpells = GetSpellTabInfo(tab)
			changed = ScanSpellbook('spell', numSpells, offset) or changed
		end

		local numPetSpells = HasPetSpells()
		if numPetSpells then
			changed = ScanSpellbook('pet', numPetSpells) or changed
		end
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
