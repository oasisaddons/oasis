-- Oasis - Texte: gesperrte Bereiche (abgedunkelt mit Hinweis, wer das darf)
local ADDON, ns = ...
local DE, EN = ns.LOCALE_DE, ns.LOCALE_EN

local DEFIX = {
    ["Nur fuer Schlachtzugsleiter"] = "Nur für Schlachtzugsleiter",
    ["Nur fuer Offiziere"] = "Nur für Offiziere",
    ["Nur fuer die Gildenleitung"] = "Nur für Gildenleitung und Offiziere",
    ["Nur fuer Anfuehrer und Assistenten"] = "Nur für Anführer und Assistenten",
    ["Dein Gildenrang darf das nicht"] = "Dein Gildenrang darf das nicht",
    ["Die Gildenleitung benennt Schlachtzugsleiter unter Krone > Module > Raids & Beute. Im laufenden Raid zaehlen auch Raidleiter und Assistenten."] = "Die Gildenleitung benennt Schlachtzugsleiter unter Krone > Module > Raids & Beute. Im laufenden Raid zählen auch Raidleiter und Assistenten.",
    ["Offiziersraenge legt der Gildenmeister im Gildenfenster fest."] = "Offiziersränge legt der Gildenmeister im Gildenfenster fest.",
    ["Wer zur Gildenleitung gehoert, legt der Gildenmeister unter Krone > Gilde fest."] = "Wer zur Gildenleitung gehört, legt der Gildenmeister unter Krone > Gilde fest.",
    ["Der Gruppenanfuehrer kann dich zum Assistenten machen."] = "Der Gruppenanführer kann dich zum Assistenten machen.",
    ["Die Gildenleitung legt unter Krone > Module fest, welche Raenge das duerfen."] = "Die Gildenleitung legt unter Krone > Module fest, welche Ränge das dürfen.",
    ["Die Gildenleitung benennt Schlachtzugsleiter unter Krone > Module > Raids & Beute. Im laufenden Raid zaehlt auch der Raidleiter."] = "Die Gildenleitung benennt Schlachtzugsleiter unter Krone > Module > Raids & Beute. Im laufenden Raid zählt auch der Raidleiter.",
    ["Nur fuer Schlachtzugsleiter & Assistenz"] = "Nur für Schlachtzugsleiter & Assistenz",
    ["Die Gildenleitung benennt Schlachtzugsleiter und Assistenz unter Krone > Module > Raids & Beute (Namen oder ab Gildenrang). Im laufenden Raid zaehlen auch Raidleiter und Assistenten."] = "Die Gildenleitung benennt Schlachtzugsleiter und Assistenz unter Krone > Module > Raids & Beute (Namen oder ab Gildenrang). Im laufenden Raid zählen auch Raidleiter und Assistenten.",
    ["Helfen im laufenden Raid: Ready-Check, Fehlende ansagen, Taktik-Karte zeichnen, Gruppen im Raidplaner sortieren. Keine Termine, keine Beute-Einstellungen, keine Taktiken dauerhaft aendern."] = "Helfen im laufenden Raid: Ready-Check, Fehlende ansagen, Taktik-Karte zeichnen, Gruppen im Raidplaner sortieren. Keine Termine, keine Beute-Einstellungen, keine Taktiken dauerhaft ändern.",
    ["Schlachtzugsleiter ab Gildenrang"] = "Schlachtzugsleiter ab Gildenrang",
    ["Schlachtzugs-Assistenz ab Gildenrang"] = "Schlachtzugs-Assistenz ab Gildenrang",
    ["Automatisch Schlachtzugsleiter: alle Mitglieder bis zu diesem Gildenrang. 0 = aus (nur die Namensliste)."] = "Automatisch Schlachtzugsleiter: alle Mitglieder bis zu diesem Gildenrang. 0 = aus (nur die Namensliste).",
    ["Automatisch Schlachtzugs-Assistenz: alle Mitglieder bis zu diesem Gildenrang. 0 = aus (nur die Namensliste)."] = "Automatisch Schlachtzugs-Assistenz: alle Mitglieder bis zu diesem Gildenrang. 0 = aus (nur die Namensliste).",
    ["Schlachtzugs-Assistenz"] = "Schlachtzugs-Assistenz",
    ["Schlachtzugsleitung"] = "Schlachtzugsleitung",
    ["Gildenleitung und Offiziere haben alle Schlachtzugsleiter-Rechte. Im laufenden Raid zaehlen Raidleiter und Assistenten fuer die Dauer des Raids."] = "Gildenleitung und Offiziere haben alle Schlachtzugsleiter-Rechte. Im laufenden Raid zählen Raidleiter und Assistenten für die Dauer des Raids.",
    ["aus"] = "aus",
}
for k, v in pairs(DEFIX) do DE[k] = v end

local ENC = {
    ["Nur fuer Schlachtzugsleiter"] = "Raid leaders only",
    ["Nur fuer Offiziere"] = "Officers only",
    ["Nur fuer die Gildenleitung"] = "Guild leadership and officers only",
    ["Nur fuer Anfuehrer und Assistenten"] = "Group leader and assistants only",
    ["Dein Gildenrang darf das nicht"] = "Your guild rank can't do this",
    ["Die Gildenleitung benennt Schlachtzugsleiter unter Krone > Module > Raids & Beute. Im laufenden Raid zaehlen auch Raidleiter und Assistenten."] = "The guild leadership names raid leaders under Crown > Modules > Raids & Loot. In a running raid, the raid leader and assistants count too.",
    ["Offiziersraenge legt der Gildenmeister im Gildenfenster fest."] = "The guild master sets officer ranks in the guild window.",
    ["Wer zur Gildenleitung gehoert, legt der Gildenmeister unter Krone > Gilde fest."] = "The guild master decides who belongs to the leadership under Crown > Guild.",
    ["Der Gruppenanfuehrer kann dich zum Assistenten machen."] = "The group leader can make you an assistant.",
    ["Die Gildenleitung legt unter Krone > Module fest, welche Raenge das duerfen."] = "The guild leadership sets which ranks may do this under Crown > Modules.",
    ["Die Gildenleitung benennt Schlachtzugsleiter unter Krone > Module > Raids & Beute. Im laufenden Raid zaehlt auch der Raidleiter."] = "The guild leadership names raid leaders under Crown > Modules > Raids & Loot. In a running raid, the raid leader counts too.",
    ["Nur fuer Schlachtzugsleiter & Assistenz"] = "Raid leaders & raid assistants only",
    ["Die Gildenleitung benennt Schlachtzugsleiter und Assistenz unter Krone > Module > Raids & Beute (Namen oder ab Gildenrang). Im laufenden Raid zaehlen auch Raidleiter und Assistenten."] = "The guild leadership names raid leaders and assistants under Crown > Modules > Raids & Loot (by name or from a guild rank). In a running raid, the raid leader and assistants count too.",
    ["Helfen im laufenden Raid: Ready-Check, Fehlende ansagen, Taktik-Karte zeichnen, Gruppen im Raidplaner sortieren. Keine Termine, keine Beute-Einstellungen, keine Taktiken dauerhaft aendern."] = "Help during a running raid: ready check, call out missing players, draw on the tactics map, sort groups in the raid planner. No events, no loot settings, no permanent tactic edits.",
    ["Schlachtzugsleiter ab Gildenrang"] = "Raid leaders from guild rank",
    ["Schlachtzugs-Assistenz ab Gildenrang"] = "Raid assistants from guild rank",
    ["Automatisch Schlachtzugsleiter: alle Mitglieder bis zu diesem Gildenrang. 0 = aus (nur die Namensliste)."] = "Automatic raid leaders: all members up to this guild rank. 0 = off (name list only).",
    ["Automatisch Schlachtzugs-Assistenz: alle Mitglieder bis zu diesem Gildenrang. 0 = aus (nur die Namensliste)."] = "Automatic raid assistants: all members up to this guild rank. 0 = off (name list only).",
    ["Schlachtzugs-Assistenz"] = "Raid assistants",
    ["Schlachtzugsleitung"] = "Raid staff",
    ["Gildenleitung und Offiziere haben alle Schlachtzugsleiter-Rechte. Im laufenden Raid zaehlen Raidleiter und Assistenten fuer die Dauer des Raids."] = "Guild leadership and officers have all raid leader rights. In a running raid, the raid leader and assistants count for the duration of the raid.",
    ["aus"] = "off",
}
for k, v in pairs(ENC) do EN[k] = v end
