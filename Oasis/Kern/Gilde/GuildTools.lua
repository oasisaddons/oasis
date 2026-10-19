-- Oasis: Gildenwerkzeuge (0.6.519)
--  * Spieler gezielt per Name in die Gilde einladen (Mitglieder-Seite, Tastenkuerzel, /oa einladen Name)
--  * Blizzards Gildenfenster oeffnen (Raenge, Rechte, Gildenbank-Rechte) - auch wenn J auf Oasis liegt
-- Die Gildenbank selbst laesst sich nur am Bankier oeffnen (Blizzard-Vorgabe).
local ADDON, ns = ...
local L = ns.L
local GT = {}
ns.GuildTools = GT

function GT.CanInvite()
    return (IsInGuild and IsInGuild()) and (CanGuildInvite and ns.safe(CanGuildInvite())) and true or false
end

function GT.Invite(name)
    name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return end
    if not GT.CanInvite() then ns.print(L["Du darfst niemanden in die Gilde einladen."]) return end
    if C_GuildInfo and C_GuildInfo.Invite then pcall(C_GuildInfo.Invite, name) elseif GuildInvite then pcall(GuildInvite, name) end
    ns.print((L["Gildeneinladung an %s geschickt."]):format(name))
end

-- NIE "StaticPopupDialogs = ..." zuweisen (siehe GuildInfo.lua)
StaticPopupDialogs["OASIS_GUILD_INVITE"] = {
    text = "%s", button1 = ACCEPT or "OK", button2 = CANCEL or "Abbrechen", hasEditBox = true, maxLetters = 64,
    OnShow = function(self)
        local eb = self.editBox or self.EditBox
        if not eb then return end
        local t = ""
        if UnitExists("target") and UnitIsPlayer("target") and not UnitIsUnit("target", "player") then t = ns.safe(GetUnitName("target", true)) or "" end
        eb:SetText(t) eb:HighlightText() eb:SetFocus()
    end,
    OnAccept = function(self) local eb = self.editBox or self.EditBox GT.Invite(eb and eb:GetText()) end,
    EditBoxOnEnterPressed = function(self) local p = self:GetParent() if p.button1 then p.button1:Click() end end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}
function GT.AskInvite()
    if not GT.CanInvite() then ns.print(L["Du darfst niemanden in die Gilde einladen."]) return end
    StaticPopup_Show("OASIS_GUILD_INVITE", L["Name des Spielers (Ziel wird vorgeschlagen):"])
end

function GT.OpenBlizzard()
    if InCombatLockdown and InCombatLockdown() then ns.print(L["Im Kampf nicht moeglich - gleich nochmal."]) return end
    if ns.HideMain and ns.MainShown and ns.MainShown() then ns.HideMain() end
    if ToggleGuildFrame then ToggleGuildFrame()
    elseif ToggleCommunitiesFrame then ToggleCommunitiesFrame()
    elseif CommunitiesFrame and ShowUIPanel then ShowUIPanel(CommunitiesFrame) end
end

ns.slash.einladen = function(arg) if arg and arg ~= "" then GT.Invite(arg) else GT.AskInvite() end end
ns.slash.invite = ns.slash.einladen
ns.slash.gilde = function() GT.OpenBlizzard() end
ns.slash.guild = ns.slash.gilde
