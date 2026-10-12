-- Oasis - Texte: Discord-Bruecke (Modules\DiscordBridge.lua)
local ADDON, ns = ...
local DE, EN = ns.LOCALE_DE, ns.LOCALE_EN

local DEFIX = {
    ["Chatlog eingeschaltet - OasisSync kann den Gildenchat an Discord geben."] = "Chatlog eingeschaltet – OasisSync kann den Gildenchat an Discord geben.",
    ["Discord-Nachrichten uebernommen: %d (neue erscheinen erst nach /reload)"] = "Discord-Nachrichten übernommen: %d (neue erscheinen erst nach /reload)",
    ["Discord-Nachrichten im Gildenchat zeigen (ueber OasisSync, nach /reload)"] = "Discord-Nachrichten im Gildenchat zeigen (über OasisSync, nach /reload)",
    ["Chatlog beim Login einschalten (Gildenchat -> Discord ueber OasisSync)"] = "Chatlog beim Login einschalten (Gildenchat → Discord über OasisSync)",
}
for k, v in pairs(DEFIX) do DE[k] = v end

local ENX = {
    ["Chatlog eingeschaltet - OasisSync kann den Gildenchat an Discord geben."] = "Chat log enabled - OasisSync can pass guild chat on to Discord.",
    ["Discord-Nachrichten uebernommen: %d (neue erscheinen erst nach /reload)"] = "Discord messages imported: %d (new ones only appear after /reload)",
    ["Discord-Nachrichten im Gildenchat zeigen (ueber OasisSync, nach /reload)"] = "Show Discord messages in guild chat (via OasisSync, after /reload)",
    ["Chatlog beim Login einschalten (Gildenchat -> Discord ueber OasisSync)"] = "Enable chat log on login (guild chat -> Discord via OasisSync)",
}
for k, v in pairs(ENX) do EN[k] = v end
