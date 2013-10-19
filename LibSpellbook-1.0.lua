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

local MAJOR, MINOR = "LibSpellbook-1.0", 1
--@debug@
MINOR = 999999999
--@end-debug@
assert(LibStub, MAJOR.." requires LibStub")
local lib, oldminor = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end
oldminor = oldminor or 0

if oldminor < 1 then

	lib.frame = CreateFrame("Frame")
	lib.frame:SetScript('OnEvent', function() return lib:ScanSpellbooks() end)
	lib.frame:RegisterEvent('SPELLS_CHANGED')
	lib.frame:RegisterEvent('PLAYER_ENTERING_WORLD')

	lib.spells = {
		byName     = {},
		byId       = {},
		lastSeen   = {},
		book       = {},
	}
	lib.generation = 0

	lib.callbacks = LibStub('CallbackHandler-1.0'):New(lib)

	-- Upvalues
	local byName, byId, book, lastSeen = lib.spells.byName, lib.spells.byId, lib.spells.book, lib.spells.lastSeen

	-- Scan one spellbook
	function lib:ScanSpellbook(bookType, numSpells, gen)
		local changed = false

		for index = 1, numSpells do
			local spellType = GetSpellBookItemInfo(index, bookType)
			if spellType  == "SPELL" then
				local link = GetSpellLink(index, bookType)
				local id, name = strmatch(link, "spell:(%d+)|h%[(.+)%]")
				id = tonumber(id)
				if not lastSeen[id] then
					changed = true
				end
				byName[name] = id
				byId[id] = name
				book[id] = bookType
				lastSeen[id] = gen
			elseif not spellType then
				break
			end
		end

		return changed
	end

	function lib:ScanSpellbooks()
		local gen = lib.generation + 1
		lib.generation = gen

		-- Scan for existing and new spells
		local changed = lib:ScanSpellbook(BOOKTYPE_SPELL, MAX_SPELLS, gen)
		local numPetSpells = HasPetSpells()
		if numPetSpells then
			changed = lib:ScanSpellbook(BOOKTYPE_PET, numPetSpells, gen) or changed
		end

		-- Remove old spells
		for id, spellGen in pairs(lib.spells.lastSeen) do
			if spellGen ~= gen then
				changed = true
				byName[byId[id]] = nil
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

	-- Resolve a spell name, link or identifier into a spell identifier, or nil.
	function lib:Resolve(spell)
		if type(spell) == "number" then
			return spell
		elseif type(spell) == "string" then
			return byName[spell] or tonumber(strmatch(spell, "spell:(%d+)") or "")
		end
	end

	--- Return whether the player or her pet knowns a spell.
	-- @name LibSpellbook:IsKnown
	-- @param spell (string|number) The spell name, link or identifier.
	-- @param bookType (string) The spellbook to look into, either BOOKTYPE_SPELL, BOOKTYPE_PET, or nil (=any).
	-- @return True if the spell exists in the given spellbook (o
	function lib:IsKnown(spell, bookType)
		local id = lib:Resolve(spell)
		if id and byId[id] then
			return bookType == nil or bookType == bookd[id]
		end
		return false
	end

	--- Return the spellbook.
	-- @name LibSpellbook:GetBookType
	-- @param spell (string|number) The spell name, link or identifier.
	-- @return BOOKTYPE_SPELL ("spell"), BOOKTYPE_PET ("pet") or nil if the spell if unknown.
	function lib:GetBookType(spell)
		local id = lib:Resolve(spell)
		return id and book[id]
	end

	--- .
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
				repeat
					k, v = next(t, k)
				until not k or v == bookType
				return k, v
			end, byId
		end
	end

end
