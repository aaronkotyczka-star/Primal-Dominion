# Buildings / base pieces. size = footprint box [x, y, z] (m). snap = grid size (0 = free).
# station: crafting station type provided. pen_capacity: creature storage units.

def B(name, cat, cost, size, snap=0, research=None, desc="", **kw):
    d = dict(name=name, cat=cat, cost=cost, size=size, snap=snap, research=research, desc=desc, hp=500)
    d.update(kw)
    return d


BUILDINGS = {
    # core
    "camp_totem": B("Lagerstein", "facility", {"stone": 10, "wood": 6}, [1.2, 2.6, 1.2], desc="Beansprucht ein Lager (Radius 60 m). Ermöglicht Gehege, sicheres Speichern und Bewohner.", hp=2000, base_radius=60, safe_save=True, pen_capacity=0),
    "campfire": B("Lagerfeuer", "facility", {"stone": 6, "wood": 4}, [1.6, 0.6, 1.6], station="campfire", light=True, safe_save=True, desc="Kochen und Wärme. Sicherer Ort zum Speichern."),
    "bedroll": B("Schlaflager", "facility", {"hide": 6, "fiber": 10}, [1.0, 0.3, 2.2], bed=True, desc="Wiedereinstiegspunkt. Schlafen gibt den Bonus „Ausgeruht“."),
    "bed": B("Bett", "facility", {"wood": 12, "pelt": 4, "fiber": 10}, [1.4, 0.7, 2.3], bed=True, research="carpentry", desc="Wie Schlaflager, stärkerer Ruhebonus."),
    "storage_box": B("Vorratskiste", "facility", {"wood": 12, "fiber": 4}, [1.2, 0.8, 0.8], storage=30, desc="30 Plätze. Wird beim Herstellen in der Nähe genutzt."),
    "storage_large": B("Großes Lager", "facility", {"wood": 30, "metal_ingot": 4}, [2.4, 1.8, 1.4], storage=80, research="carpentry"),
    "workbench": B("Werkbank", "facility", {"wood": 20, "stone": 8, "fiber": 10}, [2.0, 1.0, 1.0], station="workbench"),
    "forge": B("Schmiede", "facility", {"stone": 40, "clay": 10, "wood": 10}, [2.4, 2.4, 2.0], station="forge", research="metallurgy", light=True),
    "alchemy_table": B("Alchemietisch", "facility", {"wood": 16, "stone": 10, "crystal": 2}, [1.8, 1.1, 1.0], station="alchemy", research="alchemy_basics"),
    "kitchen": B("Kochstelle", "facility", {"stone": 20, "clay": 6, "wood": 8}, [2.0, 1.6, 1.4], station="kitchen", light=True, research="cooking"),
    "research_table": B("Forschungstisch", "facility", {"wood": 18, "hide": 4, "stone": 6}, [2.0, 1.0, 1.2], station="research", desc="Forschung durchführen und Funde untersuchen."),
    "gene_lab": B("Genlabor", "facility", {"wood": 30, "crystal": 6, "metal_ingot": 6, "elemental_essence": 2}, [3.0, 2.4, 2.4], station="gene_lab", research="genetics_1", desc="Hybridisierung, Genanalyse und Stammbäume."),
    "incubator": B("Brutstätte", "facility", {"stone": 20, "clay": 8, "pelt": 2}, [2.0, 1.0, 2.0], station="incubator", desc="Brütet Eier aus. Bei Feuer in der Nähe schneller."),
    "infirmary": B("Krankenstation", "facility", {"wood": 24, "hide": 8, "herb_healing": 10}, [3.0, 2.0, 2.4], station="infirmary", research="veterinary", desc="Heilt Kreaturen im Lager und behandelt Verletzungen."),
    "pen": B("Gehege", "facility", {"wood": 40, "fiber": 20}, [10.0, 2.0, 10.0], pen_capacity=5, desc="+5 Kapazität für Kreaturen im Lager."),
    "pen_large": B("Großgehege", "facility", {"wood": 60, "stone": 40, "metal_ingot": 6}, [16.0, 3.5, 16.0], pen_capacity=12, research="husbandry_2"),
    "water_pen": B("Wassergehege", "facility", {"wood": 40, "stone": 30, "clay": 10}, [14.0, 1.5, 14.0], pen_capacity=6, water=True, research="sea_harness", desc="Für Wasserkreaturen. Nahe der Küste bauen."),
    "flight_platform": B("Flugplattform", "facility", {"wood": 50, "stone": 20, "hide": 10}, [8.0, 4.0, 8.0], pen_capacity=4, flyer=True, research="flight_harness", desc="Landeplatz und Unterkunft für Flieger."),
    "farm_plot": B("Feldbeet", "facility", {"wood": 6, "fiber": 10, "clay": 4}, [3.0, 0.4, 3.0], farm=True, research="agriculture", desc="Bewohner bauen hier Knollen, Beeren und Kräuter an."),
    "hut": B("Wohnhütte", "facility", {"wood": 40, "thatch": 20, "hide": 6}, [5.0, 4.0, 5.0], residents=2, desc="Unterkunft für 2 Bewohner."),
    "watchtower": B("Wachturm", "defense", {"wood": 40, "stone": 20}, [3.0, 7.0, 3.0], defense=dict(range=40, dmg=18, rate=1.6), research="fortification", desc="Bewohner oder Automatik verteidigen das Lager."),
    "palisade": B("Palisade", "defense", {"wood": 6}, [4.0, 3.5, 0.6], snap=2, hp=800),
    "palisade_gate": B("Palisadentor", "defense", {"wood": 14, "fiber": 6}, [4.0, 3.5, 0.6], snap=2, hp=800, gate=True),
    "stone_wall": B("Steinmauer", "defense", {"stone": 16, "cement": 4}, [4.0, 3.5, 0.8], snap=2, hp=2500, research="masonry"),
    "spike_wall": B("Stachelwall", "defense", {"wood": 10, "flint": 4}, [4.0, 1.6, 1.2], snap=2, hp=600, damage_touch=12),
    "torch_post": B("Fackelpfahl", "decor", {"wood": 2, "fiber": 2}, [0.3, 2.2, 0.3], light=True),
    "banner": B("Banner", "decor", {"wood": 4, "hide": 2}, [0.5, 4.0, 0.5], desc="Zeigt dein Wappen; erhöht die Moral der Bewohner."),
    "rift_altar": B("Rissaltar", "facility", {"stone": 30, "demon_essence": 6, "rift_shard": 2}, [3.0, 2.0, 3.0], station="pact", research="pact_lore", desc="Rituale, Pakte und Beschwörungen."),
    # structural pieces (snap 4 m)
    "foundation": B("Fundament", "structure", {"wood": 8}, [4.0, 0.5, 4.0], snap=4),
    "wall": B("Holzwand", "structure", {"wood": 6}, [4.0, 3.0, 0.3], snap=4),
    "wall_window": B("Fensterwand", "structure", {"wood": 5}, [4.0, 3.0, 0.3], snap=4),
    "doorway": B("Türrahmen", "structure", {"wood": 5, "fiber": 2}, [4.0, 3.0, 0.3], snap=4, gate=True),
    "roof": B("Dach", "structure", {"wood": 4, "thatch": 6}, [4.0, 0.3, 4.0], snap=4),
    "stairs": B("Treppe", "structure", {"wood": 8}, [2.0, 3.0, 4.0], snap=4),
}

# prefab templates: list of [piece, offset x, y, z, rot_deg]
TEMPLATES = {
    "tpl_hut": dict(name="Kleine Hütte", pieces=[["foundation", 0, 0, 0, 0], ["wall", 0, 0.5, -2, 0], ["wall", -2, 0.5, 0, 90],
                                                 ["wall_window", 2, 0.5, 0, 90], ["doorway", 0, 0.5, 2, 0], ["roof", 0, 3.5, 0, 0]]),
    "tpl_starter": dict(name="Startlager", pieces=[["camp_totem", 0, 0, 0, 0], ["campfire", 4, 0, 2, 0], ["bedroll", -3, 0, 3, 0],
                                                    ["workbench", 0, 0, 5, 0], ["storage_box", 3, 0, -3, 0]]),
    "tpl_outpost": dict(name="Wachposten", pieces=[["watchtower", 0, 0, 0, 0], ["palisade", 4, 0, 4, 0], ["palisade", -4, 0, 4, 0],
                                                    ["torch_post", 3, 0, -3, 0]]),
}
