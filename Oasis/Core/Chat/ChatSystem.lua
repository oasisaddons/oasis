-- Empty system events create real chat lines in the Forever client.
-- Filter before AddMessage so other chat displays don't mirror empty lines either.
local ADDON, ns = ...
local issecret = issecretvalue or function() return false end
local function emptySystem(_, event, text)
    if event ~= "CHAT_MSG_SYSTEM" or issecret(text) then return false end
    return type(text) == "string" and text == ""
end
ns.ChatSystem = { Filter = emptySystem }
local add = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
if add then add("CHAT_MSG_SYSTEM", emptySystem) end
