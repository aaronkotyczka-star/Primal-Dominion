# Elements, status effects, reactions, abilities.

ELEMENTS = {
    "fire": dict(name="Feuer", color=[1.0, 0.45, 0.1], status="burning", weak_to=["water", "ice"], strong_vs=["nature", "ice"]),
    "water": dict(name="Wasser", color=[0.2, 0.5, 1.0], status="wet", weak_to=["lightning", "nature"], strong_vs=["fire", "earth"]),
    "ice": dict(name="Eis", color=[0.6, 0.85, 1.0], status="chilled", weak_to=["fire", "earth"], strong_vs=["wind", "nature"]),
    "lightning": dict(name="Blitz", color=[0.8, 0.8, 1.0], status="shocked", weak_to=["earth"], strong_vs=["water", "wind"]),
    "earth": dict(name="Erde", color=[0.55, 0.42, 0.25], status="shaken", weak_to=["water", "nature"], strong_vs=["lightning", "fire"]),
    "wind": dict(name="Wind", color=[0.75, 0.9, 0.8], status="scattered", weak_to=["ice", "lightning"], strong_vs=["poison", "earth"]),
    "nature": dict(name="Natur", color=[0.35, 0.8, 0.25], status="rooted", weak_to=["fire", "poison"], strong_vs=["water", "earth"]),
    "poison": dict(name="Gift", color=[0.5, 0.85, 0.2], status="poisoned", weak_to=["wind", "light"], strong_vs=["nature", "blood"]),
    "light": dict(name="Licht", color=[1.0, 0.95, 0.7], status="blinded", weak_to=["shadow"], strong_vs=["shadow", "blood"], vs_demonic=1.5),
    "shadow": dict(name="Schatten", color=[0.4, 0.2, 0.6], status="feared", weak_to=["light"], strong_vs=["light", "nature"]),
    "blood": dict(name="Blut", color=[0.7, 0.05, 0.08], status="bleeding", weak_to=["light", "poison"], strong_vs=["shadow"]),
}

STATUS = {
    "burning": dict(name="Brennen", dur=4.0, dot=0.025, color=[1, 0.4, 0.1]),
    "wet": dict(name="Nass", dur=6.0, color=[0.3, 0.5, 1.0]),
    "chilled": dict(name="Unterkühlt", dur=4.0, slow=0.3, stacks_to="frozen", stacks=3, color=[0.6, 0.85, 1]),
    "frozen": dict(name="Gefroren", dur=2.5, stun=True, color=[0.7, 0.9, 1]),
    "shocked": dict(name="Geschockt", dur=0.6, stun=True, chance=0.3, color=[0.8, 0.8, 1]),
    "shaken": dict(name="Erschüttert", dur=5.0, armor_mult=0.7, color=[0.6, 0.45, 0.3]),
    "scattered": dict(name="Zerstreut", dur=2.0, knockback=6.0, color=[0.75, 0.9, 0.8]),
    "rooted": dict(name="Verwurzelt", dur=1.5, root=True, chance=0.35, color=[0.35, 0.8, 0.25]),
    "poisoned": dict(name="Vergiftet", dur=8.0, dot=0.012, stackable=4, color=[0.5, 0.85, 0.2]),
    "blinded": dict(name="Geblendet", dur=3.0, miss=0.35, color=[1, 0.95, 0.7]),
    "feared": dict(name="Verängstigt", dur=4.0, dmg_mult=0.8, flee_chance=0.2, color=[0.4, 0.2, 0.6]),
    "bleeding": dict(name="Blutung", dur=6.0, dot=0.018, lifesteal=0.1, color=[0.7, 0.05, 0.08]),
    "stunned": dict(name="Betäubt", dur=1.0, stun=True, color=[1, 1, 0.5]),
    "slowed": dict(name="Verlangsamt", dur=4.0, slow=0.5, color=[0.6, 0.5, 0.4]),
    "steam": dict(name="Dampf", dur=3.0, miss=0.5, color=[0.85, 0.85, 0.85]),
    "septic": dict(name="Sepsis", dur=8.0, heal_mult=0.5, dot=0.01, color=[0.5, 0.3, 0.1]),
    "entangled": dict(name="Gefesselt", dur=5.0, root=True, color=[0.6, 0.55, 0.4]),
}

# Reaction rules: (existing status, incoming element) -> effect. Generic, no per-ability scripting.
REACTIONS = [
    dict(id="electrolysis", name="Elektrolyse", status="wet", element="lightning", dmg_mult=1.5, aoe=4.0, apply="shocked", consume=True),
    dict(id="freeze", name="Schockfrost", status="wet", element="ice", apply="frozen", consume=True),
    dict(id="steam", name="Dampfstoß", status="burning", element="water", dmg_mult=1.2, apply="steam", consume=True, aoe=3.0),
    dict(id="shatter", name="Frostbruch", status="frozen", element="fire", dmg_mult=1.8, consume=True),
    dict(id="shatter2", name="Zerschmettern", status="frozen", element="earth", dmg_mult=2.0, consume=True),
    dict(id="firestorm", name="Feuersturm", status="burning", element="wind", aoe=5.0, apply="burning", dmg_mult=1.3),
    dict(id="explosion", name="Giftexplosion", status="poisoned", element="fire", dmg_mult=1.4, aoe=3.5, consume=True),
    dict(id="wildfire", name="Flächenbrand", status="rooted", element="fire", apply="burning", dur_mult=2.0),
    dict(id="mud", name="Schlammfalle", status="shaken", element="water", apply="slowed"),
    dict(id="sandblast", name="Sandschleier", status="shaken", element="wind", apply="blinded", aoe=3.0),
    dict(id="overload", name="Überladung", status="shocked", element="wind", chain=2, dmg_mult=1.2),
    dict(id="twilight", name="Zwielicht", status="feared", element="light", dmg_mult=1.6, true_damage=True, consume=True),
    dict(id="twilight2", name="Zwielicht", status="blinded", element="shadow", dmg_mult=1.6, true_damage=True, consume=True),
    dict(id="corruption", name="Verderbnis", status="bleeding", element="shadow", lifesteal=0.3, dmg_mult=1.2),
    dict(id="sepsis", name="Sepsis", status="bleeding", element="poison", apply="septic", dmg_mult=1.2),
    dict(id="overgrowth", name="Wucherung", status="wet", element="nature", apply="entangled", consume=True),
    dict(id="purge", name="Läuterung", status="burning", element="light", dmg_mult=1.3, vs_demonic=1.5),
]

# mixture potency per component count (research unlocks higher counts)
MIXTURE = {"1": dict(potency=1.0, stamina=1.0, instability=0.0, research=None),
           "2": dict(potency=0.7, stamina=1.25, instability=0.05, research="element_fusion_1"),
           "3": dict(potency=0.55, stamina=1.5, instability=0.1, research="element_fusion_2"),
           "4": dict(potency=0.45, stamina=1.8, instability=0.16, research="element_fusion_3"),
           "5": dict(potency=0.4, stamina=2.1, instability=0.22, research="element_fusion_3")}


def A(name, kind, dmg=1.0, rng=3.0, cd=4.0, stam=15, anim="bite", desc="", **kw):
    d = dict(name=name, kind=kind, dmg=dmg, range=rng, cooldown=cd, stamina=stam, anim=anim, desc=desc)
    d.update(kw)
    return d


ABILITIES = {
    # creature melee basics
    "bite": A("Biss", "melee", 1.0, 0.0, 1.2, 6, "bite", "Grundangriff."),
    "heavy_bite": A("Zermalmen", "melee", 1.9, 0.0, 6.0, 25, "bite", "Kräftiger Biss, verursacht Blutung.", status="bleeding"),
    "slash_claw": A("Klauenhieb", "melee", 1.3, 0.0, 3.0, 12, "claw", "Schnelle Krallenattacke, Blutung.", status="bleeding"),
    "claw_rake": A("Krallenreißen", "melee", 1.5, 0.0, 5.0, 18, "claw", "Weiter Prankenhieb.", arc=120),
    "kick": A("Tritt", "melee", 0.9, 0.0, 2.5, 8, "bite", "Abwehrtritt mit Rückstoß.", knockback=4.0),
    "headbutt": A("Kopfstoß", "melee", 1.4, 0.0, 4.0, 15, "gore", "Betäubt kurz.", status="stunned"),
    "gore": A("Hornstoß", "melee", 1.6, 0.0, 5.0, 18, "gore", "Durchbohrt Panzer.", armor_pierce=0.5, knockback=5.0),
    "saber_strike": A("Säbelhieb", "melee", 2.0, 0.0, 7.0, 22, "bite", "Tiefe Wunde (starke Blutung).", status="bleeding", status_mult=2.0),
    "death_roll": A("Todesrolle", "melee", 2.4, 0.0, 10.0, 30, "bite", "Packt und reißt. Hält das Ziel fest.", status="entangled"),
    "venom_bite": A("Giftbiss", "melee", 1.2, 0.0, 4.0, 14, "bite", "Vergiftet.", element="poison"),
    "constrict": A("Würgen", "melee", 1.0, 0.0, 9.0, 25, "bite", "Umschlingt das Ziel, Schaden über Zeit.", status="entangled", dot_bonus=0.04),
    "thagomizer_strike": A("Stachelschlag", "melee", 1.8, 0.0, 5.0, 18, "tail_swipe", "Schwanzstacheln, Blutung, nach hinten.", status="bleeding", rear=True),
    "club_smash": A("Keulenschlag", "melee", 1.7, 0.0, 6.0, 20, "tail_swipe", "Betäubt und erschüttert Panzer.", status="shaken", status2="stunned", rear=True),
    "tail_swipe": A("Schwanzhieb", "aoe", 1.2, 0.0, 6.0, 20, "tail_swipe", "Trifft alle Gegner im Halbkreis.", radius=1.0, knockback=6.0, rear=True),
    "stomp": A("Stampfen", "aoe", 1.0, 0.0, 8.0, 25, "stomp", "Erschütterung: betäubt kleine Gegner.", radius=1.2, status="stunned", element="earth"),
    "charge": A("Sturmangriff", "move", 1.8, 18.0, 8.0, 25, "gore", "Ansturm mit Rückstoß.", knockback=8.0, dash=True),
    "pounce": A("Sprungangriff", "move", 1.5, 10.0, 6.0, 18, "bite", "Springt Beute an, wirft kleine Ziele um.", dash=True, status="stunned"),
    "sprint_burst": A("Sprint", "buff", 0.0, 0.0, 15.0, 30, "roar", "Kurzzeitig +40% Tempo.", buff=dict(speed=1.4, dur=6.0)),
    "plate_guard": A("Plattenwall", "buff", 0.0, 0.0, 18.0, 30, "roar", "+50% Panzerung für 8 s.", buff=dict(armor=1.5, dur=8.0)),
    "shell_up": A("Panzerkugel", "buff", 0.0, 0.0, 20.0, 30, "roar", "Schadensreduktion 60% für 5 s, bewegungsunfähig.", buff=dict(dmg_taken=0.4, root=True, dur=5.0)),
    "roar": A("Gebrüll", "aoe", 0.0, 0.0, 20.0, 30, "roar", "Verängstigt Gegner, stärkt Verbündete.", radius=14.0, status="feared", ally_buff=dict(dmg=1.15, dur=10.0), radius_abs=True),
    "howl": A("Heulen", "buff", 0.0, 0.0, 25.0, 25, "roar", "Rudel +20% Schaden.", ally_buff=dict(dmg=1.2, dur=12.0), radius=20.0, radius_abs=True),
    "pack_call": A("Rudelruf", "buff", 0.0, 0.0, 20.0, 15, "roar", "Rudelmitglieder +15% Tempo und Schaden.", ally_buff=dict(dmg=1.15, speed=1.15, dur=10.0), radius=18.0, radius_abs=True),
    "trumpet": A("Trompeten", "aoe", 0.0, 0.0, 20.0, 25, "roar", "Verängstigt kleinere Gegner.", radius=16.0, status="feared", radius_abs=True),
    "warning_call": A("Warnruf", "buff", 0.0, 0.0, 30.0, 20, "roar", "Herde und Gefährten heilen 10%.", ally_heal=0.1, radius=20.0, radius_abs=True),
    "frill_display": A("Kragendrohung", "aoe", 0.0, 0.0, 12.0, 10, "roar", "Verängstigt kleine Gegner.", radius=8.0, status="feared", radius_abs=True),
    "frenzy": A("Blutrausch", "buff", 0.0, 0.0, 20.0, 20, "roar", "+30% Angriffstempo, wenn Ziel blutet.", buff=dict(atk_speed=1.3, dur=8.0)),
    "poison_spit": A("Giftspucke", "ranged", 0.8, 18.0, 4.0, 12, "spit", "Blendet und vergiftet.", element="poison", status2="blinded", projectile="spit"),
    "web_shot": A("Netzschuss", "ranged", 0.3, 20.0, 8.0, 15, "bite", "Verlangsamt stark.", status="slowed", projectile="web"),
    "breath": A("Elementaratem", "ranged", 1.6, 16.0, 7.0, 30, "roar", "Kegelatem mit dem Element des aktiven Elementplatzes.", element="slot", cone=True),
    "hellfire_breath": A("Höllenfeuer", "ranged", 1.5, 12.0, 7.0, 28, "roar", "Dämonische Flammen.", element="fire", cone=True, status2="feared"),
    "dive": A("Sturzflug", "move", 1.8, 30.0, 8.0, 20, "bite", "Stößt aus der Luft herab.", dash=True, air=True, knockback=5.0),
    "grab": A("Greifen", "utility", 0.5, 0.0, 10.0, 20, "bite", "Packt kleine Kreaturen und trägt sie.", grab=True),
    "wing_buffet": A("Flügelschlag", "aoe", 0.6, 0.0, 9.0, 20, "wing_buffet", "Stößt Gegner zurück.", radius=1.4, knockback=10.0, element="wind"),
    "tidal_slam": A("Flutschlag", "aoe", 1.6, 0.0, 9.0, 25, "tail_swipe", "Wasserwelle, durchnässt.", radius=1.4, element="water", knockback=6.0),
    "sonar_pulse": A("Sonarpuls", "utility", 0.0, 0.0, 15.0, 10, "roar", "Enthüllt Kreaturen und Schätze unter Wasser.", reveal=60.0),
    "harvest": A("Ernten", "utility", 0.0, 0.0, 1.5, 4, "bite", "Sammelt Ressourcen (Holz, Stein, Beeren) in großer Menge.", harvest=True),
    "shadow_step": A("Schattenschritt", "move", 1.2, 14.0, 7.0, 18, "claw", "Teleportiert hinter das Ziel.", blink=True, element="shadow"),
    "bone_storm": A("Knochensturm", "aoe", 1.5, 0.0, 12.0, 35, "roar", "Splitterhagel um den Wyrm.", radius=1.5, status="bleeding", element="blood"),
    # player abilities (skills)
    "heal_minor": A("Heilung", "spell", 0.0, 0.0, 6.0, 20, "heal", "Heilt dich oder einen anvisierten Gefährten (25 LP + Heilkraft).", heal=25, target="ally_or_self", player=True),
    "heal_wave": A("Heilende Welle", "spell", 0.0, 0.0, 18.0, 40, "heal", "Heilt dich und alle Gefährten in 15 m.", heal=35, radius=15.0, player=True),
    "ward": A("Schutzglyphe", "spell", 0.0, 0.0, 20.0, 30, "cast", "Schild absorbiert 60 Schaden (Ziel oder du).", shield=60, target="ally_or_self", player=True),
    "cleanse": A("Reinigen", "spell", 0.0, 0.0, 12.0, 20, "cast", "Entfernt negative Zustände.", cleanse=True, target="ally_or_self", player=True),
    "beast_mend": A("Tierheilung", "spell", 0.0, 0.0, 10.0, 25, "heal", "Heilt einen Gefährten stark (80 LP).", heal=80, target="ally", player=True),
    "firebolt": A("Feuerlanze", "spell", 1.0, 40.0, 3.0, 18, "cast", "Feuergeschoss (Elementarmagie).", base_dmg=30, element="fire", projectile="bolt", player=True),
    "ice_shard": A("Eissplitter", "spell", 1.0, 40.0, 3.5, 18, "cast", "Unterkühlt das Ziel.", base_dmg=24, element="ice", projectile="bolt", player=True),
    "lightning_arc": A("Blitzbogen", "spell", 1.0, 25.0, 6.0, 25, "cast", "Springt auf 2 weitere Ziele über.", base_dmg=28, element="lightning", projectile="bolt", chain=2, player=True),
    "power_strike": A("Kraftschlag", "melee", 2.2, 0.0, 6.0, 25, "overhead", "Wuchtiger Schlag, betäubt.", status="stunned", player=True),
    "whirlwind": A("Wirbel", "aoe", 1.2, 0.0, 9.0, 35, "slash", "Trifft alle Gegner um dich.", radius=3.5, radius_abs=True, player=True),
    "aimed_shot": A("Gezielter Schuss", "ranged", 2.0, 80.0, 6.0, 15, "bow", "Nächster Schuss +100% Schaden und Durchschlag.", next_shot=2.0, player=True),
    "multishot": A("Salve", "ranged", 0.7, 50.0, 8.0, 25, "bow", "Drei Pfeile im Fächer.", multishot=3, player=True),
    "beast_rally": A("Bestienruf", "buff", 0.0, 0.0, 30.0, 30, "cast", "Gefährten +25% Schaden und Tempo für 12 s.", ally_buff=dict(dmg=1.25, speed=1.2, dur=12.0), radius=30.0, radius_abs=True, player=True),
    "dash": A("Hechtsprung", "move", 0.0, 8.0, 5.0, 15, "dodge", "Weiter Ausweichsprung.", player=True),
    # demon form powers
    "d_hellfire": A("Höllenfeuer", "spell", 1.0, 30.0, 4.0, 15, "cast", "Dämonisches Feuer.", base_dmg=45, element="fire", projectile="bolt", demon=True),
    "d_shadowstep": A("Schattensprung", "move", 0.8, 16.0, 6.0, 15, "slash", "Teleport hinter das Ziel.", blink=True, element="shadow", demon=True),
    "d_bloodfrenzy": A("Blutrausch", "buff", 0.0, 0.0, 20.0, 20, "cast", "+40% Schaden, Lebensraub 15% für 10 s.", buff=dict(dmg=1.4, lifesteal=0.15, dur=10.0), demon=True),
    "d_terror": A("Schreckensbrüllen", "aoe", 0.3, 0.0, 15.0, 20, "cast", "Verängstigt alle Gegner in 15 m.", radius=15.0, radius_abs=True, status="feared", demon=True),
    "d_claws": A("Klauenwirbel", "aoe", 1.4, 0.0, 6.0, 15, "slash", "Klauenwirbel, Blutung.", radius=3.0, radius_abs=True, status="bleeding", demon=True),
}
