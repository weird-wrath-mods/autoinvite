-- luajit tests/ctra_sync_test.lua (from the addon dir)

gmatch, strmatch, format = string.gmatch, string.match, string.format

local handler
CreateFrame = function()
	return { RegisterEvent = function() end, SetScript = function(_, _, fn) handler = fn end }
end

-- roster: { name, rank, mt, ma }
local roster, officer, sent, printed
local function reset(r)
	roster, officer, sent, printed = r, true, {}, {}
end
GetNumRaidMembers = function() return #roster end
GetRaidRosterInfo = function(i) return roster[i][1], roster[i][2] end
UnitName = function(unit)
	if unit == "player" then return "Me" end
	return roster[tonumber(unit:match("raid(%d+)"))][1]
end
local function find(who)
	for i, r in ipairs(roster) do
		if "raid"..i == who or r[1] == who then return r end
	end
end
GetPartyAssignment = function(t, who)
	local r = find(who)
	return r and ((t == "MAINTANK" and r[3]) or (t == "MAINASSIST" and r[4])) or false
end
IsRaidLeader = function() return officer end
IsRaidOfficer = function() return false end
SendAddonMessage = function(p, m, c) sent[#sent + 1] = p.."|"..m.."|"..c end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) printed[#printed + 1] = m end }

dofile("CTRASync.lua")
local function roster_update() sent = {}; handler(nil, "RAID_ROSTER_UPDATE"); return sent end
local function ctra(msg, from) printed = {}; handler(nil, "CHAT_MSG_ADDON", "CTRA", msg, "RAID", from); return printed end

-- Blizzard -> CTRA
reset({ { "Me", 2 }, { "Tanky", 0, true }, { "Helpy", 1, false, true }, { "Pug", 0 } })
local s = roster_update()
assert(#s == 2 and s[1] == "CTRA|SET 1 Tanky|RAID" and s[2] == "CTRA|SET 2 Helpy|RAID")
assert(#roster_update() == 0, "no resend without change")

roster[2][3], roster[4][3] = false, true            -- MT moves Tanky -> Pug
s = roster_update()
assert(#s == 2 and s[1] == "CTRA|R Tanky|RAID" and s[2] == "CTRA|SET 1 Pug|RAID")

roster[4][3], roster[3][3], roster[3][4] = false, true, false  -- Helpy MA -> MT, no MA
s = roster_update()
assert(#s == 2 and s[1] == "CTRA|R Pug|RAID" and s[2] == "CTRA|SET 1 Helpy|RAID")

officer = false
roster[3][3] = false
assert(#roster_update() == 0, "non-officer must not send")
officer = true
s = roster_update()
assert(#s == 1 and s[1] == "CTRA|R Helpy|RAID", "catches up after promotion")

-- CTRA -> prompt
reset({ { "Me", 2 }, { "Tanky", 0, true }, { "Helpy", 1 }, { "Pug", 0 } })
assert(#ctra("SET 1 Tanky", "Helpy") == 0, "already matches")
local p = ctra("SET 1 Pug#SET 2 Tanky", "Helpy")
assert(#p == 2 and p[1]:find("Main Tank: Pug") and p[2]:find("Main Assist: Tanky"))
p = ctra("R Tanky", "Helpy")
assert(#p == 1 and p[1]:find("removed Tanky from Main Tank"))
assert(#ctra("SET 1 Pug", "Pug") == 0, "non-officer sender ignored")
assert(#ctra("SET 1 Pug", "Me") == 0, "own echo ignored")
assert(#ctra("SET 5 Pug", "Helpy") == 0, "slots beyond MA ignored")
officer = false
assert(#ctra("SET 1 Pug", "Helpy") == 0, "no prompt when we can't apply")

print("ctra_sync_test: all passed")
