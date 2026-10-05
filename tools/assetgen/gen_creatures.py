"""Generates all creature / humanoid meshes into assets/creatures.
Usage: python3 gen_creatures.py [id ...]
"""
import os
import sys
import time

from families import theropod, quadruped, flyer, wyvern, marine, serpent, arthropod, humanoid

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "creatures")

SPECIES = {
    # ---------------- theropods
    "trex": lambda: theropod("trex", H=2.4, torso_len=3.0, torso_r=0.88, chest_r=0.72, neck_len=1.1, neck_r=0.42,
                             neck_angle=28, head_len=1.45, head_r=0.55, snout_r=0.3, head_pitch=-6, tail_len=5.6,
                             tail_r=0.7, leg_r=0.32, arm_len=0.75, arm_r=0.1, hand_claws=2, n_teeth=9, deep_snout=1.15, eye=0.8),
    "atrociraptor": lambda: theropod("atrociraptor", H=0.75, torso_len=0.95, torso_r=0.24, chest_r=0.2, neck_len=0.45,
                                     neck_r=0.075, neck_angle=40, head_len=0.32, head_r=0.1, snout_r=0.07, tail_len=1.7,
                                     tail_r=0.13, leg_r=0.07, arm_len=0.55, arm_r=0.04, sickle=True, deep_snout=1.25, n_teeth=7),
    "raptor": lambda: theropod("raptor", H=0.7, torso_len=0.9, torso_r=0.2, chest_r=0.17, neck_len=0.5, neck_r=0.06,
                               neck_angle=45, head_len=0.36, head_r=0.085, snout_r=0.035, tail_len=1.7, tail_r=0.11,
                               leg_r=0.06, arm_len=0.55, arm_r=0.035, sickle=True, n_teeth=8),
    "spinosaurus": lambda: theropod("spinosaurus", H=2.3, torso_len=3.6, torso_r=0.85, chest_r=0.75, neck_len=1.6,
                                    neck_r=0.35, neck_angle=30, head_len=1.8, head_r=0.38, snout_r=0.14, head_pitch=-10,
                                    tail_len=6.0, tail_r=0.55, leg_r=0.26, arm_len=1.3, arm_r=0.12, n_teeth=11),
    "carnotaurus": lambda: theropod("carnotaurus", H=1.9, torso_len=2.4, torso_r=0.7, chest_r=0.6, neck_len=0.8,
                                    neck_r=0.3, neck_angle=30, head_len=0.85, head_r=0.36, snout_r=0.25, tail_len=4.0,
                                    tail_r=0.5, leg_r=0.24, arm_len=0.35, arm_r=0.06, hand_claws=0, deep_snout=1.2, n_teeth=8),
    "dilophosaurus": lambda: theropod("dilophosaurus", H=1.1, torso_len=1.4, torso_r=0.33, chest_r=0.28, neck_len=0.8,
                                      neck_r=0.11, neck_angle=40, head_len=0.5, head_r=0.13, snout_r=0.06, tail_len=2.4,
                                      tail_r=0.2, leg_r=0.1, arm_len=0.6, arm_r=0.05, n_teeth=8),
    "gallimimus": lambda: theropod("gallimimus", H=1.3, torso_len=1.1, torso_r=0.33, chest_r=0.27, neck_len=1.3,
                                   neck_r=0.08, neck_angle=55, head_len=0.32, head_r=0.08, snout_r=0.025, tail_len=2.2,
                                   tail_r=0.17, leg_r=0.1, arm_len=0.6, arm_r=0.035, teeth=False, eye=1.3),
    "compy": lambda: theropod("compy", H=0.22, torso_len=0.25, torso_r=0.07, chest_r=0.06, neck_len=0.15,
                              neck_r=0.025, neck_angle=45, head_len=0.09, head_r=0.03, snout_r=0.012, tail_len=0.5,
                              tail_r=0.04, leg_r=0.02, arm_len=0.12, arm_r=0.01, n_teeth=5, eye=1.4),
    "parasaurolophus": lambda: theropod("parasaurolophus", H=1.8, torso_len=2.4, torso_r=0.7, chest_r=0.6,
                                        neck_len=1.0, neck_r=0.24, neck_angle=40, head_len=0.75, head_r=0.22,
                                        snout_r=0.12, head_pitch=-20, tail_len=3.6, tail_r=0.42, leg_r=0.22,
                                        arm_len=1.3, arm_r=0.08, teeth=False, hand_claws=3, family="ornithopod"),
    "pachycephalosaurus": lambda: theropod("pachycephalosaurus", H=1.0, torso_len=1.3, torso_r=0.38, chest_r=0.3,
                                           neck_len=0.5, neck_r=0.13, neck_angle=30, head_len=0.38, head_r=0.17,
                                           snout_r=0.08, head_pitch=-15, tail_len=2.0, tail_r=0.24, leg_r=0.11,
                                           arm_len=0.4, arm_r=0.04, teeth=False, family="ornithopod"),
    # ---------------- quadrupeds
    "triceratops": lambda: quadruped("triceratops", Hh=2.0, Hs=1.65, torso_len=3.4, torso_r=0.98, chest_r=0.88,
                                     neck_len=0.6, neck_r=0.55, neck_angle=-5, head_len=1.5, head_r=0.6, snout_r=0.25,
                                     head_pitch=-25, tail_len=2.8, tail_r=0.5, leg_r=0.32, fleg_r=0.3, sy_body=0.92),
    "stegosaurus": lambda: quadruped("stegosaurus", Hh=2.3, Hs=1.4, torso_len=3.6, torso_r=1.0, chest_r=0.8,
                                     neck_len=1.0, neck_r=0.3, neck_angle=-15, head_len=0.7, head_r=0.22, snout_r=0.1,
                                     head_pitch=-20, tail_len=3.8, tail_r=0.5, leg_r=0.3, fleg_r=0.22, sy_body=1.05),
    "ankylosaurus": lambda: quadruped("ankylosaurus", Hh=1.2, Hs=1.1, torso_len=3.0, torso_r=1.05, chest_r=0.95,
                                      neck_len=0.4, neck_r=0.42, neck_angle=-5, head_len=0.75, head_r=0.42, snout_r=0.3,
                                      head_pitch=-12, tail_len=3.0, tail_r=0.45, leg_r=0.26, fleg_r=0.24, sx_body=1.35,
                                      sy_body=0.7, width=0.75),
    "brontosaurus": lambda: quadruped("brontosaurus", Hh=4.2, Hs=4.0, torso_len=6.0, torso_r=2.0, chest_r=1.8,
                                      neck_len=9.0, neck_r=0.55, neck_angle=40, head_len=1.0, head_r=0.4, snout_r=0.25,
                                      head_pitch=-30, tail_len=12.0, tail_r=1.0, leg_r=0.62, fleg_r=0.58, n_tail=7),
    "sarcosuchus": lambda: quadruped("sarcosuchus", Hh=0.6, Hs=0.55, torso_len=4.2, torso_r=0.65, chest_r=0.6,
                                     neck_len=0.6, neck_r=0.42, neck_angle=0, head_len=1.8, head_r=0.38, snout_r=0.16,
                                     head_pitch=0, tail_len=5.0, tail_r=0.5, leg_r=0.14, fleg_r=0.12, teeth=True,
                                     n_teeth=12, sx_body=1.35, sy_body=0.62, sprawl=0.4, n_tail=6, feet="claw",
                                     family="crocodilian"),
    "direwolf": lambda: quadruped("direwolf", Hh=1.0, Hs=1.05, torso_len=1.25, torso_r=0.3, chest_r=0.34, neck_len=0.4,
                                  neck_r=0.18, neck_angle=30, head_len=0.48, head_r=0.15, snout_r=0.07, head_pitch=-10,
                                  tail_len=0.8, tail_r=0.1, leg_r=0.08, fleg_r=0.075, teeth=True, mammal=True,
                                  feet="paw", sy_body=1.1, sx_body=0.85, family="mammal"),
    "smilodon": lambda: quadruped("smilodon", Hh=1.0, Hs=1.15, torso_len=1.5, torso_r=0.38, chest_r=0.42, neck_len=0.4,
                                  neck_r=0.22, neck_angle=20, head_len=0.42, head_r=0.18, snout_r=0.12, head_pitch=-8,
                                  tail_len=0.35, tail_r=0.08, leg_r=0.1, fleg_r=0.11, teeth=True, mammal=True,
                                  feet="paw", sy_body=1.05, sx_body=0.9, family="mammal"),
    "mammoth": lambda: quadruped("mammoth", Hh=2.8, Hs=3.1, torso_len=3.0, torso_r=1.35, chest_r=1.45, neck_len=0.5,
                                 neck_r=0.8, neck_angle=-20, head_len=1.2, head_r=0.8, snout_r=0.25, head_pitch=-60,
                                 tail_len=0.8, tail_r=0.12, leg_r=0.4, fleg_r=0.42, mammal=False, sy_body=1.05,
                                 family="mammal"),
    # ---------------- flyers
    "pteranodon": lambda: flyer("pteranodon", H=0.7, torso_len=0.55, torso_r=0.16, neck_len=0.55, neck_r=0.06,
                                head_len=0.8, head_r=0.085, snout_r=0.012, wing_span=6.5, tail_len=0.15, tail_r=0.04,
                                family="pterosaur"),
    "argentavis": lambda: flyer("argentavis", H=0.75, torso_len=0.75, torso_r=0.3, neck_len=0.35, neck_r=0.1,
                                neck_angle=45, head_len=0.32, head_r=0.11, snout_r=0.05, wing_span=7.0, tail_len=0.35,
                                tail_r=0.1, leg_r=0.05, feathered=True, family="avian"),
    "wyvern": lambda: wyvern("wyvern"),
    # ---------------- marine
    "mosasaurus": lambda: marine("mosasaurus", length=14.0, torso_r=1.05, neck_len=0.6, neck_r=0.7, head_len=1.9,
                                 head_r=0.6, snout_r=0.22, tail_len=6.0, tail_r=0.7, flipper=1.6, rear_flipper=1.3,
                                 fluke=1.2),
    "plesiosaurus": lambda: marine("plesiosaurus", length=9.0, torso_r=0.9, neck_len=4.0, neck_r=0.25, head_len=0.6,
                                   head_r=0.22, snout_r=0.08, tail_len=1.6, tail_r=0.45, flipper=2.0,
                                   rear_flipper=1.8, fluke=0.0, sx=1.25, sy=0.75),
    "ichthyosaurus": lambda: marine("ichthyosaurus", length=4.5, torso_r=0.5, neck_len=0.1, neck_r=0.45,
                                    head_len=0.9, head_r=0.3, snout_r=0.05, tail_len=1.6, tail_r=0.32, flipper=0.6,
                                    rear_flipper=0.35, fluke=0.9, dorsal=0.45, sx=0.8, sy=1.0, family="fish"),
    "megalodon": lambda: marine("megalodon", length=12.0, torso_r=1.2, neck_len=0.1, neck_r=1.1, head_len=2.2,
                                head_r=0.95, snout_r=0.4, tail_len=4.0, tail_r=0.75, flipper=1.6, rear_flipper=0.6,
                                fluke=2.2, dorsal=1.4, sx=0.85, sy=1.0, family="fish"),
    # ---------------- others
    "titanoboa": lambda: serpent("titanoboa", length=13.0, r_body=0.38, head_len=0.8, head_r=0.3),
    "spider": lambda: arthropod("spider", size=1.6),
    # ---------------- monsters (shared rigs + demonic parts/materials)
    "hellhound": lambda: quadruped("hellhound", Hh=1.15, Hs=1.25, torso_len=1.5, torso_r=0.36, chest_r=0.45,
                                   neck_len=0.45, neck_r=0.22, neck_angle=20, head_len=0.5, head_r=0.19, snout_r=0.1,
                                   head_pitch=-10, tail_len=1.0, tail_r=0.1, leg_r=0.1, fleg_r=0.11, teeth=True,
                                   mammal=True, feet="claw", sy_body=1.1, sx_body=0.85, family="mammal"),
    "shadowstalker": lambda: theropod("shadowstalker", H=1.4, torso_len=1.4, torso_r=0.32, chest_r=0.3, neck_len=0.6,
                                      neck_r=0.12, neck_angle=30, head_len=0.45, head_r=0.15, snout_r=0.08,
                                      tail_len=2.8, tail_r=0.16, leg_r=0.12, arm_len=1.3, arm_r=0.06, sickle=True,
                                      deep_snout=1.1, n_teeth=9, eye=0.7),
    "bonewyrm": lambda: serpent("bonewyrm", length=16.0, r_body=0.5, head_len=1.1, head_r=0.45),
    "riftspider": lambda: arthropod("riftspider", size=2.6),
    # ---------------- humanoids
    "human_m": lambda: humanoid("human_m", height=1.8, build=1.0),
    "human_f": lambda: humanoid("human_f", height=1.7, build=0.9, female=True),
    "goblin": lambda: humanoid("goblin", height=1.25, build=0.95, head_scale=1.25, ears=1.0, nose=1.8, goblin=True),
    "demon": lambda: humanoid("demon", height=2.3, build=1.25, head_scale=0.9, nose=0.7, demon=True),
}

TRIS = {"trex": 11000, "spinosaurus": 11000, "brontosaurus": 12000, "mosasaurus": 9000, "megalodon": 8000,
        "wyvern": 11000, "triceratops": 10000, "stegosaurus": 9000, "ankylosaurus": 9000, "mammoth": 9000,
        "human_m": 7000, "human_f": 7000, "goblin": 6000, "demon": 8000, "compy": 3000, "spider": 6000,
        "riftspider": 6000}


def main():
    os.makedirs(OUT, exist_ok=True)
    ids = sys.argv[1:] or list(SPECIES.keys())
    for sid in ids:
        t = time.time()
        rig = SPECIES[sid]()
        tris = rig.build(OUT, target_tris=TRIS.get(sid, 7000))
        print(f"{sid}: {tris} tris, {len(rig.bones)} bones, {time.time() - t:.1f}s", flush=True)


if __name__ == "__main__":
    main()
