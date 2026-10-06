class_name Help
extends RefCounted
## Control reference text built from current key bindings.

static func controls_text() -> String:
	var lines := []
	for a in Settings.ACTIONS:
		lines.append("[b]%s[/b]: %s" % [Settings.binding_label(a), Settings.ACTIONS[a][0]])
	lines.append("\nReiten: E auf gesattelte Kreatur. Leertaste/Strg steigen/sinken bei Fliegern & Schwimmern. Fähigkeiten-Tasten nutzen die Angriffe des Reittiers.")
	lines.append("Bauen: B – Linksklick platzieren, R drehen, Rechtsklick abbrechen. Strg+E an eigenem Gebäude: abreißen.")
	lines.append("Zähmen: Fleischfresser betäuben (Keule, Betäubungspfeile, Bola) und dann füttern (E). Scheue Pflanzenfresser: ducken (Strg), langsam nähern, Futter anbieten.")
	return "\n".join(lines)
