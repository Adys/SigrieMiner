local Recorder = select(2, ...)
Recorder.version = 1

local L = Recorder.L

local CanMerchantRepair, IsInInstance, IsFishingLoot, ItemTextGetCreator, LootSlotIsItem, UnitAura = CanMerchantRepair, IsInInstance, IsFishingLoot, ItemTextGetCreator, LootSlotIsItem, UnitAura
local GetInboxHeaderInfo, GetInboxItem, GetInboxItemLink, GetInboxNumItems, GetLootMethod = GetInboxHeaderInfo, GetInboxItem, GetInboxItemLink, GetInboxNumItems, GetLootMethod
local GetMerchantItemCostInfo, GetMerchantItemCostItem, GetMerchantItemLink = GetMerchantItemCostInfo, GetMerchantItemCostItem, GetMerchantItemLink
local GetNumFactions, GetNumLootItems, GetNumTrainerServices = GetNumFactions, GetNumLootItems, GetNumTrainerServices
local GetMapInfo, GetTitleText, GetTrainerGreetingText, GetSpellInfo = GetMapInfo, GetTitleText, GetTrainerGreetingText, GetSpellInfo
local CheckInteractDistance, CheckBinderDist, CheckSpiritHealerDist, CheckTalentMasterDist = CheckInteractDistance, CheckBinderDist, CheckSpiritHealerDist, CheckTalentMasterDist

local DEBUG_LEVEL = 4
local ALLOWED_COORD_DIFF = 0.02
local LOOT_EXPIRATION = 10 * 60
local ZONE_DIFFICULTY = 0
local RECORD_TIMER = 0.50 -- Timer between last relevant event and GetTime() to acquire a loot source
local LOOT_MAX_LATENCY = 400 -- In milliseconds, discard loot recording if latency is superior
local COORD_INTERACT_DISTANCE = 3 -- Record coords at this distance. 1 = inspect, 2 = trade, 3 = duel, 4 = follow

local npcToDB = {["npc"] = "npcs", ["item"] = "items", ["object"] = "objects"}
local NPC_TYPES = {
	["mailbox"]      = 0x00001, -- Mailbox (eg. Argent Squire)
	["auctioneer"]   = 0x00002, -- Auctioneer
	["battlemaster"] = 0x00004, -- Battlemaster (all or specific)
	["binder"]       = 0x00008, -- Innkeeper
	["bank"]         = 0x00010, -- Banker
	["guildbank"]    = 0x00020, -- Guild Bank (I don't think any NPC can do that ...)
	["canrepair"]    = 0x00040, -- Can repair armor
	["flightmaster"] = 0x00080, -- Flight Master
	["stable"]       = 0x00100, -- Stable Master
	["tabard"]       = 0x00200, -- Tabard Designer
	["vendor"]       = 0x00400, -- Vendor (We record vendor/trainer anyway for easy lookups)
	["trainer"]      = 0x00800, -- Skill trainer
	["spiritres"]    = 0x01000, -- Spirit Healer
	["book"]         = 0x02000, -- Readable (do we care?)
	["talentwipe"]   = 0x04000, -- Can reset talents
	["arenaorg"]     = 0x08000, -- Arena Organizer
	["petition"]     = 0x10000, -- Guild Master
}

local BATTLEFIELD_TYPES = {
	["Alterac Valley"]         = 1,
	["Warsong Gulch"]          = 2,
	["Arathi Basin"]           = 3,
	["Nagrand Arena"]          = 4,
	["Blade's Edge Arena"]     = 5,
	["All Arenas"]             = 6,
	["Eye of the Storm"]       = 7,
	["Ruins of Lordaeron"]     = 8,
	["Strand of the Ancients"] = 9,
	["Dalaran Arena"]          = 10,
	["Ring of Valor"]          = 11,
	["Isle of Conquest"]       = 30,
	["All Battlegrounds"]      = 32;
}
local BATTLEFIELD_MAP = { -- Localize the battleground name
	[L["Alterac Valley"]]         = "Alterac Valley",
	[L["Arathi Basin"]]           = "Arathi Basin",
	[L["Warsong Gulch"]]          = "Warsong Gulch",
	[L["Eye of the Storm"]]       = "Eye of the Storm",
	[L["Strand of the Ancients"]] = "Strand of the Ancients",
	[L["Isle of Conquest"]]       = "Isle of Conquest",
	[L["All Arenas"]]             = "All Arenas"
}

-- Items to ignore when looted in a *regular* way
-- Note: Disenchant loots exist (AQ) but should be manually added to the DB
-- Attempting to loot an item between END_ROLL and CHECK_INVENTORY causes it
-- to be disenchanted on-spot if it was won by a disenchanting roll.
local DISENCHANT_LOOT = {
	[10938] = true, -- Lesser Magic Essence
	[10939] = true, -- Greater Magic Essence
	[10940] = true, -- Strange Dust
	[10978] = true, -- Small Glimmering Shard
	[10998] = true, -- Lesser Astral Essence
	[11082] = true, -- Greater Astral Essence
	[11083] = true, -- Soul Dust
	[11084] = true, -- Large Glimmering Shard
	[11134] = true, -- Lesser Mystic Essence
	[11135] = true, -- Greater Mystic Essence
	[11137] = true, -- Vision Dust
	[11138] = true, -- Small Glowing Shard
	[11139] = true, -- Large Glowing Shard
	[11174] = true, -- Lesser Nether Essence
	[11175] = true, -- Greater Nether Essence
	[11176] = true, -- Dream Dust
	[11177] = true, -- Small Radiant Shard
	[11178] = true, -- Large Radiant Shard
	[14343] = true, -- Small Brilliant Shard
	[14344] = true, -- Large Brilliant Shard
	[16202] = true, -- Lesser Eternal Essence
	[16203] = true, -- Greater Eternal Essence
	[16204] = true, -- Illusion Dust
	[20725] = true, -- Nexus Crystal
	[22445] = true, -- Arcane Dust
	[22446] = true, -- Greater Planar Essence
	[22447] = true, -- Lesser Planar Essence
	[22448] = true, -- Small Prismatic Shard
	[22449] = true, -- Large Prismatic Shard
	[22450] = true, -- Void Crystal
	[34052] = true, -- Dream Shard
	[34053] = true, -- Small Dream Shard
	[34054] = true, -- Infinite Dust
	[34055] = true, -- Greater Cosmic Essence
	[34056] = true, -- Lesser Cosmic Essence
	[34057] = true, -- Abyss Crystal
--	[49640] = true, -- Essence or Dust
}

local REPUTATION_MODIFIERS = {
	[GetSpellInfo(20599)] = true, -- Diplomacy
	[GetSpellInfo(24705)] = true, -- Invocation of the Wickerman
	[GetSpellInfo(30754)] = true, -- Cenarion Favor
	[GetSpellInfo(32098)] = true, -- Honor Hold's Favor
	[GetSpellInfo(39913)] = true, -- Nazgrel's Fervor
	[GetSpellInfo(39953)] = true, -- A'dal's Song of Battle
	[GetSpellInfo(58440)] = true, -- Pork Red Ribbon
	[GetSpellInfo(61849)] = true, -- The Spirit of Sharing
	
	-- Championing - TODO record champion data
	[GetSpellInfo(57819)] = true, -- Argent Champion (1106 - Argent Crusade)
	[GetSpellInfo(57820)] = true, -- Ebon Champion (1098 - Knights of the Ebon Blade)
	[GetSpellInfo(57821)] = true, -- Champion of the Kirin Tor (1090 - Kirin Tor)
	[GetSpellInfo(57822)] = true, -- Wyrmrest Champion (1091 - The Wyrmrest Accord)
}

local SPELL_BLACKLIST = {[1604] = true} -- Spells not recorded as casted by the npc (Dazed)

local setToAbandon, abandonedName, lootedGUID
local repGain, lootedGUID = {}, {}
local playerName = UnitName("player")

if DEBUG_LEVEL > 0 then MMOCRecorder = Recorder end
local function debug(level, msg, ...)
	if level <= DEBUG_LEVEL then
		print(string.format(msg, ...))
	end
end

function Recorder:InitializeDB()
	local version, build = GetBuildInfo()
	build = tonumber(build) or -1
	
	-- Invalidate the database if the player guid changed or the build changed
	if SigrieDB and (not SigrieDB.version or not SigrieDB.build) then
		SigrieDB = nil
		debug(1, "Reset DB")
	end
	
	-- Initialize the database
	SigrieDB = SigrieDB or {}
	SigrieDB.class = select(2, UnitClass("player"))
	SigrieDB.race = string.upper(select(2, UnitRace("player")))
	SigrieDB.guid = SigrieDB.guid or UnitGUID("player")
	SigrieDB.name = UnitName("player")
	SigrieDB.realm = GetRealmName()
	SigrieDB.version = version
	SigrieDB.build = SigrieDB.build or build
	SigrieDB.locale = GetLocale()
	SigrieDB.addonVersion = self.version

	-- On PLAYER_LOGOUT, this gets written to SigrieDB.factions
	self.factions = {}
	self.db = {}
end

-- GUID changes infrequently enough, I'm not too worried about this
function Recorder:PLAYER_LOGIN()
	local guid = UnitGUID("player")
	if SigrieDB.guid and SigrieDB.guid ~= guid then
		SigrieDB = nil
		self:InitializeDB()
		debug(1, "Reset DB, GUID changed.")
	end
	SigrieDB.guid = guid
end

function Recorder:ADDON_LOADED(event, addon)
	if( addon ~= "+MMOC_Recorder" ) then return end
	self:UnregisterEvent("ADDON_LOADED")
	
	self:InitializeDB()
	if SigrieDB.error then
		DEFAULT_CHAT_FRAME:AddMessage(string.format(L["Message: %s"], SigrieDB.error.msg))
		DEFAULT_CHAT_FRAME:AddMessage(string.format(L["Trace: %s"], SigrieDB.error.trace))
		self:Print(L["An error happened while the MMOC Recorder was serializing your data, please report the above error. You might have to scroll up to see it all."])
		SigrieDB.error = nil
	end
	
	local version, build = GetBuildInfo() -- Disable on new builds
	if SigrieDB.build < tonumber(build) then
		self:Print(L["Due to a new build, MMOC Recorder has been disabled on this character, please submit your data!"])
		return
	end
	
	self.tooltip = CreateFrame("GameTooltip", "RecorderTooltip", UIParent, "GameTooltipTemplate")
	self.tooltip:SetOwner(UIParent, "ANCHOR_NONE")
	self.tooltip:Hide()
	
	self.activeSpell = {endTime = -1}
	self:UpdateFactions()

	self:RegisterEvent("MAIL_SHOW")
	self:RegisterEvent("MERCHANT_SHOW")
	self:RegisterEvent("MERCHANT_UPDATE")
	self:RegisterEvent("AUCTION_HOUSE_SHOW")
	self:RegisterEvent("TRAINER_SHOW")
	self:RegisterEvent("PLAYER_LEAVING_WORLD")
	self:RegisterEvent("LOOT_OPENED")
	self:RegisterEvent("LOOT_CLOSED")
	self:RegisterEvent("QUEST_LOG_UPDATE")
	self:RegisterEvent("QUEST_COMPLETE")
	self:RegisterEvent("QUEST_DETAIL")
	self:RegisterEvent("CHAT_MSG_ADDON")
	self:RegisterEvent("UNIT_SPELLCAST_SENT")
	self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
	self:RegisterEvent("WORLD_MAP_UPDATE")
	self:RegisterEvent("COMBAT_TEXT_UPDATE")
	self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	self:RegisterEvent("BANKFRAME_OPENED")
	self:RegisterEvent("PET_STABLE_SHOW")
	self:RegisterEvent("GOSSIP_SHOW")
	self:RegisterEvent("CONFIRM_XP_LOSS")
	self:RegisterEvent("TAXIMAP_OPENED")
	self:RegisterEvent("GUILDBANKFRAME_OPENED")
	self:RegisterEvent("PLAYER_TARGET_CHANGED")
	self:RegisterEvent("BATTLEFIELDS_SHOW")
	self:RegisterEvent("CHAT_MSG_SYSTEM")
	self:RegisterEvent("CONFIRM_BINDER")
	self:RegisterEvent("PLAYER_LOGOUT")
	self:RegisterEvent("PLAYER_DIFFICULTY_CHANGED")
	self:RegisterEvent("UPDATE_INSTANCE_INFO")
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA")	
	self:RegisterEvent("PLAYER_LOGIN")
	self:RegisterEvent("ITEM_TEXT_BEGIN")
	self:RegisterEvent("PETITION_VENDOR_SHOW")
	self:RegisterEvent("CONFIRM_TALENT_WIPE")
	
	if select(2, UnitClass("player")) == "ROGUE" then
		self:RegisterEvent("UI_ERROR_MESSAGE")
	end
	
	self:PLAYER_LEAVING_WORLD()
end

-- For pulling data out of the actual database. This isn't the most efficient system compared to a transparent metatable
-- like I normally use, but because of how the table is structured it's a lot easier to cache "minor" bits of data instead of the ENTIRE table and unserialize it as we need it, also simplifies serializing it again
-- The downside is, it creates duplicate parent and child tables, but it saves a lot more on not loading the excess data
function Recorder:GetBasicData(parent, key)
	self.db[parent] = self.db[parent] or {}
	if self.db[parent][key] then return self.db[parent][key] end
	
	-- Load it out of the database, we've already got it
	if SigrieDB[parent] and SigrieDB[parent][key] then
		local func, msg = loadstring("return " .. SigrieDB[parent][key])
		if func then
			self.db[parent][key] = func()
		else
			geterrorhandler(msg)
		end
	else
		self.db[parent][key] = {}
	end
	
	self.db[parent][key].START_SERIALIZER = true
	return self.db[parent][key]
end

function Recorder:GetData(parent, child, key)
	self.db[parent] = self.db[parent] or {}
	self.db[parent][child] = self.db[parent][child] or {}
	if self.db[parent][child][key] then return self.db[parent][child][key] end
	
	-- Load it out of the database, we've already got it
	if SigrieDB[parent] and SigrieDB[parent][child] and SigrieDB[parent][child][key] then
		local func, msg = loadstring("return " .. SigrieDB[parent][child][key])
		if func then
			self.db[parent][child][key] = func()
		else
			geterrorhandler(msg)
		end
	else
		self.db[parent][child][key] = {}
	end
	
	self.db[parent][child][key].START_SERIALIZER = true
	return self.db[parent][child][key]
end

-- NPC identification
local npcIDMetatable = {
	__index = function(tbl, guid)
		local id = tonumber(string.sub(guid, -12, -7), 16) or false
		rawset(tbl, guid, id)
		return id
	end
}

local npcTypeMetatable = {
	__index = function(tbl, guid)
		local type = tonumber(string.sub(guid, 3, 5), 16)
		local npcType = false
		if type == 3857 or type == 3921 then
			npcType = "object"
		elseif type == 1024 then
			npcType = "item"
		elseif bit.band(type, 0x00f) == 3 or bit.band(type, 0x00f) == 5 then
			npcType = "npc"
		end
		
		rawset(tbl, guid, npcType)
		return npcType
	end,
}

function Recorder:PLAYER_LEAVING_WORLD()
	self.GUID_ID = setmetatable({}, npcIDMetatable)
	self.GUID_TYPE = setmetatable({}, npcTypeMetatable)
end

local function parseText(text)
	text = string.gsub(text, "%%d", "(%%d+)")
	text = string.gsub(text, "%%s", "(.+)")
	return string.lower(string.trim(text))
end

-- Drunk identification, so we can discard tracking levels until no longer drunk
local DRUNK_ITEM1, DRUNK_ITEM2, DRUNK_ITEM3, DRUNK_ITEM4 = string.gsub(DRUNK_MESSAGE_ITEM_SELF1, "%%s", ".+"), string.gsub(DRUNK_MESSAGE_ITEM_SELF2, "%%s", ".+"), string.gsub(DRUNK_MESSAGE_ITEM_SELF3, "%%s", ".+"), string.gsub(DRUNK_MESSAGE_ITEM_SELF4, "%%s", ".+")
function Recorder:CHAT_MSG_SYSTEM(event, message)
	if( message == DRUNK_MESSAGE_SELF1 ) then
		self.playerIsDrunk = nil
	elseif( not self.playerIsDrunk and ( message == DRUNK_MESSAGE_SELF2 or message == DRUNK_MESSAGE_SELF4 or message == DRUNK_MESSAGE_SELF3 ) ) then
		self.playerIsDrunk = true
	elseif( not self.playerIsDrunk and ( string.match(message, DRUNK_ITEM1) or string.match(message, DRUNK_ITEM2) or string.match(message, DRUNK_ITEM3) or string.match(message, DRUNK_ITEM4) ) ) then
		self.playerIsDrunk = true
	end
end

-- For :GetFaction. Do we also need TOOLTIP_UNIT_LEVEL_TYPE?
local TOOLTIP_UNIT_LEVEL = "^" .. parseText(TOOLTIP_UNIT_LEVEL)

-- Rating identification
local ITEM_REQ_ARENA_RATING = "^" .. parseText(ITEM_REQ_ARENA_RATING)
local ITEM_REQ_ARENA_RATING_3V3 = "^" .. parseText(ITEM_REQ_ARENA_RATING_3V3)
local ITEM_REQ_ARENA_RATING_5V5 = "^" .. parseText(ITEM_REQ_ARENA_RATING_5V5)

function Recorder:GetArenaData(index)
	self.tooltip:SetOwner(UIParent, "ANCHOR_NONE")
	self.tooltip:SetMerchantItem(index)
	for i=1, self.tooltip:NumLines() do
		local text = string.lower(_G["RecorderTooltipTextLeft" .. i]:GetText())
		local rating = string.match(text, ITEM_REQ_ARENA_RATING_5V5)
		if( rating ) then
			return tonumber(rating), 5
		end
		
		local rating = string.match(text, ITEM_REQ_ARENA_RATING_3V3)
		if( rating ) then
			return tonumber(rating), 3
		end
		
		local rating = string.match(text, ITEM_REQ_ARENA_RATING)
		if( rating ) then
			return tonumber(rating)
		end
	end
	
	return nil
end

-- Faction discounts
function Recorder:UpdateFactions()
	-- If you use GetNumFactions, you will miss those that are collapsed
	-- GetFactionInfo() will always return "Other" as the name when that header is shown
	-- meaning using a while true has the potential to infinite loop if the player is showing the
	-- Syndicate or Wintersaber factions, this stops that
	local lastFaction
	for i=1, 1000 do
		local name, _, standing, _, _, _, _, _, header = GetFactionInfo(i)
		if not name or lastFaction == name then break end
		if name and not header then
			self.factions[name] = standing
		end
		
		lastFaction = name
	end
end

function Recorder:GetFaction(guid)
	if not guid then return 1 end
	self:UpdateFactions()
	
	local faction, belowLevel
	self.tooltip:SetOwner(UIParent, "ANCHOR_NONE")
	self.tooltip:SetHyperlink(string.format("unit:%s", guid))
	for i=1, self.tooltip:NumLines() do
		local text = _G["RecorderTooltipTextLeft" .. i]:GetText()
		if text then
			-- Let's not confuse NPC title and faction! Faction is always just under the level
			if not belowLevel and text:lower():match(TOOLTIP_UNIT_LEVEL) then
				belowLevel = true
			elseif belowLevel then
				if self.factions[text] then
					return text
				else
					break
				end
			end
		end
	end
	
	return nil
end

function Recorder:GetFactionDiscount(guid)
	local faction = self:GetFaction(guid)
	if not faction then return 1 end
	return self.factions[faction] == 5 and 0.95 or self.factions[faction] == 6 and 0.90 or self.factions[faction] == 7 and 0.85 or self.factions[faction] == 8 and 0.80 or 1
end

-- Reputation and spell handling
local COMBATLOG_OBJECT_REACTION_HOSTILE = COMBATLOG_OBJECT_REACTION_HOSTILE
local eventsRegistered = {["PARTY_KILL"] = true, ["SPELL_CAST_SUCCESS"] = true, ["SPELL_CAST_START"] = true, ["SPELL_AURA_APPLIED"] = true}
function Recorder:COMBAT_LOG_EVENT_UNFILTERED(event, timestamp, eventType, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags, ...)
	if( not eventsRegistered[eventType] ) then return end
	
	if( ( eventType == "SPELL_CAST_START" or eventType == "SPELL_CAST_SUCCESS" or eventType == "SPELL_AURA_APPLIED" ) and bit.band(sourceFlags, COMBATLOG_OBJECT_TYPE_NPC) == COMBATLOG_OBJECT_TYPE_NPC ) then
		local spellID = ...
		if( SPELL_BLACKLIST[spellID] ) then return end
		
		local type = eventType == "SPELL_AURA_APPLIED" and "auras" or "spells"
		local npcData = self:GetData("npcs", ZONE_DIFFICULTY, self.GUID_ID[sourceGUID])
		npcData[type] = npcData[type] or {}
		if( not npcData[type][spellID] ) then
			debug(4, "%s casting %s %s (%d)", sourceName, type, select(2, ...), spellID)
			npcData.info = npcData.info or {}
			npcData.info.name = sourceName
		end

		npcData[type][spellID] = true
		
	elseif( eventType == "PARTY_KILL" and bit.band(destFlags, COMBATLOG_OBJECT_REACTION_HOSTILE) == COMBATLOG_OBJECT_REACTION_HOSTILE and bit.band(destFlags, COMBATLOG_OBJECT_TYPE_NPC) == COMBATLOG_OBJECT_TYPE_NPC ) then
		repGain.npcID = self.GUID_ID[destGUID]
		repGain.npcType = self.GUID_TYPE[destGUID]
		repGain.timeout = GetTime() + 1
	end
end

function Recorder:HasReputationModifier()
	if( select(2, UnitRace("player")) == "Human" ) then return true end
	
	for name in pairs(REPUTATION_MODIFIERS) do
		if( UnitBuff("player", name) ) then
			return true
		end
	end
	
	return false
end

function Recorder:COMBAT_TEXT_UPDATE(event, type, faction, amount)
	if( type ~= "FACTION" ) then return end
	
	if( repGain.timeout and repGain.timeout >= GetTime() and not self:HasReputationModifier() ) then
		local npcData = self:GetData(npcToDB[repGain.npcType], ZONE_DIFFICULTY, repGain.npcID)
		npcData.info = npcData.info or {}
		npcData.info.reputation = npcData.info.reputation or {}
		npcData.info.reputation.faction = faction
		npcData.info.reputation.amount = amount
		
		debug(2, "NPC #%d gives %d %s faction", repGain.npcID, amount, faction)
	end
end

-- Handle quest abandoning
hooksecurefunc("AbandonQuest", function()
	abandonedName = setToAbandon
	setToAbandon = nil
end)

hooksecurefunc("SetAbandonQuest", function()
	setToAbandon = GetAbandonQuestName()
end)

Recorder.InteractSpells = {
	-- Opening
	[GetSpellInfo(3365) or ""] = {item = true, location = true},
	-- Herb Gathering
	[GetSpellInfo(2366) or ""] = {item = true, location = true},
	-- Mining
	[GetSpellInfo(2575) or ""] = {item = true, location = true},
	-- Disenchanting
	[GetSpellInfo(13262) or ""] = {item = true, location = false, parentItem = true, lootType = "disenchanting"},
	-- Milling
	[GetSpellInfo(51005) or ""] = {item = true, location = false, parentItem = true, lootType = "milling"},
	-- Prospecting
	[GetSpellInfo(31252) or ""] = {item = true, location = false, parentItem = true, lootType = "prospecting"},
	-- Skinning
	[GetSpellInfo(8613) or ""] = {item = true, location = false, parentNPC = true, lootType = "skinning"},
	-- Herb Gathering
	[GetSpellInfo(32605) or ""] = {item = true, location = false, parentNPC = true, lootType = "herbing"},
	-- Engineering
	[GetSpellInfo(49383) or ""] = {item = true, location = false, parentNPC = true, lootType = "engineering"},
	-- Pick Pocket
	[GetSpellInfo(921) or ""] = {item = true, location = false, parentNPC = true, lootType = "pickpocket"},
	-- Used when opening an item, such as Champion's Purse
	["Bag"] = {item = true, location = false, parentItem = true, throttleByItem = true},
	-- Pick Lock
	--[GetSpellInfo(1804) or ""] = {item = true, location = false, parentItem = true},
}

-- Might have to use DungeonUsesTerrainMap, Blizzard seems to use it for subtracting from dungeon level?
function Recorder:RecordLocation()
	local currentCont = GetCurrentMapContinent()
	local currentZone = GetCurrentMapZone()
	local currentLevel = GetCurrentMapDungeonLevel()
	
	SetMapToCurrentZone()
	local dungeonLevel, zone = GetCurrentMapDungeonLevel(), GetMapInfo()
	local x, y = GetPlayerMapPosition("player")

	if( x == 0 and y == 0 ) then
		for level=1, GetNumDungeonMapLevels() do
			SetDungeonMapLevel(level)
			x, y = GetPlayerMapPosition("player")
			
			if( x > 0 and y > 0 ) then
				dungeonLevel = level
				break
			end
		end
	end

	SetMapZoom(currentCont, currentZone)
	SetDungeonMapLevel(currentLevel)
	
	-- No map, return zone name + sub zone
	if( x == 0 and y == 0 and IsInInstance() ) then
		return 0, 0, GetRealZoneText(), GetSubZoneText()
	end

	return tonumber(string.format("%.2f", x * 100)), tonumber(string.format("%.2f", y * 100)), zone, dungeonLevel
end

-- For recording a location by zone, primarily for fishing
function Recorder:RecordZoneLocation(type)
	local x, y, zone, level = self:RecordLocation()
	local zoneData = self:GetData("zone", ZONE_DIFFICULTY, zone)
	zoneData.coords = zoneData.coords or {}
	
	if( x == 0 and y == 0 and type(level) == "string" ) then
		for i=1, #(zoneData.coords), 5 do
			if( zoneData.coords[i] == 0 and zoneData.coords[i + 1] == 0 and zoneData.coords[i + 2] == zone and zoneData.coords[i + 3] == level ) then
				return zoneData
			end
		end
		
		table.insert(zoneData.coords, x)
		table.insert(zoneData.coords, y)
		table.insert(zoneData.coords, zone)
		table.insert(zoneData.coords, level)
		table.insert(zoneData.coords, 1)
		
		debug(3, "Recording %s location in %s (%s), no map found", type, zone, level)
		return zoneData
	end
	
	-- See if we already have an entry for them
	for i=1, #(zoneData.coords), 4 do
		local npcX, npcY, npcLevel, npcCount = zoneData.coords[i], zoneData.coords[i + 1], zoneData.coords[i + 2], zoneData.coords[i + 3]
		if( npcLevel == level ) then
			local xDiff, yDiff = math.abs(npcX - x), math.abs(npcY - y)
			if( xDiff <= ALLOWED_COORD_DIFF and yDiff <= ALLOWED_COORD_DIFF ) then
				zoneData.coords[i] = tonumber(string.format("%.2f", (npcX + x) / 2))
				zoneData.coords[i + 1] = tonumber(string.format("%.2f", (npcY + y) / 2))
				zoneData.coords[i + 4] = npcCount + 1
				
				debug(3, "Recording %s location at %.2f, %.2f in %s (%d floor), counter %d", type, x, y, zone, level, zoneData.coords[i + 4])
				return zoneData
			end
		end
	end
	
	table.insert(zoneData.coords, x)
	table.insert(zoneData.coords, y)
	table.insert(zoneData.coords, level)
	table.insert(zoneData.coords, 1)
	debug(3, "Recording %s location at %.2f, %.2f in %s (%d floor), counter %d", type, x, y, zone, level, 1)
	
	return zoneData
end

-- Location, location, location
function Recorder:RecordDataLocation(npcType, npcID)
	local x, y, zone, level = self:RecordLocation()
	local npcData = self:GetData(npcType, ZONE_DIFFICULTY, npcID)
	npcData.coords = npcData.coords or {}
	
	if( x == 0 and y == 0 and type(level) == "string" ) then
		for i=1, #(npcData.coords), 5 do
			if( npcData.coords[i] == 0 and npcData.coords[i + 1] == 0 and npcData.coords[i + 2] == zone and npcData.coords[i + 3] == level ) then
				return npcData
			end
		end
		
		table.insert(npcData.coords, x)
		table.insert(npcData.coords, y)
		table.insert(npcData.coords, zone)
		table.insert(npcData.coords, level)
		table.insert(npcData.coords, 1)
		
		debug(3, "Recording npc %s (%s) location in %s (%s), no map found", npcID, npcType, zone, level)
		return npcData
	end
	
	-- See if we already have an entry for them
	for i=1, #(npcData.coords), 5 do
		local npcX, npcY, npcZone, npcLevel, npcCount = npcData.coords[i], npcData.coords[i + 1], npcData.coords[i + 2], npcData.coords[i + 3], npcData.coords[i + 4]
		if( npcLevel == level and npcZone == zone ) then
			local xDiff, yDiff = math.abs(npcX - x), math.abs(npcY - y)
			if( xDiff <= ALLOWED_COORD_DIFF and yDiff <= ALLOWED_COORD_DIFF ) then
				npcData.coords[i] = tonumber(string.format("%.2f", (npcX + x) / 2))
				npcData.coords[i + 1] = tonumber(string.format("%.2f", (npcY + y) / 2))
				npcData.coords[i + 4] = npcCount + 1
				
				debug(3, "Recording npc %s (%s) location at %.2f, %.2f in %s (%d floor), counter %d", npcID, npcType, x, y, zone, level, npcData.coords[i + 4])
				return npcData
			end
		end
	end
	
	-- No data yet
	table.insert(npcData.coords, x)
	table.insert(npcData.coords, y)
	table.insert(npcData.coords, zone)
	table.insert(npcData.coords, level)
	table.insert(npcData.coords, 1)
	
	debug(3, "Recording npc %s location at %.2f, %.2f in %s (%d floor)", npcID, x, y, zone, level)
	return npcData
end

-- Add all of the data like title, health, power, faction, etc here
function Recorder:GetCreatureDB(unit)
	local guid = UnitGUID(unit)
	if not guid then return end
	
	local npcID, npcType = self.GUID_ID[guid], self.GUID_TYPE[guid]
	if not npcID or not npcType then return end
	
	return self:GetData(npcToDB[npcType], ZONE_DIFFICULTY, npcID), npcID, npcType
end

function Recorder:RecordCreatureType(npcData, type)
	npcData.info.bitType = npcData.info.bitType and bit.bor(npcData.info.bitType, NPC_TYPES[type]) or NPC_TYPES[type]
	debug(3, "Recording npc %s, type %s", npcData.info and npcData.info.name or "nil", type)
end

function Recorder:RecordCreatureData(type, unit)
	local npcData, npcID, npcType = self:GetCreatureDB(unit)
	if not npcData then return end

	local hasAura = UnitAura(unit, 1, "HARMFUL") or UnitAura(unit, 1, "HELPFUL")
	local level = UnitLevel(unit)
	local classification = UnitClassification(unit)
	if level == -1 and classification ~= "worldboss" then
		debug(4, "Discarding data: unit level too high")
		return
	end
	
	npcData.info = npcData.info or {}
	npcData.info.name = UnitName(unit)
	npcData.info.faction = self:GetFaction(UnitGUID(unit))
	npcData.info.factionGroup = UnitFactionGroup(unit)
	npcData.info.pvp = UnitIsPVP(unit)
	
	debug(3, "%s: faction %s, factionGroup %s", npcData.info.name, npcData.info.faction or "none", npcData.info.factionGroup or "none")
	
	if self.playerIsDrunk then
		debug(4, "Discarding data: player is drunk")
		return
	end
	-- Store by level for these
	if level then
		npcData.info[level] = npcData.info[level] or {}
		npcData.info[level].maxHealth = hasAura and npcData.info.maxHealth or npcData.info.maxHealth and math.max(npcData.info.maxHealth, UnitHealthMax(unit)) or UnitHealthMax(unit)
		npcData.info[level].maxPower = hasAura and npcData.info.maxPower or npcData.info.maxPower and math.min(npcData.info.maxPower, UnitPowerMax(unit)) or UnitPowerMax(unit)
		npcData.info[level].powerType = UnitPowerType(unit)
		
		debug(2, "%s (%s #%d) Level %d: %d health, %d power (%d type)", npcData.info.name, npcType, npcID, level, npcData.info[level].maxHealth or -1, npcData.info[level].maxPower or -1, npcData.info[level].powerType or -1)
	end
	
	if( type and type ~= "generic" ) then
		self:RecordCreatureType(npcData, type)
	end

	self:RecordDataLocation(npcToDB[npcType], npcID)
	return npcData
end

-- Record trainer data
local playerCache

function Recorder:UpdateTrainerData(npcData)
	-- No sense in recording training data unless the data was reset. It's not going to change
	if( npcData.teaches ) then return end
	
	local guid = UnitGUID("npc")
	local factionDiscount = self:GetFactionDiscount(guid)
	local trainerSpellMap = {}

	npcData.info.greeting = GetTrainerGreetingText()
	npcData.teaches = {}
	
	-- Save the original settings
	local availActive = GetTrainerServiceTypeFilter("available")
	local unavailActive = GetTrainerServiceTypeFilter("unavailable")
	local usedActive = GetTrainerServiceTypeFilter("used")
	SetTrainerServiceTypeFilter("available", 1)
	SetTrainerServiceTypeFilter("unavailable", 1)
	SetTrainerServiceTypeFilter("used", 1)	

	-- Cache the spell name -> spellID to reduce the need for associating spell names to spell ids manually
	if( not playerCache ) then
		playerCache = {}
		local offset, numSpells = select(3, GetSpellTabInfo(GetNumSpellTabs()))
		for id=1, (offset + numSpells) do
			local spellName, spellRank = GetSpellName(id, BOOKTYPE_SPELL)
			self.tooltip:SetOwner(UIParent, "ANCHOR_NONE")
			self.tooltip:SetSpell(id, BOOKTYPE_SPELL)
			
			local spellID = select(3, self.tooltip:GetSpell())
			if( spellID ) then
				if( spellRank and spellRank ~= "" ) then
					playerCache[string.format("%s (%s)", spellName, spellRank)] = spellID
				else
					playerCache[spellName] = spellID
				end
			end
		end
	end
	-- Scan everything!
	for serviceID=1, GetNumTrainerServices() do
		local serviceName, serviceSubText, serviceType, isExpanded = GetTrainerServiceInfo(serviceID)
		
		if( serviceType ~= "header" ) then
			local moneyCost, talentCost, skillCost = GetTrainerServiceCost(serviceID)
			self.tooltip:SetOwner(UIParent, "ANCHOR_NONE")
			self.tooltip:SetTrainerService(serviceID)
			
			local spellID = select(3, self.tooltip:GetSpell())
			if( spellID ) then
				-- Apparently :GetSpell() is not returning rank anymore?
				local spellName, spellRank = GetSpellInfo(spellID)
				
				-- Used for associating requirements with spellID if possible
				if( spellRank and spellRank ~= "" ) then
					trainerSpellMap[string.format("%s (%s)", spellName, spellRank)] = spellID
				else
					trainerSpellMap[spellName] = spellID
				end
				
				local teach = {["id"] = spellID, ["price"] = moneyCost / factionDiscount, ["levelReq"] = GetTrainerServiceLevelReq(serviceID)}
				
				-- For Typhoon (Rank 2)
				if( GetTrainerServiceNumAbilityReq(serviceID) > 0 ) then
					teach.abilityRequirements = {}
					
					-- Requirements are always listed before the ability required, Typhoon (Rank 2) is after Typhon (Rank 1)
					-- this shouldn't need any special "queuing" or rechecking
					for reqID=1, GetTrainerServiceNumAbilityReq(serviceID) do
						local reqName, hasReq = GetTrainerServiceAbilityReq(serviceID, reqID)
						table.insert(teach.abilityRequirements, trainerSpellMap[reqName] or playerCache[reqName] or reqName)
					end
				end
				
				-- For Enchanting (50) etc
				local skill, rank = GetTrainerServiceSkillReq(serviceID)
				teach.skillReq = skill
				teach.skillLevelReq = rank
				
				table.insert(npcData.teaches, teach)
			end
		end
	end
	
	-- Restore!				
	SetTrainerServiceTypeFilter("available", availActive or 0)
	SetTrainerServiceTypeFilter("unavailable", unavailActive or 0)
	SetTrainerServiceTypeFilter("used", usedActive or 0)
end

-- Record merchant items
local quickSoldMap = {}
function Recorder:UpdateMerchantData(npcData)
	if( CanMerchantRepair() ) then
		self:RecordCreatureType(npcData, "canrepair")
	end
	
	npcData.sold = npcData.sold or {}
	
	-- Setup a map so we don't have to loop over every entry every time
	table.wipe(quickSoldMap)
	for _, item in pairs(npcData.sold) do
		local id = item.id + item.price
		if( item.itemCost ) then
			for itemID, amount in pairs(item.itemCost) do
				id = id + itemID + amount
			end
		end
		
		quickSoldMap[id] = item
	end
	
	
	local factionDiscount = self:GetFactionDiscount(UnitGUID("npc"))
	for i=1, GetMerchantNumItems() do
		local name, _, price, quantity, limitedQuantity, _, extendedCost = GetMerchantItemInfo(i)
		if( name ) then
			local discard = false
			price = price / factionDiscount	
			
			local itemCost, bracket, rating
			local itemID = tonumber(string.match(GetMerchantItemLink(i), "item:(%d+)"))
			local quickID = itemID + price
			local honor, arena, total = GetMerchantItemCostInfo(i)
			-- If it costs honor or arena points, check for a personal rating
			if( honor > 0 or arena > 0 ) then
				rating, bracket = self:GetArenaData(i)
			end
			
			-- Check for item quest (Tokens -> Tier set/etc)
			for extendedIndex=1, total do
				local amount, link = select(2, GetMerchantItemCostItem(i, extendedIndex))
				local costItemID = link and tonumber(string.match(link, "item:(%d+)"))
				if( costItemID ) then
					itemCost = itemCost or {}
					itemCost[costItemID] = amount
					
					quickID = quickID + costItemID + amount
				else
					debug(3, "Item cost %i for %s not cached, discarding", extendedIndex, name)
					discard = true
				end
			end
			
			honor = honor > 0 and honor or nil
			arena = arena > 0 and arena or nil
			
			if not discard then -- Something went wrong/isn't cached
				local itemData = quickSoldMap[quickID]
				if( not itemData ) then
					itemData = {}
					table.insert(npcData.sold, itemData)
				else
					quantity = math.max(itemData.quantity, quantity)
					limitedQuantity = itemData.limitedQuantity and math.max(itemData.limitedQuantity, limitedQuantity)
				end

				itemData.id = itemID
				itemData.price = price
				itemData.quantity = quantity
				itemData.limitedQuantity = limitedQuantity and limitedQuantity > 0 and limitedQuantity or nil
				itemData.honor = honor
				itemData.arena = arena
				itemData.rating = rating
				itemData.bracket = bracket
				itemData.itemCost = itemCost
			end
		end
	end
end

-- LOOT TRACKING AND ALL HIS PALS
function Recorder:CHAT_MSG_ADDON(prefix, message, channel, sender)
	if( sender == playerName or prefix ~= "MMOC" or ( channel ~= "RAID" and channel ~= "PARTY" ) ) then return end
	
	local type, arg = string.split(":", message, 2)
	if( type == "loot" ) then
		lootedGUID[arg] = GetTime() + LOOT_EXPIRATION
	end
end

-- Simple unit find, mainly to account for things like Pick Pocketing where you can focus or mouseover a mob and use pick pocket
function Recorder:FindUnit(name)
	return UnitName("target") == name and "target" or UnitName("focus") == name and "focus" or UnitName("mouseover") == name and "mouseover"
end

-- Handle pickpocket errors
function Recorder:UI_ERROR_MESSAGE(event, message)
	if message == ERR_ALREADY_PICKPOCKETED then
		self.activeSpell.object = nil
	elseif message == SPELL_FAILED_TARGET_NO_POCKETS then
		if self.activeSpell.object and self.activeSpell.endTime <= (GetTime() + RECORD_TIMER) then
			local unit = self:FindUnit(self.activeSpell.target)
			if not unit then return end
			
			local npcData = self:GetCreatureDB(unit)
			npcData.info = npcData.info or {}
			npcData.info.noPockets = true
			
			debug(3, "Mob %s (%s) has no pockets", self.activeSpell.target, unit)
			self.activeSpell.object = nil
		end
	end
end

local COPPER_AMOUNT = string.gsub(COPPER_AMOUNT, "%%d", "(%%d+)")
local SILVER_AMOUNT = string.gsub(SILVER_AMOUNT, "%%d", "(%%d+)")
local GOLD_AMOUNT = string.gsub(GOLD_AMOUNT, "%%d", "(%%d+)")

-- So, why do this?
-- This fixes bugs when mass milling/prospecting mainly, where you have a macro with multiple /use's for different herbs or ores
-- the events/function calls are inaccurate due to it mostly falling through where it can. It's easier to just go by this method
-- even if it is slightly ugly :|
local locksAllowed = {}
function Recorder:FindByLock()
	for bag=4, 0, -1 do
		for slot=1, GetContainerNumSlots(bag) do
			-- Make sure the slot is locked
			if select(3, GetContainerItemInfo(bag, slot)) then
				local link = GetContainerItemLink(bag, slot)
				-- And we have an item in here of course, pretty sure this can't actually happen if it's locked, but to be safe
				if link then
					if locksAllowed[link] == 2 then -- We're expecting to match this one exactly, meaning we have an uniqueid
						return link
					else -- No uniqueid, strip it out and do an exact quick, assuming we're looking for an inequal
						local parseLink = select(2, GetItemInfo(string.match(link, "item:%d+")))
						if locksAllowed[parseLink] == 1 then
							return link
						end
					end
				end
			end
		end
	end
end

function Recorder:isDisenchantBug(itemID)
	-- During a disenchant roll, the item is transformed into its own
	-- disenchant loot after the end of the roll, before it goes into
	-- the winner's bag. Here, we ensure this doesn't get recorded.
	if GetNumPartyMembers() == 0 or GetNumRaidMembers() == 0 then return end -- Are we in a party/raid?
	if GetLootMethod() == "freeforall" then return end -- Is rolling enabled?
	if not DISENCHANT_LOOT[itemID] then return end -- Is the item a disenchant product?
	debug(3, "Item %i is a disenchant product. FAIL, Blizzard, FAIL!", itemID)
end

function Recorder:LOOT_CLOSED()
	self.activeSpell.object = nil
	table.wipe(locksAllowed)
end

function Recorder:LOOT_OPENED()
	local _, _, latency = GetNetStats()
	if latency > LOOT_MAX_LATENCY then
		debug(4, "Discarding loot because of lag")
		return
	end
	
	if IsFishingLoot() then
		debug(4, "Discarding fishing loot")
		return
	end
	
	local npcData, isMob
	local time = GetTime()
	local activeObject = self.activeSpell.object
	-- Object set, so looks like we're good
	if activeObject and self.activeSpell.endTime > 0 and (time - self.activeSpell.endTime) <= RECORD_TIMER then
		self.activeSpell.endTime = -1
		
		-- It has a location, meaning it's some sort of object
		if activeObject.location then
			npcData = self:RecordDataLocation("objects", self.activeSpell.target)
		-- Parent item, Milling, Prospecting, Looting items like Bags, etc
		elseif activeObject.parentItem then
			if activeObject.lootType then
				debug(4, "Discarding %s loot", activeObject.lootType)
				return
			end
			-- Throttle it by the items unique id, default to the last known link if finding by lock failed
			local itemID, uniqueID = string.match(self.activeSpell.useLock and self:FindByLock() or self.activeSpell.item, "item:(%d+):%d+:%d+:%d+:%d+:%d+:%d+:(-?%d+)")
			itemID = tonumber(itemID)
			uniqueID = tonumber(uniqueID)
			
			self.activeSpell.useLock = nil
			if not itemID then return end
			
			-- We're throttling it by the items unique id, this only applies to things that don't force auto loot, like Champion's Bags
			if activeObject.throttleByItem and uniqueID then
				if lootedGUID[uniqueID] then
					debug(4, "Discarding loot, %i already a looted GUID", uniqueID)
					return
				end
				lootedGUID[uniqueID] = time + LOOT_EXPIRATION
			end
			
			debug(4, "Looting item id %s, unique id %d", GetItemInfo(itemID), uniqueID)
			
			-- Still good
			npcData = self:GetBasicData("items", itemID)
			
		-- Has a parent NPC, so skinning, engineering, etc
		elseif activeObject.parentNPC then
			local unit = self:FindUnit(self.activeSpell.target)
			if not unit then return end
			
			npcData = self:GetCreatureDB(unit)
			npcData[activeObject.lootType] = npcData[activeObject.lootType] or {}
			npcData = npcData[activeObject.lootType]
		end
	
	-- If the target exists, is dead, not a player, and it's an actual tapped NPC then we will say we're looting that NPC
	elseif UnitExists("target") and UnitIsDead("target") and UnitIsTapped("target") and CheckInteractDistance("target", COORD_INTERACT_DISTANCE) then
		local guid = UnitGUID("target")
		if not guid or lootedGUID[guid] then return end
		
		lootedGUID[guid] = time + LOOT_EXPIRATION
		
		-- Make sure the GUID is /actually an NPC ones
		local npcID = self.GUID_TYPE[guid] == "npc" and self.GUID_ID[guid]
		if npcID then
			npcData = self:RecordCreatureData(nil, "target")
			isMob = true
			
			-- This is necessary because sending it just to raid or party without checking can cause not in raid errors
			local instanceType = select(2, IsInInstance())
			if( instanceType ~= "arena" and instanceType ~= "pvp" and ( GetNumPartyMembers() > 0 or GetNumRaidMembers() > 0 ) ) then
				SendAddonMessage("MMOC", string.format("loot:%s", guid), "RAID")
			end
		end
	end
	
	-- Clean up the list
	for guid, expiresOn in pairs(lootedGUID) do
		if expiresOn <= time then
			lootedGUID[guid] = nil
		end
	end
	
	if not npcData then return end
	npcData.looted = (npcData.looted or 0) + 1
	
	for i=1, GetNumLootItems() do
		-- Parse out coin
		if LootSlotIsCoin(i) then
			local currency = select(2, GetLootSlotInfo(i))
			local gold = (tonumber(string.match(currency, GOLD_AMOUNT)) or 0) * COPPER_PER_GOLD
			local silver = (tonumber(string.match(currency, SILVER_AMOUNT)) or 0) * COPPER_PER_SILVER
			
			npcData.coin = npcData.coin or {}
			table.insert(npcData.coin, (tonumber(string.match(currency, COPPER_AMOUNT)) or 0) + gold + silver)
			
			debug(2, "Found %d copper", npcData.coin[#(npcData.coin)])
		-- Record item data
		elseif LootSlotIsItem(i) then
			local link = GetLootSlotLink(i)
			local itemID = link and tonumber(string.match(link, "item:(%d+)"))
			if itemID and (not isMob or not self:isDisenchantBug(itemID)) then
				local quantity = select(3, GetLootSlotInfo(i))
				
				-- If we have an NPC ID then associate the npc with dropping that item
				npcData.loot = npcData.loot or {}
				npcData.loot[itemID] = npcData.loot[itemID] or {}
				npcData.loot[itemID].looted = (npcData.loot[itemID].looted or 0) + 1
				npcData.loot[itemID].minStack = npcData.loot[itemID].minStack and math.min(npcData.loot[itemID].minStack, quantity) or quantity
				npcData.loot[itemID].maxStack = npcData.loot[itemID].maxStack and math.max(npcData.loot[itemID].maxStack, quantity) or quantity
				
				local lootType = activeObject and activeObject.lootType or ""
				debug(2, "Looted item %s from them %d out of %d times (%s)", GetItemInfo(itemID), npcData.loot[itemID].looted, npcData.looted, lootType)
			else
				debug(4, "Loot slot %i makes no sense", i)
			end
		end
	end
	
-- 	debug(4, "Discarding loot, source is unknown")
end

-- Record items being opened
local function itemUsed(link, isExact)
	if not Recorder.activeSpell or not link then return end
	
	if Recorder.activeSpell.object and Recorder.activeSpell.object.parentItem and not Recorder.activeSpell.useSet then
		locksAllowed[link] = isExact and 2 or 1
		
		Recorder.activeSpell.item = link
		Recorder.activeSpell.useLock = true
		Recorder.activeSpell.useSet = true
	else
		locksAllowed[link] = isExact and 2 or 1
		
		Recorder.activeSpell.item = link
		Recorder.activeSpell.useLock = true
		Recorder.activeSpell.endTime = GetTime()
		Recorder.activeSpell.object = Recorder.InteractSpells.Bag
	end
end

hooksecurefunc("UseContainerItem", function(bag, slot, target)
	if not target then
		itemUsed(GetContainerItemLink(bag, slot), true)
	end
end)

hooksecurefunc("UseItemByName", function(name, target)
	if not target then
		itemUsed(select(2, GetItemInfo(name)))
	end
end)

function Recorder:UNIT_SPELLCAST_SENT(event, unit, name, rank, target)
	if unit ~= "player" or not self.InteractSpells[name] then return end
	
	local itemName, link = GameTooltip:GetItem()
	self.activeSpell.name = name
	self.activeSpell.rank = rank
	self.activeSpell.target = target
	self.activeSpell.startTime = GetTime()
	self.activeSpell.endTime = -1
	self.activeSpell.item = link
	self.activeSpell.useSet = nil
	self.activeSpell.object = self.InteractSpells[name]
end

function Recorder:UNIT_SPELLCAST_SUCCEEDED(event, unit, name, rank)
	if unit ~= "player" then return end
	
	if self.activeSpell.name == self.activeSpell.name and self.activeSpell.endTime == -1 and self.activeSpell.rank == rank then
		self.activeSpell.endTime = GetTime()
	end
end

function Recorder:UNIT_SPELLCAST_FAILED(event, unit)
	if unit ~= "player" then return end
	
	self.activeSpell.object = nil
end

-- QUEST DATA HANDLER
function Recorder:GetQuestName(questID)
	self.tooltip:SetOwner(UIParent, "ANCHOR_NONE")
	self.tooltip:SetHyperlink(string.format("quest:%d", questID))
	
	return RecorderTooltipTextLeft1:GetText()
end

local lastRecordedPOI = {}
function Recorder:RecordQuestPOI(questID)
	local posX, posY, objectiveID = select(2, QuestPOIGetIconInfo(questID))
	if( not posX or not posY or GetCurrentMapZone() == 0 ) then return end

	-- Quick ID so we're not saving the POIs every single map update, which tends to be a bit spammy
	local currentLevel = GetCurrentMapDungeonLevel()
	local poiID = posX + (currentLevel * 100) + (posY * 1000) + (objectiveID * 10000)
	if( lastRecordedPOI[questID] and lastRecordedPOI[questID] == poiID ) then return end
	lastRecordedPOI[questID] = poiID
	
	local questData = self:GetBasicData("quests", questID)
	questData.poi = questData.poi or  {}

	local currentZone = GetMapInfo()
	local posX, posY = tonumber(string.format("%.2f", posX * 100)), tonumber(string.format("%.2f", posY * 100))

	-- POIs don't change, if we find one with all the same data then we can just exit
	-- You can't simply index the table by objective ID and go by that because some quests can have different coords with the same objective
	for i=1, #(questData.poi), 5 do
		local dataX, dataY, dataObjectiveID, dataLevel, dataZone = questData.poi[i], questData.poi[i + 1], questData.poi[i + 2], questData.poi[i + 3], questData.poi[i + 4]
		if( dataZone == currentZone and dataLevel == currentLevel and dataObjectiveID == objectiveID and dataX == posX and dataY == posY ) then
			return
		end
	end
	
	table.insert(questData.poi, posX)
	table.insert(questData.poi, posY)
	table.insert(questData.poi, objectiveID)
	table.insert(questData.poi, currentLevel)
	table.insert(questData.poi, currentZone)

	debug(3, "Recording quest poi %s location at %.2f, %.2f, obj %d, in %s (%d floor)", questID, posX, posY, objectiveID, currentZone, currentLevel)
end

function Recorder:WORLD_MAP_UPDATE()
	for i=1, QuestMapUpdateAllQuests() do
		local questID, logIndex = QuestPOIGetQuestIDByVisibleIndex(i)
		if( questID and logIndex and logIndex > 0 ) then
			self:RecordQuestPOI(questID)
		end
	end
end

-- Quest log updated, see what changed quest-wise
local questGiverType, questGiverID
local tempQuestLog, questByName, questLog = {}, {}
function Recorder:QUEST_LOG_UPDATE(event)
	-- Scan quest log
	local foundQuests, index = 0, 1
	local numQuests = select(2, GetNumQuestLogEntries())
	while( foundQuests <= numQuests ) do
		local questName, _, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(index)
		if( not questName ) then break end
		
		if( not isHeader ) then
			foundQuests = foundQuests + 1
			
			tempQuestLog[questID] = true
		end
		
		index = index + 1
	end
	
	-- We don't have any previous data to go off of yet, store what we had
	if( not questLog ) then
		questLog = CopyTable(tempQuestLog)
		return
	end
		
	-- Find quests we accepted
	if( questGiverID ) then
		for questID in pairs(tempQuestLog) do
			if( not questLog[questID] and questGiverType ) then
				local questData = self:GetBasicData("quests", questID)
				questData.startsID = questGiverID * (questGiverType == "npc" and 1 or -1)
				
				for i=1, foundQuests do
					local logID = GetQuestIndexForTimer(i)
					if logID and select(9, GetQuestLogTitle(logID)) == questID then
						timer = select(i, GetQuestTimers())
						timer = math.ceil(timer / 10) * 10
						debug(4, "Found quest %i timer %i (%i orig)", questID, timer, select(i, GetQuestTimers()))
						
						questData.timer = questData.timer and math.max(questData.timer, timer) or timer
					end
				end
				
				debug(2, "Quest #%d starts at %s #%d", questID, questGiverType or "nil", questGiverID or -1)
				self:RecordQuestPOI(questID)
			end
		end
	end

	-- Find quests we abandoned or accepted
	for questID in pairs(questLog) do
		if( not tempQuestLog[questID] ) then
			if( abandonedName and abandonedName == self:GetQuestName(questID) ) then
				lastRecordedPOI[questID] = nil
				questLog[questID] = nil
				abandonedName = nil
				
				debug(2, "Quest #%d abandoned", questID)
				break
			elseif( not abandonedName and questGiverID ) then
				questLog[questID] = nil
				lastRecordedPOI[questID] = nil
				
				local questData = self:GetBasicData("quests", questID)
				questData.endsID = questGiverID * (questGiverType == "npc" and 1 or -1)
				
				debug(2, "Quest #%d ends at %s #%d.", questID, questGiverType or "nil", questGiverID or -1)	
			end
		end
	end
					
	for questID in pairs(tempQuestLog) do questLog[questID] = true end
	table.wipe(tempQuestLog)
end

function Recorder:QuestProgress()
	local guid = UnitGUID("npc")
	local id, type = self.GUID_ID[guid], self.GUID_TYPE[guid]
	
	-- Don't need to record start location of items
	if type ~= "item" then
		questGiverID, questGiverType = id, type
		self:RecordCreatureData(nil, "npc")
	end
end

function Recorder:QUEST_COMPLETE(event)
	self:QuestProgress()
end

-- We're looking at the details of the quest, save the quest info so we can use it later
function Recorder:QUEST_DETAIL(event)
	-- When a quest is shared with the player, "npc" is actually the "player" unitid
	if UnitIsPlayer("npc") then return end
	
	-- We don't want to record non-accepted quests
	if not IsQuestCompletable() then return end
	
	self:QuestProgress()
end

function Recorder:QUEST_PROGRESS()
	if not CheckUnit("npc") then return end
end

function Recorder:CheckUnit(unit)
	-- Check if the unit looks legit (generally used for "npc" unit)
	if not UnitExists(unit) or UnitIsDead(unit) or UnitIsPlayer(unit) then return false end
	return true
end

function Recorder:VehicleSeatIsPlayer(unit, seat)
	-- Heuristics to check if a vehicle seat is occupied by a player
	-- return nil if the seat is empty
	local type, name, realm = UnitVehicleSeatInfo(unit, seat)
	if not name then return end
	if realm then return true end
	if name:match("[%s'\"-]") then return false end -- Name contains illegal characters
	return true
end

-- Record data on target change
function Recorder:PLAYER_TARGET_CHANGED()
	if UnitExists("target") and not UnitPlayerControlled("target") and not UnitAffectingCombat("target") and CheckInteractDistance("target", COORD_INTERACT_DISTANCE) then
		for i=1, UnitVehicleSeatCount("target") do
			if self:VehicleSeatIsPlayer("target", i) then
				debug(4, "Skipped target record on %s (vehicle has non-empty seats)", UnitName("target"))
				return
			end
		end
		self:RecordCreatureData("generic", "target")
	end
end


-- General handling
function Recorder:AUCTION_HOUSE_SHOW()
	if not self:CheckUnit("npc") then return end
	
	self:RecordCreatureData("auctioneer", "npc")
end

function Recorder:MAIL_SHOW()
	if UnitIsDead("npc") or UnitIsPlayer("npc") then return end -- UnitExists on an object returns false
	
	self:RecordCreatureData("mailbox", "npc")
end

local merchantData
function Recorder:MERCHANT_SHOW()
	if not self:CheckUnit("npc") then return end
	
	merchantData = self:RecordCreatureData("vendor", "npc")
	if merchantData then
		self:UpdateMerchantData(merchantData)
	end
end

function Recorder:MERCHANT_UPDATE()
	self:UpdateMerchantData(merchantData)
end

function Recorder:TRAINER_SHOW()
	if not self:CheckUnit("npc") then return end
	
	local npcData = self:RecordCreatureData("trainer", "npc")
	if npcData then
		self:UpdateTrainerData(npcData)
	end
end

function Recorder:PET_STABLE_SHOW()
	if not self:CheckUnit("npc") then return end
	
	self:RecordCreatureData("stable", "npc")
end

function Recorder:TAXIMAP_OPENED()
	if not self:CheckUnit("npc") then return end
	
	local npcData = self:RecordCreatureData("flightmaster", "npc")
	if npcData then
		for i=1, NumTaxiNodes() do
			if TaxiNodeGetType(i) == "CURRENT" then
				npcData.info.taxiNode = TaxiNodeName(i)
				debug(3, "Set taxi node to %s.", npcData.info.taxiNode)
				break
			end
		end
	end
end

function Recorder:BANKFRAME_OPENED()
	if not self:CheckUnit("npc") then return end
	
	self:RecordCreatureData("bank", "npc")
end

function Recorder:CONFIRM_XP_LOSS()
	if not self:CheckUnit("npc") then return end
	if not CheckSpiritHealerDist() then return end -- Sanity range check
	
	self:RecordCreatureData("spiritres", "npc")
end

function Recorder:CONFIRM_BINDER()
	local unit = (self:CheckUnit("npc") and "npc") or (self:CheckUnit("target") and "target")
	if not unit then return end
	if not CheckBinderDist() then return end -- Sanity range check
	
	self:RecordCreatureData("binder", unit)
end

function Recorder:CONFIRM_TALENT_WIPE()
	if not self:CheckUnit("npc") then return end
	if not CheckTalentMasterDist() then return end -- Sanity range check
	
	self:RecordCreatureData("talentwipe", "npc")
end

function Recorder:GUILDBANKFRAME_OPENED()
	self:RecordCreatureData("guildbank", "npc")
end

function Recorder:BATTLEFIELDS_SHOW()
	if not self:CheckUnit("npc") then return end -- Despite appearances, it's still an interaction
	local type = BATTLEFIELD_TYPES[BATTLEFIELD_MAP[GetBattlefieldInfo()] or ""]
	if type then
		debug(4, "Unit %s is a battlemaster: %s (%i)", UnitName("npc"), GetBattlefieldInfo(), type)
		local npcData = self:RecordCreatureData("battlemaster", "npc")
		npcData.info.battlefields = type
	else
		debug(3, "Unknown battlemaster type:", GetBattlefieldInfo())
	end
end

function Recorder:PETITION_VENDOR_SHOW()
	if not self:CheckUnit("npc") then return end
	
	self:RecordCreatureData("arenaorg", "npc")
end

-- Record book locations
function Recorder:ITEM_TEXT_BEGIN()
	if ItemTextGetCreator() then return end -- true if the item is from an user, such as mail letters
	
	local guid = UnitGUID("npc")
	if self.GUID_TYPE[guid] then
		self:RecordDataLocation("objects", self.GUID_ID[guid])
	end
end

-- Gossip returns most of the types: banker, battlemaster, binder, gossip, tabard, taxi, trainer, vendor
-- It's a way of identifying what a NPC does without the player checking out every single option
local function checkGossip(...)
	local npcData = Recorder:RecordCreatureData(nil, "npc")
	
	for i=1, select("#", ...), 2 do
		local text, type = select(i, ...)
		if NPC_TYPES[type] then
			Recorder:RecordCreatureType(npcData, type)
		end
	end
end

function Recorder:GOSSIP_SHOW()
	-- Have more than one gossip
	if GetNumGossipAvailableQuests() > 0 or GetNumGossipActiveQuests() > 0 or GetNumGossipOptions() >= 2 then
		checkGossip(GetGossipOptions())
	-- No gossip, just grab the location
	elseif GetNumGossipAvailableQuests() == 0 and GetNumGossipActiveQuests() == 0 then
		self:RecordCreatureData(nil, "npc")
	end
end

-- Cache difficulty so we can't always rechecking it
function Recorder:UpdateDifficulty()
	if not IsInInstance() then
		ZONE_DIFFICULTY = "world"
		debug(2, "Player is not in a zone, set key to world")
		return
	end

	local instanceType, difficulty, _, maxPlayers, playerDifficulty, isDynamicInstance = select(2, GetInstanceInfo())
	local dungeonType = "normal"
	if( instanceType == "raid" ) then
		if (isDynamicInstance and playerDifficulty == 1) or (not isDynamicInstance and difficulty > 2) then
			dungeonType = "heroic"
		end
	elseif difficulty >= 2 then
		dungeonType = "heroic"
	end

	ZONE_DIFFICULTY = string.format("%s:%s:%s", instanceType, maxPlayers, dungeonType)
	debug(2, "Set zone key to %s", ZONE_DIFFICULTY)
end

Recorder.UPDATE_INSTANCE_INFO = Recorder.UpdateDifficulty
Recorder.PLAYER_DIFFICULTY_CHANGED = Recorder.UpdateDifficulty
Recorder.PLAYER_ENTERING_WORLD = Recorder.UpdateDifficulty
Recorder.ZONE_CHANGED_NEW_AREA = Recorder.UpdateDifficulty

-- Table writing
local function writeTable(tbl)
	local data = ""
	for key, value in pairs(tbl) do
		if key ~= "START_SERIALIZER" then
			local valueType = type(value)
			
			-- Wrap the key in brackets if it's a number
			if type(key) == "number" then
				key = string.format("[%s]", key)
				-- This will match any punctuation, spacing or control characters, basically anything that requires wrapping around them
			elseif string.match(key, "[%p%s%c%d]") then
				key = string.format("[\"%s\"]", key)
			end
			
			-- foo = {bar = 5}
			if valueType == "table" then
				data = string.format("%s%s=%s;", data, key, writeTable(value))
				-- foo = true / foo = 5
			elseif valueType == "number" or valueType == "boolean" then
				data = string.format("%s%s=%s;", data, key, tostring(value))
				-- foo = "bar"
			else
				data = string.format("%s%s=[[%s]];", data, key, tostring(value))
			end
		end
	end
	
	return "{" .. data .. "}"
end

local function serializeDatabase(tbl, db, parent)
	for key, value in pairs(tbl) do
		if type(value) == "table" then
			-- Find the serializer marker, so we know to just turn it into a string and don't go in farther
			if value.START_SERIALIZER then
				db[key] = writeTable(value)
			-- Still no serialize marker, so just keep building the structure
			else
				db[key] = db[key] or {}
				serializeDatabase(value, db[key], parent or key)
			end
		end
	end
end

-- Because serializing happens during logout, will save the error so users can report them still, without having BugGrabber
local function serializeError(msg)
	if not SigrieDB.error then
		SigrieDB.error = {msg = msg, trace = debugstack(2)}
	end
end

function Recorder:PLAYER_LOGOUT()
	local errorHandler = geterrorhandler()
	seterrorhandler(serializeError)
	serializeDatabase(self.db, SigrieDB)

	SigrieDB.factions = SigrieDB.factions or {}
	for faction in pairs(self.factions) do
		SigrieDB.factions[faction] = true
	end

	seterrorhandler(errorHandler)
end

-- General stuff
function Recorder:RegisterEvent(event) self.frame:RegisterEvent(event) end
function Recorder:UnregisterEvent(event) self.frame:UnregisterEvent(event) end
Recorder.frame = CreateFrame("Frame")
Recorder.frame:SetScript("OnEvent", function(self, event, ...) Recorder[event](Recorder, event, ...) end)
Recorder.frame:RegisterEvent("ADDON_LOADED")
Recorder.frame:Hide()


function Recorder:Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff33ff99MMOC Recorder|r: %s", msg))
end

SLASH_MMOCRECORDER1 = "/mmoc"
SLASH_MMOCRECORDER2 = "/mmochampion"
SlashCmdList["MMOCRECORDER"] = function(msg)
	msg = string.lower(msg or "")
	
	if msg == "reset" then
		if not StaticPopupDialogs["MMOCRECORD_CONFIRM_RESET"] then
			StaticPopupDialogs["MMOCRECORD_CONFIRM_RESET"] = {
				text = L["Are you sure you want to reset ALL data recorded?"],
				button1 = L["Yes"],
				button2 = L["No"],
				OnAccept = function()
					SigrieDB = nil
					Recorder.db = {}
					Recorder:InitializeDB()
					Recorder:Print(L["Reset all saved data for this character."])
				end,
				timeout = 30,
				whileDead = 1,
				hideOnEscape = 1,
			}
		end
		
		StaticPopup_Show("MMOCRECORD_CONFIRM_RESET")
	else
		Recorder:Print(L["Slash commands"])
		DEFAULT_CHAT_FRAME:AddMessage(L["/mmoc reset - Resets all saved data for this character"])
	end
end
