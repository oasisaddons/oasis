-- Oasis - languages (client language or chosen in the window header)
-- Keys are the English texts used in the code (since 0.6.572). German lives in Locales/Base/German.lua,
-- the other languages in Locales/XX.lua; a missing translation falls back to English.
local ADDON, ns = ...

local DE, EN = {}, {}
ns.LOCALE_DE, ns.LOCALE_EN = DE, EN
ns.LOCALES = { de = DE, en = EN, fr = {}, es = {}, ru = {}, pt = {}, it = {}, zh = {}, ko = {}, tw = {}, ja = {}, pl = {} }

-- Reihenfolge im Umschalter; flag = Media\flags\<flag>.tga, cyr = braucht kyrillische Schrift
ns.LANGS = {
    -- Reihenfolge = geschaetzte Zahl der WoW-Spieler je Sprache, groesste zuerst (Schaetzung, keine
    -- amtliche Zahl). cjk = eigene Schrift (die normalen WoW-Schriften haben die Zeichen nicht); ext = braucht
    -- polnische Buchstaben, Zierschriften ohne sie weichen auf PT Sans aus. tw wird aus zh erzeugt (Tools/make_tw.py).
    -- Japanisch und Polnisch haben keinen eigenen WoW-Client: waehlt man im Umschalter.
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

-- fehlt ein DE-Eintrag: Umlaute aus dem Schluessel ableiten (fuer -> für, Staerke -> Stärke),
-- ausser bei echten Vokalfolgen (neue, Feuer, Dauer, Quest, aktuell, Duell ...)
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
            if lv == "a" and (pre == "e" or pre == "E") then return nil end   -- z.B. "Raphael" selten, "eae" kommt kaum vor
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
-- ausgefuehrt wird beim Start nur die gewaehlte Sprache, die anderen Funktionen werden verworfen (kein Speicher).
-- Die nicht gebrauchte Grundsprache (Englisch bei Deutsch, Deutsch bei allen anderen) wird ebenfalls verworfen.
local FOREIGN = { fr = true, es = true, ru = true, pt = true, it = true, zh = true, ko = true, tw = true, ja = true, pl = true }
ns.langFiles = {}   -- [lang] = { fn, ... } bis zum Start
ns.langLoaded, ns.langDropped = {}, {}
function ns.LangFile(lang, fn)
    if not ns.langFiles then return end   -- nach dem Start: nichts mehr annehmen
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
    setmetatable(t, { __newindex = function() end })   -- spaeter geladene Module schreiben ins Leere
end
-- einmal beim Start (ADDON_LOADED, Sprache bekannt)
function ns.PrepareLang()
    ns.EnsureLang(ns.lang)
    if ns.lang == "de" then
        if not ns.langDropped.en then sink(EN) ns.langDropped.en = true end
    else
        if not ns.langDropped.de then sink(DE) ns.langDropped.de = true end
    end
    ns.langFiles = nil   -- uebrige Fremdsprachen verwerfen
    umlautCache = {}
    ns.RelabelAll()
end
-- braucht die Sprache Verworfenes? Dann geht der Wechsel erst nach /reload
function ns.LangNeedsReload(lang)
    if FOREIGN[lang] and not ns.langLoaded[lang] and not (ns.langFiles and ns.langFiles[lang]) then return true end
    if lang == "de" then return ns.langDropped.de and true or false end
    return ns.langDropped.en and true or false
end

-- Texte, die schon beim Laden einer Datei gelesen werden (Tabellen mit Beschriftungen), stuenden sonst fuer immer
-- in der Client-Sprache: die Sprache des Nutzers steht erst bei ADDON_LOADED fest. fn laeuft sofort und nach
-- jedem Festlegen oder Wechseln der Sprache erneut.
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
