local _, ns = ...

local lib = ns.lib

local FoundSpell = ns.FoundSpell
local CleanUp    = ns.CleanUp

local supportedBookTypes = {
	spell  = true,
	pet    = true,
	talent = true,
	pvp    = true,
}

local playerClass
local spellRanks = {
	DEATHKNIGHT = {
		278223, -- Death Strike (Rank 2) (Unholy)
	},
	DRUID = {
		159456, -- Travel Form (Rank 2)
		231021, -- Starsurge (Rank 2) (Balance)
		231040, -- Rejuvenation (Rank 2) (Restoration)
		231042, -- Moonkin Form (Rank 2) (Balance)
		231050, -- Sunfire (Rank 2) (Balance/Restoration)
		231052, -- Rake (Rank 2) (Feral)
		231055, -- Tiger's Fury (Rank 2) (Feral)
		231056, -- Ferocious Bite (Rank 2) (Feral)
		231057, -- Shred (Rank 3) (Feral)
		231063, -- Shred (Rank 2) (Feral)
		231064, -- Mangle (Rank 2) (Guardian)
		231070, -- Ironfur (Rank 2) (Guardian)
		231283, -- Swipe (Rank 2) (Feral)
		270100, -- Bear Form (Rank 2) (Guardian)
		273048, -- Frenzied Regeneration (Rank 2) (Guardian)
	},
	HUNTER = {
		231546, -- Exhilaration (Rank 2)
		231549, -- Disengage (Rank 2)
		231550, -- Harpoon (Rank 2) (Survival)
		262837, -- Cobra Shot (Rank 2) (Beast Mastery)
		262838, -- Cobra Shot (Rank 3) (Beast Mastery)
		262839, -- Raptor Strike (Rank 2) (Survival)
		263186, -- Kill Command (Rank 2) (Survival)
	},
	MAGE = {
		231564, -- Arcane Barrage (Rank 2) (Arcane)
		231565, -- Evocation (Rank 2) (Arcane)
		231567, -- Fire Blast (Rank 3) (Fire)
		231568, -- Fire Blast (Rank 2) (Fire)
		231582, -- Shatter (Rank 2) (Frost)
		231584, -- Brain Freeze (Rank 2) (Frost)
		231596, -- Freeze (Pet) (Frost)
		236662, -- Blizzard (Rank 2) (Frost)
	},
	MONK = {
		231231, -- Renewing Mist (Rank 2) (Mistweaver)
		231602, -- Vivify (Rank 2)
		231605, -- Enveloping Mist (Rank 2) (Mistweaver)
		231627, -- Storm, Earth, and Fire (Rank 2) (Windwalker)
		231633, -- Essence Font (Rank 2) (Mistweaver)
		231876, -- Thunder Focus Tea (Rank 2) (Mistweaver)
		261916, -- Blackout Kick (Rank 2) (Windwalker)
		261917, -- Blackout Kick (Rank 3) (Windwalker)
		262840, -- Rising Sun Kick (Rank 2) (Mistweaver/Windwalker)
		274586, -- Vivify (Rank 2) (Mistweaver)
	},
	PALADIN = {
		200327, -- Blessing of Sacrifice (Rank 2) (Holy)
		231642, -- Beacon of Light (Rank 2) (Holy)
		231644, -- Judgement (Rank 2) (Holy)
		231657, -- Judgement (Rank 2) (Protection)
		231663, -- Judgement (Rank 2) (Retribution)
		231667, -- Crusader Strike (Rank 2) (Holy/Retribution)
		272906, -- Holy Shock (Rank 2) (Holy)
	},
	PRIEST = {
		231682, -- Smite (Rank 2) (Discipline)
		231688, -- Void Bolt (Rank 2) (Shadow)
		262861, -- Smite (Rank 2) (Discipline/Holy)
	},
	ROGUE = {
		231691, -- Sprint (Rank 2)
		231716, -- Eviscerate (Rank 2) (Subtlety)
		231718, -- Shadowstrike (Rank 2) (Subtlety)
		231719, -- Garotte (Rank 2) (Assasination)
		235484, -- Between the Eyes (Rank 2) (Outlaw)
		245751, -- Sprint (Rank 2) (Subtlety)
		279876, -- Sinister Strike (Rank 2) (Outlaw)
		279877, -- Sinister Strike (Rank 2) (Assasination)
	},
	SHAMAN = {
		190899, -- Healing Surge (Rank 2) (Enhancement)
		231721, -- Lava Burst (Rank 2) (Elemental/Restoration)
		231722, -- Chain Lightning (Rank 2) (Elemental)
		231723, -- Feral Spirit (Rank 2) (Enhancement)
		231725, -- Riptide (Rank 2) (Restoration)
		231780, -- Chain Heal (Rank 2) (Restoration)
		231785, -- Tidal Waves (Rank 2) (Restoration)
		280609, -- Mastery: Elemental Overload (Rank 2) (Elemental)
	},
	WARLOCK = {
		231791, -- Unstable Affliction (Rank 2) (Affliction)
		231792, -- Agony (Rank 2) (Affliction)
		231793, -- Conflagrate (Rank 2) (Destruction)
		231811, -- Soulstone (Rank 2)
	},
	WARRIOR = {
		 12950, -- Whirlwind (Rank 2) (Fury)
		231827, -- Execute (Rank 2) (Fury)
		231830, -- Execute (Rank 2) (Arms)
		231834, -- Shield Slam (Rank 2) (Protection)
		231847, -- Shield Block (Rank 2) (Protection)
	},
}

local function ScanRanks()
	playerClass = playerClass or select(2, UnitClass('player'))
	local ranks = spellRanks[playerClass]
	if not ranks then return end

	local changed = false
	for spellId in next, ranks do
		if IsPlayerSpell(spellId) then
			local name = GetSpellInfo(spellId)
			changed = FoundSpell(spellId, name, 'spell') or changed
		end
	end

	return changed
end

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

local function ScanTalents()
	local changed = false
	local spec = GetActiveSpecGroup()
	for tier = 1, MAX_TALENT_TIERS do
		for column = 1, NUM_TALENT_COLUMNS do
			local _, _, _, _, _, spellId, _, _, _, isKnown, isGrantedByAura = GetTalentInfo(tier, column, spec)
			if isKnown or isGrantedByAura then
				local name = GetSpellInfo(spellId)
				changed = FoundSpell(spellId, name, 'talent') or changed
			end
		end
	end

	return changed
end

local function ScanPvpTalents()
	local changed = false
	if C_PvP.IsWarModeDesired() then
		local selectedPvpTalents = C_SpecializationInfo.GetAllSelectedPvpTalentIDs
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
		local spellType, actionId = GetSpellBookItemInfo(i, bookType)
		if spellType == 'SPELL' then
			local name, _, spellId = GetSpellBookItemName(i, bookType)
			changed = FoundSpell(spellId, name, bookType) or changed

			local link = GetSpellLink(i, bookType)
			if link then
				local id, n = link:match('spell:(%d+):%d+\124h%[(.+)%]')
				id = tonumber(id)
				if id ~= spellId then
					-- TODO: check this
					print('Differing ids from link and spellbook', id, spellId)
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

	for tab = 1, 2 do
		local _, _, offset, numSpells = GetSpellTabInfo(tab)
		changed = ScanSpellbook('spell', numSpells, offset) or changed
	end

	changed = ScanRanks() or changed

	local numPetSpells = HasPetSpells()
	if numPetSpells then
		changed = ScanSpellbook('pet', numPetSpells) or changed
	end

	local inCombat = InCombatLockdown()
	if not inCombat then
		changed = ScanTalents() or changed
	end

	changed = ScanPvpTalents() or changed

	local current = ns.generation
	for id, generation in next, ns.spells.lastSeen do
		if generation < current then
			changed = true
			local bookType = ns.spells.book[id]
			if supportedBookTypes[bookType] and (not inCombat or bookType ~= 'talent') then
				CleanUp(id)
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

lib:RegisterEvent('SPELLS_CHANGED', ScanSpells)
lib:RegisterEvent('PLAYER_ENTERING_WORLD', ScanSpells)
