-- Every menu row must be protected so the secure owner:Hide() wrap fires; an
-- insecure menu:Hide() is blocked in combat and leaves the menu stuck open.
local frames, hides = {}, 0
local function newFrame(kind, name, parent, template)
	local f = { name = name, template = template, attrs = {}, scripts = {} }
	local mt = { __index = function(_, k)
		if k == "SetScript" then return function(self, s, fn) self.scripts[s] = fn end end
		if k == "SetAttribute" then return function(self, a, v) self.attrs[a] = v end end
		if k == "GetAttribute" then return function(self, a) return self.attrs[a] end end
		if k == "Hide" then return function(self) if self.name == "AIRaidMenu" then hides = hides + 1 end end end
		if k == "CreateFontString" then return function() return newFrame() end end
		if k == "CreateTexture" then return function() return newFrame() end end
		if k == "GetStringWidth" then return function() return 50 end end
		return function() end
	end }
	setmetatable(f, mt)
	if name then frames[name] = f end
	return f
end
CreateFrame = newFrame
UIParent = newFrame()
TOOLTIP_DEFAULT_BACKGROUND_COLOR = { r = 0, g = 0, b = 0 }
TOOLTIP_DEFAULT_COLOR = { r = 1, g = 1, b = 1 }
MAX_RAID_MEMBERS = 0
InCombatLockdown = function() return false end
IsAddOnLoaded = function() return true end
SecureHandlerWrapScript = function() end
hooksecurefunc = function() end
RaidGroupFrame_Update = function() end
UnitName = function() return "Bob" end
local ran = 0
UninviteUnit = function() ran = ran + 1 end
DemoteAssistant, PromoteToLeader, PromoteToAssistant, SetLootMethod = UninviteUnit, UninviteUnit, UninviteUnit, UninviteUnit
AutoInvite_TogglePromote = UninviteUnit

dofile((arg and arg[0]:match("^(.*)tests/") or "") .. "RaidMenu.lua")
frames.AIRaidMenuLoader.scripts.OnEvent(frames.AIRaidMenuLoader, "PLAYER_LOGIN")

local menu = frames.AIRaidMenu
assert(menu, "menu built")
menu.attrs.unit = "raid1"
hides = 0
local n = 0
for i = 1, 20 do
	local row = frames["AIRaidMenuRow" .. i]
	if row then
		n = n + 1
		assert(row.template == "SecureActionButtonTemplate" or row.template == "SecureFrameTemplate",
			"row " .. i .. " not protected")
		if row.scripts.OnClick then row.scripts.OnClick(row) end
	end
end
assert(n == 10, "expected 10 rows, got " .. n)
assert(hides == 0, "insecure menu:Hide() called " .. hides .. " times")
assert(ran == 6, "plain row actions ran " .. ran)
print("raid_menu_test ok")
