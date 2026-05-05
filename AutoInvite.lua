-- AutoInvite (3.3.5 port + merge of AutoPromote)
-- Original 1.12: Ayradyss / Nathanmx / Weird Vibes / ehawne
-- Combines whisper-keyword auto invite, raid kick buttons, and
-- auto-promote-to-assistant.

local ADDON = "AutoInvite"
local VERSION = "0.8-wotlk"
local DEFAULT_INVITE = "+"

AutoInviteOptions = AutoInviteOptions or {}
AutoPromoteDB = AutoPromoteDB or {}

local Realm, Player

local function aprint(msg)
	DEFAULT_CHAT_FRAME:AddMessage(msg, 0.4, 0.7, 1)
end

local function opts()
	return AutoInviteOptions[Realm][Player]
end

----------------------------------------------------------------------
-- Init / saved variables
----------------------------------------------------------------------

local function InitAutoInvite()
	Player = UnitName("player")
	Realm = GetRealmName()
	AutoInviteOptions[Realm] = AutoInviteOptions[Realm] or {}
	AutoInviteOptions[Realm][Player] = AutoInviteOptions[Realm][Player] or {}
	local o = AutoInviteOptions[Realm][Player]
	if o.Invite == nil then o.Invite = DEFAULT_INVITE end
	if o.Type   == nil then o.Type   = "Raid" end
	-- Always start each session disabled; user must /ai on to enable.
	o.Status = "Off"
end

local function InitAutoPromote()
	AutoPromoteDB.watch_names = AutoPromoteDB.watch_names or {}
end

----------------------------------------------------------------------
-- Invite logic
----------------------------------------------------------------------

local function InviteOne(who)
	local gtype = opts().Type
	if gtype == "Party" then
		local numparty = GetNumPartyMembers()
		if numparty == 0 or (IsPartyLeader() and numparty < 4) then
			InviteUnit(who)
		elseif numparty >= 4 then
			aprint("Can't invite "..who..", party is full.")
		else
			aprint("Can't invite "..who..", you're not the party leader.")
		end
		return
	end

	-- Raid mode
	local numraid = GetNumRaidMembers()
	if numraid == 0 then
		local numparty = GetNumPartyMembers()
		if numparty == 0 then
			InviteUnit(who)
		elseif numparty < 4 then
			if IsPartyLeader() then
				InviteUnit(who)
			else
				aprint("Can't invite "..who..", you're not the party leader.")
			end
		elseif numparty == 4 then
			if IsPartyLeader() then
				aprint("Raid mode: converting your group to a raid.")
				ConvertToRaid()
				InviteUnit(who)
			else
				aprint("Can't invite "..who..", you're not the party leader.")
			end
		end
	elseif (IsRaidLeader() or IsRaidOfficer()) and numraid < 40 then
		InviteUnit(who)
	elseif numraid >= 40 then
		aprint("Can't invite "..who..", raid is full.")
	else
		aprint("Can't invite "..who..", you're not the raid leader/assist.")
	end
end

local function CheckMessage(what)
	local _, _, first = string.find(string.lower(what or ""), "^%s*(%S+)")
	return first and first == opts().Invite
end

----------------------------------------------------------------------
-- AutoInvite slash command
----------------------------------------------------------------------

local function PrintHelp()
	aprint("AutoInvite v"..VERSION.." (starts disabled each session):")
	aprint("  /ai on | off | party | raid")
	aprint("  /ai <keyword>  -- set the whisper keyword (current: "..opts().Invite..")")
	aprint("AutoPromote: right-click a raid member -> AutoPromote to toggle.")
end

local function AutoInvite_Slash(msg)
	if not Realm then aprint("AutoInvite still initializing, try again in a moment."); return end
	msg = msg or ""
	local lower = string.lower(msg)

	local o = opts()
	if msg == "" or lower == "help" then
		PrintHelp()
	elseif lower == "on" then
		o.Status = "On"; aprint("AutoInvite ON. Keyword: "..o.Invite)
	elseif lower == "off" then
		o.Status = "Off"; aprint("AutoInvite OFF.")
	elseif lower == "party" then
		o.Type = "Party"; aprint("AutoInvite: 5-man party mode.")
	elseif lower == "raid" then
		o.Type = "Raid"; aprint("AutoInvite: raid (40-man) mode.")
	else
		-- treat the whole input as the new keyword
		local _, _, kw = string.find(msg, "^%s*(.-)%s*$")
		o.Invite = string.lower(kw)
		aprint("AutoInvite: keyword set to '"..o.Invite.."'")
	end
end

SLASH_AUTOINVITE1 = "/autoinvite"
SLASH_AUTOINVITE2 = "/ai"
SlashCmdList["AUTOINVITE"] = AutoInvite_Slash

----------------------------------------------------------------------
-- AutoPromote logic
----------------------------------------------------------------------

local function Promote()
	if not IsRaidLeader() then return end
	for i = 1, GetNumRaidMembers() do
		local name, rank = GetRaidRosterInfo(i)
		if name and rank == 0 and AutoPromoteDB.watch_names[string.lower(name)] then
			PromoteToAssistant(name)
		end
	end
end

-- Add menu entry "AutoPromote" to right-click on raid members.
UnitPopupButtons["RAID_AUTOPROMOTE"] = { text = "AutoPromote", dist = 0, checkable = 1 }
do
	local raid = UnitPopupMenus["RAID"]
	if raid then
		local has = false
		for _, v in ipairs(raid) do if v == "RAID_AUTOPROMOTE" then has = true; break end end
		if not has then
			-- Insert before CANCEL if present, else append.
			local idx
			for i, v in ipairs(raid) do if v == "CANCEL" then idx = i; break end end
			if idx then table.insert(raid, idx, "RAID_AUTOPROMOTE") else table.insert(raid, "RAID_AUTOPROMOTE") end
		end
	end
end

hooksecurefunc("UnitPopup_OnClick", function(self)
	if self.value ~= "RAID_AUTOPROMOTE" then return end
	local dropdownFrame = UIDROPDOWNMENU_INIT_MENU
	local name = dropdownFrame and dropdownFrame.name
	if not name then return end
	local lname = string.lower(name)
	if AutoPromoteDB.watch_names[lname] then
		AutoPromoteDB.watch_names[lname] = nil
		aprint("AutoPromote: removed "..name)
		if IsRaidLeader() then DemoteAssistant(name) end
	else
		AutoPromoteDB.watch_names[lname] = true
		aprint("AutoPromote: added "..name)
		if IsRaidLeader() then PromoteToAssistant(name) end
	end
end)

-- Set the checkbox texture on our entry so toggle state is visible.
-- UnitPopup_ShowMenu builds the menu via UIDropDownMenu_AddButton; after it
-- returns, walk DropDownList<level>Button<i> and toggle the Check texture
-- on the button whose value is RAID_AUTOPROMOTE.
hooksecurefunc("UnitPopup_ShowMenu", function(dropdownMenu, which, unit, popupName)
	if which ~= "RAID" then return end
	local target = popupName or (unit and UnitName(unit))
	if not target then return end
	local checked = AutoPromoteDB.watch_names[string.lower(target)] and true or false
	local level = UIDROPDOWNMENU_MENU_LEVEL or 1
	for i = 1, (UIDROPDOWNMENU_MAXBUTTONS or 30) do
		local btn = _G["DropDownList"..level.."Button"..i]
		if btn and btn.value == "RAID_AUTOPROMOTE" then
			local check = _G[btn:GetName().."Check"]
			if check then
				if checked then check:Show() else check:Hide() end
			end
			return
		end
	end
end)

----------------------------------------------------------------------
-- Raid kick buttons (added to Raid tab)
----------------------------------------------------------------------

StaticPopupDialogs["AUTOINV_KICK_ALL"] = {
	text = "Kick all group members?",
	button1 = "Kick",
	button2 = "Cancel",
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	OnAccept = function()
		local rnum = GetNumRaidMembers()
		if rnum > 0 then
			for i = rnum, 1, -1 do
				local name = GetRaidRosterInfo(i)
				if name and name ~= UnitName("player") then UninviteUnit(name) end
			end
		else
			local pnum = GetNumPartyMembers()
			for i = pnum, 1, -1 do
				local name = UnitName("party"..i)
				if name then UninviteUnit(name) end
			end
		end
	end,
}

local kickAll, kickOfflines

local function CreateKickButtons()
	if kickAll or not RaidFrame then return end
	kickAll = CreateFrame("Button", "AutoInviteKickAllBtn", RaidFrame, "UIPanelButtonTemplate")
	kickAll:SetPoint("BOTTOMLEFT", RaidFrame, "TOPLEFT", 60, -10)
	kickAll:SetWidth(60); kickAll:SetHeight(20)
	kickAll:SetText("Kick All")
	kickAll:SetScript("OnClick", function() StaticPopup_Show("AUTOINV_KICK_ALL") end)

	kickOfflines = CreateFrame("Button", "AutoInviteKickOfflineBtn", RaidFrame, "UIPanelButtonTemplate")
	kickOfflines:SetPoint("LEFT", kickAll, "RIGHT", 0, 0)
	kickOfflines:SetWidth(90); kickOfflines:SetHeight(20)
	kickOfflines:SetText("Kick Offline")
	kickOfflines:SetScript("OnClick", function()
		local rnum = GetNumRaidMembers()
		if rnum > 0 then
			for i = 1, rnum do
				local name, _, _, _, _, _, _, online = GetRaidRosterInfo(i)
				if name and not online and name ~= UnitName("player") then UninviteUnit(name) end
			end
		else
			local pnum = GetNumPartyMembers()
			for i = 1, pnum do
				local unit = "party"..i
				if not UnitIsConnected(unit) then
					local name = UnitName(unit)
					if name then UninviteUnit(name) end
				end
			end
		end
	end)

	local function refresh()
		local has = (GetNumPartyMembers() + GetNumRaidMembers()) > 0
		if has then kickAll:Enable(); kickOfflines:Enable()
		else kickAll:Disable(); kickOfflines:Disable() end
	end
	refresh()
	if RaidFrame_Update then hooksecurefunc("RaidFrame_Update", refresh) end
	-- also refresh on roster changes since RaidFrame_Update only runs while the tab is visible
	kickAll:RegisterEvent("PARTY_MEMBERS_CHANGED")
	kickAll:RegisterEvent("RAID_ROSTER_UPDATE")
	kickAll:SetScript("OnEvent", refresh)
end

----------------------------------------------------------------------
-- Event dispatcher
----------------------------------------------------------------------

local rcount = 0
local f = CreateFrame("Frame", "AutoInviteFrame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("RAID_ROSTER_UPDATE")
f:RegisterEvent("CHAT_MSG_WHISPER")
f:RegisterEvent("CHAT_MSG_GUILD")

f:SetScript("OnEvent", function(self, event, ...)
	if event == "ADDON_LOADED" then
		local who = ...
		if who == ADDON then
			InitAutoInvite()
			InitAutoPromote()
			aprint("AutoInvite v"..VERSION.." loaded. /ai for help.")
			CreateKickButtons()
			self:UnregisterEvent("ADDON_LOADED")
		end
	elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
		CreateKickButtons()
		rcount = GetNumRaidMembers()
		Promote()
	elseif event == "RAID_ROSTER_UPDATE" then
		local n = GetNumRaidMembers()
		-- Always clear the cache when the raid is gone, regardless of leader
		-- status. Otherwise rcount sticks at the last-seen size and a
		-- same-headcount re-form skips Promote().
		if n == 0 then
			rcount = 0
		elseif IsRaidLeader() and n ~= rcount then
			rcount = n
			Promote()
		end
	elseif event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_GUILD" then
		if not Realm then return end
		if opts().Status == "On" then
			local what, who = ...
			if CheckMessage(what) then InviteOne(who) end
		end
	end
end)
