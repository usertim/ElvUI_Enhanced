local E, L, V, P, G = unpack(ElvUI)
local ENP = E:NewModule("Enhanced_NamePlates", "AceHook-3.0", "AceEvent-3.0")
local NP = E:GetModule("NamePlates")
local M = E:GetModule("Misc")

local ipairs = ipairs
local next = next
local pairs = pairs
local sub = string.sub
local tinsert = table.insert

local UnitClass = UnitClass
local UnitIsPlayer = UnitIsPlayer
local UnitName = UnitName
local UnitReaction = UnitReaction
local GetGuildInfo = GetGuildInfo

local classMap = {}
local guildMap = {}

function ENP:UPDATE_MOUSEOVER_UNIT()
	if UnitIsPlayer("mouseover") and UnitReaction("mouseover", "player") ~= 2 then
		local name, realm = UnitName("mouseover")
		if realm or not name then return end

		if E.db.enhanced.nameplates.classCache then
			local _, class = UnitClass("mouseover")
			class = classMap[class]

			if EnhancedDB.UnitClass[name] ~= class then
				EnhancedDB.UnitClass[name] = class
			end
		end

		if E.db.enhanced.nameplates.titleCache then
			local guildName = GetGuildInfo("mouseover")
			if not guildName then return end

			if not guildMap[guildName] then
				tinsert(EnhancedDB.GuildList, guildName)
				guildMap[guildName] = #EnhancedDB.GuildList
			end

			if EnhancedDB.UnitTitle[name] ~= guildMap[guildName] then
				EnhancedDB.UnitTitle[name] = guildMap[guildName]
			end
		end
	end
end

-- Class Cache
local function UnitClassHook(self, frame, unitType)
	if unitType == "FRIENDLY_PLAYER" then
		local unitName = frame.UnitName
		local unit = self[unitType][unitName]
		if unit then
			local _, class = UnitClass(unit)
			if class then
				return class
			end
		elseif EnhancedDB.UnitClass[unitName] then
			return CLASS_SORT_ORDER[EnhancedDB.UnitClass[unitName]]
		else
			return NP:GetUnitClassByGUID(frame)
		end
	elseif unitType == "ENEMY_PLAYER" then
		local r, g, b = self:RoundColors(frame.oldHealthBar:GetStatusBarColor())
		for class in pairs(RAID_CLASS_COLORS) do -- ENEMY_PLAYER
			if RAID_CLASS_COLORS[class].r == r and RAID_CLASS_COLORS[class].g == g and RAID_CLASS_COLORS[class].b == b then
				return class
			end
		end
	end
end

function ENP:ClassCache()
	if E.db.enhanced.nameplates.classCache then
		if not self:IsHooked(NP, "UnitClass") then
			self:RawHook(NP, "UnitClass", UnitClassHook)
		end
	else
		if self:IsHooked(NP, "UnitClass") then
			self:Unhook(NP, "UnitClass")
		end
	end
end

-- Title Cache
local function UpdateElement_NameHook(self, frame)
	if not E.db.enhanced.nameplates.titleCache then return end

	if not self.db.units[frame.UnitType].healthbar.enable and not (self.db.alwaysShowTargetHealth and frame.isTarget) then
		if EnhancedDB.GuildList[EnhancedDB.UnitTitle[frame.UnitName]] then
			if not frame.Title then
				frame.Title = frame:CreateFontString(nil, "OVERLAY")
				frame.Title:SetWordWrap(false)
			end

			local db = E.db.enhanced.nameplates.guild
			frame.Title:SetFont(E.LSM:Fetch("font", db.font), db.fontSize, db.fontOutline)
			frame.Title:SetTextColor(db.color.r, db.color.g, db.color.b)
			frame.Title:SetPoint("TOP", frame.Name, "BOTTOM")
			frame.Title:SetFormattedText("%s %s %s", db.separator, EnhancedDB.GuildList[EnhancedDB.UnitTitle[frame.UnitName]], db.separator)
			frame.Title:Show()
		end
	end
end

function ENP:TitleCache()
	if E.db.enhanced.nameplates.titleCache then
		if not self:IsHooked(NP, "UpdateElement_Name") then
			self:Hook(NP, "UpdateElement_Name", UpdateElement_NameHook)
		end
	else
		if self:IsHooked(NP, "UpdateElement_Name") then
			self:Unhook(NP, "UpdateElement_Name")
		end
	end
end

-- Chat Bubbles
local events = {
	"CHAT_MSG_GUILD",
	"CHAT_MSG_OFFICER",
	"CHAT_MSG_PARTY",
	"CHAT_MSG_PARTY_LEADER",
	"CHAT_MSG_RAID",
	"CHAT_MSG_RAID_LEADER",
	"CHAT_MSG_RAID_WARNING",
	"CHAT_MSG_BATTLEGROUND",
	"CHAT_MSG_BATTLEGROUND_LEADER",
	"CHAT_MSG_CHANNEL",
	"CHAT_MSG_SAY",
	"CHAT_MSG_YELL",
}

local inactiveBubbles = {}

local function ReleaseBubble(frame)
	inactiveBubbles[#inactiveBubbles + 1] = frame
	frame:GetParent().bubbleFrame = nil
	frame:Hide()
end

local function FadeClosure(frame)
	if frame.fadeInfo.mode == "OUT" then
		ReleaseBubble(frame)
	end
end

local function Bubble_OnUpdate(self, elapsed)
	self.delay = self.delay - elapsed
	if self.delay <= 0 then
		self.delay = 0
		E:UIFrameFadeOut(self, .2, self:GetAlpha(), 0)
	end
end

local function CreateBubble()
	local frame = CreateFrame("Frame", nil, UIParent)
	frame:Hide()
	frame.text = frame:CreateFontString()
	frame.text:SetJustifyH("CENTER")
	frame.text:SetJustifyV("MIDDLE")
	frame.text:SetWordWrap(true)
	frame.text:SetNonSpaceWrap(true)
	frame:SetPoint("TOPLEFT", frame.text, -15, 15)
	frame:SetPoint("BOTTOMRIGHT", frame.text, 15, -15)
	M:SkinBubble(frame)

	frame.delay = 0
	frame.FadeObject = {
		finishedFuncKeep = true,
		finishedArg1 = frame,
		finishedFunc = FadeClosure
	}

	frame:SetScript("OnUpdate", Bubble_OnUpdate)

	return frame
end

local function AcquireBubble()
	local numInactiveObjects = #inactiveBubbles
	if numInactiveObjects > 0 then
		local frame = inactiveBubbles[numInactiveObjects]
		inactiveBubbles[numInactiveObjects] = nil
		return frame
	end

	return CreateBubble()
end

function ENP:FindNameplateByChatMsg(event, msg, author, _, _, _, _, _, channelID)
	if author == UnitName("player") then return end
	if not next(NP.VisiblePlates) then return end

	local chatType = sub(event, 10)
	if sub(chatType, 1, 7) == "CHANNEL" then
		chatType = "CHANNEL"..channelID
	end

	local info = ChatTypeInfo[chatType]
	if not info then return end

	for frame in pairs(NP.VisiblePlates) do
		if (frame.UnitType == "FRIENDLY_PLAYER" or frame.UnitType == "ENEMY_PLAYER") and frame.UnitName == author then
			local nameplateBubble
			if not frame.bubbleFrame then
				nameplateBubble = AcquireBubble()
				frame.bubbleFrame = nameplateBubble
				nameplateBubble:SetParent(frame)
				nameplateBubble.text:ClearAllPoints()
				nameplateBubble.text:SetPoint("BOTTOM", frame, "TOP", 0, 20)
				nameplateBubble:Show()
				E:UIFrameFadeIn(nameplateBubble, .2, 0, 1)
			else
				nameplateBubble = frame.bubbleFrame
			end

			nameplateBubble.text:SetSize(0, 0)
			nameplateBubble.text:SetText(msg)
			nameplateBubble.text:SetTextColor(info.r, info.g, info.b)

			if nameplateBubble.text:GetStringWidth() > 300 then
				nameplateBubble.text:SetWidth(300)
			end

			M.UpdateBubbleBorder(nameplateBubble)

			if nameplateBubble.delay == 0 then
				E:UIFrameFadeRemoveFrame(nameplateBubble)
				E:UIFrameFadeIn(nameplateBubble, .2, nameplateBubble:GetAlpha(), 1)
			end

			nameplateBubble.delay = 5
		end
	end
end

local function OnHideHook(frame)
	if frame.UnitFrame.bubbleFrame then
		ReleaseBubble(frame.UnitFrame.bubbleFrame)
	end
	if frame.UnitFrame.Title then
		frame.UnitFrame.Title:SetText()
		frame.UnitFrame.Title:Hide()
	end
end

function ENP:ChatBubbles()
	if E.db.enhanced.nameplates.chatBubbles then
		for _, event in ipairs(events) do
			ENP:RegisterEvent(event, "FindNameplateByChatMsg")
		end
	else
		for _, event in ipairs(events) do
			ENP:UnregisterEvent(event)
		end
	end
end

function ENP:UpdateAllSettings()
	self:ClassCache()
	self:ChatBubbles()
	self:TitleCache()

	if E.db.enhanced.nameplates.titleCache or E.db.enhanced.nameplates.classCache then
		self:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
	elseif not E.db.enhanced.nameplates.titleCache and not E.db.enhanced.nameplates.classCache then
		self:UnregisterEvent("UPDATE_MOUSEOVER_UNIT")
	end

	if E.db.enhanced.nameplates.chatBubbles or E.db.enhanced.nameplates.titleCache then
		if not ENP:IsHooked(NP, "OnHide") then
			ENP:Hook(NP, "OnHide", OnHideHook)
		end
	elseif not E.db.enhanced.nameplates.chatBubbles and not E.db.enhanced.nameplates.titleCache then
		if ENP:IsHooked(NP, "OnHide") then
			ENP:Unhook(NP, "OnHide")
		end
	end
end

function ENP:Initialize()
	EnhancedDB = EnhancedDB or {}
	EnhancedDB.UnitClass = EnhancedDB.UnitClass or {}
	EnhancedDB.UnitTitle = EnhancedDB.UnitTitle or {}

	if EnhancedDB.GuildList then
		for i, guildName in ipairs(EnhancedDB.GuildList) do
			guildMap[guildName] = i
		end
	else
		EnhancedDB.GuildList = {}
	end

	for i, class in ipairs(CLASS_SORT_ORDER) do
		classMap[class] = i
	end

	ENP:UpdateAllSettings()
end

local function InitializeCallback()
	ENP:Initialize()
end

E:RegisterModule(ENP:GetName(), InitializeCallback)