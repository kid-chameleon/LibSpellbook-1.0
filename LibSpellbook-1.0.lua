--[[
LibSpellbook-1.0 - Track the spellbook to parry to IsSpellKnown discrepancies.
Copyright (C) 2013 Adirelle (adirelle@gmail.com)

All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright notice,
      this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright notice,
      this list of conditions and the following disclaimer in the documentation
      and/or other materials provided with the distribution.
    * Redistribution of a stand alone version is strictly prohibited without
      prior written authorization from the LibDispellable project manager.
    * Neither the name of the LibDispellable authors nor the names of its contributors
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

local MAJOR, MINOR = "LibSpellbook-1.0", 6
--@debug@
MINOR = math.huge
--@end-debug@
assert(LibStub, MAJOR.." requires LibStub")
local lib, oldminor = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

-- oldminor is used to upgrade only what's needed
oldminor = oldminor or 0

if oldminor < 1 then

	lib.spells = {
		byName     = {},
		byId       = {},
		lastSeen   = {},
		book       = {},
	}

end

-- Upvalues
local byName, byId, book, lastSeen = lib.spells.byName, lib.spells.byId, lib.spells.book, lib.spells.lastSeen

if oldminor < 1 then

	lib.frame = CreateFrame("Frame")
	lib.frame:SetScript('OnEvent', function() return lib:ScanSpellbooks() end)
	lib.frame:RegisterEvent('SPELLS_CHANGED')
	lib.frame:RegisterEvent('PLAYER_ENTERING_WORLD')

	lib.generation = 0

	lib.callbacks = LibStub('CallbackHandler-1.0'):New(lib)

	-- Resolve a spell name, link or identifier into a spell identifier, or nil.
	function lib:Resolve(spell)
		if type(spell) == "number" then
			return spell
		elseif type(spell) == "string" then
			return byName[spell] or tonumber(strmatch(spell, "spell:(%d+)") or "")
		end
	end

end

if oldminor < 3 then

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

end

if oldminor < 1 then

	--- Return the spellbook.
	-- @name LibSpellbook:GetBookType
	-- @param spell (string|number) The spell name, link or identifier.
	-- @return BOOKTYPE_SPELL ("spell"), BOOKTYPE_PET ("pet") or nil if the spell if unknown.
	function lib:GetBookType(spell)
		local id = lib:Resolve(spell)
		return id and book[id]
	end

end

if oldminor < 5 then

	--- Iterate through all spells.
	-- @name LibSpellbook:IterateSpells
	-- @param bookType (string) The book to iterate : BOOKTYPE_SPELL, BOOKTYPE_PET, or nil for both.
	-- @return An iterator and a table, suitable to use in "in" part of a "for ... in" loop.
	-- @usage
	--   for id, name in LibSpellbook:IterateSpells(BOOKTYPE_SPELL) do
	--     -- Do something
	--   end
	function lib:IterateSpells(bookType)
		if not bookType then
			return pairs(byId)
		else
			return function(t, k)
				local v
				repeat
					k, v = next(t, k)
				until not k or v == bookType
				return k, v
			end, byId
		end
	end

end

if oldminor < 6 then

	function lib:FoundSpell(id, name)
		local isNew = not lastSeen[id]
		byName[name] = id
		byId[id] = name
		book[id] = bookType
		lastSeen[id] = gen
		if isNew then
			lib.callbacks:Fire("LibSpellbook_Spell_Added", id, bookType, name)
			return true
		end
	end

	-- Scan one spellbook
	function lib:ScanSpellbook(bookType, numSpells, gen, offset)
		local changed = false
		offset = offset or 0

		for index = offset + 1, offset + numSpells do
			local spellType, id1 = GetSpellBookItemInfo(index, bookType)
			if spellType  == "SPELL" then
				local link = GetSpellLink(index, bookType)
				local id2, name = strmatch(link, "spell:(%d+)|h%[(.+)%]")
				changed = lib:FoundSpell(tonumber(id2), name) or changed
				if id1 ~= id2 then
					changed = lib:FoundSpell(tonumber(id1), GetSpellBookItemName(index, bookType)) or changed
				end
			elseif not spellType then
				break
			end
		end

		return changed
	end

end

if oldminor < 4 then

	function lib:ScanSpellbooks()
		local gen = lib.generation + 1
		lib.generation = gen

		-- Scan spell tabs
		local changed = false
		for tab = 1, 2 do
			local name, _, offset, numSlots = GetSpellTabInfo(tab)
			changed = lib:ScanSpellbook(BOOKTYPE_SPELL, numSlots, gen, offset) or changed
		end

		-- Scan pet spells
		local numPetSpells = HasPetSpells()
		if numPetSpells then
			changed = lib:ScanSpellbook(BOOKTYPE_PET, numPetSpells, gen) or changed
		end

		-- Remove old spells
		for id, spellGen in pairs(lib.spells.lastSeen) do
			if spellGen ~= gen then
				changed = true
				local name = byId[id]
				lib.callbacks:Fire("LibSpellbook_Spell_Removed", id, book[id], name)
				byName[name] = nil
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

end
