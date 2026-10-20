-- Oasis - languages (client language or chosen in the window header)
-- Keys are the English texts used in the code (since 0.6.572). German lives in Locales/Base/German.lua,
-- the other languages in Locales/XX.lua; a missing translation falls back to English.
local ADDON, ns = ...

local DE, EN = {}, {}
ns.LOCALE_DE, ns.LOCALE_EN = DE, EN
ns.LOCALES = { de = DE, en = EN, fr = {}, es = {}, ru = {}, pt = {}, it = {}, zh = {}, ko = {}, tw = {}, ja = {}, pl = {} }

-- order in the switcher; flag = Media\flags\<flag>.tga, cyr = needs a Cyrillic font
ns.LANGS = {
    -- order = estimated number of WoW players per language, largest first (estimate, not an
    -- official figure). cjk = own font (the normal WoW fonts lack the characters); ext = needs
    -- Polish letters, decorative fonts without them fall back to PT Sans. tw is generated from zh (Tools/make_tw.py).
    -- Japanese and Polish have no WoW client of their own: chosen in the switcher.
    { key = "en", name = "English", flag = "gb", client = { enUS = true, enGB = true } },
    { key = "zh", name = "简体中文", flag = "cn", client = { zhCN = true }, cjk = "notosc" },
    { key = "de", name = "Deutsch", flag = "de", client = { deDE = true } },
    { key = "fr", name = "Français", flag = "fr", client = { frFR = true } },
    { key = "ru", name = "Русский", flag = "ru", client = { ruRU = true }, cyr = true },
    { key = "es", name = "Español", flag = "es", client = { esES = true, esMX = true } },
    { key = "ko", name = "한국어", flag = "kr", client = { koKR = true }, cjk = "notokr" },
    { key = "pt", name = "Português", flag = "br", client = { ptBR = true, ptPT = true } },
    { key = "tw", name = "繁體中文", flag = "tw", client = { zhTW = true }, cjk = "nototc" },
    { key = "it", name = "Italiano", flag = "it", client = { itIT = true } },
    { key = "pl", name = "Polski", flag = "pl", client = { plPL = true }, ext = true },
    { key = "ja", name = "日本語", flag = "jp", client = { jaJP = true }, cjk = "notojp" },
}
ns.langByKey = {}
for _, l in ipairs(ns.LANGS) do ns.langByKey[l.key] = l end

function ns.ClientLang()
    local locale = GetLocale and GetLocale() or "enUS"
    for _, l in ipairs(ns.LANGS) do if l.client[locale] then return l.key end end
    return "en"
end
ns.lang = ns.ClientLang()

-- missing DE entry: derive umlauts from the key (fuer -> für, Staerke -> Stärke),
-- except for real vowel sequences (neue, Feuer, Dauer, Quest, aktuell, Duell ...)
local umlautCache = {}
local SKIP = { "zuerst", "Zuerst", "uenc", "uenz", "Aero", "aero", "uell", "Duell", "duell", "Statue", "Poesie", "Oboe", "Michael", "Israel", "Queue", "queue" }
local function autoUmlaut(s)
    if type(s) ~= "string" then return s end
    local c = umlautCache[s]
    if c then return c end
    local out = s
    if not (s:find("|T", 1, true) or s:find("\\", 1, true) or s:find("|H", 1, true)) then
        local keep = {}
        for _, w in ipairs(SKIP) do
            out = out:gsub(w, function() keep[#keep + 1] = w return "\1" .. #keep .. "\2" end)
        end
        out = out:gsub("([%a]?)([AaOoUu])e", function(pre, v)
            local lv = v:lower()
            if lv == "u" and (pre == "q" or pre == "Q" or pre == "e" or pre == "a" or pre == "E" or pre == "A") then return nil end
            if lv == "a" and (pre == "e" or pre == "E") then return nil end   -- e.g. "Raphael" rare, "eae" hardly occurs
            if lv == "o" and (pre == "o" or pre == "O") then return nil end
            local map = { A = "Ä", a = "ä", O = "Ö", o = "ö", U = "Ü", u = "ü" }
            return pre .. map[v]
        end)
        out = out:gsub("\1(%d+)\2", function(n) return keep[tonumber(n)] end)
    end
    umlautCache[s] = out
    return out
end
ns.AutoUmlaut = autoUmlaut

-- 0.5.580: Fremdsprachen liegen in Locales\XX.lua. Jede Datei verpackt ihren Inhalt in ns.LangFile("xx", function() ... end);
-- at startup only the chosen language is executed, the other functions are discarded (no memory).
-- The unused base language (English for German, German for all others) is discarded too.
local FOREIGN = { fr = true, es = true, ru = true, pt = true, it = true, zh = true, ko = true, tw = true, ja = true, pl = true }
ns.langFiles = {}   -- [lang] = { fn, ... } until startup
ns.langLoaded, ns.langDropped = {}, {}
function ns.LangFile(lang, fn)
    if not ns.langFiles then return end   -- after startup: accept nothing more
    local t = ns.langFiles[lang] or {}
    ns.langFiles[lang] = t
    t[#t + 1] = fn
end
function ns.EnsureLang(lang)
    if not FOREIGN[lang] then return true end
    if ns.langLoaded[lang] ~= nil then return ns.langLoaded[lang] end
    local fns = ns.langFiles and ns.langFiles[lang]
    if not fns then ns.langMissing = ns.langFiles and "MISSING" or "DROPPED" return false end
    local ok = true
    for _, fn in ipairs(fns) do
        local fine, err = pcall(fn)
        if not fine then ok = false ns.langMissing = tostring(err) end
    end
    ns.langFiles[lang] = nil
    ns.langLoaded[lang] = ok
    return ok
end
local function sink(t)
    for k in pairs(t) do t[k] = nil end
    setmetatable(t, { __newindex = function() end })   -- modules loaded later write into the void
end
-- once at startup (ADDON_LOADED, language known)
function ns.PrepareLang()
    ns.EnsureLang(ns.lang)
    if ns.lang == "de" then
        if not ns.langDropped.en then sink(EN) ns.langDropped.en = true end
    else
        if not ns.langDropped.de then sink(DE) ns.langDropped.de = true end
    end
    ns.langFiles = nil   -- discard remaining foreign languages
    umlautCache = {}
    ns.RelabelAll()
end
-- does the language need something discarded? Then the switch only works after /reload
function ns.LangNeedsReload(lang)
    if FOREIGN[lang] and not ns.langLoaded[lang] and not (ns.langFiles and ns.langFiles[lang]) then return true end
    if lang == "de" then return ns.langDropped.de and true or false end
    return ns.langDropped.en and true or false
end

-- Texts read while a file loads (tables with labels) would otherwise stay forever
-- in the client language: the user's language is only known at ADDON_LOADED. fn runs immediately and again after
-- each setting or switching of the language.
local relabel = {}
function ns.Relabel(fn)
    relabel[#relabel + 1] = fn
    fn()
end
function ns.RelabelAll()
    for _, fn in ipairs(relabel) do pcall(fn) end
end

ns.L = setmetatable({}, {
    __index = function(_, key)
        local lang = ns.lang
        if lang == "de" then return DE[key] or key end
        if lang ~= "en" then
            local t = ns.LOCALES[lang]
            local v = t and t[key]
            if v then return v end
        end
        return EN[key] or key
    end,
})
