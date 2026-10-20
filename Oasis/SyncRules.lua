-- Pure rules for encoding, revisions and guild separation; testable without WoW.
local _, ns = ...
local R = {}
ns.SyncRules = R
R.Limits = { message = 262144, record = 96000, fields = 1500, key = 64, value = 8000,
    wireField = 96000, chunk = 238, zip = 24000 }
function R.Finite(x) return type(x) == "number" and x == x and x > -1e15 and x < 1e15 end
function R.Escape(s)
    return (tostring(s == nil and "" or s):gsub("[%%%^\n|;=,:]", function(c) return ("%%%02X"):format(c:byte()) end))
end
function R.Unescape(s)
    return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end
function R.Encode(t)
    local parts = {}
    for k, v in pairs(t) do
        local tag = type(v) == "number" and "#" or type(v) == "boolean" and "?" or type(v) == "string" and "$"
        if tag and (type(k) ~= "string" or k:sub(1, 1) ~= "_") then
            parts[#parts + 1] = R.Escape(k) .. "=" .. tag .. (tag == "$" and R.Escape(v) or tag == "?" and (v and "1" or "0") or tostring(v))
        end
    end
    table.sort(parts)
    return table.concat(parts, ";")
end
function R.Decode(s)
    local lim = R.Limits
    if type(s) ~= "string" or #s > lim.record then return nil, "record-size" end
    if s == "" then return {} end
    if s:sub(1, 1) == ";" or s:sub(-1) == ";" or s:find(";;", 1, true) then return nil, "record-framing" end
    local t, count = {}, 0
    for pair in s:gmatch("[^;]+") do
        count = count + 1
        if count > lim.fields then return nil, "record-fields" end
        local k, tag, val = pair:match("^([^=]+)=([#$?])(.*)$")
        if not k or pair:gsub("%%[%x][%x]", ""):find("%", 1, true) then return nil, "record-encoding" end
        k = R.Unescape(k)
        if #k > lim.key or k:find("[%c|]") or t[k] ~= nil then return nil, "record-key" end
        if tag == "#" then
            local value = tonumber(val)
            if not R.Finite(value) then return nil, "record-number" end
            t[k] = value
        elseif tag == "?" then
            if val ~= "0" and val ~= "1" then return nil, "record-boolean" end
            t[k] = val == "1"
        else
            local value = R.Unescape(val)
            if #value > lim.value then return nil, "record-value" end
            t[k] = ns.CleanText and ns.CleanText(value) or value
        end
    end
    return t
end
-- Same logical time: unique revision, then full content as collision guard.
-- No arrival time: both clients choose the same regardless of receive order.
function R.Compare(a, b)
    local au, bu = tonumber(a.u) or 0, tonumber(b.u) or 0
    if au ~= bu then return au > bu and 1 or -1 end
    if (a.del == true) ~= (b.del == true) then return a.del == true and 1 or -1 end
    local ar, br = tostring(a.rv or ""), tostring(b.rv or "")
    if ar ~= br then return ar > br and 1 or -1 end
    local ac, bc = R.Encode(a), R.Encode(b)
    if ac == bc then return 0 end
    return ac > bc and 1 or -1
end
function R.CanReadGuild(rec, guild)
    return rec.gn == nil or (guild ~= nil and rec.gn == guild)
end
