-- Oasis - Guild module: developer unlock (0.5.907 moved here from Core.lua - the public version has no
-- developer mode; there ns.IsDev() always returns false). Replaces ns.IsDev and registers /oa entwickler.
local ns = Oasis
if not (ns and ns.slash) then return end

-- Developer unlock (guild version): demo data and the guild leadership test mode only for
-- unlocked accounts. Unlock: /oa entwickler <code>  (applies to all chars of the account,
-- local only - other players always check the real guild rank). Turn off: /oa entwickler aus
-- Only a stretched hash (2 lanes x 3000 rounds, 48 bit) is in the code, never the plain text.
-- Values stay below 2^31 (same result in Lua 5.1 and in 32-bit test environments).
-- The dev status lives exclusively in the local SavedVariables and is never sent.
local DEV_HASH = "5641a7182f3d"
local function devHash(str)
    local a, b = 5381, 52711
    local s = "oasis|" .. tostring(str or "")
    for r = 1, 3000 do
        for i = 1, #s do
            local c = s:byte(i)
            a = (a * 33 + c + r) % 16777213
            b = (b * 31 + c * 7 + a % 977) % 16777199
        end
        s = ("%06x%06x"):format(a, b)
    end
    return s
end
function ns.IsDev()
    -- 0.5.944: only unlocked with the code (devCode = checksum of the current code); older unlocks
    -- without code and those with an earlier code no longer count.
    if ns.db and ns.db.devUnlock == true and ns.db.devCode == DEV_HASH then ns.db.devKnown = true return true end
    return false
end
function ns.DevSlash(arg)
    arg = tostring(arg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    -- 0.6.527: without argument status + help instead of "Unknown command"
    if arg == "" then
        ns.print(ns.IsDev() and "Entwickler-Modus ist an. Ausschalten: /oa entwickler aus" or "Entwickler-Modus ist aus. Einschalten: /oa entwickler <dein Code>")
        return
    end
    if arg:lower() == "ein" or arg:lower() == "an" or arg:lower() == "on" then
        -- user request 12.10.2026: turning on only with code from now on (previously without, for testing).
        if ns.IsDev() then ns.print("Entwickler-Modus ist schon an.") return end
        ns.print("Entwickler-Modus braucht den Code: /oa entwickler <code>")
        return
    elseif arg:lower() == "aus" or arg:lower() == "off" then
        ns.db.devUnlock = nil
        ns.db.devCode = nil
        ns.db.settings.adminTest = nil
        if ns.Demo and ns.Demo.IsActive and ns.Demo.IsActive() then pcall(ns.Demo.Remove) end
        ns.print("Entwickler-Modus aus.")
    elseif arg:lower():find("^hash%s+%S") then
        -- prepare a new code: only shows the checksum (the code itself is stored nowhere)
        local code = arg:match("^%S+%s+(.+)$")
        ns.print("Pruefsumme fuer deinen neuen Code: " .. devHash(code) .. "  (diese Zahl an den Entwickler geben, den Code selbst nicht)")
        return
    elseif arg ~= "" and #arg <= 64 and devHash(arg) == DEV_HASH then
        ns.db.devUnlock = true
        ns.db.devCode = DEV_HASH
        ns.db.devKnown = true
        -- set developer sounds on unlock as long as nothing of your own is chosen there
        local Snd, ev = ns.Sound, ns.db.settings
        if Snd and Snd.SetChoice and ev then
            ev.soundEvents = ev.soundEvents or {}
            if Snd.byKey.dev_matrix and not ev.soundEvents.entrance then Snd.SetChoice("entrance", "dev_matrix") end
            if Snd.byKey.dev_mariotod and Snd.eventByKey.mydeath and not ev.soundEvents.mydeath then Snd.SetChoice("mydeath", "dev_mariotod") end
        end
        ns.print("Entwickler-Modus an: Demo-Daten und Testmodus der Gildenleitung sind freigeschaltet (nur bei dir).")
    else
        ns.print("Code passt nicht. Einschalten: /oa entwickler <dein Code>  -  Ausschalten: /oa entwickler aus")
        return
    end
    if ns.UpdateDemoSwitch then pcall(ns.UpdateDemoSwitch) end
    if ns.Admin and ns.Admin.ApplyBrand then pcall(ns.Admin.ApplyBrand, true) end
end
ns.slash.entwickler = function(a) ns.DevSlash(a) end
ns.slash.dev = ns.slash.entwickler
