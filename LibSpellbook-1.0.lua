--[[
LibSpellbook-1.0 - Track the spellbook to parry to IsSpellKnown discrepancies.
Copyright (C) 2013-2014 Adirelle (adirelle@gmail.com)

All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright notice,
      this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright notice,
      this list of conditions and the following disclaimer in the documentation
      and/or other materials provided with the distribution.
    * Redistribution of a stand alone version is strictly prohibited without
      prior written authorization from the LibSpellbook project manager.
    * Neither the name of the LibSpellbook authors nor the names of its contributors
      may be used to endorse or promote products derived from this software without
      specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
--]]

local MAJOR, MINOR = "LibSpellbook-1.0", 12
assert(LibStub, MAJOR.." requires LibStub")
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

local _G = _G
local BOOKTYPE_PET = _G.BOOKTYPE_PET
local BOOKTYPE_SPELL = _G.BOOKTYPE_SPELL
local NUM_GLYPH_SLOTS = _G.NUM_GLYPH_SLOTS
local CreateFrame = _G.CreateFrame
local GetCompanionInfo = _G.GetCompanionInfo
local GetFlyoutInfo = _G.GetFlyoutInfo
local GetFlyoutSlotInfo = _G.GetFlyoutSlotInfo
local GetNumCompanions = _G.GetNumCompanions
local GetSpecialization = _G.GetSpecialization
local GetSpecializationMasterySpells = _G.GetSpecializationMasterySpells
local GetSpellBookItemInfo = _G.GetSpellBookItemInfo
local GetSpellBookItemName = _G.GetSpellBookItemName
local GetSpellLink = _G.GetSpellLink
local GetSpellInfo = _G.GetSpellInfo
local GetSpellTabInfo = _G.GetSpellTabInfo
local GetGlyphSocketInfo = _G.GetGlyphSocketInfo
local HasPetSpells = _G.HasPetSpells
local IsPlayerSpell = _G.IsPlayerSpell
local next = _G.next
local pairs = _G.pairs
local strmatch = _G.strmatch
local tonumber = _G.tonumber
local type = _G.type

if not lib.spells then
	lib.spells = {
		byName     = {},
		byId       = {},
		lastSeen   = {},
		book       = {},
	}
end

if not lib.frame then
	lib.frame = CreateFrame("Frame")
	lib.frame:SetScript('OnEvent', function() return lib:ScanSpellbooks() end)
	lib.frame:RegisterEvent('SPELLS_CHANGED')
	lib.frame:RegisterEvent('PLAYER_ENTERING_WORLD')
end

lib.generation = lib.generation or 0

lib.callbacks = lib.callbacks or LibStub('CallbackHandler-1.0'):New(lib)

-- Upvalues
local byName, byId, book, lastSeen = lib.spells.byName, lib.spells.byId, lib.spells.book, lib.spells.lastSeen

-- Resolve a spell name, link or identifier into a spell identifier, or nil.
function lib:Resolve(spell)
	if type(spell) == "number" then
		return spell
	elseif type(spell) == "string" then
		local ids = byName[spell]
		if ids then
			return next(ids)
		else
			return tonumber(strmatch(spell, "spell:(%d+)") or "")
		end
	end
end

--- Return all ids associated to a spell name
-- @name LibSpellbook:GetAllIds
-- @param spell (string|number) The spell name, link or identifier.
-- @return ids A table with spell ids as keys.
function lib:GetAllIds(spell)
	local id = lib:Resolve(spell)
	local name = id and byId[id]
	return name and byName[name]
end

--- Return whether the player or her pet knowns a spell.
-- @name LibSpellbook:IsKnown
-- @param spell (string|number) The spell name, link or identifier.
-- @param bookType (string) The spellbook to look into, either BOOKTYPE_SPELL, BOOKTYPE_PET, or nil (=any).
-- @return True if the spell exists in the given spellbook (o
function lib:IsKnown(spell, bookType)
	local id = lib:Resolve(spell)
	if id and byId[id] then
		return bookType == nil or bookType == book[id]
	end
	return false
end

--- Return the spellbook.
-- @name LibSpellbook:GetBookType
-- @param spell (string|number) The spell name, link or identifier.
-- @return BOOKTYPE_SPELL ("spell"), BOOKTYPE_PET ("pet"), "GLYPH", "MASTERY", "MOUNT", "CRITTER" or nil if the spell if unknown.
function lib:GetBookType(spell)
	local id = lib:Resolve(spell)
	return id and book[id]
end

-- Filtering iterator
local function iterator(bookType, id)
	local name
	repeat
		id, name = next(byId, id)
		if id and book[id] == bookType then
			return id, name
		end
	until not id
end

--- Iterate through all spells.
-- @name LibSpellbook:IterateSpells
-- @param bookType (string) The book to iterate : BOOKTYPE_SPELL, BOOKTYPE_PET, or nil for both.
-- @return An iterator and a table, suitable to use in "in" part of a "for ... in" loop.
-- @usage
--   for id, name in LibSpellbook:IterateSpells(BOOKTYPE_SPELL) do
--     -- Do something
--   end
function lib:IterateSpells(bookType)
	if bookType then
		return iterator, bookType
	else
		return pairs(byId)
	end
end

function lib:FoundSpell(id, name, bookType)
	local isNew = not lastSeen[id]
	if byName[name] then
		byName[name][id] = true
	else
		byName[name] = { [id] = true }
	end
	byId[id] = name
	book[id] = bookType
	lastSeen[id] = lib.generation
	if isNew then
		lib.callbacks:Fire("LibSpellbook_Spell_Added", id, bookType, name)
		return true
	end
end

-- Scan the spells of a flyout
function lib:ScanFlyout(flyoutId, bookType)
	local _, _, numSlots, isKnown = GetFlyoutInfo(flyoutId)
	if not isKnown or numSlots < 1 then
		return
	end
	local changed = false
	for i = 1, numSlots do
		local id1, id2, isKnown, spellName = GetFlyoutSlotInfo(flyoutId, i)
		if isKnown then
			changed = self:FoundSpell(id1, spellName, bookType) or changed
			if id2 ~= id1 then
				changed = self:FoundSpell(id2, spellName, bookType) or changed
			end
		end
	end
	return changed
end

-- Scan one spellbook
function lib:ScanSpellbook(bookType, numSpells, offset)
	local changed = false
	offset = offset or 0

	for index = offset + 1, offset + numSpells do
		local spellType, id1 = GetSpellBookItemInfo(index, bookType)
		if spellType == "SPELL" then
			local link = GetSpellLink(index, bookType)
			local id2, name = strmatch(link, "spell:(%d+)|h%[(.+)%]")
			changed = lib:FoundSpell(tonumber(id2), name, bookType) or changed
			if id1 ~= id2 then
				changed = lib:FoundSpell(id1, GetSpellBookItemName(index, bookType), bookType) or changed
			end
		elseif spellType == "FLYOUT" then
			changed = lib:ScanFlyout(id1, bookType) or changed
		elseif not spellType then
			break
		end
	end

	return changed
end

function lib:ScanGlyphs()
	local changed = false

	for index = 1, NUM_GLYPH_SLOTS do
		local _, _, _, id = GetGlyphSocketInfo(index)
		if id then
			local name = GetSpellInfo(id) -- not all glyph spells have links - Glyph of Death's Embrace
			changed = lib:FoundSpell(tonumber(id), name, "GLYPH") or changed
		end
	end

	return changed
end

function lib:ScanMasterySpells()
	local changed = false
	-- actually there is only one mastery spell per spec
	-- however this returns the spell id regardless of whether the spell is known
	local id = GetSpecializationMasterySpells(GetSpecialization() or 0) or 1

	if IsPlayerSpell(id) then
		local name = GetSpellInfo(id)
		changed = lib:FoundSpell(id, name, "MASTERY") or changed
	end

	return changed
end

-- Scan one companion list
function lib:ScanCompanions(companionType)
	local changed = false

	for index = 1, GetNumCompanions(companionType) do
		local _, name, id = GetCompanionInfo(companionType, index)
		if name then
			changed = self:FoundSpell(id, name, companionType) or changed
		end
	end

	return changed
end

function lib:ScanSpellbooks()
	lib.generation = lib.generation + 1

	-- Scan spell tabs
	local changed = false
	for tab = 1, 2 do
		local name, _, offset, numSlots = GetSpellTabInfo(tab)
		changed = lib:ScanSpellbook(BOOKTYPE_SPELL, numSlots, offset) or changed
	end

	-- Scan mounts and critters
	changed = lib:ScanCompanions("MOUNT") or changed
	changed = lib:ScanCompanions("CRITTER") or changed

	-- Scan pet spells
	local numPetSpells = HasPetSpells()
	if numPetSpells then
		changed = lib:ScanSpellbook(BOOKTYPE_PET, numPetSpells) or changed
	end

	-- Scan glyphs
	changed = lib:ScanGlyphs() or changed

	-- Scan mastery spells for the current specialization
	changed = lib:ScanMasterySpells() or changed

	-- Remove old spells
	local current = lib.generation
	for id, gen in pairs(lib.spells.lastSeen) do
		if gen ~= current then
			changed = true
			local name = byId[id]
			lib.callbacks:Fire("LibSpellbook_Spell_Removed", id, book[id], name)
			byName[name][id] = nil
			if not next(byName[name]) then
				byName[name] = nil
			end
			byId[id] = nil
			book[id] = nil
			lastSeen[id] = nil
		end
	end

	-- Fire an event if anything was added or removed
	if changed then
		lib.callbacks:Fire("LibSpellbook_Spells_Changed")
	end
end

function lib:HasSpells()
	return next(byId) and lib.generation > 0
end
