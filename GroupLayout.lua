-- Save / restore raid subgroup arrangement.
-- Restore matches current members to the snapshot by name first, then by
-- class for newcomers, so a replacement of the same class takes the leaver's
-- spot. Moves are applied in passes: each pass simulates the whole move set
-- locally, then waits for the roster to settle before re-checking, because
-- re-issuing a swap against a half-updated roster would undo it.

AutoInviteLayoutDB = AutoInviteLayoutDB or {}

local MAX_PASSES = 6
local SETTLE = 0.5

local function aprint(msg) DEFAULT_CHAT_FRAME:AddMessage(msg, 0.4, 0.7, 1) end

local function ReadRoster()
	local r = {}
	for i = 1, GetNumRaidMembers() do
		local name, _, group, _, _, class = GetRaidRosterInfo(i)
		if name then r[#r + 1] = { index = i, name = name, class = class, group = group } end
	end
	return r
end

-- saved: { {name, class, group}, ... }; roster: ReadRoster() shape.
-- Returns target[name] = group, plus counts of how each member was placed.
local function Plan(saved, roster)
	local target, used, fill = {}, {}, {}
	local byName, stats = {}, { name = 0, class = 0, free = 0 }
	for i, s in ipairs(saved) do byName[s.name] = i end
	local function take(m, i)
		used[i] = true
		target[m.name] = saved[i].group
		fill[saved[i].group] = (fill[saved[i].group] or 0) + 1
	end
	local rest = {}
	for _, m in ipairs(roster) do
		local i = byName[m.name]
		if i then take(m, i); stats.name = stats.name + 1 else rest[#rest + 1] = m end
	end
	local left = {}
	for _, m in ipairs(rest) do
		-- prefer a same-class slot in the member's current group: saves a move
		local pick
		for i, s in ipairs(saved) do
			if not used[i] and s.class == m.class and (not pick or s.group == m.group) then
				pick = i
				if s.group == m.group then break end
			end
		end
		if pick then take(m, pick); stats.class = stats.class + 1 else left[#left + 1] = m end
	end
	for _, m in ipairs(left) do
		local g = m.group
		if (fill[g] or 0) >= 5 then
			for k = 1, 8 do if (fill[k] or 0) < 5 then g = k; break end end
		end
		target[m.name] = g
		fill[g] = (fill[g] or 0) + 1
		stats.free = stats.free + 1
	end
	return target, stats
end

-- Returns a list of ops {"set", i, group} / {"swap", i, j}; empty when done.
local function Step(roster, target)
	local cur, count, ops = {}, {}, {}
	for _, m in ipairs(roster) do
		cur[m.index] = m.group
		count[m.group] = (count[m.group] or 0) + 1
	end
	for _, m in ipairs(roster) do
		local from, to = cur[m.index], target[m.name]
		if to and from ~= to then
			if (count[to] or 0) < 5 then
				ops[#ops + 1] = { "set", m.index, to }
				cur[m.index] = to
				count[from] = count[from] - 1
				count[to] = (count[to] or 0) + 1
			else
				-- swap with someone in the full group who doesn't belong there,
				-- preferring one who wants our current group
				local pick
				for _, o in ipairs(roster) do
					if cur[o.index] == to and target[o.name] ~= to then
						if not pick or target[o.name] == from then pick = o end
						if target[o.name] == from then break end
					end
				end
				if pick then
					ops[#ops + 1] = { "swap", m.index, pick.index }
					cur[pick.index], cur[m.index] = from, to
				end
			end
		end
	end
	return ops
end

AutoInviteGroupLayout = { Plan = Plan, Step = Step }

----------------------------------------------------------------------
-- Runtime
----------------------------------------------------------------------

local runner = CreateFrame("Frame")
local activeTarget, activeStats, passes, wait

local function stop() activeTarget = nil; runner:Hide() end

local function RunPass()
	if GetNumRaidMembers() == 0 or not (IsRaidLeader() or IsRaidOfficer()) then
		aprint("Group layout: restore stopped (not raid leader/assist).")
		return stop()
	end
	local ops = Step(ReadRoster(), activeTarget)
	if #ops == 0 then
		local st = activeStats
		aprint(format("Group layout restored: %d by name, %d by class, %d unmatched.", st.name, st.class, st.free))
		return stop()
	end
	passes = passes + 1
	if passes > MAX_PASSES then aprint("Group layout: gave up after "..MAX_PASSES.." passes."); return stop() end
	for _, op in ipairs(ops) do
		if op[1] == "set" then SetRaidSubgroup(op[2], op[3]) else SwapRaidSubgroup(op[2], op[3]) end
	end
	wait = SETTLE * 2 -- fallback if no roster event arrives
end

runner:Hide()
runner:SetScript("OnUpdate", function(_, elapsed)
	wait = wait - elapsed
	if wait <= 0 then RunPass() end
end)
runner:RegisterEvent("RAID_ROSTER_UPDATE")
runner:SetScript("OnEvent", function() if activeTarget then wait = SETTLE end end)

local function Start(target)
	activeTarget, passes = target, 0
	RunPass()
	if activeTarget then runner:Show() end
end

local function SaveLayout()
	local roster = ReadRoster()
	if #roster == 0 then aprint("Group layout: not in a raid."); return end
	local snap = {}
	for _, m in ipairs(roster) do snap[#snap + 1] = { name = m.name, class = m.class, group = m.group } end
	AutoInviteLayoutDB.saved = snap
	aprint("Group layout saved ("..#snap.." members).")
end

local function RestoreLayout()
	local saved = AutoInviteLayoutDB.saved
	if not saved then aprint("Group layout: nothing saved."); return end
	if GetNumRaidMembers() == 0 then aprint("Group layout: not in a raid."); return end
	if not (IsRaidLeader() or IsRaidOfficer()) then aprint("Group layout: need raid leader or assist."); return end
	local target, s = Plan(saved, ReadRoster())
	activeStats = s
	Start(target)
end

function AutoInvite_CreateLayoutButtons(anchor)
	if AutoInviteSaveLayoutBtn then return end
	local save = CreateFrame("Button", "AutoInviteSaveLayoutBtn", anchor:GetParent(), "UIPanelButtonTemplate")
	save:SetPoint("LEFT", anchor, "RIGHT", 40, 0)
	save:SetWidth(85); save:SetHeight(20)
	save:SetText("Save Groups")
	save:SetScript("OnClick", SaveLayout)

	local restore = CreateFrame("Button", "AutoInviteRestoreLayoutBtn", anchor:GetParent(), "UIPanelButtonTemplate")
	restore:SetPoint("LEFT", save, "RIGHT", 0, 0)
	restore:SetWidth(95); restore:SetHeight(20)
	restore:SetText("Restore Groups")
	restore:SetScript("OnClick", RestoreLayout)

	local function refresh()
		local inRaid = GetNumRaidMembers() > 0
		if inRaid then save:Enable() else save:Disable() end
		if inRaid and AutoInviteLayoutDB.saved and (IsRaidLeader() or IsRaidOfficer()) then
			restore:Enable() else restore:Disable()
		end
	end
	refresh()
	save:RegisterEvent("RAID_ROSTER_UPDATE")
	save:RegisterEvent("PARTY_MEMBERS_CHANGED")
	save:SetScript("OnEvent", refresh)
	save:HookScript("OnClick", refresh)
end
