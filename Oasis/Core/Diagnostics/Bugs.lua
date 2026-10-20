-- Oasis - Bug reports: collect Lua errors from Oasis automatically + manual bug reports,
-- both go via the guild collection "bugs" to the developer (clients with /oa entwickler).
-- Whoever does not want to share: checkbox "Share errors automatically" in the report window (settings.shareErrors).
local ADDON, ns = "Oasis", Oasis   -- guild module: runs in the Oasis namespace (dependency in Oasis_Guild.toc)
if not ns then return end
local K, C, L = ns.K, ns.K.C, ns.L

local B = {}
ns.Bugs = B
local ICON = ns.MEDIA .. "icons\\bug"
B.ICON = ICON

local function S() return ns.db and ns.db.settings end
local function Store() return ns.Store end

------------------------------------------------------------------------
-- collect errors
------------------------------------------------------------------------
-- shorten paths, drop memory addresses (otherwise every error becomes a new entry)
local function clean(s, max)
    s = tostring(s or "")
    s = s:gsub("Interface[\\/]AddOns[\\/]Oasis[\\/]", "")
    s = s:gsub("Interface[\\/]AddOns[\\/]", "")
    s = s:gsub("table: [%x]+", "table"):gsub("function: [%x]+", "function"):gsub("0x%x+", "0x")
    s = s:gsub("|", "||")
    if #s > (max or 400) then s = s:sub(1, max or 400) .. "..." end
    return s
end
B.clean = clean

local pending = {}        -- errors before the saved file is loaded
local lastPut = {}        -- id -> time of last send (throttle: at most every 10 min per error)
local sessionNew = 0      -- limit new bug reports per session (endless loops!)
local busy = false

function B.Record(where, msg, stack)
    if busy then return end
    busy = true
    local ok = pcall(function()
        if not (ns.db and ns.db.store and Store() and ns.me and ns.me()) then
            if #pending < 20 then pending[#pending + 1] = { where, msg, stack } end
            return
        end
        if S().shareErrors == false then return end
        local m = clean(msg, 400)
        local w = clean(where, 60)
        local me = ns.me()
        local id = "bug-e-" .. ns.hash(me .. "|" .. w .. "|" .. m .. "|" .. (ns.version or ""))
        local cur = Store().Get("bugs", id)
        local now = ns.now()
        if cur then
            -- known error: only increase counter, send at most every 10 minutes
            local rec = {}
            for k, v in pairs(cur) do rec[k] = v end
            rec.n = (tonumber(rec.n) or 1) + 1
            rec.last = now
            if now - (lastPut[id] or 0) >= 600 then
                lastPut[id] = now
                Store().Put("bugs", rec)
            else
                Store().coll("bugs")[id] = rec   -- count locally, include on next send
            end
            return
        end
        if sessionNew >= 15 then return end
        sessionNew = sessionNew + 1
        lastPut[id] = now
        local rec = Store().Put("bugs", {
            id = id, kind = "e", w = w, m = m, s = clean(stack, 700), n = 1,
            t = now, last = now, v = ns.version, lc = GetLocale and GetLocale() or "",
        })
        if ns.Net and ns.Net.QueueBug then pcall(ns.Net.QueueBug, rec) end
        B.Wago(m)
    end)
    busy = false
    return ok
end

-- "Oasis was blocked" (ADDON_ACTION_FORBIDDEN/_BLOCKED): also into the shared collection,
-- so the developer gets it via sync - even if he was not online (previously only a TNT live message)
function B.RecordBlock(e)
    if not (e and ns.db and ns.db.store and Store() and ns.me and ns.me()) then return end
    if S().shareErrors == false then return end
    local fn = clean(e.fn, 60)
    local id = "bug-t-" .. ns.hash(ns.me() .. "|" .. fn .. "|" .. (ns.version or ""))
    local now = ns.now()
    local cur = Store().Get("bugs", id)
    local zone = ns.safe(GetRealZoneText and GetRealZoneText()) or ""
    local rec = {}
    if cur then for k, v in pairs(cur) do rec[k] = v end end
    rec.id, rec.kind, rec.w, rec.m = id, "t", "Blocked", fn
    rec.n = cur and ((tonumber(cur.n) or 1) + 1) or 1
    rec.t = rec.t or now
    rec.last = now
    rec.v, rec.lc = ns.version, GetLocale and GetLocale() or ""
    rec.pg = tostring(e.page or ""):sub(1, 30)
    rec.z = zone:sub(1, 40)
    rec.cb = e.combat and 1 or nil
    rec.s = clean(e.trail or "", 400)
    rec.ad = S().shareAddonList and clean(e.addons or "", 400) or nil   -- 0.5.617: addon list only with consent
    if cur and now - (lastPut[id] or 0) < 600 then
        Store().coll("bugs")[id] = rec   -- count locally, include on next send
        return
    end
    if not cur then
        if sessionNew >= 15 then return end
        sessionNew = sessionNew + 1
    end
    lastPut[id] = now
    Store().Put("bugs", rec)
    if not cur then
        if ns.Net and ns.Net.QueueBug then pcall(ns.Net.QueueBug, rec) end
        B.Wago("Blockiert: " .. tostring(rec.m))
    end
end

-- Wago Analytics (optional): if the addon "WagoAnalytics" is loaded and a project ID is set (ns.WAGO_ID
-- in Core.lua), errors also go via the Wago app to the developer dashboard - only for players
-- who enabled "Help addon developers" there. Without ID/addon nothing happens.
local wago
function B.Wago(msg)
    if wago == nil then
        wago = false
        local id = ns.WAGO_ID
        local LS = _G.LibStub
        local lib = id and id ~= "" and LS and LS("WagoAnalytics", true)
        if lib and lib.Register then
            local ok, o = pcall(lib.Register, lib, id)
            if ok and o then wago = o end
        end
    end
    if wago and wago.Error then pcall(wago.Error, wago, tostring(msg or ""):sub(1, 400)) end
end

-- bug report to copy (for Discord/GitHub): version, client, language + the last own reports
function B.ReportText(userText)
    local t = {}
    t[#t + 1] = "**Oasis " .. tostring(ns.version or "?") .. "** (" .. tostring(ns.versionDate or "") .. ")"
    local _, build = GetBuildInfo()
    t[#t + 1] = "Client: " .. tostring(build or "?") .. " · " .. tostring(GetLocale and GetLocale() or "") .. " · " .. tostring(ns.safe(GetRealZoneText and GetRealZoneText()) or "")
    if userText and userText:gsub("%s", "") ~= "" then t[#t + 1] = "" t[#t + 1] = userText end
    local mine = {}
    for _, r in ipairs(Store() and Store().List("bugs") or {}) do
        if ns.isMe(r.by) and r.kind ~= "r" then mine[#mine + 1] = r end
    end
    table.sort(mine, function(a, b) return (a.last or a.t or 0) > (b.last or b.t or 0) end)
    if #mine > 0 then t[#t + 1] = "" t[#t + 1] = "Letzte Fehler:" end
    for i = 1, math.min(5, #mine) do
        local r = mine[i]
        t[#t + 1] = ("- [%s] v%s %dx: %s"):format(r.kind == "t" and "Blocked" or (r.w or "Lua"), tostring(r.v or "?"), tonumber(r.n) or 1, tostring(r.m or ""):gsub("||", "|"))
        if r.s and r.s ~= "" then t[#t + 1] = "  " .. tostring(r.s):gsub("||", "|"):gsub("\n", "\n  "):sub(1, 400) end
    end
    return table.concat(t, "\n")
end
local copyWin
function B.ShowCopy(text)
    if not copyWin then
        local f = CreateFrame("Frame", "OasisBugCopy", UIParent)
        f:SetSize(520, 330)
        f:SetPoint("CENTER", 0, 40)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        K.Fill(f, C.bg)
        K.Border(f, C.line)
        if K.ApplySkin then K.ApplySkin(f, "panel", C.bg) end
        ns.EscClose("OasisBugCopy")
        f.title = K.Title(f, 14, C.text)
        f.title:SetPoint("TOPLEFT", 16, -14)
        f.title:SetText(L["Copy error report"])
        f.sub = K.Text(f, 11, C.muted)
        f.sub:SetPoint("TOPLEFT", 16, -36)
        f.sub:SetPoint("RIGHT", -16, 0)
        f.sub:SetWordWrap(true)
        local close = K.CloseButton(f, function() f:Hide() end)
        close:SetPoint("TOPRIGHT", -8, -8)
        local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 16, -72)
        sf:SetPoint("BOTTOMRIGHT", -34, 16)
        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetAutoFocus(false)
        eb:SetFont(K.FONT, 11, "")
        eb:SetWidth(460)
        eb:SetScript("OnEscapePressed", function() f:Hide() end)
        eb:SetScript("OnTextChanged", function(self, user) if user and self.locked then self:SetText(self.locked) self:HighlightText() end end)
        sf:SetScrollChild(eb)
        f.eb = eb
        copyWin = f
    end
    local link = ns.SUPPORT_URL
    copyWin.sub:SetText(L["Ctrl+A, Ctrl+C - then paste it where the developer reads it"] .. ((link and link ~= "") and (": |cff6ab0ff" .. link .. "|r") or "."))
    copyWin.eb.locked = text
    copyWin.eb:SetText(text)
    copyWin:Show()
    copyWin.eb:SetFocus()
    copyWin.eb:HighlightText()
end

-- real Lua errors: wrap WoW's error handler, only remember errors from Oasis files
do
    local get, set = _G.geterrorhandler, _G.seterrorhandler
    local prev = get and get()
    if set and prev then
        set(function(msg, ...)
            pcall(function()
                local s = tostring(msg)
                local st = debugstack and debugstack(3, 8, 0) or ""
                -- remove own error handler (Bugs.lua) and C lines from the stack,
                -- otherwise foreign errors (e.g. from nesUI) end up here
                local lines = {}
                for ln in st:gmatch("[^\n]+") do
                    if not ln:find("Modules[\\/]Bugs%.lua") and not ln:find("^%[C%]") then lines[#lines + 1] = ln end
                    if #lines >= 3 then break end
                end
                local first = table.concat(lines, "\n")
                -- foreign addon in the error text ("tainted by 'nesUI'") -> not our error
                local foreign = s:match("tainted by '([^']+)'")
                if foreign and foreign ~= "Oasis" then return end
                if s:find("AddOns[\\/]Oasis[\\/]") or first:find("AddOns[\\/]Oasis[\\/]") then
                    B.Record("Lua", s, st)
                end
            end)
            return prev(msg, ...)
        end)
    end
end

-- also report ns.err (caught errors in modules)
do
    local orig = ns.err
    ns.err = function(where, msg, ...)
        orig(where, msg, ...)
        B.Record(where, msg, (ns.lastErrStack and GetTime() - (ns.lastErrAt or 0) < 0.5) and ns.lastErrStack or (debugstack and debugstack(2, 6, 0) or ""))
    end
end

------------------------------------------------------------------------
-- manual bug report
------------------------------------------------------------------------
B.CATS = {
    { key = "bug", text = "Bug" },
    { key = "idea", text = "Idea" },
    { key = "other", text = "Miscellaneous" },
}
function B.Submit(cat, text)
    text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return false end
    local zone = GetRealZoneText and GetRealZoneText() or ""
    local rec = {
        id = ns.newId("bug"), kind = "r", cat = cat or "bug", m = text:sub(1, 600),
        pg = ns.CurrentPage and ns.CurrentPage() or "", z = zone, lvl = UnitLevel and UnitLevel("player") or 0,
        t = ns.now(), v = ns.version, lc = GetLocale and GetLocale() or "",
    }
    Store().Put("bugs", rec)
    if ns.Net and ns.Net.QueueBug then pcall(ns.Net.QueueBug, rec) end
    return true
end

------------------------------------------------------------------------
-- developer: list, new, done
------------------------------------------------------------------------
function B.All()
    local out = Store() and Store().List("bugs") or {}
    if ns.Net and ns.Net.Incoming and ns.IsDev and ns.IsDev() then
        for _, r in ipairs(ns.Net.Incoming()) do out[#out + 1] = r end
    end
    -- do not show cleaned up (deleted) reports anymore - only for me, the guild keeps them until expiry
    local gone = ns.db.bugGone
    if gone and next(gone) then
        local keep = {}
        for _, r in ipairs(out) do if not gone[r.id] then keep[#keep + 1] = r end end
        out = keep
    end
    table.sort(out, function(a, b) return (a.last or a.t or 0) > (b.last or b.t or 0) end)
    return out
end
-- fixed in version X: reports from older versions automatically count as done
-- (key = function for blocks or start of the error message). Add here with every fix.
B.FIXED = {
    ["SpellStopCasting()"] = "0.5.478", ["SpellStopTargeting()"] = "0.5.478",
    ["CancelLogout()"] = "0.5.478", ["UseContainerItem()"] = "0.5.478", ["C_Container.UseContainerItem()"] = "0.5.478",
    ["CheckButton:SetID()"] = "0.5.478", ["CheckButton:SetShown()"] = "0.5.478",   -- Esc/dialog list
    ["SendChatMessage()"] = "0.5.486",
    -- 0.5.504: action bar range, tooltip/chat/bag/quest log markers, micro menu hiding
    -- 0.5.941 (review): UNKNOWN() came back after 0.5.504 - triggers were C_GuildInfo.GuildRoster (0.5.774) and
    -- the protected C_Discord queries (0.5.775, suspended in combat since 0.5.799)
    ["UNKNOWN()"] = "0.5.799",
    -- 0.5.941: Oasis no longer opens the world map in combat (click on "show on map" tainted Blizzard's map pins)
    ["Button:SetPassThroughButtons()"] = "0.6.520",
    -- 0.5.575: /tar from the Oasis chat history (arrow up) - slash commands no longer go into the history
    ["TargetUnit()"] = "0.5.575",
    -- since 0.5.504 action bars are only hidden via transparency (no more SetPoint)
    ["MultiBarBottomRight:SetPointBase()"] = "0.5.504", ["MultiBarBottomRight:ClearAllPointsBase()"] = "0.5.504",
    ["MultiBarBottomLeft:SetPointBase()"] = "0.5.504", ["MultiBarBottomLeft:ClearAllPointsBase()"] = "0.5.504",
    ["MultiBarRight:SetPointBase()"] = "0.5.504", ["MultiBarRight:ClearAllPointsBase()"] = "0.5.504",
    ["MultiBarLeft:SetPointBase()"] = "0.5.504", ["MultiBarLeft:ClearAllPointsBase()"] = "0.5.504",
    ["MainActionBar:SetPointBase()"] = "0.5.504", ["MainActionBar:ClearAllPointsBase()"] = "0.5.504",
    ["MainMenuBar:SetPointBase()"] = "0.5.504", ["MainMenuBar:ClearAllPointsBase()"] = "0.5.504",
    -- 0.5.660: Oasis has not touched action bars/chat frames since 0.5.504
    ["MultiBarLeftButton1:SetShown()"] = "0.5.504", ["MultiBarLeftButton2:SetShown()"] = "0.5.504", ["MultiBarLeftButton3:SetShown()"] = "0.5.504", ["MultiBarLeftButton4:SetShown()"] = "0.5.504",
    ["MultiBarLeftButton5:SetShown()"] = "0.5.504", ["MultiBarLeftButton6:SetShown()"] = "0.5.504", ["MultiBarLeftButton7:SetShown()"] = "0.5.504", ["MultiBarLeftButton8:SetShown()"] = "0.5.504",
    ["MultiBarLeftButton9:SetShown()"] = "0.5.504", ["MultiBarLeftButton10:SetShown()"] = "0.5.504", ["MultiBarLeftButton11:SetShown()"] = "0.5.504", ["MultiBarLeftButton12:SetShown()"] = "0.5.504",
    ["MultiBarLeftButtonContainer1:SetShown()"] = "0.5.504", ["MultiBarLeftButtonContainer2:SetShown()"] = "0.5.504", ["MultiBarLeftButtonContainer3:SetShown()"] = "0.5.504", ["MultiBarLeftButtonContainer4:SetShown()"] = "0.5.504",
    ["MultiBarLeftButtonContainer5:SetShown()"] = "0.5.504", ["MultiBarLeftButtonContainer6:SetShown()"] = "0.5.504", ["MultiBarLeftButtonContainer7:SetShown()"] = "0.5.504", ["MultiBarLeftButtonContainer8:SetShown()"] = "0.5.504",
    ["MultiBarLeftButtonContainer9:SetShown()"] = "0.5.504", ["MultiBarLeftButtonContainer10:SetShown()"] = "0.5.504", ["MultiBarLeftButtonContainer11:SetShown()"] = "0.5.504", ["MultiBarLeftButtonContainer12:SetShown()"] = "0.5.504",
    ["ChatFrame1:HideBase()"] = "0.5.504", ["ChatFrame1:Show()"] = "0.5.504",
}
-- free-text reports (no function name): mark as fixed individually by report ID
B.FIXED_ID = {
    -- 0.6.536: review - death dice layout (EditBox anchored to itself, only 0.6.207-0.6.212, rebuilt since),
    -- Emoji.lua:578 secret boolean (0.6.236, file since moved to Kern/Chat with ns.safe), UNKNOWN() after GuildRoster (Daito 0.6.518)
    ["bug-e-18892544"] = "0.6.536", ["bug-e-673c0517"] = "0.6.536", ["bug-e-054e474d"] = "0.6.536", ["bug-e-7cda4ff5"] = "0.6.536",
    ["bug-e-095ccee8"] = "0.6.536", ["bug-e-465a2134"] = "0.6.536", ["bug-e-14f42995"] = "0.6.536",
    ["bug-e-3dd2e62d"] = "0.6.536", ["bug-t-0c81824c"] = "0.6.536",
    -- 0.5.941: review of all open reports
    ["bug-e-6bb916a3"] = "0.5.814",   -- DungeonUI.lua:949 SetColorTexture: quality color of the loot icons (fixed in 0.5.814)
    -- deliberately left OPEN (cause not proven): bug-t-043de1e4 ChatFrame1:HideBase() (0.5.742, probably nesUI)
    -- and bug-t-0799d19a callback() (before 0.5.478)
    -- 0.5.767: draw markers individually, separate effects and cache atlas lookups.
    ["bug-e-1216d057"] = "0.5.767", ["bug-e-07937898"] = "0.5.767", ["bug-e-2647edf6"] = "0.5.767",
    -- 0.5.759: numeric counters in the name migration; name adapter rejects non-strings.
    ["bug-e-4f314f78"] = "0.5.759", ["bug-e-4f314f7b"] = "0.5.759",
    ["bug-e-4f314f7d"] = "0.5.759", ["bug-e-4f314f7f"] = "0.5.759",
    -- spread the quest item snapshot over three frames; protect member building against re-entry,
    -- batch automatic updates and draw the level race in the next frame.
    ["bug-e-3968fa7c"] = "0.5.759",
    ["bug-e-22fe0c66"] = "0.5.759", ["bug-e-33e9fe65"] = "0.5.759", ["bug-e-2d8b7ec0"] = "0.5.759",
    ["bug-e-6b54eac4"] = "0.5.759", ["bug-e-73f9bccf"] = "0.5.759", ["bug-e-2cbbe6b1"] = "0.5.759",
    ["bug-e-4bc5a0f7"] = "0.5.759", ["bug-e-79a54e51"] = "0.5.759", ["bug-e-68700540"] = "0.5.759",
    ["bug-e-323b726c"] = "0.5.742", -- marker debug: read GetAttribute before tostring (already fixed).
    -- 0.5.660: review of all open reports
    ["bug-e-737250f5"] = "0.5.660", ["bug-e-5e3a0f12"] = "0.5.660", ["bug-e-3cbb37b6"] = "0.5.660",   -- Comm GCREQ: negative wait time
    ["bug-e-7eac8a10"] = "0.5.415", ["bug-e-469518e9"] = "0.5.415",   -- NoGuild (0.5.414), page rebuilt since, has not occurred again
    ["bug-e-05f32953"] = "0.5.408", ["bug-e-706a09d9"] = "0.5.408",   -- SetTexCoord with mask -> K.MaskSafe
    ["bug-e-7ea0c5d7"] = "0.5.415",   -- auras "secret" - caused by nesUI, not Oasis
    ["bug-e-4230588d"] = "0.5.492",   -- Settings.lua:1327 (0.5.491), page rebuilt since
    ["bug-e-299d30a6"] = "0.5.503",   -- CreateTexture parameters (0.5.502), has not occurred again
}
local function verNum(v)
    local a, b, c = tostring(v or ""):match("(%d+)%.(%d+)%.?(%d*)")
    if not a then return 0 end
    return tonumber(a) * 1000000 + tonumber(b) * 1000 + (tonumber(c) or 0)
end
function B.FixedIn(r)
    local fix = (r.id and B.FIXED_ID[r.id]) or B.FIXED[tostring(r.m or "")]
    -- report IDs differ per player. Also recognize the confirmed name error for Oni.
    local message = tostring(r.m or "")
    if not fix and message:match("^Core%.lua:%d+: attempt to index local 'name' %(a number value%)") then
        fix = "0.5.759"
    end
    -- Comm GCREQ: negative wait time (fixed in 0.5.660) - the report IDs differ per player
    if not fix and message:find("C_Timer.After requires a non-negative duration", 1, true) then
        fix = "0.5.660"
    end
    -- 0.6.256: 0.6.255 was a broken build (UI/Main.lua did not load, follow-up error "attempt to call a nil value"
    -- in many modules) - all reports from exactly this version are done with 0.6.256
    if not fix and tostring(r.v or "") == "0.6.255" then return "0.6.256" end
    if not fix then return nil end
    local v = tostring(r.v or "")
    -- "before 0.5.478" (imported old reports) or an older version
    if v:find("^vor ") or verNum(v) < verNum(fix) then return fix end
end
function B.IsDone(r)
    if ns.db.bugDone and ns.db.bugDone[r.id] ~= nil then return ns.db.bugDone[r.id] == true end
    return B.FixedIn(r) ~= nil
end
-- cleanup (0.5.660): delete all done reports; reports from the Oasis network are removed entirely
function B.ClearDone()
    ns.db.bugGone = ns.db.bugGone or {}
    local n = 0
    for _, r in ipairs(B.All()) do
        if B.IsDone(r) then
            n = n + 1
            ns.db.bugGone[r.id] = ns.now()
            if ns.db.netInbox then ns.db.netInbox[r.id] = nil end
            if ns.db.bugDone then ns.db.bugDone[r.id] = nil end
        end
    end
    -- drop markers older than 120 days (reports expire after 90 days anyway)
    for id, t in pairs(ns.db.bugGone) do if ns.now() - (tonumber(t) or 0) > 120 * 86400 then ns.db.bugGone[id] = nil end end
    B.UpdateBadge()
    ns.RefreshPage("bugs")
    return n
end
function B.SetDone(r, on)
    ns.db.bugDone = ns.db.bugDone or {}
    ns.db.bugDone[r.id] = on and true or false   -- false = explicitly open again (even if fixed)
    B.UpdateBadge()
    ns.RefreshPage("bugs")
end
-- new = arrived after the last look at the page, not done, not from me
function B.NewCount()
    if not (ns.IsDev and ns.IsDev()) then return 0 end
    local seen, n = ns.db.bugSeen or 0, 0
    for _, r in ipairs(B.All()) do
        if (r.u or 0) > seen and not B.IsDone(r) and not ns.isMe(r.by) then n = n + 1 end
    end
    return n
end
function B.UpdateBadge()
    local n = B.NewCount()
    local mf = ns.MainFrame and ns.MainFrame()
    local b = mf and mf.bugBtn
    if b and b.SetCount then b:SetCount(n) end
    -- red number on the navigation item "Bug reports" (developers only; NewCount is 0 otherwise)
    if ns.SetNavBadge then
        local cur = ns._badges and ns._badges.bugs
        local text = n > 0 and (n > 99 and "99+" or tostring(n)) or nil
        if text ~= cur then ns.SetNavBadge("bugs", text) end
    end
end

ns.Listen("STORE", function(coll, rec, old)
    if coll ~= "bugs" or not rec then return end
    if ns.IsDev and ns.IsDev() and not old and not rec.del and not ns.isMe(rec.by) and rec.kind == "r" then
        if ns.Sound and ns.Sound.Next then ns.Sound.Next("notice") end
        K.Toast(L["New bug report"], ns.displayName(rec.by) .. ": " .. tostring(rec.m or ""):sub(1, 90), C.red or C.accent,
            function() ns.ShowPage("bugs") end)
    end
    B.UpdateBadge()
    ns.RefreshPage("bugs")
end)

ns.Listen("LOGIN", function()
    if S().shareErrors == nil then S().shareErrors = true end
    local list = pending
    pending = {}
    for _, e in ipairs(list) do B.Record(e[1], e[2], e[3]) end
    ns.After(5, B.UpdateBadge)
    ns.After(20, function() pcall(B.MigrateOldBlocks) end)
end)

-- one-time (0.5.480): blocks from before 0.5.478 were only local (ns.db.taint) or at the developer
-- only as live receipt (ns.db.taintGuild) -> move into the shared collection "bugs" so they
-- are saved and synced by everyone like everything else.
function B.MigrateOldBlocks()
    if ns.db.bugMig480 or not (Store() and ns.me and ns.me()) then return end
    if S().shareErrors == false then ns.db.bugMig480 = true return end
    local minTs = ns.now() - 90 * 86400
    local groups, order = {}, {}
    local function add(by, fn, v, e)
        fn = clean(fn, 60)
        local key = by .. "|" .. fn .. "|" .. v
        local g = groups[key]
        if not g then
            g = { id = "bug-t-" .. ns.hash(key), kind = "t", w = "Blocked", m = fn, by = by, v = v, n = 0, t = e.ts, last = e.ts,
                lc = e.loc or (GetLocale and GetLocale()) or "" }
            groups[key] = g
            order[#order + 1] = g
        end
        g.n = g.n + 1
        g.t, g.last = math.min(g.t, e.ts), math.max(g.last, e.ts)
        g.cb = g.cb or (e.combat and 1 or nil)
        if (e.page or "") ~= "" then g.pg = tostring(e.page):sub(1, 30) end
        if (e.zone or "") ~= "" then g.z = clean(e.zone, 40) end
        if (e.trail or "") ~= "" then g.s = clean(tostring(e.trail):gsub("\n", " | "), 400) end
        if (e.addons or "") ~= "" and S().shareAddonList then g.ad = clean(e.addons, 400) end
    end
    for _, e in ipairs(ns.db.taint or {}) do
        if (e.ts or 0) >= minTs and e.fn then add(ns.me(), e.fn, "vor 0.5.478", e) end
    end
    -- at the developer: what he previously only received live (sender stays the author)
    for _, e in ipairs(ns.db.taintGuild or {}) do
        if (e.ts or 0) >= minTs and e.fn and (e.who or "") ~= "" then add(e.who, e.fn, e.v or "?", e) end
    end
    for _, g in ipairs(order) do
        if not Store().Get("bugs", g.id) then Store().Put("bugs", g) end
    end
    ns.db.bugMig480 = true
end

------------------------------------------------------------------------
-- report window (for everyone): kind, text, checkbox "Share errors automatically"
------------------------------------------------------------------------
local dlg
local function buildDialog()
    local f = CreateFrame("Frame", "OasisBugDialog", UIParent)
    f:SetSize(440, 340)
    f:SetPoint("CENTER", 0, 60)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f.bg = K.Fill(f, C.bg)
    K.Border(f, C.line)
    if K.ApplySkin then K.ApplySkin(f, "panel", C.bg) end
    ns.EscClose("OasisBugDialog")

    f.icon = K.Glyph(f, 18, ICON, C.accent)
    f.icon:SetPoint("TOPLEFT", 18, -18)
    f.title = K.Title(f, 15, C.text)
    f.title:SetPoint("LEFT", f.icon, "RIGHT", 10, 0)
    f.title:SetText(L["Report a bug"])
    f.close = K.CloseButton(f, function() f:Hide() end, L["Close"])
    f.close:SetPoint("TOPRIGHT", -10, -10)
    f.sub = K.Text(f, 11, C.muted)
    f.sub:SetPoint("TOPLEFT", 18, -46)
    f.sub:SetPoint("RIGHT", -18, 0)
    f.sub:SetWordWrap(true)
    f.sub:SetText(L["What happened? The more precise, the faster it gets fixed. Your report goes to the Oasis developer."])

    local items = {}
    for _, c in ipairs(B.CATS) do items[#items + 1] = { key = c.key, text = L[c.text] } end
    f.cat = K.Segments(f, items, function(k) f.catKey = k end, nil, { size = 12, pad = 18 })
    f.cat:SetPoint("TOPLEFT", 14, -82)
    f.catKey = "bug"

    local box = CreateFrame("Frame", nil, f)
    box:SetPoint("TOPLEFT", 18, -114)
    box:SetPoint("RIGHT", -18, 0)
    box:SetHeight(104)
    box.bg = K.Fill(box, C.field)
    K.Border(box, C.line)
    if K.ApplySkin then box:SetSize(384, 104) K.ApplySkin(box, "field", C.field) end
    local eb = CreateFrame("EditBox", nil, box)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFont(K.FONT, 12, "")
    eb:SetTextColor(C.text[1], C.text[2], C.text[3])
    eb:SetPoint("TOPLEFT", 8, -7)
    eb:SetPoint("BOTTOMRIGHT", -8, 7)
    eb:SetMaxLetters(600)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    eb.ph = K.Text(box, 12, C.dim)
    eb.ph:SetPoint("TOPLEFT", 9, -8)
    eb.ph:SetText(L["For example: on the Groups page the list stays empty when ..."])
    eb:SetScript("OnTextChanged", function(self)
        local t = self:GetText() or ""
        self.ph:SetShown(t == "")
        f.count:SetText(#t .. " / 600")
        f.send:SetEnabled(t:gsub("%s", "") ~= "")
    end)
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function() eb:SetFocus() end)
    f.eb = eb
    f.count = K.Text(f, 10, C.dim, "RIGHT")
    f.count:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 0, -4)

    f.share = K.Toggle(f, L["Share errors automatically"], function() return S().shareErrors ~= false end,
        function(v) S().shareErrors = v and true or false end,
        L["Lua errors from Oasis go to the developer with version and game language - no chat messages, no data from other addons."])
    f.share:SetPoint("TOPLEFT", box, "BOTTOMLEFT", -4, -20)
    f.share:SetPoint("RIGHT", f, "RIGHT", -18, 0)
    -- wrap description in the window (ran out on the right)
    if f.share.desc then
        f.share.desc:SetPoint("RIGHT", f, "RIGHT", -18, 0)
        f.share.desc:SetWordWrap(true)
        f.share.desc:SetJustifyH("LEFT")
    end

    f.send = K.Button(f, L["Send"], 110, 26, "primary", function()
        if B.Submit(f.catKey, eb:GetText()) then
            eb:SetText("")
            eb:ClearFocus()
            f:Hide()
            K.Toast(L["Thank you!"], L["Your report is on its way to the developer."], C.mint)
        end
    end)
    f.send:SetPoint("BOTTOMRIGHT", -18, 16)
    f.send:SetEnabled(false)
    f.cancel = K.Button(f, L["Cancel"], 100, 26, "ghost", function() f:Hide() end)
    f.cancel:SetPoint("RIGHT", f.send, "LEFT", -8, 0)
    -- for guilds without connection to the developer: copy the finished report (Discord/GitHub)
    f.copy = K.Button(f, L["Copy report"], 130, 26, "ghost", function() B.ShowCopy(B.ReportText(eb:GetText())) end)
    f.copy:SetPoint("BOTTOMLEFT", 18, 16)
    f:Hide()
    return f
end
function B.ShowDialog()
    dlg = dlg or buildDialog()
    dlg.cat:Select("bug")
    dlg.catKey = "bug"
    dlg:Show()
    dlg:Raise()
    dlg.eb:SetFocus()
end
ns.slash.bug = function() B.ShowDialog() end
-- navigation: own group "Developer" at the very bottom (only visible when the page is visible = developer mode)
if ns.ICONS then ns.ICONS.bugs = ICON end
if ns.NAV_GROUPS then table.insert(ns.NAV_GROUPS, { key = "dev", text = "Developer", pages = { "bugs" } }) end

------------------------------------------------------------------------
-- header button (Main.lua calls B.AttachHeader)
------------------------------------------------------------------------
function B.AttachHeader(btn)
    btn.icon = K.Glyph(btn, 16, ICON)
    btn.icon:SetPoint("CENTER")
    btn.badge = CreateFrame("Frame", nil, btn)
    btn.badge:SetSize(14, 14)
    btn.badge:SetPoint("CENTER", btn, "TOPRIGHT", -5, -6)
    btn.badge.bg = btn.badge:CreateTexture(nil, "ARTWORK")
    btn.badge.bg:SetAllPoints()
    btn.badge.bg:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    btn.badge.bg:SetVertexColor(C.red and C.red[1] or 0.9, C.red and C.red[2] or 0.25, C.red and C.red[3] or 0.25)
    btn.badge.t = K.Text(btn.badge, 9, { 1, 1, 1 }, "CENTER")
    if K.CenterNum then K.CenterNum(btn.badge.t, btn.badge, "CENTER", 0, 0) else btn.badge.t:SetPoint("CENTER") end
    btn.badge:Hide()
    function btn:SetCount(n)
        self.badge:SetShown((n or 0) > 0)
        self.badge.t:SetText(n and n > 9 and "9+" or tostring(n or ""))
    end
    local function tint(hover)
        local c = hover and C.text or C.muted
        btn.icon:SetVertexColor(c[1], c[2], c[3])
    end
    tint(false)
    btn:SetScript("OnEnter", function(self)
        tint(true)
        if ns.IsDev and ns.IsDev() then
            K.ShowTip(self, { L["Report a bug"], L["Click: write a report"], "|cffe8b44a" .. L["Right-click: incoming bug reports"] .. "|r" })
        else
            K.ShowTip(self, { L["Report a bug"], L["Something broken or got an idea? Write it here - it goes straight to the developer."] })
        end
    end)
    btn:SetScript("OnLeave", function() tint(false) GameTooltip:Hide() end)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick", function(_, mb)
        if mb == "RightButton" and ns.IsDev and ns.IsDev() then ns.ShowPage("bugs") else B.ShowDialog() end
    end)
    B.UpdateBadge()
end

------------------------------------------------------------------------
-- page "Bug reports" (developers only)
------------------------------------------------------------------------
local FILTERS = { { key = "open", text = "Open" }, { key = "r", text = "Reports" }, { key = "e", text = "Lua errors" }, { key = "t", text = "Blocked" }, { key = "done", text = "Done" } }
local CAT_TEXT = { bug = "Bug", idea = "Idea", other = "Miscellaneous" }

ns.RegisterPage({
    key = "bugs", title = "Bug reports", order = 99,
    sub = "Lua errors and reports from the guild",
    visible = function() return ns.IsDev and ns.IsDev() or false end,
    build = function(p)
        p.filter = "open"
        local items = {}
        for _, f in ipairs(FILTERS) do items[#items + 1] = { key = f.key, text = L[f.text] } end
        p.seg = K.Segments(p, items, function(k) p.filter = k p.sel = nil ns.RefreshPage("bugs") end)
        p.seg:SetPoint("TOPLEFT", 0, 0)
        p.write = K.Button(p, L["Report myself"], 120, 24, "ghost", function() B.ShowDialog() end)
        p.write:SetPoint("TOPRIGHT", 0, 0)
        -- cleanup: delete done reports (click twice = confirm)
        p.clean = K.Button(p, L["Delete resolved"], 140, 24, "ghost", function(self)
            if not self.armed or GetTime() - self.armed > 4 then
                self.armed = GetTime()
                self:SetLabel(L["Really delete?"])
                C_Timer.After(4, function() if self.armed and GetTime() - self.armed >= 4 then self.armed = nil self:SetLabel(L["Delete resolved"]) end end)
                return
            end
            self.armed = nil
            self:SetLabel(L["Delete resolved"])
            local n = B.ClearDone()
            K.Toast(L["Bug reports"], (L["%d resolved reports deleted."]):format(n), C.mint)
        end)
        p.clean:SetPoint("RIGHT", p.write, "LEFT", -8, 0)

        p.list = K.List(p, 46, function(l)
            local r = CreateFrame("Button", nil, l)
            r.hl = r:CreateTexture(nil, "BACKGROUND")
            r.hl:SetAllPoints()
            r.hl:SetColorTexture(1, 1, 1, 0)
            r.icon = K.Glyph(r, 16, ICON)
            r.icon:SetPoint("LEFT", 8, 0)
            r.t = K.Text(r, 12, C.text)
            r.t:SetPoint("TOPLEFT", 34, -6)
            r.t:SetPoint("RIGHT", -60, 0)
            r.t:SetWordWrap(false)
            r.s = K.Text(r, 10, C.muted)
            r.s:SetPoint("BOTTOMLEFT", 34, 7)
            r.s:SetPoint("RIGHT", -60, 0)
            r.s:SetWordWrap(false)
            r.n = K.Text(r, 11, C.muted, "RIGHT")
            r.n:SetPoint("RIGHT", -10, 0)
            r:SetScript("OnClick", function(self) p.sel = self.item and self.item.id ns.RefreshPage("bugs") end)
            r:SetScript("OnEnter", function(self) if p.sel ~= (self.item and self.item.id) then self.hl:SetColorTexture(1, 1, 1, 0.04) end end)
            r:SetScript("OnLeave", function(self) if p.sel ~= (self.item and self.item.id) then self.hl:SetColorTexture(1, 1, 1, 0) end end)
            return r
        end, function(r, it)
            local isErr = it.kind == "e" or it.kind == "t"
            local c = it.kind == "t" and (C.amber or C.accent) or isErr and (C.red or C.accent) or C.accent
            if B.IsDone(it) then c = C.dim end
            r.icon:SetVertexColor(c[1], c[2], c[3])
            local first = tostring(it.m or ""):match("^[^\n]*") or ""
            r.t:SetText((isErr and ("|cff8a8a90" .. (it.w or "Lua") .. ":|r ") or "") .. first)
            local vs = tostring(it.v or "?")
            local parts = { ns.displayName(it.by or "?"), vs:find("^%d") and ("v" .. vs) or vs }
            if B.FixedIn(it) then parts[#parts + 1] = "|cff66db9e" .. (L["fixed in %s"]):format(B.FixedIn(it)) .. "|r" end
            if not isErr then parts[#parts + 1] = L[CAT_TEXT[it.cat] or "Bug"] end
            if it.lc and it.lc ~= "" then parts[#parts + 1] = it.lc end
            parts[#parts + 1] = ns.ago(it.last or it.t or it.u or 0)
            r.s:SetText(table.concat(parts, "  ·  "))
            r.n:SetText(isErr and ((tonumber(it.n) or 1) .. "x") or "")
            r.hl:SetColorTexture(1, 1, 1, p.sel == it.id and 0.08 or 0)
        end)
        p.list:SetPoint("TOPLEFT", 0, -36)
        p.list:SetPoint("BOTTOMLEFT", 0, 0)
        p.list.empty:SetText(L["No bug reports - all quiet."])

        -- detail right
        local d = K.Panel(p, C.raised)
        d:SetPoint("TOPRIGHT", 0, -36)
        d:SetPoint("BOTTOMRIGHT", 0, 0)
        p.detail = d
        d.head = K.Text(d, 12, C.text)
        d.head:SetPoint("TOPLEFT", 14, -12)
        d.head:SetPoint("RIGHT", -14, 0)
        d.head:SetWordWrap(false)
        d.meta = K.Text(d, 10, C.muted)
        d.meta:SetPoint("TOPLEFT", 14, -32)
        d.meta:SetPoint("RIGHT", -14, 0)
        d.meta:SetWordWrap(true)
        -- full text in a (read-only) edit box: select + Ctrl+C to copy
        local sf = CreateFrame("ScrollFrame", nil, d, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 14, -70)
        sf:SetPoint("BOTTOMRIGHT", -30, 50)
        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetAutoFocus(false)
        eb:SetFont(K.FONT, 11, "")
        eb:SetTextColor(C.text[1], C.text[2], C.text[3])
        eb:SetWidth(300)
        eb:SetScript("OnEscapePressed", eb.ClearFocus)
        eb:SetScript("OnTextChanged", function(self, user) if user and self.locked then self:SetText(self.locked) self:HighlightText() end end)
        sf:SetScrollChild(eb)
        sf:SetScript("OnSizeChanged", function(self, w) eb:SetWidth(math.max(50, (w or 300) - 4)) end)
        d.text = eb
        d.done = K.Button(d, L["Done"], 110, 24, "primary", function()
            local it = p.cur
            if it then B.SetDone(it, not B.IsDone(it)) end
        end)
        d.done:SetPoint("BOTTOMRIGHT", -14, 14)
        d.copy = K.Button(d, L["Copy"], 90, 24, "ghost", function()
            d.text:SetFocus()
            d.text:HighlightText()
            ns.print(L["Text is selected - press Ctrl+C to copy."])
        end)
        d.copy:SetPoint("RIGHT", d.done, "LEFT", -8, 0)
        d.whisper = K.Button(d, L["Whisper"], 100, 24, "ghost", function()
            if p.cur and p.cur.by then ns.Whisper(p.cur.by) end
        end)
        d.whisper:SetPoint("RIGHT", d.copy, "LEFT", -8, 0)
        d.none = K.Text(d, 12, C.dim, "CENTER")
        d.none:SetPoint("CENTER")
        d.none:SetText(L["Pick a report on the left."])

        p:HookScript("OnSizeChanged", function(self, w)
            local lw = math.floor((w or 700) * 0.52)
            self.list:SetWidth(lw)
            self.detail:SetPoint("TOPLEFT", self, "TOPLEFT", lw + 14, -36)
        end)
    end,
    refresh = function(p)
        ns.db.bugSeen = ns.now()
        B.UpdateBadge()
        local out = {}
        for _, r in ipairs(B.All()) do
            local done = B.IsDone(r)
            local f = p.filter
            if (f == "open" and not done) or (f == "done" and done) or ((f == "r" or f == "e" or f == "t") and r.kind == f and not done) then
                out[#out + 1] = r
            end
        end
        p.list:SetData(out)
        local cur
        for _, r in ipairs(out) do if r.id == p.sel then cur = r end end
        p.cur = cur
        local d = p.detail
        local show = cur ~= nil
        for _, w in ipairs({ d.head, d.meta, d.text, d.done, d.copy, d.whisper }) do w:SetShown(show) end
        d.none:SetShown(not show)
        if not cur then return end
        local isErr = cur.kind == "e" or cur.kind == "t"
        d.head:SetText(cur.kind == "t" and (L["Blocked:"] .. "  " .. tostring(cur.m or "")) or isErr and (L["Lua errors"] .. "  ·  " .. (cur.w or "")) or (L[CAT_TEXT[cur.cat] or "Bug"] .. "  ·  " .. ns.displayName(cur.by or "?")))
        local meta = { ns.displayName(cur.by or "?"), "Oasis " .. tostring(cur.v or "?"), cur.lc or "" }
        if isErr then meta[#meta + 1] = ((tonumber(cur.n) or 1) .. "x, " .. L["last"] .. " " .. ns.ago(cur.last or cur.t or 0))
        else
            if cur.pg and cur.pg ~= "" then meta[#meta + 1] = L["Page"] .. ": " .. cur.pg end
            if cur.z and cur.z ~= "" then meta[#meta + 1] = cur.z end
            meta[#meta + 1] = ns.ago(cur.t or cur.u or 0)
        end
        d.meta:SetText(table.concat(meta, "  ·  "))
        local body = tostring(cur.m or "")
        if cur.kind == "t" then
            -- block: explanation + circumstances + last Oasis actions + other addons
            local why = ns.Taint and ns.Taint.Why and ns.Taint.Why(cur.m)
            local t = { body }
            if why then t[#t + 1] = why end
            if cur.cb then t[#t + 1] = L["in a fight"] end
            if (cur.pg or "") ~= "" or (cur.z or "") ~= "" then t[#t + 1] = L["Page/zone:"] .. " " .. ((cur.pg or "") ~= "" and cur.pg or "-") .. "  ·  " .. (cur.z or "") end
            if (cur.s or "") ~= "" then t[#t + 1] = L["Last Oasis actions:"] .. "\n" .. cur.s end
            if (cur.ad or "") ~= "" then t[#t + 1] = L["Other addons:"] .. " " .. cur.ad end
            body = table.concat(t, "\n\n")
        elseif isErr and cur.s and cur.s ~= "" then body = body .. "\n\n" .. cur.s end

        d.text.locked = body
        d.text:SetText(body)
        d.text:SetCursorPosition(0)
        d.done:SetText(B.IsDone(cur) and L["Reopen"] or L["Done"])
        d.whisper:SetShown(not ns.isMe(cur.by or ""))
    end,
})
