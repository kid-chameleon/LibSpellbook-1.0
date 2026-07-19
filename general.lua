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

local playerClass

-- war mode and pvp talents only exist on retail
local hasPvpTalents = C_PvP and C_PvP.IsWarModeDesired
	and C_SpecializationInfo and C_SpecializationInfo.GetAllSelectedPvpTalentIDs
	and true or false

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

local function ScanPvpTalents()
	local changed = false
	if C_PvP.IsWarModeDesired() then
		local selectedPvpTalents = C_SpecializationInfo.GetAllSelectedPvpTalentIDs()
		for _, talentId in next, selectedPvpTalents do
			local _, name, _, _, _, spellId = GetPvpTalentInfoByID(talentId)
			if IsPlayerSpell(spellId) then
				changed = FoundSpell(spellId, name, 'pvp') or changed
			end
		end
	end
end

local function ScanSpellbook(bookType, numSpells, offset)
	local changed = false
	offset = offset or 0

	for i = offset + 1, offset + numSpells do
		local info = C_SpellBook.GetSpellBookItemInfo(i, bookType)
		local itemType = info.itemType
		if itemType == Enum.SpellBookItemType.Spell then
			changed = FoundSpell(info.actionID, info.name, bookType) or changed

			if (info.spellID and info.spellID ~= info.actionID) then
				changed = FoundSpell(info.spellID, C_Spell.GetSpellName(info.spellID), bookType) or changed
			end
		elseif itemType == Enum.SpellBookItemType.Flyout then
			changed = ScanFlyout(info.actionID, bookType)
		elseif itemType == Enum.SpellBookItemType.PetAction then
			if info.spellID then
				changed = FoundSpell(info.spellID, info.name, bookType) or changed
			end
		else
			break
		end
	end

	return changed
end

local function ScanSpells(event)
	local changed = false
	ns.generation = ns.generation + 1

	for skillLine = 1, C_SpellBook.GetNumSpellBookSkillLines() do
		local skillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo(skillLine)

		if not skillLineInfo.offspecID then
			changed = ScanSpellbook(Enum.SpellBookSpellBank.Player, skillLineInfo.numSpellBookItems, skillLineInfo.itemIndexOffset) or changed
		end
	end

	local numPetSpells = C_SpellBook.HasPetSpells()
	if numPetSpells then
		changed = ScanSpellbook(Enum.SpellBookSpellBank.Pet, numPetSpells) or changed
	end

	local inCombat = InCombatLockdown()

	if hasPvpTalents then
		changed = ScanPvpTalents() or changed
	end

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
if hasPvpTalents then
	lib:RegisterEvent('PVP_TIMER_UPDATE', ScanSpells, true)
end
lib:RegisterEvent('SPELLS_CHANGED', ScanSpells)
