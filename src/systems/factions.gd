class_name Factions
extends RefCounted
## Faction relations and reactions (incl. visible demon form; reputation persists across form changes).

const HOSTILE_BELOW := -40


static func attitude(fid: String) -> String:
	var r := GameState.rep(fid)
	if fid == "daemonengoblins" and GameState.player()["demon"].get("in_form", false):
		return "neutral"
	if r <= HOSTILE_BELOW:
		return "hostile"
	if r < 0:
		return "wary"
	if r < 50:
		return "neutral"
	return "friendly"


static func rep_label(r: int) -> String:
	if r <= -60:
		return "Verfeindet"
	if r <= -20:
		return "Feindselig"
	if r < 20:
		return "Neutral"
	if r < 60:
		return "Freundlich"
	return "Verbündet"


static func on_form_seen(player: Node3D, demon: bool) -> void:
	## NPCs within sight react to a visible transformation. Known deeds/rep persist.
	if not demon:
		return
	var seen := {}
	for n in player.get_tree().get_nodes_in_group("npcs"):
		if n.global_position.distance_to(player.global_position) < 35.0 and not n.get("hostile_npc"):
			seen[n.faction] = true
	var d: Dictionary = GameState.player()["demon"]
	for fid in seen:
		var reaction: String = DB.faction(fid).get("demon_reaction", "hostile")
		if not d["seen_by"].has(fid):
			d["seen_by"][fid] = true
			match reaction:
				"hostile":
					GameState.change_rep(fid, -30, "Dämonengestalt gesehen")
				"flee":
					GameState.change_rep(fid, -20, "Dämonengestalt gesehen")
				"respect":
					GameState.change_rep(fid, 15, "Dämonengestalt bewundert")
				"ally":
					GameState.change_rep(fid, 20, "Als Gehörnter erkannt")
	if not seen.is_empty():
		GameState.add_path("demon", 1)


static func npc_reacts_to_demon(fid: String) -> String:
	if not GameState.player()["demon"].get("in_form", false):
		return ""
	return DB.faction(fid).get("demon_reaction", "hostile")
