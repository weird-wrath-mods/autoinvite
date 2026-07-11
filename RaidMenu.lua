-- RaidMenu: taint-free replacement for the Blizzard raid-grid right-click menu.
--
-- The stock menu breaks Set Main Tank / Set Main Assist once any insecure addon
-- injects an entry, because writing into the shared DropDownList frame taints it
-- and SetPartyAssignment is protected. Instead of adding to Blizzard's menu we
-- own our own: a protected menu frame whose MT/MA/Focus rows are
-- SecureActionButtonTemplate widgets (type "maintank"/"mainassist"/"focus"), so
-- the assignment runs inside Blizzard's SECURE_ACTIONS handler with no taint.
--
-- A restricted snippet, wrapped onto each RaidGroupButton's OnClick, opens and
-- retargets the menu at click time. That is the only path that works in combat:
-- showing/positioning a protected frame and setting the target unit are all
-- forbidden to insecure code under lockdown, but are legal inside the snippet.
-- The snippet sets a single "unit" attribute on the menu; secure rows inherit it
-- via useparent-unit, and plain rows read it back with GetAttribute.

local MENU_WIDTH = 150
local ROW_HEIGHT = 16
local PAD = 8

-- Fixed row set. We intentionally do not recompute per-row visibility the way
-- Blizzard's UnitPopup_HideButtons does: that logic needs IsRaidLeader /
-- GetLootMethod / GetPartyAssignment, none of which are callable from the
-- restricted environment, so it could not run in combat anyway. Rows whose
-- action does not apply (e.g. Master Looter when you are not leader) no-op
-- server-side, so showing them unconditionally is harmless.
-- check(unit, name) marks a row as stateful: it draws a checkmark when the
-- function returns truthy, refreshed each time the menu opens on a member.
local ROWS = {
	{ text = "Set Focus",          secure = true, type1 = "focus",
	  check = function(unit) return UnitIsUnit(unit, "focus") end },
	{ text = "Set Raid Leader",    run = function(name) PromoteToLeader(name) end,
	  check = function(unit)
		local n = tonumber(strmatch(unit, "raid(%d+)"))
		if n then local _, rank = GetRaidRosterInfo(n); return rank == 2 end
	  end },
	{ text = "Promote to Assistant", run = function(name) PromoteToAssistant(name) end,
	  check = function(unit) return UnitIsRaidOfficer(unit) end },
	{ text = "Set Main Tank",      secure = true, type1 = "maintank",  action = "toggle",
	  check = function(unit) return GetPartyAssignment("MAINTANK", unit) end },
	{ text = "Set Main Assist",    secure = true, type1 = "mainassist", action = "toggle",
	  check = function(unit) return GetPartyAssignment("MAINASSIST", unit) end },
	{ text = "Master Looter",      run = function(name) SetLootMethod("master", name) end,
	  check = function(unit)
		local method, _, mlRaid = GetLootMethod()
		return method == "master" and mlRaid and UnitIsUnit(unit, "raid"..mlRaid)
	  end },
	{ text = "Demote",             run = function(name) DemoteAssistant(name) end },
	{ text = "Remove",             run = function(name) UninviteUnit(name) end },
	{ text = "AutoPromote",        run = function(name) AutoInvite_TogglePromote(name) end,
	  check = function(unit, name) return AutoInvite_IsPromoteWatched(name) end },
	{ text = "Cancel",             cancel = true },
}

local menu

-- Row visuals copied from UIDropDownMenuButtonTemplate: 16px tall, left-aligned
-- GameFontHighlightSmallLeft text, and the same quest-title highlight shown on
-- mouseover. Returns the fontstring so the caller can size the menu to content.
local function StyleRow(row)
	row:SetHeight(ROW_HEIGHT)
	row:RegisterForClicks("LeftButtonUp")
	local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallLeft")
	-- Indent past the check gutter so checked and unchecked rows stay aligned.
	fs:SetPoint("LEFT", 18, 0)
	fs:SetPoint("RIGHT", -8, 0)
	fs:SetJustifyH("LEFT")
	row:SetFontString(fs)
	local hl = row:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
	hl:SetBlendMode("ADD")
	return fs
end

local function BuildMenu()
	if menu then return end

	-- SecureHandlerBaseTemplate gives the frame a restricted-env control so it
	-- can be the "header" that our wrapped snippets run against; SecureFrame
	-- (protected) is required so the snippet may Show/SetPoint/SetAttribute it
	-- in combat.
	menu = CreateFrame("Frame", "AIRaidMenu", UIParent, "SecureHandlerBaseTemplate")
	menu:SetFrameStrata("FULLSCREEN_DIALOG")
	menu:SetToplevel(true)
	menu:EnableMouse(true)
	menu:Hide()
	-- Tooltip backdrop + colors, matching Blizzard's dropdown MenuBackdrop.
	menu:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 5, right = 5, top = 5, bottom = 4 },
	})
	menu:SetBackdropColor(TOOLTIP_DEFAULT_BACKGROUND_COLOR.r, TOOLTIP_DEFAULT_BACKGROUND_COLOR.g, TOOLTIP_DEFAULT_BACKGROUND_COLOR.b)
	menu:SetBackdropBorderColor(TOOLTIP_DEFAULT_COLOR.r, TOOLTIP_DEFAULT_COLOR.g, TOOLTIP_DEFAULT_COLOR.b)

	-- Header row: the member's name, like the title Blizzard puts atop the menu.
	-- Filled on show (unit is only known once the snippet retargets us); SetText
	-- on a fontstring is not combat-restricted, so this is safe in lockdown.
	local title = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	title:SetPoint("TOP", 0, -PAD)
	title:SetHeight(ROW_HEIGHT)
	menu.title = title
	menu.UpdateChecks = function(self)
		local unit = self:GetAttribute("unit")
		local name = unit and UnitName(unit)
		for _, r in ipairs(self.checkRows) do
			if unit and r.checkFn(unit, name) then r.checkTex:Show() else r.checkTex:Hide() end
		end
	end
	menu:SetScript("OnShow", function(self)
		local unit = self:GetAttribute("unit")
		self.title:SetText((unit and UnitName(unit)) or "")
		self:UpdateChecks()
	end)

	local checkRows = {}
	local maxw = title:GetStringWidth()
	local y = -PAD - ROW_HEIGHT
	for i, def in ipairs(ROWS) do
		local row
		if def.secure then
			row = CreateFrame("Button", "AIRaidMenuRow"..i, menu, "SecureActionButtonTemplate")
			row:SetAttribute("type1", def.type1)
			row:SetAttribute("useparent-unit", true)
			if def.action then row:SetAttribute("action", def.action) end
		else
			row = CreateFrame("Button", "AIRaidMenuRow"..i, menu)
			if def.run then
				local run = def.run
				row:SetScript("OnClick", function()
					local unit = menu:GetAttribute("unit")
					local name = unit and UnitName(unit)
					if name then run(name) end
					menu:UpdateChecks()
				end)
			end
		end
		local fs = StyleRow(row)
		row:SetText(def.text)
		if def.check then
			local chk = row:CreateTexture(nil, "ARTWORK")
			chk:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
			chk:SetWidth(16)
			chk:SetHeight(16)
			chk:SetPoint("LEFT", 0, 0)
			chk:Hide()
			row.checkTex = chk
			row.checkFn = def.check
			checkRows[#checkRows + 1] = row
		end
		if def.cancel then y = y - 4 end  -- gap before Cancel, like UnitPopup space=1
		row:SetPoint("TOPLEFT", menu, "TOPLEFT", PAD, y)
		row:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -PAD, y)
		if fs:GetStringWidth() > maxw then maxw = fs:GetStringWidth() end

		-- Every row closes the menu on click, like Blizzard's menu. The hide
		-- postBody only runs when the preBody returns a non-nil message, so
		-- preBody returns (nil, true) (nil = don't remap the click button,
		-- true = the message that enables the hide). Checks refresh on reopen.
		SecureHandlerWrapScript(row, "OnClick", menu, "return nil, true", "owner:Hide()")

		y = y - ROW_HEIGHT
	end
	menu.checkRows = checkRows
	menu:SetWidth(math.max(MENU_WIDTH, maxw + 20 + PAD * 2))
	menu:SetHeight(-y + PAD)
end

-- Snippet run on each RaidGroupButton's OnClick. On right-click it retargets and
-- opens our menu at the cursor and returns false to suppress Blizzard's menu;
-- other buttons fall through so left-click targeting is unaffected.
-- Hide before re-showing so OnShow always re-fires (refreshing the title and
-- checks); Show() on an already-visible frame is a no-op and would leave them
-- stuck on whoever the menu first opened on.
local OPEN_SNIPPET = [[
	if button == "RightButton" then
		local unit = self:GetAttribute("ai-unit")
		if unit then
			owner:Hide()
			owner:SetAttribute("unit", unit)
			owner:ClearAllPoints()
			owner:SetPoint("TOPLEFT", "$cursor", 0, 0)
			owner:Show()
		end
		return false
	end
]]

local wrapped = {}

local function WrapGridButtons()
	if InCombatLockdown() then return end
	BuildMenu()
	for i = 1, MAX_RAID_MEMBERS do
		local b = _G["RaidGroupButton"..i]
		if b and not wrapped[b] then
			-- Expose the static per-slot unit as an attribute the snippet can
			-- read (the restricted env cannot see the Lua .unit field).
			b:SetAttribute("ai-unit", b.unit or ("raid"..i))
			SecureHandlerWrapScript(b, "OnClick", menu, OPEN_SNIPPET)
			wrapped[b] = true
		end
	end
end

-- Blizzard builds RaidGroupButtonN lazily in RaidGroupFrame_Update, so wrap
-- straight after each rebuild (the InCombatLockdown guard in WrapGridButtons
-- makes the hook a no-op during combat; PLAYER_REGEN_ENABLED catches up).
local hookedUpdate = false
local function HookRaidUI()
	if hookedUpdate then return end
	if RaidGroupFrame_Update then
		hooksecurefunc("RaidGroupFrame_Update", WrapGridButtons)
		hookedUpdate = true
	end
	WrapGridButtons()
end

local f = CreateFrame("Frame", "AIRaidMenuLoader")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("RAID_ROSTER_UPDATE")
f:RegisterEvent("PARTY_MEMBERS_CHANGED")
f:RegisterEvent("PLAYER_FOCUS_CHANGED")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == "Blizzard_RaidUI" then HookRaidUI() end
	elseif event == "PLAYER_LOGIN" then
		if IsAddOnLoaded("Blizzard_RaidUI") then HookRaidUI() end
	elseif event == "PLAYER_REGEN_ENABLED" or event == "RAID_ROSTER_UPDATE" then
		WrapGridButtons()
	end
	-- Refresh checks live so state changed elsewhere, or via a secure row that
	-- cannot refresh from its own click (MT/MA/Focus), appears while open.
	if menu and menu:IsShown() then menu:UpdateChecks() end
end)
