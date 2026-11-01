-- CTRASync: keep Blizzard MT/MA and the CTRA tank list (XPerl/CTRA/oRA) in step.
--
-- Blizzard -> CTRA is automatic: each roster update, an officer broadcasts any
-- change in MAINTANK/MAINASSIST as CTRA slot 1/2. Reading the roster rather than
-- hooking our menu catches every source (our menu, /maintank, other addons).
--
-- CTRA -> Blizzard can only be a prompt: SetPartyAssignment is protected, so an
-- addon-message handler can never call it. We print what changed and the
-- officer applies it from the raid menu.

local SLOTS = {
	{ type = "MAINTANK",   label = "Main Tank" },
	{ type = "MAINASSIST", label = "Main Assist" },
}

local function cprint(msg)
	DEFAULT_CHAT_FRAME:AddMessage(msg, 0.4, 0.7, 1)
end

local function IsOfficer()
	return IsRaidLeader() or IsRaidOfficer()
end

local sent = {}  -- slot -> name last broadcast

local function Broadcast()
	local n = GetNumRaidMembers()
	if n == 0 then sent = {}; return end
	-- Receivers ignore non-officers; leaving sent untouched means a later
	-- promotion broadcasts the current state.
	if not IsOfficer() then return end

	local cur = {}
	for i = 1, n do
		local unit = "raid"..i
		for s, def in ipairs(SLOTS) do
			if not cur[s] and GetPartyAssignment(def.type, unit) then
				cur[s] = UnitName(unit)
			end
		end
	end

	local removed = {}
	for s in ipairs(SLOTS) do
		local old = sent[s]
		if old and old ~= cur[1] and old ~= cur[2] and not removed[old] then
			removed[old] = true
			SendAddonMessage("CTRA", "R "..old, "RAID")
		end
	end
	for s in ipairs(SLOTS) do
		if cur[s] and cur[s] ~= sent[s] then
			SendAddonMessage("CTRA", "SET "..s.." "..cur[s], "RAID")
		end
	end
	sent = cur
end

local function SenderIsOfficer(sender)
	for i = 1, GetNumRaidMembers() do
		local name, rank = GetRaidRosterInfo(i)
		if name == sender then return rank >= 1 end
	end
end

-- CTRA batches several commands into one message, separated by '#'.
local function OnCTRA(msg, sender)
	if sender == UnitName("player") or not IsOfficer() or not SenderIsOfficer(sender) then return end
	for cmd in gmatch(msg, "[^#]+") do
		local num, name = strmatch(cmd, "^SET (%d+) (.+)$")
		local def = num and SLOTS[tonumber(num)]
		if def then
			if not GetPartyAssignment(def.type, name, 1) then
				cprint(format("%s set %s: %s. Open the raid menu to apply.", sender, def.label, name))
			end
		else
			name = strmatch(cmd, "^R (.+)$")
			if name then
				for _, d in ipairs(SLOTS) do
					if GetPartyAssignment(d.type, name, 1) then
						cprint(format("%s removed %s from %s. Open the raid menu to clear.", sender, name, d.label))
					end
				end
			end
		end
	end
end

local f = CreateFrame("Frame", "AICTRASync")
f:RegisterEvent("RAID_ROSTER_UPDATE")
f:RegisterEvent("CHAT_MSG_ADDON")
f:SetScript("OnEvent", function(self, event, prefix, msg, channel, sender)
	if event == "RAID_ROSTER_UPDATE" then
		Broadcast()
	elseif prefix == "CTRA" and channel == "RAID" then
		OnCTRA(msg, sender)
	end
end)
