
# Crafting recipes. kind: fixed | modular
# station: hand, campfire, workbench, forge, alchemy, kitchen
# req_research: research id needed (None = known from start); req_skill: (skill, rank)

def F(name, station, inputs, out, n=1, research=None, skill=None, time=1.0, xp=4):
    return dict(kind="fixed", name=name, station=station, inputs=inputs, output=out, count=n,
                research=research, skill=skill, time=time, xp=xp)


def MOD(name, station, base, slots, extra=None, research=None, xp=8):
    return dict(kind="modular", name=name, station=station, base=base, slots=slots, inputs=extra or {},
                research=research, xp=xp)


RECIPES = {
    # ---------------------------------------------------------------- hand crafting
    "r_torch": F("Fackel", "hand", {"wood": 1, "fiber": 2}, "torch"),
    "r_bandage": F("Verband", "hand", {"fiber": 4, "herb_healing": 1}, "bandage"),
    "r_thatch": F("Stroh", "hand", {"fiber": 4}, "thatch", 2),
    "r_arrow_stone": F("Steinpfeile", "hand", {"wood": 1, "flint": 1, "fiber": 1}, "arrow_stone", 5),
    "r_arrow_tranq": F("Betäubungspfeile", "hand", {"arrow_stone": 2, "narcotic": 1}, "arrow_tranq", 2),
    "r_bola": F("Bola", "hand", {"fiber": 6, "stone": 2}, "bola", 1),
    "r_narcotic": F("Betäubungsmittel", "hand", {"narcoberry": 5, "raw_meat": 1}, "narcotic", 1),
    "r_javelin": F("Wurfspeer", "hand", {"wood": 2, "flint": 1, "fiber": 2}, "javelin", 2),
    # modular weapons (workbench or hand for primitive)
    "m_spear": MOD("Speer", "hand", "spear_stone", {"head": dict(tag="head", n=2), "shaft": dict(tag="shaft", n=3), "binding": dict(tag="binding", n=3)}),
    "m_axe": MOD("Axt", "hand", "axe_stone", {"head": dict(tag="head", n=3), "shaft": dict(tag="shaft", n=2), "binding": dict(tag="binding", n=3)}),
    "m_pick": MOD("Spitzhacke", "hand", "pick_stone", {"head": dict(tag="head", n=3), "shaft": dict(tag="shaft", n=2), "binding": dict(tag="binding", n=3)}),
    "m_club": MOD("Keule", "hand", "club_wood", {"shaft": dict(tag="shaft", n=4), "binding": dict(tag="binding", n=2)}),
    "m_sword": MOD("Schwert", "forge", "sword_metal", {"head": dict(tag="head", n=4), "shaft": dict(tag="shaft", n=1), "binding": dict(tag="binding", n=2)}, research="metallurgy"),
    "m_bow": MOD("Bogen", "workbench", "bow_wood", {"shaft": dict(tag="shaft", n=4), "binding": dict(tag="binding", n=5)}),
    "m_staff": MOD("Stab", "workbench", "staff_wood", {"shaft": dict(tag="shaft", n=3), "focus": dict(tag="focus", n=1, optional=True)}),
    # ---------------------------------------------------------------- workbench
    "r_bow_composite": F("Kompositbogen", "workbench", {"hardwood": 4, "sinew": 6, "horn": 2}, "bow_composite", research="advanced_archery"),
    "r_crossbow": F("Armbrust", "forge", {"hardwood": 4, "metal_ingot": 4, "sinew": 4}, "crossbow", research="mechanics"),
    "r_blowpipe": F("Blasrohr", "workbench", {"wood": 3, "fiber": 4}, "blowpipe", research="tranquilizers"),
    "r_dart_tranq": F("Betäubungspfeilchen", "workbench", {"fiber": 2, "narcotic": 1, "feather": 1}, "dart_tranq", 4, research="tranquilizers"),
    "r_shield_wood": F("Holzschild", "workbench", {"wood": 8, "hide": 2, "fiber": 4}, "shield_wood"),
    "r_shield_metal": F("Metallschild", "forge", {"metal_ingot": 6, "leather": 2}, "shield_metal", research="metallurgy"),
    "r_leather": F("Leder gerben", "workbench", {"hide": 3, "salt": 1}, "leather", 2),
    "r_sinew": F("Sehnen gewinnen", "workbench", {"hide": 2, "bone": 1}, "sinew", 2),
    "r_armor_hide_head": F("Lederkappe", "workbench", {"hide": 4, "fiber": 4}, "armor_hide_head"),
    "r_armor_hide_chest": F("Lederweste", "workbench", {"hide": 8, "fiber": 6}, "armor_hide_chest"),
    "r_armor_hide_legs": F("Lederhose", "workbench", {"hide": 6, "fiber": 5}, "armor_hide_legs"),
    "r_armor_fur_chest": F("Pelzmantel", "workbench", {"pelt": 6, "leather": 2, "sinew": 2}, "armor_fur_chest", research="cold_gear"),
    "r_armor_bone_chest": F("Knochenpanzer", "workbench", {"bone": 12, "large_bone": 2, "leather": 3}, "armor_bone_chest", research="bone_craft"),
    "r_armor_bone_head": F("Knochenhelm", "workbench", {"bone": 6, "leather": 1}, "armor_bone_head", research="bone_craft"),
    "r_armor_chitin_chest": F("Chitinpanzer", "workbench", {"chitin": 10, "silk": 4}, "armor_chitin_chest", research="chitin_craft"),
    "r_armor_chitin_legs": F("Chitinbeinlinge", "workbench", {"chitin": 7, "silk": 3}, "armor_chitin_legs", research="chitin_craft"),
    "r_saddle_small": F("Leichter Sattel", "workbench", {"leather": 6, "fiber": 10, "wood": 4}, "saddle_small", research="saddlery"),
    "r_saddle_large": F("Schwerer Sattel", "workbench", {"leather": 14, "sinew": 6, "hardwood": 6}, "saddle_large", research="saddlery"),
    "r_saddle_huge": F("Kolosssattel", "workbench", {"leather": 24, "sinew": 12, "metal_ingot": 6, "hardwood": 10}, "saddle_huge", research="saddlery_2"),
    "r_saddle_flyer": F("Flugsattel", "workbench", {"leather": 10, "silk": 4, "feather": 10}, "saddle_flyer", research="flight_harness"),
    "r_saddle_sea": F("Seesattel", "workbench", {"leather": 10, "scales": 6, "silk": 2}, "saddle_sea", research="sea_harness"),
    "r_trap_bear": F("Fußfalle", "workbench", {"wood": 4, "flint": 4, "sinew": 2}, "trap_bear", research="trapping"),
    "r_trap_net": F("Netzfalle", "workbench", {"fiber": 20, "wood": 4, "narcotic": 2}, "trap_net", research="trapping"),
    "r_trap_spike": F("Stachelgrube", "workbench", {"wood": 10, "flint": 4}, "trap_spike", research="trapping"),
    "r_firebomb": F("Feuertopf", "workbench", {"clay": 2, "sulfur": 2, "fiber": 2}, "firebomb", 2, research="incendiaries"),
    "r_arrow_fire": F("Brandpfeile", "workbench", {"arrow_stone": 4, "sulfur": 1}, "arrow_fire", 4, research="incendiaries"),
    "r_trinket_beast": F("Bestienzahn-Amulett", "workbench", {"raptor_claw": 2, "trex_tooth": 1, "sinew": 2}, "trinket_beast", research="beast_lore"),
    # ---------------------------------------------------------------- forge
    "r_metal_ingot": F("Metall schmelzen", "forge", {"metal_ore": 2, "charcoal": 1}, "metal_ingot", 1, time=2.0),
    "r_charcoal": F("Holzkohle", "campfire", {"wood": 2}, "charcoal", 2),
    "r_cement": F("Mörtel", "workbench", {"stone": 3, "clay": 2}, "cement", 2),
    "r_arrow_metal": F("Metallpfeile", "forge", {"metal_ingot": 1, "wood": 2, "feather": 2}, "arrow_metal", 8, research="metallurgy"),
    "r_bolt_metal": F("Metallbolzen", "forge", {"metal_ingot": 1, "hardwood": 1}, "bolt_metal", 6, research="mechanics"),
    "r_bolt_tranq": F("Betäubungsbolzen", "forge", {"bolt_metal": 2, "narcotic": 2}, "bolt_tranq", 2, research="mechanics"),
    "r_armor_metal_chest": F("Metallharnisch", "forge", {"metal_ingot": 14, "leather": 4}, "armor_metal_chest", research="metallurgy"),
    "r_armor_metal_head": F("Metallhelm", "forge", {"metal_ingot": 6, "leather": 1}, "armor_metal_head", research="metallurgy"),
    "r_armor_wyvern": F("Wyvernschuppenrüstung", "forge", {"wyvern_scale": 12, "silk": 6, "metal_ingot": 4}, "armor_wyvern_chest", research="dragon_smith"),
    "r_gunpowder": F("Schwarzpulver", "alchemy", {"sulfur": 2, "charcoal": 2, "salt": 1}, "gunpowder", 3, research="black_powder"),
    "r_donnerrohr": F("Donnerrohr", "forge", {"metal_ingot": 12, "hardwood": 4, "gunpowder": 4}, "donnerrohr", research="black_powder"),
    "r_shot_iron": F("Eisenkugeln", "forge", {"metal_ingot": 1, "gunpowder": 2}, "shot_iron", 6, research="black_powder"),
    "r_runenbuechse": F("Runenbüchse", "forge", {"metal_ingot": 10, "crystal": 6, "elemental_essence": 4, "hardwood": 4}, "runenbuechse", research="runetech"),
    "r_rune_charge": F("Runenladung", "alchemy", {"crystal": 1, "elemental_essence": 1}, "rune_charge", 5, research="runetech"),
    "r_staff_crystal": F("Kristallstab", "workbench", {"hardwood": 4, "crystal": 4, "silk": 2}, "staff_crystal", research="crystal_focus"),
    # ---------------------------------------------------------------- campfire / kitchen
    "r_cooked_meat": F("Fleisch braten", "campfire", {"raw_meat": 1}, "cooked_meat", 1, time=0.5, xp=1),
    "r_cooked_prime": F("Edelfleisch braten", "campfire", {"raw_prime_meat": 1}, "cooked_prime", 1, time=0.5, xp=1),
    "r_cooked_fish": F("Fisch braten", "campfire", {"raw_fish": 1}, "cooked_fish", 1, time=0.5, xp=1),
    "r_cooked_prime_fish": F("Edelfisch braten", "campfire", {"raw_prime_fish": 1}, "cooked_prime", 1, time=0.5, xp=1),
    "r_jerky": F("Trockenfleisch", "kitchen", {"cooked_meat": 2, "salt": 1}, "jerky", 2),
    "r_stew": F("Jägereintopf", "kitchen", {"cooked_meat": 2, "veggies": 3, "mushroom": 1}, "stew", 1),
    "r_kibble": F("Bestienfutter", "kitchen", {"raw_meat": 2, "veggies": 2, "berries": 4}, "kibble", 2, research="beast_lore"),
    # ---------------------------------------------------------------- alchemy
    "r_healing_salve": F("Heilsalbe", "alchemy", {"herb_healing": 3, "mushroom": 1}, "healing_salve"),
    "r_healing_potion": F("Heiltrank", "alchemy", {"herb_healing": 4, "rare_flower": 1, "crystal": 1}, "healing_potion", research="potency"),
    "r_stamina_tonic": F("Ausdauertonikum", "alchemy", {"berries": 6, "mushroom": 2}, "stamina_tonic"),
    "r_antidote": F("Gegengift", "alchemy", {"venom_gland": 1, "herb_healing": 2}, "antidote"),
    "r_creature_medicine": F("Tiermedizin", "alchemy", {"herb_healing": 4, "veggies": 2, "salt": 1}, "creature_medicine", research="veterinary"),
    "r_purify_tonic": F("Reinigungstrank", "alchemy", {"rare_flower": 2, "crystal": 1, "essence_light": 1}, "purify_tonic", research="gene_therapy"),
    "r_gene_stabilizer": F("Genstabilisator", "alchemy", {"crystal": 1, "elemental_essence": 1, "blood_crystal": 1}, "gene_stabilizer", research="gene_therapy"),
    "r_forget_potion": F("Trank des Vergessens", "alchemy", {"rare_flower": 3, "shadow_shard": 1, "mushroom": 4}, "forget_potion", research="potency"),
    "r_repel_musk": F("Moschussalbe", "alchemy", {"herb_healing": 2, "venom_gland": 1}, "repel_musk"),
    "r_binding_rune": F("Bindungsrune", "alchemy", {"crystal": 2, "elemental_essence": 2, "silk": 1}, "binding_rune", research="binding_magic"),
    "r_pact_sigil": F("Paktsiegel", "alchemy", {"demon_essence": 4, "blood_crystal": 1, "rift_shard": 1}, "pact_sigil", research="pact_lore"),
    "r_soul_crystal": F("Seelenkristall", "alchemy", {"crystal": 6, "elemental_essence": 3, "rift_shard": 1}, "soul_crystal", research="crystal_2"),
    "r_trinket_rift": F("Rissamulett", "alchemy", {"rift_shard": 2, "crystal": 2, "essence_light": 1}, "trinket_rift", research="rift_analysis"),
}

# element runes: alchemy, need research "runecraft"; higher tier elements need extra research
EL_DE = {"fire": "Feuer", "water": "Wasser", "ice": "Eis", "lightning": "Blitz", "earth": "Erde", "wind": "Wind",
         "nature": "Natur", "poison": "Gift", "light": "Licht", "shadow": "Schatten", "blood": "Blut"}
for e in ["fire", "water", "ice", "lightning", "earth", "wind", "nature", "poison", "light", "shadow", "blood"]:
    RECIPES[f"r_rune_{e}"] = F(f"{EL_DE[e]}rune", "alchemy", {"stone": 2, "crystal": 1, f"essence_{e}": 2}, f"rune_{e}",
                               research="runecraft" if e not in ("light", "shadow", "blood") else "runecraft_2")
    RECIPES[f"r_essence_{e}"] = F(f"{EL_DE[e]}essenz destillieren", "alchemy", {"elemental_essence": 2}, f"essence_{e}", 1,
                                  research="element_theory")
