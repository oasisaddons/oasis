-- Oasis: quest items - "Who has the quest item I need?"
-- Reads the required items (n/m) from your own quest log, finds quest items in the bags that
-- are left over (quest already done / more than needed), and shareable quests. Everything shared guild-wide
-- (one row per player, throttled) and matched against each other: who can help me, whom can I help.
local ADDON, ns = ...
ns.ModuleFile("Oasis_QuestItems", function()   -- Quest items module (can be disabled, see ModuleLoader.lua)
local L = ns.L
local K, C, Comm, Store = ns.K, ns.K.C, ns.Comm, ns.Store

local QI = {}
ns.QuestItems = QI
if ns.ICONS then ns.ICONS.questitems = ns.MEDIA .. "icons\\wants" end

local COLL = "qitems"            -- collection in the store (own message QIU, sync via QIREQ)
local KEEP = 3 * 86400           -- forget other players' entries after 3 days without a heartbeat
local MAX_NEED, MAX_SPARE, MAX_PUSH = 25, 25, 15
local SEND_MIN = 30              -- send at most every 30 s
local HEARTBEAT = 1800           -- resend at the latest every 30 min (heartbeat)
local TOAST_KEY_GAP, TOAST_GAP = 1800, 120
local FS, ES = "{", "}"          -- field / entry separator in the shared lists
local NOICON = 134400

local view = "help"              -- help | can | mine
local refreshPage                -- assigned further below
local lastSent, lastHash, sendPending = 0, nil, false
local toastAt, toastKeys = 0, {}
local demoMine = nil             -- Demo: own needs

local function S() return ns.db.settings end
local function demoOn() return ns.Demo and ns.Demo.IsActive and ns.Demo.IsActive() end
local function low(s) return s and tostring(s):lower() or "" end
local function clean(s) return (tostring(s or ""):gsub("[{}]", "")) end
local function myKey() return "qi:" .. Comm.whoKey(ns.me()) end
local function api(t, f) return t ~= nil and type(t[f]) == "function" end

------------------------------------------------------------------------
-- Read quest log
------------------------------------------------------------------------
-- "Zhevrahufe: 3/4", "3/4 Zhevrahufe", "- Zhevrahufe (3/4)" -> Name, n, m
local function parseObjective(text)
    text = ns.safe(text)
    if type(text) ~= "string" then return nil end
    local t = text:gsub("^%s*%-%s*", ""):gsub("%s+$", "")
    local name, a, b = t:match("^(.-)%s*:%s*(%d+)%s*/%s*(%d+)$")
    if not name then a, b, name = t:match("^(%d+)%s*/%s*(%d+)%s+(.+)$") end
    if not name then name, a, b = t:match("^(.-)%s*%((%d+)%s*/%s*(%d+)%)$") end
    if not name or name == "" then return nil end
    return name, tonumber(a), tonumber(b)
end
QI.ParseObjective = parseObjective

-- bags: name -> { id, n } (for name resolution and stock), plus quest info per slot
local function scanBags()
    local byName, slots = {}, {}
    local CC = C_Container
    if not (api(CC, "GetContainerNumSlots") and api(CC, "GetContainerItemInfo")) then return byName, slots end
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local ok, n = pcall(CC.GetContainerNumSlots, bag)
        for slot = 1, (ok and n or 0) do
            local ok2, info = pcall(CC.GetContainerItemInfo, bag, slot)
            local id = ok2 and type(info) == "table" and ns.safe(info.itemID)
            if id then
                local name = ns.safe(info.itemName) or (C_Item and C_Item.GetItemNameByID and ns.safe(C_Item.GetItemNameByID(id)))
                local cnt = ns.safe(info.stackCount) or 1
                if name then
                    local e = byName[low(name)] or { id = id, n = 0, name = name }
                    e.n = e.n + cnt
                    byName[low(name)] = e
                end
                local q
                if api(CC, "GetContainerItemQuestInfo") then
                    local ok3, qi = pcall(CC.GetContainerItemQuestInfo, bag, slot)
                    if ok3 and type(qi) == "table" then q = qi end
                end
                if q and (ns.safe(q.isQuestItem) or ns.safe(q.questID)) then
                    slots[#slots + 1] = { id = id, name = name, n = cnt, isQuest = ns.safe(q.isQuestItem) and true or false,
                        qid = tonumber(ns.safe(q.questID)), active = ns.safe(q.isActive) and true or false }
                end
            end
        end
    end
    return byName, slots
end

local function isDone(qid)
    local Q = C_QuestLog
    if not qid or not api(Q, "IsQuestFlaggedCompleted") then return false end
    local ok, r = pcall(Q.IsQuestFlaggedCompleted, qid)
    return ok and r == true
end
QI.IsDone = isDone

-- a quest's required items via the old API (name -> ID)
local function requiredLinks(qid, logIndex)
    local out = {}
    if not (GetNumQuestLogRequiredItems and GetQuestLogItemLink) then return out end
    local Q = C_QuestLog
    local prev = api(Q, "GetSelectedQuest") and select(2, pcall(Q.GetSelectedQuest)) or nil
    local sel = false
    if api(Q, "SetSelectedQuest") then sel = pcall(Q.SetSelectedQuest, qid)
    elseif SelectQuestLogEntry and logIndex then sel = pcall(SelectQuestLogEntry, logIndex) end
    if sel then
        local ok, n = pcall(GetNumQuestLogRequiredItems)
        for i = 1, (ok and tonumber(n) or 0) do
            local ok2, link = pcall(GetQuestLogItemLink, "required", i)
            local id = ok2 and ns.itemID(ns.safe(link))
            local nm = ok2 and type(link) == "string" and link:match("%[(.-)%]")
            if id and nm then out[low(nm)] = id end
        end
    end
    if prev and api(Q, "SetSelectedQuest") then pcall(Q.SetSelectedQuest, prev) end
    return out
end

local function nameCache()
    ns.db.qiNames = ns.db.qiNames or {}
    local loc = GetLocale and GetLocale() or "deDE"
    ns.db.qiNames[loc] = ns.db.qiNames[loc] or {}
    return ns.db.qiNames[loc]
end
-- item ID for a name: quest log link > bags > own memo > Oasis item search
local noID = {}   -- 0.5.726: don't search names without a hit again for 10 min (the item search was the expensive part: up to 80 ms per pass)
local function resolve(name, req, bags)
    local k = low(name)
    local id = (req and req[k]) or (bags and bags[k] and bags[k].id) or nameCache()[k]
    if not id and ns.ItemSearch and ns.ItemSearch.ExactID and not (noID[k] and GetTime() - noID[k] < 600) then
        local ok, r = pcall(ns.ItemSearch.ExactID, name)
        if ok then id = r end
        if not id then noID[k] = GetTime() end
    end
    if id then nameCache()[k] = id end
    return id
end

-- own quests: { id, title, lvl, done, push, needs = { {id, name, have, need, done} } }
function QI.MyQuests(bags)
    local out = {}
    local Q = C_QuestLog
    if not (api(Q, "GetNumQuestLogEntries") and api(Q, "GetInfo")) then return out, false end
    bags = bags or scanBags()
    local okN, num = pcall(Q.GetNumQuestLogEntries)
    local zone                       -- quest log header (zone) for grouping on the page
    for i = 1, (okN and tonumber(num) or 0) do
        local ok, info = pcall(Q.GetInfo, i)
        if ok and type(info) == "table" and info.isHeader then zone = ns.safe(info.title) end
        local qid = ok and type(info) == "table" and not info.isHeader and not info.isHidden and tonumber(ns.safe(info.questID))
        if qid then
            local q = { id = qid, title = ns.safe(info.title) or ("#" .. qid), lvl = tonumber(ns.safe(info.level)), needs = {}, zone = zone, logIndex = i }
            q.done = api(Q, "IsComplete") and select(2, pcall(Q.IsComplete, qid)) == true or false
            if api(Q, "IsPushableQuest") then
                local okP, p = pcall(Q.IsPushableQuest, qid)
                q.push = okP and p == true
            end
            local objs
            if api(Q, "GetQuestObjectives") then
                local okO, o = pcall(Q.GetQuestObjectives, qid)
                if okO and type(o) == "table" then objs = o end
            end
            local req
            for _, ob in ipairs(objs or {}) do
                if type(ob) == "table" and ns.safe(ob.type) == "item" then
                    local name, a, b = parseObjective(ob.text)
                    if name then
                        -- only fetch quest log links if bags and memo don't already know the name (SetSelectedQuest is expensive)
                        local lk = low(name)
                        if not req and not ((bags and bags[lk] and bags[lk].id) or nameCache()[lk]) then req = requiredLinks(qid, i) end
                        local have = tonumber(ns.safe(ob.numFulfilled)) or a or 0
                        local need = tonumber(ns.safe(ob.numRequired)) or b or 1
                        q.needs[#q.needs + 1] = { id = resolve(name, req, bags), name = name, have = have, need = need,
                            done = ns.safe(ob.finished) == true or have >= need }
                    end
                end
            end
            out[#out + 1] = q
        end
    end
    if demoOn() and demoMine then for _, q in ipairs(demoMine) do out[#out + 1] = q end end
    return out, true
end

-- remember item -> quest so leftovers are recognized as "quest completed" after turn-in
local function itemQuestMemo()
    ns.char.qiItemQuest = ns.char.qiItemQuest or {}
    return ns.char.qiItemQuest
end

-- leftover quest items in the bags: { id, name, n, qid, why = "d" (quest done) | "x" (more than needed) | "o" (no active quest) }
function QI.MySpare(quests, bags, slots)
    local out, seen = {}, {}
    local needBy = {}
    for _, q in ipairs(quests) do
        for _, nd in ipairs(q.needs) do
            needBy[low(nd.name)] = { q = q, nd = nd }
            if nd.id then itemQuestMemo()[nd.id] = q.id end
        end
    end
    for _, s in ipairs(slots or {}) do
        local key = s.id .. ":" .. (s.qid or 0)
        if not seen[key] then
            seen[key] = true
            local total = (bags[low(s.name)] and bags[low(s.name)].n) or s.n
            if s.qid and not s.active and isDone(s.qid) then
                out[#out + 1] = { id = s.id, name = s.name, n = total, qid = s.qid, why = "d" }
            elseif s.isQuest and not s.qid then
                local m = needBy[low(s.name)]
                if m then
                    if total > m.nd.need then out[#out + 1] = { id = s.id, name = s.name, n = total - m.nd.need, qid = m.q.id, why = "x" } end
                else
                    local qid = itemQuestMemo()[s.id]
                    out[#out + 1] = { id = s.id, name = s.name, n = total, qid = qid, why = (qid and isDone(qid)) and "d" or "o" }
                end
            end
        end
        if #out >= MAX_SPARE then break end
    end
    return out
end

------------------------------------------------------------------------
-- build, encode, send own state
------------------------------------------------------------------------
local function join(list, fn)
    local t = {}
    for _, x in ipairs(list) do t[#t + 1] = fn(x) end
    return table.concat(t, ES)
end
local function split(s)
    local out = {}
    for e in (s or ""):gmatch("[^" .. ES .. "]+") do
        local f = {}
        for v in (e .. FS):gmatch("(.-)" .. FS) do f[#f + 1] = v end
        out[#out + 1] = f
    end
    return out
end

function QI.Snapshot(bags, slots, quests, ok)
    if not bags then bags, slots = scanBags() end
    if not quests then quests, ok = QI.MyQuests(bags) end
    local needs, push, titles, tset = {}, {}, {}, {}
    local function title(q) if not tset[q.id] then tset[q.id] = true titles[#titles + 1] = q end end
    for _, q in ipairs(quests) do
        if not q.demo then
            for _, nd in ipairs(q.needs) do
                if not nd.done and #needs < MAX_NEED then needs[#needs + 1] = { nd = nd, q = q } title(q) end
            end
            if q.push and not q.done and #push < MAX_PUSH then push[#push + 1] = q title(q) end
        end
    end
    local spare = {}
    for _, s in ipairs(QI.MySpare(quests, bags, slots)) do
        spare[#spare + 1] = s
        if s.qid then
            local t = C_QuestLog and api(C_QuestLog, "GetTitleForQuestID") and ns.safe(select(2, pcall(C_QuestLog.GetTitleForQuestID, s.qid)))
            if t and not tset[s.qid] then tset[s.qid] = true titles[#titles + 1] = { id = s.qid, title = t } end
        end
    end
    local rec = {
        id = myKey(), who = ns.me(),
        n = join(needs, function(x) return (x.nd.id or 0) .. FS .. clean(x.nd.name) .. FS .. x.q.id .. FS .. x.nd.have .. FS .. x.nd.need end),
        s = join(spare, function(x) return x.id .. FS .. clean(x.name) .. FS .. x.n .. FS .. (x.qid or 0) .. FS .. x.why end),
        p = join(push, function(q) return tostring(q.id) end),
        t = join(titles, function(q) return q.id .. FS .. clean(q.title) end),
        lv = ns.safe(UnitLevel("player")),
    }
    return rec, quests, spare, ok
end

local sendNow
local function publishSnapshot(force, rec)
    if not ns.loggedIn or not IsInGuild() then return end
    if S().qiShare == false then return end
    local h = ns.hash((rec.n or "") .. "|" .. (rec.s or "") .. "|" .. (rec.p or ""))
    local now = ns.now()
    if not force and h == lastHash and now - lastSent < HEARTBEAT then return end
    if now - lastSent < SEND_MIN then
        -- throttled: try again later
        if not sendPending then
            sendPending = true
            ns.After(SEND_MIN - (now - lastSent) + 1, function() sendPending = false sendNow(force) end)
        end
        return
    end
    lastSent, lastHash = now, h
    rec.u = now
    rec.by = rec.who
    Store.merge(COLL, rec)
    Comm.Guild("QIU", Comm.encodeRecord(rec))
end
-- scan across three frames: bags, quest log and evaluation get separate script time budgets.
local scanPending, pendingForce
sendNow = function(force)
    if not ns.loggedIn or not IsInGuild() or S().qiShare == false then return end
    pendingForce = pendingForce or force
    if scanPending then return end
    scanPending = true
    ns.After(0, function()
        local okB, bags, slots = pcall(scanBags)
        if not okB then scanPending = nil ns.err("Questitems Taschen", bags) return end
        ns.After(0, function()
            local okQ, quests, complete = pcall(QI.MyQuests, bags)
            if not okQ then scanPending = nil ns.err("Questitems Quests", quests) return end
            ns.After(0, function()
                local okS, rec = pcall(QI.Snapshot, bags, slots, quests, complete)
                local wanted = pendingForce
                scanPending, pendingForce = nil, nil
                if okS and complete then publishSnapshot(wanted, rec)
                elseif not okS then ns.err("Questitems Auswertung", rec) end
            end)
        end)
    end)
end
QI.Send = sendNow

local pend
local function changed()
    if pend then return end
    pend = true
    ns.After(8, function()
        pend = nil
        sendNow(false)
        if refreshPage then refreshPage() end
    end)
end
ns.On("QUEST_LOG_UPDATE", changed)
ns.On("QUEST_ACCEPTED", changed)
ns.On("QUEST_REMOVED", changed)
ns.On("QUEST_TURNED_IN", changed)
ns.On("BAG_UPDATE_DELAYED", changed)
ns.On("GROUP_ROSTER_UPDATE", function() if refreshPage then refreshPage() end end)

-- receive: only accept the sender's own entry
Comm.On("QIU", function(sender, _, recStr)
    if not recStr then return end
    local rec = Comm.decodeRecord(recStr)
    if not rec then return end
    if rec.id ~= "qi:" .. Comm.whoKey(sender) then return end
    rec.who, rec.by, rec.mb, rec.demo = sender, sender, nil, nil
    rec.u = math.min(tonumber(rec.u) or ns.now(), ns.now() + 300)   -- no time in the future
    Store.merge(COLL, rec, true, sender)
end)
-- sync: newcomers ask; everyone answers with their own entry (randomly delayed, throttled)
local reqPending = false
Comm.On("QIREQ", function()
    if reqPending or S().qiShare == false then return end
    reqPending = true
    ns.After(math.random(20, 120) / 10, function()
        reqPending = false
        if ns.now() - lastSent > 60 then sendNow(true) end
    end)
end)

local function prune()
    local c = Store.coll(COLL)
    local now = ns.now()
    for id, r in pairs(c) do
        if not r.demo and now - (r.u or 0) > KEEP then c[id] = nil end
    end
end

------------------------------------------------------------------------
-- Sync
------------------------------------------------------------------------
local function parseRec(r)
    if r._p and r._pu == r.u then return r._p end
    local titles = {}
    for _, f in ipairs(split(r.t)) do titles[tonumber(f[1]) or 0] = f[2] end
    local p = { needs = {}, spare = {}, push = {}, titles = titles }
    for _, f in ipairs(split(r.n)) do
        local id = tonumber(f[1])
        p.needs[#p.needs + 1] = { id = (id and id > 0) and id or nil, name = f[2] or "?", qid = tonumber(f[3]), have = tonumber(f[4]) or 0, need = tonumber(f[5]) or 1 }
    end
    for _, f in ipairs(split(r.s)) do
        local q = tonumber(f[4])
        p.spare[#p.spare + 1] = { id = tonumber(f[1]), name = f[2] or "?", n = tonumber(f[3]) or 1, qid = (q and q > 0) and q or nil, why = f[5] or "o" }
    end
    for q in (r.p or ""):gmatch("%d+") do p.push[#p.push + 1] = tonumber(q) end
    r._p, r._pu = p, r.u
    return p
end

local function sameItem(a, b)
    if a.id and b.id then return a.id == b.id end
    return low(a.name) == low(b.name)
end
local function online(who)
    if ns.Radar and ns.Radar.IsOnline and ns.Radar.IsOnline(who) then return true end
    local m = ns.Radar and ns.Radar.byName and ns.Radar.byName[ns.fullName(who)]
    return m and m.online or false
end
QI.Online = online
local function questTitle(qid, titles)
    if not qid then return nil end
    if titles and titles[qid] then return titles[qid] end
    if C_QuestLog and api(C_QuestLog, "GetTitleForQuestID") then
        local ok, t = pcall(C_QuestLog.GetTitleForQuestID, qid)
        if ok and ns.safe(t) then return t end
    end
    return "#" .. qid
end
QI.QuestTitle = questTitle

local function others()
    local out = {}
    for _, r in ipairs(Store.List(COLL)) do
        if r.who and not ns.isMe(r.who) and r.id ~= myKey() and (demoOn() or not r.demo) then out[#out + 1] = r end
    end
    return out
end
QI.Others = others
-- 0.6.524: [itemID] = { { who, title, have, need }, ... } - others' open quest item needs (bags & alts)
function QI.NeedsByItem()
    local out = {}
    for _, r in ipairs(others()) do
        local p = parseRec(r)
        for _, o in ipairs(p.needs) do
            if o.id and (o.have or 0) < (o.need or 1) then
                out[o.id] = out[o.id] or {}
                table.insert(out[o.id], { who = r.who, title = p.titles[o.qid or 0], have = o.have, need = o.need })
            end
        end
    end
    return out
end

local function inGroup(who)
    if ns.Social and ns.Social.InMyGroup then return ns.Social.InMyGroup(who) end
    return false
end
-- member with quest list (profile field qs from Quest together)
local function profileQuests(name)
    local key = Comm.whoKey(name)
    for n, p in pairs(ns.db.members or {}) do
        if Comm.whoKey(n) == key and p.qs then
            local set = {}
            for id in p.qs:gmatch("%d+") do set[tonumber(id)] = true end
            return set
        end
    end
end

-- help for me: for each of my open item goals the players who have it left over / also collect it; shareable quests
function QI.HelpForMe(quests)
    local rows = {}
    local list = others()
    local mine = {}
    for _, q in ipairs(quests) do mine[q.id] = true end
    for _, q in ipairs(quests) do
        for _, nd in ipairs(q.needs) do
            if not nd.done then
                local row = { kind = "need", q = q, nd = nd, givers = {}, farmers = {} }
                for _, r in ipairs(list) do
                    local p = parseRec(r)
                    for _, s in ipairs(p.spare) do
                        if sameItem(s, nd) then row.givers[#row.givers + 1] = { who = r.who, n = s.n, why = s.why, on = online(r.who), demo = r.demo } break end
                    end
                    for _, o in ipairs(p.needs) do
                        if sameItem(o, nd) then
                            row.farmers[#row.farmers + 1] = { who = r.who, have = o.have, need = o.need, same = o.qid == q.id, on = online(r.who), demo = r.demo }
                            break
                        end
                    end
                end
                local function byOn(a, b) if a.on ~= b.on then return a.on end return (a.n or 0) > (b.n or 0) end
                table.sort(row.givers, byOn)
                table.sort(row.farmers, byOn)
                rows[#rows + 1] = row
            end
        end
    end
    -- quests someone (online) can share with me
    for _, r in ipairs(list) do
        if online(r.who) then
            local p = parseRec(r)
            for _, qid in ipairs(p.push) do
                if not mine[qid] and not isDone(qid) then
                    rows[#rows + 1] = { kind = "push", qid = qid, title = questTitle(qid, p.titles), who = r.who, on = true, demo = r.demo }
                end
            end
        end
    end
    table.sort(rows, function(a, b)
        local sa = a.kind == "need" and (#a.givers > 0 and 0 or #a.farmers > 0 and 1 or 3) or 2
        local sb = b.kind == "need" and (#b.givers > 0 and 0 or #b.farmers > 0 and 1 or 3) or 2
        if sa ~= sb then return sa < sb end
        local na = a.nd and a.nd.name or a.title or ""
        local nb = b.nd and b.nd.name or b.title or ""
        return na < nb
    end)
    return rows
end

-- I can help: who needs something I have (leftover or in the bags); whom in the group can I share a quest with
function QI.ICanHelp(quests, spare, bags)
    local rows = {}
    local needMine = {}
    for _, q in ipairs(quests) do for _, nd in ipairs(q.needs) do needMine[low(nd.name)] = nd end end
    for _, r in ipairs(others()) do
        local p = parseRec(r)
        for _, o in ipairs(p.needs) do
            local have, why = 0, nil
            for _, s in ipairs(spare) do if sameItem(s, o) then have, why = s.n, s.why break end end
            if have == 0 and bags then
                local b = bags[low(o.name)]
                local mineNd = needMine[low(o.name)]
                -- in the bags but needed myself -> only the surplus counts
                if b then have = math.max(0, b.n - (mineNd and mineNd.need or 0)) why = "b" end
            end
            if have > 0 then
                rows[#rows + 1] = { kind = "give", who = r.who, o = o, have = have, why = why, title = questTitle(o.qid, p.titles), on = online(r.who), demo = r.demo }
            end
        end
    end
    -- share quest: group members without this quest
    if IsInGroup and IsInGroup() then
        local raid = IsInRaid and IsInRaid()
        for _, q in ipairs(quests) do
            if q.push and not q.done then
                local missing = {}
                for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do
                    local u = raid and ("raid" .. i) or ("party" .. i)
                    if UnitExists(u) and not UnitIsUnit(u, "player") then
                        local n = ns.safe(ns.UnitName(u))
                        local set = n and profileQuests(n)
                        if n and not (set and set[q.id]) then missing[#missing + 1] = n end
                    end
                end
                if #missing > 0 then rows[#rows + 1] = { kind = "share", q = q, who = missing[1], names = missing, on = true } end
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.on ~= b.on then return a.on end
        if a.kind ~= b.kind then return a.kind == "share" end
        return (a.o and a.o.name or "") < (b.o and b.o.name or "")
    end)
    return rows
end

------------------------------------------------------------------------
-- Actions
------------------------------------------------------------------------
local function linkOf(id, name)
    if id and ns.ItemSearch and ns.ItemSearch.Link then
        local ok, l = pcall(ns.ItemSearch.Link, id)
        if ok and l then return l end
    end
    return name or "?"
end
function QI.AskFor(who, nd, qtitle, demo)
    if demo then ns.print((L["Demo: would whisper %s."]):format(ns.displayName(who))) return end
    ns.Whisper(who, (L["Hi! Do you have a spare %s? I need it for %s (%d/%d)."]):format(linkOf(nd.id, nd.name), qtitle or "?", nd.have or 0, nd.need or 1))
end
function QI.OfferTo(who, o, qtitle, demo)
    if demo then ns.print((L["Demo: would whisper %s."]):format(ns.displayName(who))) return end
    ns.Whisper(who, (L["Hi! I have %s for you (%s) - where are you?"]):format(linkOf(o.id, o.name), qtitle or "?"))
end
function QI.FarmTogether(who, nd, demo)
    if demo then ns.print((L["Demo: would invite %s."]):format(ns.displayName(who))) return end
    if ns.InviteName then ns.InviteName(who) end
    ns.Whisper(who, (L["Want to farm %s together? I invited you."]):format(linkOf(nd.id, nd.name)))
end
function QI.Invite(who, demo)
    if demo then ns.print((L["Demo: would invite %s."]):format(ns.displayName(who))) return end
    if ns.InviteName then ns.InviteName(who) end
end
-- share quest with the group
function QI.Push(qid)
    if ns.inCombat() then ns.print(L["Not possible in combat - try again shortly."]) return end
    local Q = C_QuestLog
    if not (QuestLogPushQuest and api(Q, "SetSelectedQuest")) then
        ns.print(L["Sharing does not work here - click Share in the quest log."])
        return
    end
    local prev = api(Q, "GetSelectedQuest") and select(2, pcall(Q.GetSelectedQuest)) or nil
    pcall(Q.SetSelectedQuest, qid)
    ns.Trace("QuestLogPushQuest")
    local ok = pcall(QuestLogPushQuest)
    if prev then pcall(Q.SetSelectedQuest, prev) end
    ns.print(ok and (L["Quest shared with the group: %s"]):format(questTitle(qid) or "?") or L["Sharing the quest did not work."])
end

------------------------------------------------------------------------
-- notice when someone can help me (throttled)
------------------------------------------------------------------------
local function checkToast()
    if S().qiToast == false or ns.demoLoading or not ns.loggedIn then return end
    local now = GetTime()
    if now - toastAt < TOAST_GAP then return end
    local ok, quests = pcall(QI.MyQuests)
    if not ok then return end
    for _, row in ipairs(QI.HelpForMe(quests)) do
        if row.kind == "need" then
            local g = row.givers[1]
            if g and g.on then
                local key = Comm.whoKey(g.who) .. ":" .. low(row.nd.name)
                if not toastKeys[key] or now - toastKeys[key] > TOAST_KEY_GAP then
                    toastKeys[key], toastAt = now, now
                    K.Toast((L["%s has spare %s"]):format(ns.displayName(g.who), row.nd.name),
                        (L["For %s (%d/%d) - click: whisper"]):format(row.q.title, row.nd.have, row.nd.need), C.mint,
                        function() QI.AskFor(g.who, row.nd, row.q.title, g.demo) end)
                    return
                end
            end
        end
    end
end
local toastPend
ns.Listen("STORE", function(name)
    if name ~= COLL then return end
    if refreshPage then refreshPage() end
    if toastPend then return end
    toastPend = true
    -- 0.5.724: collect longer (login sync delivers many entries at once) and never in combat - the first pass cost up to 56 ms in one go
    ns.After(20, function()
        toastPend = nil
        if ns.inCombat() then return end
        checkToast()
    end)
end)

------------------------------------------------------------------------
-- Tooltip: "Needed by: name (quest) n/m"
------------------------------------------------------------------------
local function tipLine(tt, itemID)
    if S().qiTooltip == false or not itemID then return end
    local name = C_Item and C_Item.GetItemNameByID and ns.safe(C_Item.GetItemNameByID(itemID))
    local probe = { id = itemID, name = name }
    local parts = {}
    for _, r in ipairs(others()) do
        local p = parseRec(r)
        for _, o in ipairs(p.needs) do
            if (o.id and o.id == itemID) or (not o.id and name and low(o.name) == low(name)) then
                parts[#parts + 1] = (online(r.who) and "|cff66db9e" or "|cff999999") .. ns.displayName(r.who) .. "|r |cff777777("
                    .. (questTitle(o.qid, p.titles) or "?") .. " " .. o.have .. "/" .. o.need .. ")|r"
                break
            end
        end
        if #parts >= 4 then parts[#parts + 1] = "..." break end
    end
    -- 0.6.621: your own quests too (before only guild members' needs were shown)
    if name and GetNumQuestLogEntries and GetQuestLogLeaderBoard then
        for i = 1, (GetNumQuestLogEntries() or 0) do
            local title, _, _, isHeader = GetQuestLogTitle(i)
            if title and not isHeader then
                for j = 1, (GetNumQuestLeaderBoards(i) or 0) do
                    local text, kind, done = GetQuestLogLeaderBoard(j, i)
                    text = ns.safe(text)
                    if kind == "item" and not done and type(text) == "string" then
                        local n, have, need = text:match("^(.-):%s*(%d+)%s*/%s*(%d+)")
                        if n and low(n) == low(name) then
                            table.insert(parts, 1, "|cffffd100" .. L["you"] .. "|r |cff777777(" .. title .. " " .. have .. "/" .. need .. ")|r")
                        end
                    end
                end
            end
        end
    end
    if #parts == 0 then return end
    tt:AddLine("|cffff1200Oasis|r  " .. L["Needed by:"] .. " " .. table.concat(parts, ", "), 0.85, 0.85, 0.85, true)
end
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
        if tt ~= GameTooltip and tt ~= ItemRefTooltip then return end
        local id = data and ns.safe(data.id)
        pcall(tipLine, tt, id)
    end)
end
QI.TipLine = tipLine

------------------------------------------------------------------------
-- Demo
------------------------------------------------------------------------
-- per companion: name, needs (id{name{quest{n{m}...), leftover (id{name{count{quest{reason}...), shareable, quest titles
local DEMO = {
    { "Grukthar", "0{Raptorkopf{870{1{4", "5086{Zhevrahufe{6{881{d", "887", "870{Die vergessenen Teiche}881{Echeyakee}887{Suedmeerfreibeuter" },
    { "Mokrash", "5086{Zhevrahufe{1062{1{4}0{Federn der Harpyie{1062{3{8", "", "", "1062{Ziegenwaerter" },
    { "Tavira", "", "0{Federn der Harpyie{11{0{o", "1489", "1489{Hamuuls Befehl" },
    { "Hoknar", "0{Kodo-Horn{6548{0{3", "", "", "6548{Rache an meinem Dorf" },
}
function QI.SeedDemo()
    for i, d in ipairs(DEMO) do
        local who = ns.fullName(d[1])
        Store.merge(COLL, { id = "demo-qi-" .. i, who = who, by = who, n = d[2], s = d[3], p = d[4], t = d[5], demo = true, u = ns.now() })
    end
    demoMine = {
        { id = 1062, title = L["Goatherd"], demo = true, lvl = 24, zone = L["Stonetalon Mountains"], needs = {
            { id = 5086, name = "Zhevra hooves", have = 1, need = 4 }, { name = "Harpy feathers", have = 2, need = 8 } } },
        { id = 870, title = L["The Forgotten Pools"], demo = true, lvl = 18, push = true, zone = L["The Barrens"], needs = { { name = "Raptor head", have = 0, need = 4 } } },
    }
    if refreshPage then refreshPage() end
end
function QI.RemoveDemo()
    local c = Store.coll(COLL)
    for id, r in pairs(c) do if r.demo then c[id] = nil end end
    demoMine = nil
    if refreshPage then refreshPage() end
end

------------------------------------------------------------------------
-- Page
------------------------------------------------------------------------
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local EMBER = ns.MEDIA .. "ember"
local CLASS_SHEET = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
local ICO = ns.MEDIA .. "icons\\"
local QCOL = { [0] = { 0.62, 0.62, 0.62 }, [1] = { 0.78, 0.78, 0.80 }, [2] = { 0.12, 1, 0 }, [3] = { 0.1, 0.5, 0.95 },
    [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 }, [6] = { 0.9, 0.8, 0.5 } }
local H_HEAD, H_CARD, H_SLIM, GAP, CARD_X = 30, 78, 50, 5, 0
local WHY = { d = "quest completed", x = "more than needed", o = "no active quest", b = "in your bags" }
local TABS = {
    { key = "help", text = "Help for me", glyph = "wants", color = C.amber },
    { key = "can", text = "I can help", glyph = "heart", color = C.blue },
    { key = "mine", text = "My quest items", glyph = "checklist", color = C.mint },
}
local TILES = {
    { key = "open", label = "Open quest items", glyph = "wants", color = C.amber, tip = "Click: all open quest items" },
    { key = "helpers", label = "Helpers online", glyph = "social", color = C.mint, tip = "Click: only entries with helpers online" },
    { key = "can", label = "I can help", glyph = "heart", color = C.blue, tip = "Click: whom you can help" },
    { key = "push", label = "Shareable quests", glyph = "announce", color = C.pink, tip = "Click: quests someone can share with you" },
}
local SORTS = { { key = "helper", text = "Helpers first" }, { key = "close", text = "Almost done" }, { key = "name", text = "Name" } }
local search, onlyHelp, tileFilter, sortBy = "", false, nil, "helper"
local page
local collapsed = {}
local zoneMode, uiLoaded = "focus", false
local function uiState()
    ns.char.qiUI = ns.char.qiUI or {}
    return ns.char.qiUI
end
local function saveUI()
    if not uiLoaded then return end
    local st = uiState()
    st.view, st.search, st.onlyHelp, st.tileFilter, st.sortBy = view, search, onlyHelp, tileFilter, sortBy
    st.zoneMode, st.collapsed = zoneMode, collapsed
    if page and page.tl then
        st.scroll = st.scroll or {}
        st.scroll[view] = page.tl.target or page.tl.off or 0
    end
end
local function loadUI()
    if uiLoaded then return end
    uiLoaded = true
    local st = uiState()
    view = (st.view == "can" or st.view == "mine") and st.view or "help"
    search = type(st.search) == "string" and st.search or ""
    onlyHelp = st.onlyHelp == true
    tileFilter = (st.tileFilter == "helpers" or st.tileFilter == "push") and st.tileFilter or nil
    sortBy = (st.sortBy == "close" or st.sortBy == "name") and st.sortBy or "helper"
    zoneMode = (st.zoneMode == "all" or st.zoneMode == "here") and st.zoneMode or "focus"
    collapsed = type(st.collapsed) == "table" and st.collapsed or {}
end
local function compact() return ns.char.qiCompact ~= false end

local function animOn() return not S().noAnim end
-- glass building blocks like chronicle and members; without Insta the base UI stays.
local function hasGlass() return ns.Insta and ns.Insta.Glass end
local function glass(f, fill, line, radius)
    if hasGlass() then ns.Insta.Glass(f, fill, line, radius or 10) end
end
local function calmButton(b, primary)
    if not hasGlass() then return b end
    local c = primary and C.accent or C.text
    local fill = { c[1], c[2], c[3], primary and 0.12 or 0.035 }
    local line = { c[1], c[2], c[3], primary and 0.28 or 0.085 }
    if b.sheen then b.sheen:Hide() end
    glass(b, fill, line, 8)
    local enter, leave = b:GetScript("OnEnter"), b:GetScript("OnLeave")
    b:SetScript("OnEnter", function(self)
        if enter then enter(self) end
        glass(self, { c[1], c[2], c[3], fill[4] + 0.055 }, { c[1], c[2], c[3], line[4] + 0.12 })
    end)
    b:SetScript("OnLeave", function(self)
        if leave then leave(self) end
        glass(self, fill, line)
    end)
    return b
end
local function hidden() ns.char.qiHidden = ns.char.qiHidden or {} return ns.char.qiHidden end
local function gradient(tex, dir, c, a1, a2, fb)
    if not K.Gradient(tex, dir, { c[1], c[2], c[3], a1 }, { c[1], c[2], c[3], a2 }) then
        tex:SetColorTexture(c[1], c[2], c[3], fb or (a1 + a2) / 2)
    end
end
local function circleMask(owner, tex)
    if not owner.CreateMaskTexture then return end
    local ok, m = pcall(owner.CreateMaskTexture, owner)
    if not ok or not m then return end
    pcall(function()
        m:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m:SetAllPoints(tex)
        tex:AddMaskTexture(m)
    end)
end
local function setClassIcon(tex, class)
    if ns.GuildInfo and ns.GuildInfo.SetClassIcon then
        local ok, r = pcall(ns.GuildInfo.SetClassIcon, tex, class)
        if ok and r then return true end
    end
    local tc = type(class) == "string" and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if not tc then return false end
    tex:SetTexture(CLASS_SHEET)
    tex:SetTexCoord(tc[1] + 0.015, tc[2] - 0.015, tc[3] + 0.015, tc[4] - 0.015)
    return true
end
local function plain(s)
    return (tostring(s or ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""))
end

-- item data: ID (also via name), icon, quality; request missing ones from the client (GET_ITEM_INFO_RECEIVED loads later)
local requested = {}
local function request(id)
    if id and not requested[id] and C_Item and api(C_Item, "RequestLoadItemDataByID") then
        requested[id] = true
        pcall(C_Item.RequestLoadItemDataByID, id)
    end
end
local function itemIdOf(x)
    if x.id then return x.id end
    if not x.name then return nil end
    local id = nameCache()[low(x.name)]
    if not id and C_Item and api(C_Item, "GetItemInfoInstant") then
        local ok, r = pcall(C_Item.GetItemInfoInstant, x.name)
        id = ok and tonumber(ns.safe(r)) or nil
        if id then nameCache()[low(x.name)] = id end
    end
    return id
end
local function iconOf(id)
    if not id or not C_Item or not api(C_Item, "GetItemIconByID") then return nil end
    local ok, t = pcall(C_Item.GetItemIconByID, id)
    t = ok and ns.safe(t) or nil
    if not t or t == NOICON then request(id) return nil end
    return t
end
local function qualityOf(id)
    if not id or not C_Item or not api(C_Item, "GetItemQualityByID") then return nil end
    local ok, q = pcall(C_Item.GetItemQualityByID, id)
    q = ok and tonumber(ns.safe(q)) or nil
    if not q then request(id) end
    return q
end
-- quest level color as in the quest log
local function questColor(lvl)
    if not lvl then return C.muted end
    if GetQuestDifficultyColor then
        local ok, c = pcall(GetQuestDifficultyColor, lvl)
        if ok and type(c) == "table" and tonumber(c.r) then return { c.r, c.g, c.b } end
    end
    local d = lvl - (tonumber(ns.safe(UnitLevel("player"))) or lvl)
    if d >= 5 then return { 1, 0.1, 0.1 } elseif d >= 3 then return { 1, 0.5, 0.25 } elseif d >= -2 then return { 1, 0.82, 0 }
    elseif d >= -8 then return { 0.25, 0.75, 0.25 } end
    return { 0.55, 0.55, 0.55 }
end
local function questLine(title, lvl)
    if not title then return "" end
    if not lvl then return "|cffa3a3a8" .. title .. "|r" end
    return K.hex(questColor(lvl)) .. "[" .. lvl .. "] " .. title .. "|r"
end
local function openQuest(qid, logIndex)
    if ns.inCombat and ns.inCombat() then ns.print(L["Not possible in combat - try again shortly."]) return end
    if QuestMapFrame_OpenToQuestDetails then
        if pcall(QuestMapFrame_OpenToQuestDetails, qid) then return end
    end
    if api(C_QuestLog, "SetSelectedQuest") then pcall(C_QuestLog.SetSelectedQuest, qid) end
    if QuestLogFrame and ShowUIPanel then pcall(ShowUIPanel, QuestLogFrame) elseif ToggleQuestLog then pcall(ToggleQuestLog) end
    if logIndex and QuestLog_SetSelection then pcall(QuestLog_SetSelection, logIndex) end
end
QI.OpenQuest = openQuest
local function linkItem(id, name)
    local l = linkOf(id, name)
    if ChatEdit_InsertLink then
        local ok, r = pcall(ChatEdit_InsertLink, l)
        if ok and r then return true end
    end
    if ns.OpenChat then ns.OpenChat(l) end
end
QI.LinkItem = linkItem

------------------------------------------------------------------------
-- Building blocks
------------------------------------------------------------------------
-- empty state: icon in a circle + text + up to two actions
local function emptyState(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(340, 120)
    f.halo = f:CreateTexture(nil, "BACKGROUND")
    f.halo:SetTexture(EMBER)
    f.halo:SetBlendMode("ADD")
    f.halo:SetSize(90, 90)
    f.halo:SetPoint("TOP", 0, 18)
    f.halo:SetAlpha(0.3)
    f.disc = f:CreateTexture(nil, "BORDER")
    f.disc:SetTexture(CIRCLE)
    f.disc:SetSize(44, 44)
    f.disc:SetPoint("TOP", 0, -5)
    f.icon = K.Glyph(f, 22, ICO .. "wants", C.amber)
    f.icon:SetPoint("CENTER", f.disc)
    f.text = K.Text(f, 13, C.muted, "CENTER")
    f.text:SetPoint("TOP", f.disc, "BOTTOM", 0, -10)
    f.text:SetWidth(330)
    f.text:SetWordWrap(true)
    f.btn = K.Button(f, "", 150, 22, "primary")
    f.btn2 = K.Button(f, "", 110, 22, "ghost")
    function f:Set(glyph, color, msg, b1, fn1, b2, fn2)
        self.icon:SetTexture(ICO .. glyph)
        self.icon:SetVertexColor(color[1], color[2], color[3])
        self.halo:SetVertexColor(color[1], color[2], color[3])
        self.disc:SetVertexColor(color[1] * 0.25, color[2] * 0.25, color[3] * 0.25)
        self.text:SetText(msg)
        self.btn:SetShown(b1 ~= nil)
        self.btn2:SetShown(b2 ~= nil)
        self.btn:ClearAllPoints()
        self.btn2:ClearAllPoints()
        if b1 then
            self.btn:SetLabel(b1)
            self.btn:SetWidth(math.max(110, (self.btn.label:GetStringWidth() or 0) + 26))
            self.btn:SetScript("OnClick", fn1)
        end
        if b2 then
            self.btn2:SetLabel(b2)
            self.btn2:SetWidth(math.max(90, (self.btn2.label:GetStringWidth() or 0) + 26))
            self.btn2:SetScript("OnClick", fn2)
            self.btn:SetPoint("TOPRIGHT", self.text, "BOTTOM", -4, -12)
            self.btn2:SetPoint("TOPLEFT", self.text, "BOTTOM", 4, -12)
        else
            self.btn:SetPoint("TOP", self.text, "BOTTOM", 0, -12)
        end
    end
    f:Hide()
    return f
end

-- tab bar: icon + text + counter, sliding bar in the tab color
local function buildTabs(p, onPick)
    local f = CreateFrame("Frame", nil, p)
    f:SetHeight(34)
    f.maxW = 480
    f.base = f:CreateTexture(nil, "BACKGROUND")
    f.base:SetPoint("BOTTOMLEFT", p, "TOPLEFT", 0, -34)
    f.base:SetPoint("BOTTOMRIGHT", p, "TOPRIGHT", 0, -34)
    f.base:SetHeight(1)
    f.base:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    if hasGlass() then f.base:Hide() glass(f, nil, nil, 10) end
    f.buttons = {}
    for i, d in ipairs(TABS) do
        local b = CreateFrame("Button", nil, f)
        b.key, b.color = d.key, d.color
        b.hov = b:CreateTexture(nil, "BACKGROUND")
        b.hov:SetAllPoints()
        gradient(b.hov, "VERTICAL", b.color, 0.10, 0, 0.05)
        if hasGlass() then b.hov:SetColorTexture(1, 1, 1, 0.035) end
        b.hov:SetAlpha(0)
        b.ico = K.Glyph(b, 14, ICO .. d.glyph, C.muted)
        b.label = K.Text(b, 13, C.muted)
        b.label:SetText(L[d.text])
        b.count = K.Text(b, 10, C.dim)
        b:SetScript("OnClick", function() onPick(d.key) end)
        b:SetScript("OnEnter", function(self)
            self.hov:SetAlpha(1)
            if f.value ~= self.key then self.label:SetTextColor(C.text[1], C.text[2], C.text[3]) end
        end)
        b:SetScript("OnLeave", function(self)
            self.hov:SetAlpha(f.value == self.key and 0.6 or 0)
            if f.value ~= self.key then self.label:SetTextColor(C.muted[1], C.muted[2], C.muted[3]) end
        end)
        f.buttons[i] = b
    end
    f.ind = f:CreateTexture(nil, "OVERLAY")
    f.ind:SetHeight(2)
    f.indGlow = f:CreateTexture(nil, "ARTWORK")
    f.indGlow:SetHeight(12)
    f.indGlow:SetPoint("BOTTOMLEFT", f.ind, "TOPLEFT")
    f.indGlow:SetPoint("BOTTOMRIGHT", f.ind, "TOPRIGHT")
    function f:Layout()
        local W = self.maxW or 480
        local nat, sum, withIcon = {}, 0, true
        for pass = 1, 2 do
            sum = 0
            for i, b in ipairs(self.buttons) do
                local cw = (b.count:GetText() or "") ~= "" and ((b.count:GetStringWidth() or 0) + 5) or 0
                nat[i] = (withIcon and 19 or 0) + (b.label:GetStringWidth() or 0) + cw + 22
                sum = sum + nat[i]
            end
            if pass == 1 and sum > W then withIcon = false else break end
        end
        local scale = math.min(1, W / math.max(1, sum))
        local x = 0
        for i, b in ipairs(self.buttons) do
            local bw = math.max(40, math.floor(nat[i] * scale))
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", x, 0)
            b:SetSize(bw, 33)
            b.x, b.w = x, bw
            x = x + bw + 2
            local cw = (b.count:GetText() or "") ~= "" and ((b.count:GetStringWidth() or 0) + 5) or 0
            local iw = withIcon and 19 or 0
            local tw = math.max(10, math.min(b.label:GetStringWidth() or 0, bw - iw - cw - 12))
            local x0 = math.max(4, math.floor((bw - (iw + tw + cw)) / 2))
            b.ico:SetShown(withIcon)
            b.ico:ClearAllPoints()
            b.ico:SetPoint("LEFT", b, "LEFT", x0, 0)
            b.label:ClearAllPoints()
            b.label:SetPoint("LEFT", b, "LEFT", x0 + iw, 0)
            b.label:SetWidth(tw + 1)
            b.count:ClearAllPoints()
            b.count:SetPoint("LEFT", b.label, "RIGHT", 4, 0)
        end
        self:SetWidth(math.max(1, x))
        self:MoveInd(self.value, false)
    end
    function f:SetCounts(t)
        local changed = false
        for _, b in ipairs(self.buttons) do
            local n = t[b.key] or 0
            local s = n > 0 and tostring(n) or ""
            if b.count:GetText() ~= s then b.count:SetText(s) changed = true end
        end
        if changed then self:Layout() end
    end
    function f:MoveInd(key, animate)
        local tb
        for _, b in ipairs(self.buttons) do if b.key == key then tb = b end end
        if not tb or not tb.x then return end
        local c = tb.color
        self.ind:SetColorTexture(c[1], c[2], c[3], 1)
        gradient(self.indGlow, "VERTICAL", c, 0.22, 0, 0.1)
        if hasGlass() then self.indGlow:Hide() end
        local x1, w1 = tb.x + 6, math.max(1, tb.w - 12)
        local x0, w0 = self.indX or x1, self.indW or w1
        self.indX, self.indW = x1, w1
        local function put(x, w)
            self.ind:ClearAllPoints()
            self.ind:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", x, 0)
            self.ind:SetWidth(math.max(1, w))
        end
        if not animate or not animOn() then put(x1, w1) return end
        K.Tween(self.ind, 0.24, function(q) put(x0 + (x1 - x0) * q, w0 + (w1 - w0) * q) end, function() put(x1, w1) end)
    end
    function f:Select(key, animate)
        local changed = self.value ~= key
        self.value = key
        for _, b in ipairs(self.buttons) do
            local on = b.key == key
            local c = on and C.text or C.muted
            b.label:SetTextColor(c[1], c[2], c[3])
            local ic = on and b.color or C.muted
            b.ico:SetVertexColor(ic[1], ic[2], ic[3])
            b.hov:SetAlpha(on and 0.6 or 0)
            local cc = on and b.color or C.dim
            b.count:SetTextColor(cc[1], cc[2], cc[3])
        end
        if changed or not self.indX then self:MoveInd(key, animate) end
    end
    return f
end

-- stat tile: glass, subtle hover lift, counting up; click = filter
local function buildTile(parent, d, onClick)
    local c = d.color
    local t = CreateFrame("Button", nil, parent)
    t:SetHeight(60)
    t.key, t.lift = d.key, 0
    t.bg = K.Fill(t, C.raised)
    t.grad = t:CreateTexture(nil, "BORDER", nil, 1)
    t.grad:SetAllPoints()
    gradient(t.grad, "HORIZONTAL", c, 0.16, 0.02)
    t.hov = t:CreateTexture(nil, "BORDER", nil, 2)
    t.hov:SetAllPoints()
    gradient(t.hov, "VERTICAL", c, 0, 0.20, 0.08)
    t.hov:SetAlpha(0)
    K.Border(t, C.line)
    t.top = t:CreateTexture(nil, "ARTWORK")
    t.top:SetPoint("TOPLEFT") t.top:SetPoint("TOPRIGHT")
    t.top:SetHeight(2)
    t.top:SetColorTexture(c[1], c[2], c[3], 0.85)
    t.gloss = t:CreateTexture(nil, "ARTWORK", nil, 1)
    t.gloss:SetPoint("TOPLEFT", 1, -2) t.gloss:SetPoint("TOPRIGHT", -1, -2)
    t.gloss:SetHeight(16)
    if not K.Gradient(t.gloss, "VERTICAL", { 1, 1, 1, 0 }, { 1, 1, 1, 0.05 }) then t.gloss:Hide() end
    t.iconGlow = t:CreateTexture(nil, "BORDER", nil, 3)
    t.iconGlow:SetTexture(EMBER)
    t.iconGlow:SetBlendMode("ADD")
    t.iconGlow:SetSize(52, 52)
    t.iconGlow:SetVertexColor(c[1], c[2], c[3])
    t.iconGlow:SetAlpha(0.3)
    t.icon = K.Glyph(t, 22, ICO .. d.glyph, c)
    t.icon:SetPoint("RIGHT", -12, 0)
    t.iconGlow:SetPoint("CENTER", t.icon)
    t.value = K.Title(t, 20, C.text)
    t.value:SetPoint("TOPLEFT", 12, -8)
    t.sub = K.Text(t, 10, c)
    t.sub:SetPoint("BOTTOMLEFT", t.value, "BOTTOMRIGHT", 6, 2)
    t.sub:SetPoint("RIGHT", t.icon, "LEFT", -4, 0)
    t.label = K.Text(t, 10, C.muted)
    t.label:SetPoint("BOTTOMLEFT", 12, 8)
    t.label:SetPoint("RIGHT", t.icon, "LEFT", -4, 0)
    t.label:SetText(L[d.label])
    if hasGlass() then
        glass(t, nil, nil, 12)
        t.grad:Hide() t.top:Hide() t.gloss:Hide() t.iconGlow:Hide()
        t.hov:SetColorTexture(1, 1, 1, 0.04)
        if K.RoundMask then K.RoundMask(t.hov, t, 12) end
    end
    function t:Place()
        if not self.bx then return end
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", self:GetParent(), "TOPLEFT", self.bx, self.lift)
        self:SetWidth(self.bw)
    end
    local function hover(on)
        local from, to = t.lift, on and 2 or 0
        local h0, h1 = t.hov:GetAlpha() or 0, (on or t.sel) and 1 or 0
        if animOn() then
            K.Tween(t.hov, 0.16, function(q)
                t.lift = from + (to - from) * q
                t.hov:SetAlpha(h0 + (h1 - h0) * q)
                t.iconGlow:SetAlpha(0.3 + 0.4 * (t.hov:GetAlpha() or 0))
                t:Place()
            end)
        else
            t.lift = to
            t.hov:SetAlpha(h1)
            t.iconGlow:SetAlpha(on and 0.7 or 0.3)
            t:Place()
        end
    end
    t:SetScript("OnEnter", function(self)
        hover(true)
        K.ShowTip(self, { L[d.label], "|cff888888" .. (self.sel and L["Click: clear filter"] or L[d.tip]) .. "|r" })
    end)
    t:SetScript("OnLeave", function() hover(false) GameTooltip:Hide() end)
    t:SetScript("OnClick", function() onClick(d.key) end)
    function t:SetSel(on)
        self.sel = on
        K.SetBorderColor(self, on and c or C.line, on and 0.9 or 1)
        if hasGlass() then glass(self, { 1, 1, 1, on and 0.065 or 0.04 }, on and { c[1], c[2], c[3], 0.40 } or nil, 12) end
        self.top:SetHeight(on and 3 or 2)
        if not (self.IsMouseOver and self:IsMouseOver()) then self.hov:SetAlpha(on and 1 or 0) end
    end
    return t
end

-- toggle chip ("Only with helpers")
local function buildChip(parent, text, get, set)
    local b = calmButton(K.Button(parent, text, 80, 22, "ghost"))
    K.SetFontSafe(b.label, K.FONT, 11, "", K.FONT)
    b:SetWidth(math.max(70, (b.label:GetStringWidth() or 0) + 26))
    function b:Update()
        local on = get()
        local c = on and C.accent or C.muted
        self.label:SetTextColor(c[1], c[2], c[3])
        K.SetBorderColor(self, on and C.accent2 or C.line)
        if hasGlass() then glass(self, { 1, 1, 1, on and 0.08 or 0.035 }, on and { C.accent[1], C.accent[2], C.accent[3], 0.35 } or nil, 8) end
    end
    b:SetScript("OnClick", function(self) set(not get()) self:Update() end)
    b:HookScript("OnLeave", function(self) self:Update() end)
    b:Update()
    return b
end

-- status pill: dot (green = freshly shared) + text + "Share now"
local function buildStatus(p, onShare)
    local f = CreateFrame("Frame", nil, p)
    f:SetHeight(24)
    f.bg = K.Fill(f, C.raised)
    K.Border(f, C.line)
    f.glow = f:CreateTexture(nil, "BORDER")
    f.glow:SetTexture(EMBER)
    f.glow:SetBlendMode("ADD")
    f.glow:SetSize(22, 22)
    f.dot = f:CreateTexture(nil, "ARTWORK")
    f.dot:SetTexture(CIRCLE)
    f.dot:SetSize(8, 8)
    f.dot:SetPoint("LEFT", 10, 0)
    f.glow:SetPoint("CENTER", f.dot)
    if hasGlass() then glass(f, nil, nil, 8) f.glow:Hide() end
    f.text = K.Text(f, 11, C.muted)
    f.text:SetPoint("LEFT", f.dot, "RIGHT", 7, 0)
    f.hit = CreateFrame("Frame", nil, f)
    f.hit:SetPoint("TOPLEFT") f.hit:SetPoint("BOTTOM")
    f.hit:SetPoint("RIGHT", f.text, "RIGHT", 4, 0)
    f.hit:EnableMouse(true)
    f.hit:SetScript("OnEnter", function(self) if f.tip then K.ShowTip(self, f.tip) end end)
    f.hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.sep = f:CreateTexture(nil, "ARTWORK")
    f.sep:SetSize(1, 14)
    f.sep:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    f.btn = CreateFrame("Button", nil, f)
    f.btn:SetPoint("TOPRIGHT") f.btn:SetPoint("BOTTOMRIGHT")
    f.btn.hov = f.btn:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.btn.hov:SetAllPoints()
    f.btn.hov:SetColorTexture(1, 1, 1, 0.06)
    f.btn.hov:Hide()
    f.btn.g = K.Glyph(f.btn, 12, ICO .. "sync", C.muted)
    f.btn.g:SetPoint("LEFT", 9, 0)
    f.btn.label = K.Text(f.btn, 11, C.text)
    f.btn.label:SetPoint("LEFT", f.btn.g, "RIGHT", 5, 0)
    f.btn.label:SetText(L["Share now"])
    f.sep:SetPoint("RIGHT", f.btn, "LEFT", 0, 0)
    f.btn:SetScript("OnEnter", function(self)
        self.hov:Show()
        self.g:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
        K.ShowTip(self, { L["Share now"], "|cff888888" .. L["Sends your status to the guild right away"] .. "|r" })
    end)
    f.btn:SetScript("OnLeave", function(self)
        self.hov:Hide()
        self.g:SetVertexColor(C.muted[1], C.muted[2], C.muted[3])
        GameTooltip:Hide()
    end)
    f.btn:SetScript("OnClick", function(self)
        onShare()
        if animOn() and self.g.SetRotation then
            K.Tween(self.g, 0.7, function(q) pcall(self.g.SetRotation, self.g, -q * math.pi * 2) end, function() pcall(self.g.SetRotation, self.g, 0) end)
        end
    end)
    function f:Set(c, long, short, tip, maxW)
        self.dot:SetVertexColor(c[1], c[2], c[3])
        self.glow:SetVertexColor(c[1], c[2], c[3])
        self.glow:SetAlpha(0.55)
        self.tip = tip
        local bw = (self.btn.label:GetStringWidth() or 60) + 32
        self.btn:SetWidth(bw)
        self.text:SetText(long)
        local w = 10 + 8 + 7 + (self.text:GetStringWidth() or 0) + 12 + bw
        if maxW and w > maxW then
            self.text:SetText(short)
            w = 10 + 8 + 7 + (self.text:GetStringWidth() or 0) + 12 + bw
        end
        self:SetWidth(math.floor(w))
    end
    return f
end

-- round item image with ring (quality or type color), icon fallback instead of a red question mark
local function makeAvatar(parent, s)
    local a = CreateFrame("Frame", nil, parent)
    a:SetSize(s, s)
    a.glow = a:CreateTexture(nil, "BACKGROUND", nil, 2)
    a.glow:SetTexture(EMBER)
    a.glow:SetBlendMode("ADD")
    a.glow:SetSize(s * 2, s * 2)
    a.glow:SetPoint("CENTER")
    a.glow:SetAlpha(0.35)
    a.ring = a:CreateTexture(nil, "BORDER")
    a.ring:SetTexture(CIRCLE)
    a.ring:SetAllPoints()
    a.inner = a:CreateTexture(nil, "ARTWORK", nil, -1)
    a.inner:SetTexture(CIRCLE)
    a.inner:SetVertexColor(0.06, 0.06, 0.07)
    a.inner:SetSize(s - 4, s - 4)
    a.inner:SetPoint("CENTER")
    a.icon = a:CreateTexture(nil, "ARTWORK", nil, 1)
    a.icon:SetSize(s - 6, s - 6)
    a.icon:SetPoint("CENTER")
    circleMask(a, a.icon)
    a.glyph = a:CreateTexture(nil, "ARTWORK", nil, 2)
    a.glyph:SetSize(math.floor(s * 0.5), math.floor(s * 0.5))
    a.glyph:SetPoint("CENTER")
    return a
end
local function setAvatar(a, vm)
    local c = vm.color or C.amber
    local tex = vm.id and iconOf(vm.id)
    local q = vm.id and qualityOf(vm.id)
    local ring = c
    if tex then
        a.icon:SetTexture(tex)
        a.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        a.icon:Show()
        a.glyph:Hide()
        ring = (q and QCOL[q]) or C.line
    else
        a.icon:Hide()
        a.glyph:SetTexture(ICO .. (vm.glyph or "wants"))
        a.glyph:SetVertexColor(c[1], c[2], c[3])
        a.glyph:Show()
    end
    a.ring:SetVertexColor(ring[1], ring[2], ring[3])
    a.glow:SetVertexColor(ring[1], ring[2], ring[3])
    a.glow:SetShown(vm.hot == true and not hasGlass())
    return ring, q
end

local function whisperTo(who, demo, text)
    if demo then ns.print((L["Demo: would whisper %s."]):format(ns.displayName(who))) return end
    ns.Whisper(who, text)
end
local function hideEntry(key)
    hidden()[key] = ns.now()
    ns.print(L["Hidden - use the button at the top to show it again."])
    if refreshPage then refreshPage() end
end

------------------------------------------------------------------------
-- list: zone chapters (pinned at the top) + cards, rows are reused per key
------------------------------------------------------------------------
local function buildList(p)
    local TL = CreateFrame("Frame", nil, p)
    TL:SetClipsChildren(true)
    TL:EnableMouseWheel(true)
    TL.items, TL.total, TL.off, TL.target = {}, 0, 0, 0
    TL.used, TL.pools, TL.byKey, TL.bars = {}, { head = {}, card = {} }, {}, {}
    TL.thumb = TL:CreateTexture(nil, "OVERLAY")
    TL.thumb:SetWidth(3)
    TL.thumb:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)

    -- Chapters --------------------------------------------------------
    local function newHead(parent)
        local r = CreateFrame("Button", nil, parent or TL)
        r:SetScript("OnClick", function(self)
            local it = self.item or TL.sticky.cur
            if not it or not it.zone then return end
            collapsed[it.zone] = not collapsed[it.zone]
            saveUI()
            ns.RefreshPage("questitems")
        end)
        r:SetScript("OnEnter", function(self) K.ShowTip(self, { L["Click: expand or collapse zone"] }) end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r.mark = r:CreateTexture(nil, "ARTWORK")
        r.mark:SetSize(3, 12)
        r.mark:SetPoint("LEFT", 2, -1)
        r.text = K.Title(r, 12, C.text)
        r.text:SetPoint("LEFT", 12, -1)
        r.info = K.Text(r, 11, C.dim)
        r.info:SetPoint("LEFT", r.text, "RIGHT", 8, 0)
        r.rule = r:CreateTexture(nil, "ARTWORK")
        r.rule:SetHeight(1)
        r.rule:SetPoint("LEFT", r.info, "RIGHT", 10, 0)
        r.rule:SetPoint("RIGHT", r, "RIGHT", 0, -1)
        gradient(r.rule, "HORIZONTAL", C.line, 1, 0, 0.6)
        r.type = "head"
        return r
    end
    local function fillHead(r, it)
        r.text:SetText((it.closed and "+  " or "-  ") .. (K.Upper and K.Upper(it.label) or it.label:upper()))
        r.info:SetText(it.info or "")
        local c = it.color or C.accent
        r.mark:SetColorTexture(c[1], c[2], c[3], 1)
    end

    -- Cards ---------------------------------------------------------
    local function cardHover(r, on)
        if not on and r.IsMouseOver and r:IsMouseOver() then return end   -- only switched on chip/button
        if r.hovered == on then return end
        r.hovered = on
        r.hov:Show()
        local from, target = r.hov:GetAlpha() or 0, on and 1 or 0
        if animOn() then
            K.Tween(r.hov, 0.16, function(q) r.hov:SetAlpha(from + (target - from) * q) end)
        else r.hov:SetAlpha(target) end
        if hasGlass() then glass(r, { 1, 1, 1, on and 0.055 or 0.03 }, { 1, 1, 1, on and 0.16 or 0.085 }, 12) end
        local vm = r.item and r.item.vm
        K.SetBorderColor(r, on and (vm and vm.ring or C.accent2) or C.line, on and 0.8 or 1)
        r.acts:SetShown((r.nActs or 0) > 0)
        r.acts:SetAlpha(1)
        if not on then GameTooltip:Hide() end
    end
    local function cardTip(r)
        local vm = r.item and r.item.vm
        if not vm then return end
        local hint = "|cff777777" .. L["Right-click: actions"] .. (vm.id and ("  ·  " .. L["Shift-click: link"]) or "") .. "|r"
        if vm.id then
            GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
            if pcall(GameTooltip.SetItemByID, GameTooltip, vm.id) then
                GameTooltip:AddLine(" ")
                for _, l in ipairs(vm.tip or {}) do GameTooltip:AddLine(l, 0.85, 0.85, 0.85, true) end
                for _, chip in ipairs(vm.chips or {}) do
                    GameTooltip:AddLine(ns.displayName(chip.who) .. (chip.extra and ("  " .. chip.extra) or "") .. "  " .. (chip.on and L["online"] or L["offline"]), 0.65, 0.85, 0.72, true)
                end
                GameTooltip:AddLine(hint, 1, 1, 1, true)
                GameTooltip:Show()
                return
            end
        end
        local lines = { vm.name }
        for _, l in ipairs(vm.tip or {}) do lines[#lines + 1] = l end
        for _, chip in ipairs(vm.chips or {}) do
            lines[#lines + 1] = ns.displayName(chip.who) .. (chip.extra and ("  " .. chip.extra) or "") .. "  " .. (chip.on and L["online"] or L["offline"])
        end
        lines[#lines + 1] = hint
        K.ShowTip(r, lines)
    end
    local function cardMenu(r, owner)
        local vm = r.item and r.item.vm
        if not vm or not vm.menu then return end
        K.ShowMenu(owner or r, vm.menu(), plain(vm.name), 210)
    end
    local function newChip(r)
        local b = CreateFrame("Button", nil, r)
        b:SetHeight(18)
        b:RegisterForClicks("AnyUp")
        b.bg = K.Fill(b, C.raised)
        K.Border(b, C.line)
        b.cls = b:CreateTexture(nil, "ARTWORK")
        b.cls:SetSize(14, 14)
        b.cls:SetPoint("LEFT", 2, 0)
        circleMask(b, b.cls)
        b.dot = b:CreateTexture(nil, "OVERLAY")
        b.dot:SetTexture(CIRCLE)
        b.dot:SetSize(6, 6)
        b.dot:SetPoint("CENTER", b.cls, "BOTTOMRIGHT", -1, 1)
        b.text = K.Text(b, 11, C.text)
        b.text:SetPoint("LEFT", b.cls, "RIGHT", 5, 0)
        b:SetScript("OnEnter", function(self)
            cardHover(r, true)
            K.SetBorderColor(self, C.accent2)
            local x = self.x
            if x then
                K.ShowTip(self, { (ns.Radar and ns.Radar.Colored and ns.Radar.Colored(x.who) or ns.displayName(x.who))
                    .. (x.on and ("  " .. K.hex(C.mint) .. L["online"] .. "|r") or ("  |cff888888" .. L["offline"] .. "|r")),
                    x.tip or "", "|cff777777" .. (x.click or L["Click: whisper"]) .. "  ·  " .. L["Right-click: actions"] .. "|r" })
            end
        end)
        b:SetScript("OnLeave", function(self)
            K.SetBorderColor(self, self.x and self.x.giver and C.mint or C.line, self.x and self.x.giver and 0.5 or 1)
            GameTooltip:Hide()
            cardHover(r, false)
        end)
        b:SetScript("OnClick", function(self, btn)
            if btn == "RightButton" then cardMenu(r, self) return end
            if self.x and self.x.fn then self.x.fn() end
        end)
        glass(b, nil, nil, 5)
        return b
    end
    local function setChip(b, x)
        b.x = x
        local cls = ns.Radar and ns.Radar.ClassOf and ns.Radar.ClassOf(x.who)
        b.cls:SetVertexColor(1, 1, 1)
        if not (cls and setClassIcon(b.cls, cls)) then
            b.cls:SetTexture(CIRCLE)
            b.cls:SetTexCoord(0, 1, 0, 1)
            b.cls:SetVertexColor(C.dim[1], C.dim[2], C.dim[3])
        end
        local dc = x.on and C.mint or C.dim
        b.dot:SetVertexColor(dc[1], dc[2], dc[3])
        b.text:SetText((x.on and K.hex(C.mint) or "|cff9a9aa0") .. ns.displayName(x.who) .. "|r" .. (x.extra and ("  " .. x.extra) or ""))
        b:SetWidth(math.floor((b.text:GetStringWidth() or 40) + 30))
        K.SetBorderColor(b, x.giver and C.mint or C.line, x.giver and 0.5 or 1)
        local bc = x.giver and { C.mint[1] * 0.16, C.mint[2] * 0.16, C.mint[3] * 0.16 } or C.raised
        b.bg:SetColorTexture(bc[1], bc[2], bc[3], 1)
    end
    local function newAct(r)
        local b = CreateFrame("Button", nil, r.acts)
        b:SetSize(22, 22)
        b.bg = K.Fill(b, C.raised)
        K.Border(b, C.line)
        b.g = K.Glyph(b, 13, nil, C.muted)
        b.g:SetPoint("CENTER")
        b:SetScript("OnEnter", function(self)
            cardHover(r, true)
            K.SetBorderColor(self, C.accent2)
            self.g:SetVertexColor(C.text[1], C.text[2], C.text[3])
            if self.a then K.ShowTip(self, { self.a.tip }) end
        end)
        b:SetScript("OnLeave", function(self)
            K.SetBorderColor(self, C.line)
            self.g:SetVertexColor(C.muted[1], C.muted[2], C.muted[3])
            GameTooltip:Hide()
            cardHover(r, false)
        end)
        b:SetScript("OnClick", function(self) if self.a and self.a.fn then self.a.fn() end end)
        calmButton(b)
        return b
    end
    local function newCard()
        local r = CreateFrame("Button", nil, TL)
        r:RegisterForClicks("AnyUp")
        r.bg = K.Fill(r, C.panel)
        r.tint = r:CreateTexture(nil, "BORDER", nil, 1)
        r.tint:SetAllPoints()
        r.hov = r:CreateTexture(nil, "BORDER", nil, 2)
        r.hov:SetAllPoints()
        r.hov:SetColorTexture(1, 1, 1, 0.045)
        r.hov:SetAlpha(0)
        r.hov:Hide()
        K.Border(r, C.line)
        r.edge = r:CreateTexture(nil, "ARTWORK")
        r.edge:SetPoint("TOPLEFT") r.edge:SetPoint("BOTTOMLEFT")
        r.edge:SetWidth(2)
        r.av = makeAvatar(r, 38)
        r.av:SetPoint("LEFT", 10, 0)
        r.name = K.Text(r, 13, C.text)
        r.ptext = K.Title(r, 12, C.amber)
        r.bar = CreateFrame("Frame", nil, r)
        r.bar:SetSize(56, 4)
        r.bar.bg = K.Fill(r.bar, C.field)
        r.bar.fill = r.bar:CreateTexture(nil, "ARTWORK")
        r.bar.fill:SetPoint("TOPLEFT") r.bar.fill:SetPoint("BOTTOMLEFT")
        r.badge = K.Badge(r)
        r.qline = K.Text(r, 11, C.muted)
        r.more = K.Text(r, 11, C.dim)
        r.chips, r.abtn = {}, {}
        r.prim = calmButton(K.Button(r, "", 90, 28, "primary"), true)
        r.prim:HookScript("OnEnter", function(self)
            cardHover(r, true)
            local pr = r.item and r.item.vm and r.item.vm.primary
            if pr and pr.tip then K.ShowTip(self, { pr.tip }) end
        end)
        r.prim:HookScript("OnLeave", function() GameTooltip:Hide() cardHover(r, false) end)
        r.prim:SetScript("OnClick", function()
            local pr = r.item and r.item.vm and r.item.vm.primary
            if pr and pr.fn then pr.fn() end
        end)
        r.acts = CreateFrame("Frame", nil, r)
        r.acts:SetHeight(22)
        r.acts:Hide()
        r:SetScript("OnEnter", function(self) cardHover(self, true) cardTip(self) end)
        r:SetScript("OnLeave", function(self) cardHover(self, false) end)
        r:SetScript("OnClick", function(self, btn)
            local vm = self.item and self.item.vm
            if not vm then return end
            if btn == "RightButton" then cardMenu(self) return end
            if IsModifiedClick and IsModifiedClick("CHATLINK") and vm.id then linkItem(vm.id, vm.name) end
        end)
        if hasGlass() then
            glass(r, { 1, 1, 1, 0.03 }, nil, 12)
            r.tint:Hide() r.edge:Hide()
            if K.RoundMask then K.RoundMask(r.hov, r, 12) end
        end
        r.type = "card"
        return r
    end
    local function fillCard(r, it)
        local vm = it.vm
        local W = math.max(300, (TL:GetWidth() or 600) - CARD_X - 10)
        local ring, q = setAvatar(r.av, vm)
        vm.ring = ring
        gradient(r.tint, "HORIZONTAL", ring, vm.hot and 0.14 or 0.07, 0, vm.hot and 0.07 or 0.035)
        r.edge:SetColorTexture(ring[1], ring[2], ring[3], vm.hot and 1 or 0.45)
        if not r.hovered then K.SetBorderColor(r, C.line) end
        -- Right: main action and permanently visible extra actions.
        local reserve = 10
        r.prim:ClearAllPoints()
        if vm.primary then
            r.prim:SetLabel(vm.primary.text)
            local pw = math.max(78, math.floor((r.prim.label:GetStringWidth() or 60) + 22))
            r.prim:SetWidth(pw)
            r.prim:SetPoint("RIGHT", r, "RIGHT", -10, 0)
            r.prim:Show()
            reserve = reserve + pw + 6
        else
            r.prim:Hide()
        end
        local acts = vm.acts or {}
        for i, a in ipairs(acts) do
            local b = r.abtn[i] or newAct(r)
            r.abtn[i] = b
            b.a = a
            b.g:SetTexture(ICO .. a.glyph)
            b:ClearAllPoints()
            b:SetPoint("RIGHT", r.acts, "RIGHT", -(i - 1) * 26, 0)
            b:Show()
        end
        for i = #acts + 1, #r.abtn do r.abtn[i]:Hide() end
        r.nActs = #acts
        r.acts:SetWidth(math.max(1, #acts * 26))
        r.acts:ClearAllPoints()
        r.acts:SetPoint("RIGHT", r, "RIGHT", -reserve, 0)
        r.acts:SetShown(#acts > 0)
        reserve = reserve + #acts * 26 + 6
        -- line 1: name in quality color + progress or tag
        local nc = vm.nameColor or ((q and q >= 2 and QCOL[q]) or C.text)
        if vm.done then nc = C.mint end
        r.name:SetText(K.hex(nc) .. (vm.name or "?") .. "|r")
        local avail = W - 58 - reserve
        local extra = vm.need and 110 or (vm.badge and 96 or 0)
        r.name:SetWidth(math.max(40, math.min((r.name:GetStringWidth() or 0) + 2, avail - extra)))
        r.name:ClearAllPoints()
        r.name:SetPoint("TOPLEFT", 58, it.slim and -8 or -10)
        r.ptext:SetShown(vm.need ~= nil)
        r.bar:SetShown(vm.need ~= nil)
        r.badge:SetShown(vm.need == nil and vm.badge ~= nil)
        if vm.need then
            local have, need = vm.have or 0, math.max(1, vm.need)
            r.ptext:SetText(have .. "/" .. need)
            local pc = (vm.done or have >= need) and C.mint or C.amber
            r.ptext:SetTextColor(pc[1], pc[2], pc[3])
            r.ptext:ClearAllPoints()
            r.ptext:SetPoint("LEFT", r.name, "RIGHT", 8, 0)
            r.bar:ClearAllPoints()
            r.bar:SetPoint("LEFT", r.ptext, "RIGHT", 7, 0)
            r.bar.fill:SetColorTexture(pc[1], pc[2], pc[3], 0.9)
            local pct = math.min(1, have / need)
            local prev = TL.bars[it.key]
            TL.bars[it.key] = pct
            local fill = r.bar.fill
            local function put(x) fill:SetWidth(math.max(0.01, 56 * x)) fill:SetShown(x > 0) end
            if animOn() and prev ~= pct then
                local from = prev or 0
                put(from)
                K.Tween(fill, 0.55, function(x) put(from + (pct - from) * x) end, function() put(pct) end, 0.05)
            else
                K.Tween(fill, 0.01, function() put(pct) end, function() put(pct) end)
                put(pct)
            end
        elseif vm.badge then
            r.badge:Set(vm.badge, vm.badgeColor or vm.color or C.blue)
            r.badge:ClearAllPoints()
            r.badge:SetPoint("LEFT", r.name, "RIGHT", 8, 0)
        end
        -- line 2: quest (level color) or explanation
        local qline = vm.qline or ""
        if it.slim and #(vm.chips or {}) > 0 then
            local online = 0
            for _, chip in ipairs(vm.chips) do if chip.on then online = online + 1 end end
            qline = qline .. "  |cff555555·|r  " .. K.hex(online > 0 and C.mint or C.muted) .. (L["%d helpers, %d online"]):format(#vm.chips, online) .. "|r"
        end
        r.qline:SetText(qline)
        r.qline:ClearAllPoints()
        r.qline:SetPoint("TOPLEFT", 58, it.slim and -27 or -29)
        r.qline:SetPoint("RIGHT", r, "RIGHT", -reserve, 0)
        -- line 3: helper chips
        local x, shown = 58, 0
        local chips = vm.chips or {}
        for i, c in ipairs(chips) do
            local b = r.chips[i] or newChip(r)
            r.chips[i] = b
            setChip(b, c)
            local cw = b:GetWidth() or 60
            if it.slim or x + cw > W - reserve - 30 then
                b:Hide()
            else
                b:ClearAllPoints()
                b:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", x, 9)
                b:Show()
                x = x + cw + 5
                shown = shown + 1
            end
        end
        for i = #chips + 1, #r.chips do r.chips[i]:Hide() end
        r.more:SetShown(not it.slim and shown < #chips)
        if shown < #chips then
            r.more:SetText("+" .. (#chips - shown))
            r.more:ClearAllPoints()
            r.more:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", x + 2, 12)
        end
        if r.IsMouseOver and r:IsMouseOver() and not r.hovered then cardHover(r, true) end
    end

    local MAKE = { head = newHead, card = newCard }
    local FILL = { head = fillHead, card = fillCard }

    -- pinned chapter
    TL.sticky = CreateFrame("Frame", nil, TL)
    TL.sticky:SetHeight(H_HEAD - 4)
    TL.sticky:SetFrameLevel((TL:GetFrameLevel() or 1) + 20)
    TL.sticky.bg = TL.sticky:CreateTexture(nil, "BACKGROUND")
    TL.sticky.bg:SetAllPoints()
    TL.sticky.bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.97)
    TL.sticky.fade = TL.sticky:CreateTexture(nil, "BACKGROUND")
    TL.sticky.fade:SetPoint("TOPLEFT", TL.sticky, "BOTTOMLEFT")
    TL.sticky.fade:SetPoint("TOPRIGHT", TL.sticky, "BOTTOMRIGHT")
    TL.sticky.fade:SetHeight(8)
    gradient(TL.sticky.fade, "VERTICAL", C.bg, 0, 0.9, 0)
    TL.sticky.row = newHead(TL.sticky)
    TL.sticky.row:SetPoint("TOPLEFT", CARD_X, 0)
    TL.sticky.row:SetPoint("BOTTOMRIGHT", -10, 0)
    TL.sticky:Hide()

    function TL:MaxOff() return math.max(0, self.total - (self:GetHeight() or 0) + 8) end
    function TL:Release(key, r)
        r:Hide()
        r.item = nil
        if r.hovered then r.hovered = false r.hov:Hide() if r.acts then r.acts:Hide() end end
        self.used[key] = nil
        local pool = self.pools[r.type]
        pool[#pool + 1] = r
    end
    function TL:Layout(force)
        local H = self:GetHeight() or 0
        local off = math.floor(self.off + 0.5)
        for key, r in pairs(self.used) do
            local it = self.byKey[key]
            if not it or it.t ~= r.type or not (it.y + it.h > off and it.y < off + H) then self:Release(key, r)
            elseif force then r.item = nil end
        end
        local first, nextH
        for _, it in ipairs(self.items) do
            if it.t == "head" then
                if it.y <= off then first = it elseif not nextH and first then nextH = it end
            end
            if it.y + it.h > off and it.y < off + H then
                local r = self.used[it.key]
                if not r then
                    r = table.remove(self.pools[it.t]) or MAKE[it.t]()
                    self.used[it.key] = r
                    r.item = nil
                    r:Show()
                end
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", self, "TOPLEFT", CARD_X, -(it.y - off))
                r:SetPoint("RIGHT", self, "RIGHT", -10, 0)
                r:SetHeight(it.h - (it.t == "card" and GAP or 0))
                if r.item ~= it then
                    r.item = it
                    local ok, err = pcall(FILL[it.t], r, it)
                    if not ok and ns.err then ns.err(L["Quest items"], err) end
                end
            elseif it.y >= off + H and first then
                if it.t == "head" and not nextH then nextH = it end
                break
            end
        end
        -- pin chapter at the top, gently pushed out by the next one
        if first and off > 0 then
            local push = 0
            if nextH then push = math.min(0, (nextH.y - off) - (H_HEAD - 4)) end
            self.sticky:ClearAllPoints()
            self.sticky:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -push)
            self.sticky:SetPoint("RIGHT", self, "RIGHT", 0, 0)
            if self.sticky.cur ~= first then self.sticky.cur = first fillHead(self.sticky.row, first) end
            self.sticky:Show()
        else
            self.sticky:Hide()
        end
        local maxOff = self:MaxOff()
        if maxOff > 0 and H > 0 then
            local th = math.max(24, H * H / math.max(H, self.total))
            self.thumb:SetHeight(th)
            self.thumb:ClearAllPoints()
            self.thumb:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -((H - th) * off / maxOff))
            self.thumb:Show()
        else
            self.thumb:Hide()
        end
    end
    function TL:ScrollTo(v, animate)
        self.target = math.max(0, math.min(self:MaxOff(), v))
        saveUI()
        if not animate or not animOn() then
            self.off = self.target
            self:SetScript("OnUpdate", nil)
            self:Layout()
            return
        end
        self:SetScript("OnUpdate", function(s, el)
            local d = s.target - s.off
            if math.abs(d) < 0.6 then
                s.off = s.target
                s:SetScript("OnUpdate", nil)
            else
                s.off = s.off + d * math.min(1, el * 14)
            end
            s:Layout()
        end)
    end
    TL:SetScript("OnMouseWheel", function(self, delta) self:ScrollTo(self.target - delta * 72, true) end)
    TL:SetScript("OnSizeChanged", function(self) self:Layout(true) end)
    TL:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) self.off = self.target saveUI() end)

    -- keep = hold reading position (data reloaded): anchor is the topmost visible entry
    function TL:SetItems(items, keep)
        local anchorKey, anchorDy
        if keep and self.off > 0 then
            for _, it in ipairs(self.items) do
                if it.y + it.h > self.off then anchorKey, anchorDy = it.key, it.y - self.off break end
            end
        end
        local y, byKey = 0, {}
        for i, it in ipairs(items) do
            if byKey[it.key] then it.key = it.key .. "#" .. i end
            byKey[it.key] = it
            it.y = y
            y = y + it.h
        end
        self.items, self.total, self.byKey = items, y, byKey
        self.sticky.cur = nil
        if anchorKey and byKey[anchorKey] then
            self.off = byKey[anchorKey].y - anchorDy
            self.target = self.off
        elseif not keep then
            self.off, self.target = 0, 0
            self:SetScript("OnUpdate", nil)
        end
        self.off = math.max(0, math.min(self:MaxOff(), self.off))
        self.target = math.max(0, math.min(self:MaxOff(), self.target))
        self:Layout()
    end
    -- fade in visible cards staggered (only on open/tab change)
    function TL:Stagger()
        if not animOn() then return end
        local list = {}
        for _, r in pairs(self.used) do if r.item then list[#list + 1] = { r.item.y, r } end end
        table.sort(list, function(a, b) return a[1] < b[1] end)
        for i, x in ipairs(list) do
            local r = x[2]
            r:SetAlpha(0)
            K.Tween(r, 0.26, function(q) r:SetAlpha(q) end, function() r:SetAlpha(1) end, math.min(0.45, (i - 1) * 0.035))
        end
        ns.After(1.2, function() for _, r in pairs(self.used) do r:SetAlpha(1) end end)
    end
    return TL
end

------------------------------------------------------------------------
-- prepare entries (one description per card)
------------------------------------------------------------------------
local function chipNames(list)
    local t = {}
    for _, x in ipairs(list) do t[#t + 1] = low(ns.displayName(x.who)) end
    return table.concat(t, " ")
end
local function vmNeed(e)
    local nd, q = e.nd, e.q
    local id = itemIdOf(nd)
    local v = { key = "n:" .. q.id .. ":" .. low(nd.name), kind = "need", id = id, name = nd.name, have = nd.have or 0, need = nd.need or 1,
        zone = q.zone, glyph = "wants", color = C.amber, chips = {}, acts = {}, tip = {} }
    local bestG, bestF, anyOn
    for _, g in ipairs(e.givers) do
        v.chips[#v.chips + 1] = { who = g.who, on = g.on, giver = true, extra = K.hex(C.amber) .. g.n .. "x|r",
            tip = (L["has %d spare"]):format(g.n) .. (WHY[g.why] and (" (" .. L[WHY[g.why]] .. ")") or ""),
            fn = function() QI.AskFor(g.who, nd, q.title, g.demo) end }
        if g.on then anyOn = true if not bestG then bestG = g end end
    end
    for _, f in ipairs(e.farmers) do
        v.chips[#v.chips + 1] = { who = f.who, on = f.on, extra = "|cff888888" .. f.have .. "/" .. f.need .. "|r",
            tip = L["is collecting it too"] .. (f.same and (" - " .. L["same quest"]) or ""), click = L["Click: farm together (invite)"],
            fn = function() QI.FarmTogether(f.who, nd, f.demo) end }
        if f.on then anyOn = true if not bestF and not inGroup(f.who) then bestF = f end end
    end
    v.hot = anyOn == true
    local s = 5
    if bestG then s = 0 elseif #e.givers > 0 then s = 1 elseif anyOn then s = 2 elseif #e.farmers > 0 then s = 3 end
    v.score = s
    if bestG then
        v.primary = { text = L["Ask"], tip = (L["Whisper %s: do you have it spare?"]):format(ns.displayName(bestG.who)),
            fn = function() QI.AskFor(bestG.who, nd, q.title, bestG.demo) end }
    elseif bestF then
        v.primary = { text = L["Farm together"], tip = (L["Invite %s and farm together"]):format(ns.displayName(bestF.who)),
            fn = function() QI.FarmTogether(bestF.who, nd, bestF.demo) end }
    end
    local w = bestG or e.givers[1] or e.farmers[1]
    if w then
        v.acts[#v.acts + 1] = { glyph = "announce", tip = (L["Whisper %s"]):format(ns.displayName(w.who)),
            fn = function() if w.n then QI.AskFor(w.who, nd, q.title, w.demo) else whisperTo(w.who, w.demo) end end }
    end
    local inv
    for _, x in ipairs(e.givers) do if x.on and not inGroup(x.who) then inv = x break end end
    if not inv then for _, x in ipairs(e.farmers) do if x.on and not inGroup(x.who) then inv = x break end end end
    if inv then
        v.acts[#v.acts + 1] = { glyph = "groups", tip = (L["Invite %s"]):format(ns.displayName(inv.who)), fn = function() QI.Invite(inv.who, inv.demo) end }
    end
    if not q.demo then v.acts[#v.acts + 1] = { glyph = "map", tip = L["Open quest in quest log"], fn = function() openQuest(q.id, q.logIndex) end } end
    v.qline = questLine(q.title, q.lvl)
    if #v.chips == 0 then v.qline = v.qline .. "  |cff555555·|r  |cff666666" .. L["Nobody in the guild has it spare yet."] .. "|r" end
    v.tip[1] = questLine(q.title, q.lvl) .. ((q.zone and q.zone ~= "") and ("  |cff888888" .. q.zone .. "|r") or "")
    if #e.givers > 0 or #e.farmers > 0 then
        v.tip[2] = (L["%d have it spare, %d are collecting it too"]):format(#e.givers, #e.farmers)
    end
    v.search = table.concat({ low(nd.name), low(q.title), low(q.zone), chipNames(e.givers), chipNames(e.farmers) }, " ")
    v.menu = function()
        local m = {}
        for _, g in ipairs(e.givers) do
            m[#m + 1] = { text = (L["Whisper: %s (%dx spare)"]):format(ns.displayName(g.who), g.n), fn = function() QI.AskFor(g.who, nd, q.title, g.demo) end }
        end
        for _, f in ipairs(e.farmers) do
            if not inGroup(f.who) then
                m[#m + 1] = { text = (L["Farm together: %s"]):format(ns.displayName(f.who)), disabled = not f.on, fn = function() QI.FarmTogether(f.who, nd, f.demo) end }
            end
        end
        local seen, nInv = {}, 0
        for _, list in ipairs({ e.givers, e.farmers }) do
            for _, x in ipairs(list) do
                if x.on and not inGroup(x.who) and not seen[x.who] and nInv < 3 then
                    seen[x.who], nInv = true, nInv + 1
                    m[#m + 1] = { text = (L["Invite: %s"]):format(ns.displayName(x.who)), fn = function() QI.Invite(x.who, x.demo) end }
                end
            end
        end
        m[#m + 1] = { text = L["Link item in chat"], fn = function() linkItem(id, nd.name) end }
        if not q.demo then m[#m + 1] = { text = L["Open quest in quest log"], fn = function() openQuest(q.id, q.logIndex) end } end
        m[#m + 1] = { text = L["Hide"], fn = function() hideEntry(v.key) end }
        return m
    end
    return v
end
local function vmPush(e)
    local who = ns.displayName(e.who)
    local function ask()
        if e.demo then QI.Invite(e.who, true) return end
        ns.Whisper(e.who, (L["Can you share %s with me?"]):format(e.title))
    end
    local v = { key = "p:" .. e.qid .. ":" .. Comm.whoKey(e.who), kind = "push", name = e.title, nameColor = C.text, glyph = "announce", color = C.pink,
        badge = L["shareable quest"], badgeColor = C.pink, zone = L["Shareable quests"], score = 4, hot = true, acts = {},
        qline = "|cffa3a3a8" .. (L["%s can share the quest with you"]):format(who) .. "|r",
        chips = { { who = e.who, on = e.on, tip = L["can share the quest with you"], click = L["Click: ask for the quest"], fn = ask } },
        tip = { (L["%s can share the quest with you"]):format(who) } }
    if not inGroup(e.who) then
        v.primary = { text = L["Invite"], tip = (L["Invite %s - then the quest can be shared"]):format(who), fn = function() QI.Invite(e.who, e.demo) end }
    end
    v.acts[1] = { glyph = "announce", tip = L["Ask for the quest (whisper)"], fn = ask }
    v.search = low(e.title) .. " " .. low(who)
    v.menu = function()
        local m = { { text = L["Ask for the quest (whisper)"], fn = ask } }
        if not inGroup(e.who) then m[#m + 1] = { text = (L["Invite: %s"]):format(who), fn = function() QI.Invite(e.who, e.demo) end } end
        m[#m + 1] = { text = L["Hide"], fn = function() hideEntry(v.key) end }
        return m
    end
    return v
end
local function vmGive(e)
    local o = e.o
    local id = itemIdOf(o)
    local who = ns.displayName(e.who)
    local function offer() QI.OfferTo(e.who, o, e.title, e.demo) end
    local v = { key = "g:" .. Comm.whoKey(e.who) .. ":" .. (o.qid or 0) .. ":" .. low(o.name), kind = "give", id = id, name = o.name, have = o.have, need = o.need,
        glyph = "wants", color = C.blue, zone = e.on and L["Online"] or L["Offline"], score = e.on and 1 or 3, hot = e.on, acts = {},
        qline = questLine(e.title) .. "  |cff555555·|r  " .. K.hex(C.mint) .. (L["you have %d"]):format(e.have) .. "|r"
            .. (e.why and WHY[e.why] and ("  |cff777777(" .. L[WHY[e.why]] .. ")|r") or ""),
        chips = { { who = e.who, on = e.on, extra = "|cff888888" .. o.have .. "/" .. o.need .. "|r", tip = (L["needs it for %s"]):format(e.title or "?"),
            click = L["Click: offer (whisper)"], fn = offer } },
        tip = { (L["%s needs it for %s"]):format(who, e.title or "?"), (L["you have %d"]):format(e.have) } }
    if e.on then
        v.primary = { text = L["Offer"], tip = (L["Whisper %s: I have it for you"]):format(who), fn = offer }
        if not inGroup(e.who) then v.acts[#v.acts + 1] = { glyph = "groups", tip = (L["Invite %s"]):format(who), fn = function() QI.Invite(e.who, e.demo) end } end
    end
    table.insert(v.acts, 1, { glyph = "announce", tip = (L["Whisper %s"]):format(who), fn = offer })
    v.search = low(o.name) .. " " .. low(e.title) .. " " .. low(who)
    v.menu = function()
        local m = { { text = (L["Whisper: %s"]):format(who), fn = offer } }
        if e.on and not inGroup(e.who) then m[#m + 1] = { text = (L["Invite: %s"]):format(who), fn = function() QI.Invite(e.who, e.demo) end } end
        m[#m + 1] = { text = L["Link item in chat"], fn = function() linkItem(id, o.name) end }
        m[#m + 1] = { text = L["Hide"], fn = function() hideEntry(v.key) end }
        return m
    end
    return v
end
local function vmShare(e)
    local q = e.q
    local function push() if q.demo then ns.print(L["Demo: quest would be shared."]) else QI.Push(q.id) end end
    local v = { key = "s:" .. q.id, kind = "share", name = q.title, nameColor = C.text, glyph = "social", color = C.blue, badge = L["shareable quest"],
        badgeColor = C.blue, zone = L["Share quest"], score = 0, hot = true, chips = {}, acts = {},
        qline = "|cffa3a3a8" .. L["In your group without this quest:"] .. "|r",
        primary = { text = L["Share"], tip = L["Share quest with group"], fn = push }, tip = { L["In your group without this quest:"] } }
    local names = {}
    for _, n in ipairs(e.names) do
        v.chips[#v.chips + 1] = { who = n, on = true, tip = L["in your group"], fn = function() whisperTo(n, q.demo) end }
        names[#names + 1] = low(ns.displayName(n))
        v.tip[#v.tip + 1] = ns.displayName(n)
    end
    if not q.demo then v.acts[1] = { glyph = "map", tip = L["Open quest in quest log"], fn = function() openQuest(q.id, q.logIndex) end } end
    v.search = low(q.title) .. " " .. table.concat(names, " ")
    v.menu = function()
        local m = { { text = L["Share quest with group"], fn = push } }
        if not q.demo then m[#m + 1] = { text = L["Open quest in quest log"], fn = function() openQuest(q.id, q.logIndex) end } end
        m[#m + 1] = { text = L["Hide"], fn = function() hideEntry(v.key) end }
        return m
    end
    return v
end
local function vmMine(q, nd)
    local id = itemIdOf(nd)
    local v = { key = "m:" .. q.id .. ":" .. low(nd.name), kind = "mine", id = id, name = nd.name, have = nd.have or 0, need = nd.need or 1, done = nd.done,
        zone = q.zone, glyph = "checklist", color = C.mint, score = nd.done and 3 or 1, chips = {}, acts = {},
        qline = questLine(q.title, q.lvl) .. (nd.done and ("  |cff555555·|r  " .. K.hex(C.mint) .. L["done"] .. "|r") or ""),
        tip = { questLine(q.title, q.lvl) } }
    v.acts[1] = { glyph = "pin", tip = L["Link item in chat"], fn = function() linkItem(id, nd.name) end }
    if not q.demo then v.acts[2] = { glyph = "map", tip = L["Open quest in quest log"], fn = function() openQuest(q.id, q.logIndex) end } end
    v.search = low(nd.name) .. " " .. low(q.title) .. " " .. low(q.zone)
    v.menu = function()
        local m = { { text = L["Link item in chat"], fn = function() linkItem(id, nd.name) end } }
        if not q.demo then m[#m + 1] = { text = L["Open quest in quest log"], fn = function() openQuest(q.id, q.logIndex) end } end
        return m
    end
    return v
end
local function vmSpare(s)
    local qt = s.qid and questTitle(s.qid) or nil
    local v = { key = "x:" .. s.id .. ":" .. (s.qid or 0), kind = "spare", id = s.id, name = s.name, glyph = "wants", color = C.blue,
        badge = s.n .. "x " .. L["spare"], badgeColor = C.blue, zone = L["Spare in your bags"], score = 2, chips = {}, acts = {},
        qline = "|cffa3a3a8" .. L[WHY[s.why] or "uebrig"] .. (qt and ("  |cff555555·|r  " .. qt) or "") .. "|r",
        tip = { L["Offered to the guild automatically."] } }
    v.acts[1] = { glyph = "pin", tip = L["Link item in chat"], fn = function() linkItem(s.id, s.name) end }
    v.search = low(s.name) .. " " .. low(qt)
    v.menu = function() return { { text = L["Link item in chat"], fn = function() linkItem(s.id, s.name) end } } end
    return v
end

-- group by zone, sort, chapter before them
local function closeness(v) return v.need and ((v.have or 0) / math.max(1, v.need)) or -1 end
local function arrange(vms, color)
    local groups, byZone = {}, {}
    for _, v in ipairs(vms) do
        local z = (v.zone and v.zone ~= "") and v.zone or L["No zone"]
        local g = byZone[z]
        if not g then
            g = { zone = z, list = {}, best = 99, hot = 0, close = -2 }
            byZone[z] = g
            groups[#groups + 1] = g
        end
        g.list[#g.list + 1] = v
        g.best = math.min(g.best, v.score or 9)
        g.close = math.max(g.close, closeness(v))
        if v.hot then g.hot = g.hot + 1 end
    end
    local function cmp(a, b)
        if sortBy == "close" then
            local ca, cb = closeness(a), closeness(b)
            if ca ~= cb then return ca > cb end
        elseif sortBy == "helper" then
            if (a.hot == true) ~= (b.hot == true) then return a.hot == true end
            if (a.score or 9) ~= (b.score or 9) then return (a.score or 9) < (b.score or 9) end
        end
        return low(plain(a.name)) < low(plain(b.name))
    end
    for _, g in ipairs(groups) do table.sort(g.list, cmp) end
    table.sort(groups, function(a, b)
        local here = ns.safe(GetRealZoneText()) or ""
        if zoneMode ~= "all" and (a.zone == here) ~= (b.zone == here) then return a.zone == here end
        if sortBy == "helper" and (a.hot > 0) ~= (b.hot > 0) then return a.hot > 0 end
        if sortBy == "helper" and a.best ~= b.best then return a.best < b.best end
        if sortBy == "close" and a.close ~= b.close then return a.close > b.close end
        return low(a.zone) < low(b.zone)
    end)
    local items = {}
    for _, g in ipairs(groups) do
        local info = (L["%d entries"]):format(#g.list)
        if g.hot > 0 and view == "help" then info = info .. "  ·  " .. K.hex(C.mint) .. (L["%d with helpers online"]):format(g.hot) .. "|r" end
        -- on a search show all hits without losing the saved collapse state.
        local here = ns.safe(GetRealZoneText()) or ""
        local folded = collapsed[g.zone]
        if folded == nil then folded = view == "help" and zoneMode == "focus" and g.zone ~= here and g.hot == 0 end
        local closed = search == "" and folded == true
        items[#items + 1] = { t = "head", key = "h:" .. g.zone, zone = g.zone, closed = closed, label = g.zone, info = info, color = (g.list[1] and g.list[1].color) or color, h = H_HEAD }
        if not closed then
            for _, v in ipairs(g.list) do
                local slim = compact() or #(v.chips or {}) == 0
                items[#items + 1] = { t = "card", key = v.key, vm = v, slim = slim, h = (slim and H_SLIM or H_CARD) + GAP }
            end
        end
    end
    return items
end

-- tab/filter change: crossfade content softly, reset reading position
local function switchTo(newView, newTile)
    saveUI()
    view, tileFilter = newView, newTile
    if page and page.tl then
        page.switch = true
        if animOn() then
            local tl = page.tl
            tl:SetAlpha(0.15)
            K.Tween(tl, 0.22, function(q) tl:SetAlpha(0.15 + 0.85 * q) end, function() tl:SetAlpha(1) end)
        end
    end
    ns.RefreshPage("questitems")
end
local function onTile(k)
    if k == "can" then switchTo("can", nil)
    elseif k == "open" then switchTo("help", nil)
    elseif view == "help" and tileFilter == k then switchTo("help", nil)
    else switchTo("help", k) end
end

local TOOL_Y = -116
local apiOk = true
ns.RegisterPage({
    key = "questitems", title = "Quest items", order = 2.82,
    sub = "Who has the quest item you need? And whom can you help?",
    build = function(p)
        loadUI()
        page = p
        p.fresh = true
        p:HookScript("OnShow", function(self) self.fresh = true end)

        p.tabs = buildTabs(p, function(k) switchTo(k, nil) end)
        p.tabs:SetPoint("TOPLEFT", 0, 0)
        p.status = buildStatus(p, function() lastHash = nil sendNow(true) ns.RefreshPage("questitems") end)
        p.status:SetPoint("TOPRIGHT", 0, -5)

        -- Stat tiles
        p.tileRow = CreateFrame("Frame", nil, p)
        p.tileRow:SetPoint("TOPLEFT", 0, -46)
        p.tileRow:SetPoint("TOPRIGHT", 0, -46)
        p.tileRow:SetHeight(62)
        p.tiles = {}
        for i, d in ipairs(TILES) do p.tiles[i] = buildTile(p.tileRow, d, onTile) end

        -- toolbar: search, sorting, "only with helpers", hidden, count
        p.search = K.Input(p, 170, L["Search ..."], function(t)
            local s = (t or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
            if s == search then return end
            search = s
            ns.RefreshPage("questitems")
        end)
        p.search:SetPoint("TOPLEFT", 0, TOOL_Y)
        p.search:SetText(search)
        p.sort = calmButton(K.Button(p, "", 150, 22, "ghost"))
        p.sort.isDropdown = true
        K.SetFontSafe(p.sort.label, K.FONT, 11, "", K.FONT)
        p.sort:SetPoint("LEFT", p.search, "RIGHT", 8, 0)
        p.sort:SetScript("OnClick", function(self)
            local items = {}
            for _, s in ipairs(SORTS) do
                items[#items + 1] = { text = L[s.text], checked = sortBy == s.key, fn = function() sortBy = s.key ns.RefreshPage("questitems") end }
            end
            K.ShowMenu(self, items, L["Sort by"], 160)
        end)
        p.helpChip = buildChip(p, L["Online helpers only"], function() return onlyHelp end, function(v) onlyHelp = v ns.RefreshPage("questitems") end)
        p.hidChip = K.Button(p, "", 120, 22, "ghost", function()
            ns.char.qiHidden = {}
            ns.RefreshPage("questitems")
        end)
        K.SetFontSafe(p.hidChip.label, K.FONT, 11, "", K.FONT)
        p.hidChip:HookScript("OnEnter", function(self) K.ShowTip(self, { L["Hidden entries"], "|cff888888" .. L["Click: show all again"] .. "|r" }) end)
        p.hidChip:HookScript("OnLeave", function() GameTooltip:Hide() end)
        p.viewButton = calmButton(K.Button(p, L["Reset view"], 76, 22, "ghost"))
        p.viewButton.isDropdown = true
        p.viewButton:SetScript("OnClick", function(self)
            local function setCompact(value)
                ns.char.qiCompact = value
                ns.RefreshPage("questitems")
            end
            local function foldAll(value)
                for _, it in ipairs(p.tl.items) do
                    if it.t == "head" and it.zone then collapsed[it.zone] = value end
                end
                ns.RefreshPage("questitems")
            end
            K.ShowMenu(self, {
                { text = L["Current zone first"], checked = zoneMode == "focus", fn = function() zoneMode = "focus" ns.RefreshPage("questitems") end },
                { text = L["Current zone only"], checked = zoneMode == "here", fn = function() zoneMode = "here" ns.RefreshPage("questitems") end },
                { text = L["All zones"], checked = zoneMode == "all", fn = function() zoneMode = "all" ns.RefreshPage("questitems") end },
                { text = L["Disable animations"], checked = S().noAnim == true, fn = function() S().noAnim = not S().noAnim ns.RefreshPage("questitems") end },
                { text = L["Compact list"], checked = compact(), fn = function() setCompact(true) end },
                { text = L["Detailed cards"], checked = not compact(), fn = function() setCompact(false) end },
                { text = L["Collapse all zones"], fn = function() foldAll(true) end },
                { text = L["Expand all zones"], fn = function() foldAll(false) end },
            }, L["Reset view"], 210)
        end)
        p.count = K.Text(p, 11, C.dim, "RIGHT")
        p.count:SetPoint("TOPRIGHT", p, "TOPRIGHT", -12, TOOL_Y - 6)

        -- list + empty state
        p.tl = buildList(p)
        p.tl:SetPoint("TOPLEFT", 0, TOOL_Y - 32)
        p.tl:SetPoint("BOTTOMRIGHT", 0, 0)
        p.empty = emptyState(p.tl)
        p.empty:SetPoint("TOP", 0, -40)

        function p:Layout()
            local W = self:GetWidth() or 760
            if W < 50 then return end
            -- Tiles
            local n, gap = #self.tiles, 8
            local tw = math.floor((W - gap * (n - 1)) / n)
            for i, t in ipairs(self.tiles) do
                t.bx, t.bw = (i - 1) * (tw + gap), tw
                t:Place()
            end
            -- header row: status on the right, tabs take the rest
            self.statusMax = math.floor(W * 0.46)
            local sa = self.statusArgs or { C.dim, "", "" }
            self.status:Set(sa[1], sa[2], sa[3], sa[4], self.statusMax)
            self.tabs.maxW = math.max(160, W - (self.status:GetWidth() or 240) - 16)
            self.tabs:Layout()
            -- Toolbar
            self.search:SetWidth(W < 640 and 130 or 170)
            local x = (W < 640 and 130 or 170) + 8 + (self.sort:GetWidth() or 150)
            local row = 0
            local function place(b, show)
                local bw = b:GetWidth() or 100
                if show and x + 6 + bw > W - 8 then row = row + 1 x = -6 end
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", self, "TOPLEFT", x + 6, TOOL_Y - row * 28)
                b:SetShown(show)
                if show then x = x + 6 + bw end
            end
            place(self.helpChip, view == "help")
            place(self.hidChip, (self.nHidden or 0) > 0)
            place(self.viewButton, true)
            local wrapped = row > 0
            self.tl:ClearAllPoints()
            self.tl:SetPoint("TOPLEFT", 0, TOOL_Y - 32 - row * 28)
            self.tl:SetPoint("BOTTOMRIGHT", 0, 0)
            self.count:SetShown(not wrapped and W - x > 110)
        end
        p:HookScript("OnSizeChanged", function(self) self:Layout() end)
        p:Layout()
    end,
    refresh = function(p)
        local fresh, switch = p.fresh, p.switch
        p.fresh, p.switch = false, nil
        local bags, slots = scanBags()
        local quests, ok = QI.MyQuests(bags)
        apiOk = ok
        local spare = QI.MySpare(quests, bags, slots)
        local help = QI.HelpForMe(quests)
        local can = QI.ICanHelp(quests, spare, bags)

        -- Stats
        local open, helpers, pushN, mineN = 0, {}, 0, #spare
        for _, q in ipairs(quests) do
            for _, nd in ipairs(q.needs) do
                mineN = mineN + 1
                if not nd.done then open = open + 1 end
            end
        end
        for _, h in ipairs(help) do
            for _, g in ipairs(h.givers or {}) do if g.on then helpers[g.who] = true end end
            for _, f in ipairs(h.farmers or {}) do if f.on then helpers[f.who] = true end end
            if h.kind == "push" then helpers[h.who] = true pushN = pushN + 1 end
        end
        local nh = 0
        for _ in pairs(helpers) do nh = nh + 1 end
        local vals = { open = open, helpers = nh, can = #can, push = pushN }
        for i, t in ipairs(p.tiles) do
            local n = vals[t.key] or 0
            t:SetSel((t.key == "open" and view == "help" and not tileFilter) or (t.key == "can" and view == "can") or (view == "help" and tileFilter == t.key))
            local vc = n > 0 and C.text or C.dim
            t.value:SetTextColor(vc[1], vc[2], vc[3])
            if fresh and animOn() then K.CountUp(t.value, n, 0.8, nil, (i - 1) * 0.05)
            elseif t.shown ~= n then t.value:SetText(n) end
            t.shown = n
        end
        if fresh and animOn() then for i, t in ipairs(p.tiles) do K.FadeIn(t, (i - 1) * 0.05) end end
        p.tabs:SetCounts({ help = #help, can = #can, mine = mineN })
        p.tabs:Select(view, not fresh)

        -- Status pill
        local n = #others()
        local dot, long, short
        if S().qiShare == false then
            dot, long, short = C.red, L["Sharing is off (settings)"], L["Sharing is off"]
        else
            dot = lastSent == 0 and C.dim or ((ns.now() - lastSent < 900) and C.mint or C.amber)
            local when = lastSent > 0 and ns.ago(lastSent) or L["not yet"]
            long = (L["%d players with quest item data"]):format(n) .. "  |cff555555·|r  " .. L["shared"] .. " " .. when
            short = (L["%d players"]):format(n) .. "  |cff555555·|r  " .. when
        end
        p.statusArgs = { dot, long, short, { L["Guild quest items"], long,
            "|cff888888" .. L["Only members with Oasis. Shared: open quest items, spare quest items and shareable quests."] .. "|r" } }

        -- entries of the tab
        local vms, nHidden, total = {}, 0, 0
        local hid = hidden()
        local function add(v)
            total = total + 1
            if view ~= "mine" and hid[v.key] then nHidden = nHidden + 1 return end
            if view == "help" then
                if tileFilter == "push" and v.kind ~= "push" then return end
                if tileFilter == "helpers" and not v.hot then return end
                if onlyHelp and not v.hot then return end
            end
            if zoneMode == "here" and search == "" and v.zone ~= (ns.safe(GetRealZoneText()) or "") then return end
            if search ~= "" and not (v.search or ""):find(search, 1, true) then return end
            vms[#vms + 1] = v
        end
        if ok then
            if view == "help" then
                for _, e in ipairs(help) do add(e.kind == "push" and vmPush(e) or vmNeed(e)) end
            elseif view == "can" then
                for _, e in ipairs(can) do add(e.kind == "share" and vmShare(e) or vmGive(e)) end
            else
                for _, q in ipairs(quests) do for _, nd in ipairs(q.needs) do add(vmMine(q, nd)) end end
                for _, s in ipairs(spare) do add(vmSpare(s)) end
            end
        end
        local tabColor = view == "can" and C.blue or view == "mine" and C.mint or C.amber
        local items = arrange(vms, tabColor)
        p.tl:SetItems(items, not (fresh or switch))
        if fresh or switch then
            local saved = uiState().scroll and uiState().scroll[view]
            if type(saved) == "number" then p.tl:ScrollTo(saved, false) end
        end
        if fresh or switch then p.tl:Stagger() end

        -- empty state with a fitting action
        p.empty:SetShown(#items == 0)
        if #items == 0 then
            local filtered = zoneMode == "here" or search ~= "" or (view == "help" and (onlyHelp or tileFilter ~= nil)) or nHidden > 0
            if not ok then
                p.empty:Set("wants", C.red, L["Your game client does not return the quest log as expected - this page stays empty.\nUse /oa probe questitems to see what arrives."],
                    L["Run probe"], function() QI.Probe() end)
            elseif filtered and total > 0 then
                p.empty:Set("wants", C.muted, L["Nothing found – try other filters?"], L["Reset filters"], function()
                    search, onlyHelp, tileFilter, zoneMode = "", false, nil, "all"
                    p.search:SetText("")
                    p.helpChip:Update()
                    ns.char.qiHidden = {}
                    ns.RefreshPage("questitems")
                end)
            elseif view == "help" then
                p.empty:Set("wants", C.amber, L["No open quest items in your quest log.\nAccept collection quests - Oasis shows you who in the guild can help."],
                    L["Quest together"], function() ns.ShowPage("social") end, L["I can help"], function() switchTo("can", nil) end)
            elseif view == "can" then
                p.empty:Set("heart", C.blue, L["Nobody needs anything you have right now.\nSpare quest items in your bags are offered automatically."],
                    L["My quest items"], function() switchTo("mine", nil) end, L["Share now"], function() lastHash = nil sendNow(true) ns.RefreshPage("questitems") end)
            else
                p.empty:Set("checklist", C.mint, L["No quest items in your quest log or bags."],
                    L["Open quest log"], function()
                        if ToggleQuestLog then pcall(ToggleQuestLog) elseif QuestLogFrame and ShowUIPanel then pcall(ShowUIPanel, QuestLogFrame) end
                    end)
            end
        end

        -- Toolbar
        local sl
        for _, s in ipairs(SORTS) do if s.key == sortBy then sl = L[s.text] end end
        p.sort:SetLabel("|cff888888" .. L["Sort:"] .. "|r " .. (sl or "") .. "  |cff666666v|r")
        p.sort:SetWidth(math.floor((p.sort.label:GetStringWidth() or 120) + 24))
        p.helpChip:Update()
        p.nHidden = nHidden
        if nHidden > 0 then
            p.hidChip:SetLabel((L["%d hidden"]):format(nHidden) .. "  |cff888888x|r")
            p.hidChip:SetWidth(math.floor((p.hidChip.label:GetStringWidth() or 90) + 22))
        end
        local cards = 0
        for _, it in ipairs(items) do if it.t == "card" then cards = cards + 1 end end
        p.count:SetText((L["%d entries"]):format(cards))
        p:Layout()
        saveUI()
    end,
})

-- item data arrives later: refill visible cards (throttled, reading position stays)
local itemPend
local function itemsArrived()
    if itemPend or not (page and page.IsVisible and page:IsVisible()) then return end
    itemPend = true
    ns.After(0.6, function()
        itemPend = nil
        if page and page:IsVisible() then ns.RefreshPage("questitems") end
    end)
end
pcall(ns.On, "GET_ITEM_INFO_RECEIVED", itemsArrived)
pcall(ns.On, "ITEM_DATA_LOAD_RESULT", itemsArrived)
refreshPage = function() ns.RefreshPage("questitems") end

------------------------------------------------------------------------
-- settings of the section
------------------------------------------------------------------------
if ns.AddPageSettings then
    ns.AddPageSettings("questitems", function(det, y)
        local s = S()
        local defs = {
            { "Share my quest items with the guild", "qiShare", "Open and spare quest items plus shareable quests" },
            { "Notify me when someone can help", "qiToast", "At most every 2 minutes, per player and item every 30 minutes" },
            { "Item tooltip line: needed by", "qiTooltip", "Shows who in the guild needs the item for a quest" },
        }
        for _, d in ipairs(defs) do
            if s[d[2]] == nil then s[d[2]] = true end
            local t = K.Toggle(det, L[d[1]], function() return S()[d[2]] ~= false end, function(v)
                S()[d[2]] = v
                if d[2] == "qiShare" and v then lastHash = nil sendNow(true) end
                refreshPage()
            end, L[d[3]])
            t:SetPoint("TOPLEFT", 14, y)
            t:SetWidth(600)
            if det.t then det.t[#det.t + 1] = t end
            y = y - 44
        end
        return y - 10
    end)
end

------------------------------------------------------------------------
-- /oa probe questitems: what do the APIs deliver in the game?
------------------------------------------------------------------------
function QI.Probe()
    local Q, CC = C_QuestLog, C_Container
    local function has(t, f) return api(t, f) and "ja" or "FEHLT" end
    ns.print("Questitems-Probe:")
    ns.print(("  C_QuestLog.GetQuestObjectives %s  IsPushableQuest %s  IsQuestFlaggedCompleted %s  SetSelectedQuest %s"):format(
        has(Q, "GetQuestObjectives"), has(Q, "IsPushableQuest"), has(Q, "IsQuestFlaggedCompleted"), has(Q, "SetSelectedQuest")))
    ns.print(("  GetQuestLogItemLink %s  GetNumQuestLogRequiredItems %s  QuestLogPushQuest %s  C_Container.GetContainerItemQuestInfo %s"):format(
        GetQuestLogItemLink and "ja" or "FEHLT", GetNumQuestLogRequiredItems and "ja" or "FEHLT", QuestLogPushQuest and "ja" or "FEHLT", has(CC, "GetContainerItemQuestInfo")))
    local quests, ok = QI.MyQuests()
    ns.print(("  Questlog lesbar: %s, %d Quests"):format(tostring(ok), #quests))
    local shown = 0
    for _, q in ipairs(quests) do
        if shown >= 6 then break end
        shown = shown + 1
        local raw = {}
        if api(Q, "GetQuestObjectives") then
            local okO, objs = pcall(Q.GetQuestObjectives, q.id)
            for _, o in ipairs(okO and type(objs) == "table" and objs or {}) do
                raw[#raw + 1] = ("[%s] %s (%s/%s)"):format(tostring(o.type), tostring(o.text), tostring(o.numFulfilled), tostring(o.numRequired))
            end
        end
        ns.print(("  #%d %s  teilbar=%s fertig=%s"):format(q.id, q.title, tostring(q.push), tostring(q.done)))
        for _, r in ipairs(raw) do ns.print("     " .. r) end
        for _, nd in ipairs(q.needs) do ns.print(("     -> Item %s = ID %s"):format(nd.name, tostring(nd.id))) end
    end
    local _, slots = scanBags()
    ns.print(("  Questitems in den Taschen: %d"):format(#slots))
    for i, s in ipairs(slots) do
        if i > 8 then break end
        ns.print(("     %s (%d) x%d isQuestItem=%s questID=%s isActive=%s erledigt=%s"):format(tostring(s.name), s.id, s.n, tostring(s.isQuest),
            tostring(s.qid), tostring(s.active), tostring(s.qid and isDone(s.qid))))
    end
    local rec = QI.Snapshot()
    ns.print(("  Geteilt: brauche %d Zeichen, uebrig %d Zeichen, teilbar '%s'"):format(#(rec.n or ""), #(rec.s or ""), rec.p or ""))
end
do
    local prev = ns.slash.probe
    ns.slash.probe = function(rest)
        local topic = (rest or ""):match("^(%S*)"):lower()
        if topic == "questitems" or topic == "qi" then QI.Probe() return end
        if prev then return prev(rest) end
        ns.print("/oa probe questitems")
    end
    ns.slash.qiprobe = QI.Probe
end

------------------------------------------------------------------------
-- Start
------------------------------------------------------------------------
ns.Listen("LOGIN", function()
    prune()
    ns.Every(600, prune)
    ns.After(15, function()
        sendNow(true)
        if IsInGuild() then Comm.Guild("QIREQ") end
    end)
    ns.Every(HEARTBEAT, function() sendNow(false) end)
    local D = ns.Demo
    if D and not D.qiHooked and D.Load and D.Remove then
        D.qiHooked = true
        local load, remove = D.Load, D.Remove
        D.Load = function(...) load(...) QI.SeedDemo() end
        D.Remove = function(...) remove(...) QI.RemoveDemo() end
        if D.IsActive() then ns.After(3, QI.SeedDemo) end
    end
end)
end)
