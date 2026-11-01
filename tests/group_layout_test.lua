-- luajit tests/group_layout_test.lua (from the addon dir)
format = string.format
CreateFrame = function()
	return setmetatable({}, { __index = function() return function() end end })
end
dofile("GroupLayout.lua")
local L = AutoInviteGroupLayout

local function roster(list) -- { {name, class, group}, ... }
	local r = {}
	for i, m in ipairs(list) do r[i] = { index = i, name = m[1], class = m[2], group = m[3] } end
	return r
end
local function snap(list)
	local s = {}
	for i, m in ipairs(list) do s[i] = { name = m[1], class = m[2], group = m[3] } end
	return s
end
-- fake server: apply ops, rejecting moves into full groups
local function apply(r, ops)
	local count = {}
	for _, m in ipairs(r) do count[m.group] = (count[m.group] or 0) + 1 end
	for _, op in ipairs(ops) do
		if op[1] == "set" then
			local m = r[op[2]]
			if (count[op[3]] or 0) < 5 then
				count[m.group] = count[m.group] - 1; m.group = op[3]; count[op[3]] = (count[op[3]] or 0) + 1
			end
		else
			r[op[2]].group, r[op[3]].group = r[op[3]].group, r[op[2]].group
		end
	end
end
local function converge(r, target)
	for _ = 1, 6 do
		local ops = L.Step(r, target)
		if #ops == 0 then return true end
		apply(r, ops)
	end
	return #L.Step(r, target) == 0
end
local function groupOf(r, name) for _, m in ipairs(r) do if m.name == name then return m.group end end end

-- two full groups fully swapped needs swaps, not sets
local base = {}
for i = 1, 5 do base[#base + 1] = { "A"..i, "WARRIOR", 1 } end
for i = 1, 5 do base[#base + 1] = { "B"..i, "PRIEST", 2 } end
local cur = {}
for i = 1, 5 do cur[#cur + 1] = { "A"..i, "WARRIOR", 2 } end
for i = 1, 5 do cur[#cur + 1] = { "B"..i, "PRIEST", 1 } end
local r = roster(cur)
local t, s = L.Plan(snap(base), r)
assert(s.name == 10 and s.class == 0 and s.free == 0)
assert(converge(r, t))
for i = 1, 5 do assert(groupOf(r, "A"..i) == 1 and groupOf(r, "B"..i) == 2) end

-- leaver A3 replaced by a warrior lands in A3's slot; a mage with no match fits anywhere
cur = {}
for i = 1, 5 do if i ~= 3 then cur[#cur + 1] = { "A"..i, "WARRIOR", 2 } end end
for i = 1, 5 do cur[#cur + 1] = { "B"..i, "PRIEST", 1 } end
cur[#cur + 1] = { "NewWar", "WARRIOR", 3 }
cur[#cur + 1] = { "NewMage", "MAGE", 3 }
r = roster(cur)
t, s = L.Plan(snap(base), r)
assert(s.name == 9 and s.class == 1 and s.free == 1, format("%d %d %d", s.name, s.class, s.free))
assert(t.NewWar == 1)
assert(converge(r, t))
assert(groupOf(r, "NewWar") == 1 and groupOf(r, "NewMage") == 3)

-- class match prefers a slot in the member's current group (no move)
t = L.Plan(snap({ { "X", "MAGE", 1 }, { "Y", "MAGE", 4 } }), roster({ { "Z", "MAGE", 4 } }))
assert(t.Z == 4)

-- unmatched member whose current group is claimed full gets bumped to a free group
base = {}
for i = 1, 5 do base[#base + 1] = { "P"..i, "ROGUE", 1 } end
cur = {}
for i = 1, 4 do cur[#cur + 1] = { "P"..i, "ROGUE", 2 } end
cur[#cur + 1] = { "Q", "MAGE", 1 }
cur[#cur + 1] = { "P5", "ROGUE", 1 }
r = roster(cur)
t = L.Plan(snap(base), r)
assert(t.Q ~= 1)
assert(converge(r, t))

-- randomized: shuffle a 25-man, replace some with same/different class, must converge legally
math.randomseed(1)
local classes = { "WARRIOR", "PRIEST", "MAGE", "ROGUE", "DRUID", "PALADIN" }
for trial = 1, 300 do
	local n = math.random(10, 40)
	base = {}
	for i = 1, n do base[i] = { "N"..i, classes[math.random(#classes)], math.floor((i - 1) / 5) + 1 } end
	local names = {}
	for i = 1, n do
		local m = base[i]
		local roll = math.random()
		if roll < 0.15 then names[#names + 1] = { "R"..i, m[2] }
		elseif roll < 0.25 then names[#names + 1] = { "R"..i, classes[math.random(#classes)] }
		elseif roll > 0.95 then -- leaver, no replacement
		else names[#names + 1] = { m[1], m[2] } end
	end
	for i = #names, 2, -1 do local j = math.random(i); names[i], names[j] = names[j], names[i] end
	cur = {}
	for i, m in ipairs(names) do cur[i] = { m[1], m[2], math.floor((i - 1) / 5) + 1 } end
	r = roster(cur)
	t = L.Plan(snap(base), r)
	assert(converge(r, t), "trial "..trial.." did not converge")
	local cnt = {}
	for _, m in ipairs(r) do cnt[m.group] = (cnt[m.group] or 0) + 1; assert(cnt[m.group] <= 5) end
	for _, m in ipairs(base) do
		local g = groupOf(r, m[1]); if g then assert(g == m[3], "trial "..trial.." "..m[1]) end
	end
end
print("group_layout_test: ok")
