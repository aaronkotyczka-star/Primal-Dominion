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
    "trex": lambda: theropod("trex", H=3.2, body_len=2.7, body_d=1.05, body_w=0.72, neck_len=1.5, neck_r=0.5,
                             neck_rise=42, head_len=1.55, head_h=1.05, head_w=0.48, snout_h=0.5, snout_w=0.16,
                             head_pitch=-5, tail_len=6.0, tail_r=0.74, leg_r=0.52, arm_len=0.8, arm_r=0.1,
                             fingers=2, n_teeth=11, tooth_len=0.14, brow=1.0, horn_boss=0.6, scutes=0.6, toe_len=0.22),
    "atrociraptor": lambda: theropod("atrociraptor", H=0.8, body_len=0.8, body_d=0.26, body_w=0.18, neck_len=0.42,
                                     neck_r=0.085, neck_rise=50, head_len=0.33, head_h=0.17, head_w=0.08, snout_h=0.09,
                                     snout_w=0.035, tail_len=1.6, tail_r=0.13, leg_r=0.1, arm_len=0.55, arm_r=0.04,
                                     sickle=True, feathers=0.5, n_teeth=10, tooth_len=0.02, toe_len=0.2, eye=1.4),
    "raptor": lambda: theropod("raptor", H=0.85, body_len=0.75, body_d=0.24, body_w=0.17, neck_len=0.45, neck_r=0.075,
                               neck_rise=55, head_len=0.36, head_h=0.14, head_w=0.07, snout_h=0.05, snout_w=0.028,
                               head_pitch=-6, tail_len=1.7, tail_r=0.12, leg_r=0.1, arm_len=0.6, arm_r=0.04,
                               sickle=True, feathers=0.8, n_teeth=12, tooth_len=0.016, toe_len=0.2, eye=1.5),
    "spinosaurus": lambda: theropod("spinosaurus", H=2.6, body_len=3.8, body_d=0.95, body_w=0.75, neck_len=1.9,
                                    neck_r=0.38, neck_rise=35, head_len=1.9, head_h=0.5, head_w=0.28, snout_h=0.18,
                                    snout_w=0.1, snout_drop=0.05, tail_len=6.5, tail_r=0.6, leg_r=0.36, arm_len=1.4,
                                    arm_r=0.13, n_teeth=14, tooth_len=0.07, scutes=0.3),
    "carnotaurus": lambda: theropod("carnotaurus", H=2.1, body_len=2.5, body_d=0.75, body_w=0.6, neck_len=0.9,
                                    neck_r=0.34, neck_rise=35, head_len=0.85, head_h=0.55, head_w=0.3, snout_h=0.38,
                                    snout_w=0.16, tail_len=4.2, tail_r=0.55, leg_r=0.32, arm_len=0.35, arm_r=0.06,
                                    fingers=2, n_teeth=10, tooth_len=0.07, brow=0.6, scutes=1.2),
    "dilophosaurus": lambda: theropod("dilophosaurus", H=1.3, body_len=1.4, body_d=0.38, body_w=0.28, neck_len=0.9,
                                      neck_r=0.13, neck_rise=45, head_len=0.55, head_h=0.2, head_w=0.1, snout_h=0.08,
                                      snout_w=0.04, tail_len=2.6, tail_r=0.22, leg_r=0.16, arm_len=0.65, arm_r=0.055,
                                      n_teeth=11, tooth_len=0.03),
    "gallimimus": lambda: theropod("gallimimus", H=1.5, body_len=1.0, body_d=0.34, body_w=0.25, neck_len=1.3,
                                   neck_r=0.08, neck_rise=60, head_len=0.3, head_h=0.1, head_w=0.06, snout_h=0.035,
                                   snout_w=0.025, teeth=False, beak=True, eye=1.5, tail_len=2.3, tail_r=0.17,
                                   leg_r=0.15, arm_len=0.6, arm_r=0.04, feathers=0.3, toe_len=0.2),
    "compy": lambda: theropod("compy", H=0.24, body_len=0.25, body_d=0.075, body_w=0.055, neck_len=0.17,
                              neck_r=0.028, neck_rise=50, head_len=0.1, head_h=0.04, head_w=0.022, snout_h=0.015,
                              snout_w=0.01, tail_len=0.55, tail_r=0.045, leg_r=0.03, arm_len=0.12, arm_r=0.011,
                              n_teeth=8, tooth_len=0.005, eye=1.3),
    "parasaurolophus": lambda: theropod("parasaurolophus", H=2.0, body_len=2.6, body_d=0.85, body_w=0.7,
                                        neck_len=1.1, neck_r=0.3, neck_rise=35, head_len=0.85, head_h=0.32,
                                        head_w=0.2, snout_h=0.16, snout_w=0.16, teeth=False, duck=True, beak=True,
                                        head_pitch=-25, tail_len=4.0, tail_r=0.5, leg_r=0.32, arm_len=1.4, arm_r=0.1,
                                        toe_len=0.18, quadish=True, family="ornithopod"),
    "pachycephalosaurus": lambda: theropod("pachycephalosaurus", H=1.1, body_len=1.4, body_d=0.42, body_w=0.33,
                                           neck_len=0.55, neck_r=0.15, neck_rise=30, head_len=0.42, head_h=0.24,
                                           head_w=0.14, snout_h=0.1, snout_w=0.05, beak=True, teeth=False,
                                           head_pitch=-15, tail_len=2.2, tail_r=0.26, leg_r=0.16, arm_len=0.4,
                                           arm_r=0.045, dome=1.0, family="ornithopod"),
    # ---------------- quadrupeds
    "triceratops": lambda: quadruped("triceratops", Hh=2.1, Hs=1.75, body_len=3.2, body_d=1.0, body_w=0.95,
                                     neck_len=0.7, neck_r=0.6, neck_angle=-5, head_len=1.75, head_h=0.75,
                                     head_w=0.5, snout_h=0.36, snout_w=0.18, head_pitch=-30, beak=True,
                                     tail_len=3.0, tail_r=0.5, leg_r=0.36, fleg_r=0.34, sprawl=0.06, frill=1.0,
                                     brow=0.3, detail=1.2),
    "stegosaurus": lambda: quadruped("stegosaurus", Hh=2.3, Hs=1.45, body_len=3.4, body_d=1.0, body_w=0.75,
                                     neck_len=1.1, neck_r=0.3, neck_angle=-15, head_len=0.7, head_h=0.26,
                                     head_w=0.16, snout_h=0.12, snout_w=0.07, head_pitch=-20, beak=True,
                                     tail_len=3.8, tail_r=0.5, leg_r=0.36, fleg_r=0.25),
    "ankylosaurus": lambda: quadruped("ankylosaurus", Hh=1.3, Hs=1.15, body_len=3.0, body_d=0.8, body_w=1.1,
                                      neck_len=0.45, neck_r=0.45, neck_angle=-5, head_len=0.75, head_h=0.4,
                                      head_w=0.45, snout_h=0.25, snout_w=0.28, head_pitch=-12, beak=True,
                                      horn_boss=1.5, tail_len=3.2, tail_r=0.45, leg_r=0.3, fleg_r=0.28,
                                      sprawl=0.1, osteo=1.0),
    "brontosaurus": lambda: quadruped("brontosaurus", Hh=4.3, Hs=4.0, body_len=5.5, body_d=1.9, body_w=1.6,
                                      neck_len=8.0, neck_r=0.55, neck_angle=38, head_len=1.0, head_h=0.45,
                                      head_w=0.3, snout_h=0.25, snout_w=0.18, head_pitch=-30, teeth=False, tail_len=11.0, tail_r=1.0, n_tail=7, leg_r=0.75,
                                      fleg_r=0.7, tail_droop=0.02),
    "sarcosuchus": lambda: quadruped("sarcosuchus", Hh=1.0, Hs=0.9, body_len=3.6, body_d=0.45, body_w=0.62,
                                     neck_len=0.6, neck_r=0.4, neck_angle=0, head_len=1.8, head_h=0.35,
                                     head_w=0.32, snout_h=0.18, snout_w=0.12, snout_drop=0.02, head_pitch=0,
                                     teeth=True, n_teeth=16, tooth_len=0.05, tail_len=5.0, tail_r=0.5, tail_sx=0.5,
                                     n_tail=6, tail_droop=0.01, leg_r=0.2, fleg_r=0.17, feet="croc", sprawl=0.45,
                                     style="croc", scutes=1.0, family="crocodilian"),
    "direwolf": lambda: quadruped("direwolf", Hh=0.82, Hs=0.88, body_len=0.8, body_d=0.2, body_w=0.13, neck_len=0.28,
                                  neck_r=0.11, neck_angle=18, head_len=0.3, head_h=0.17, head_w=0.09, head_pitch=-14,
                                  style="canid", muzzle=0.5, muzzle_r=0.34, ears=1.0, teeth=True, fang=0.4,
                                  tail_len=0.7, tail_r=0.1, tail_droop=0.25, tail_sx=1.0, leg_r=0.07, fleg_r=0.065,
                                  feet="paw", family="mammal"),
    "smilodon": lambda: quadruped("smilodon", Hh=0.95, Hs=1.05, body_len=1.05, body_d=0.27, body_w=0.21, neck_len=0.3,
                                  neck_r=0.16, neck_angle=15, head_len=0.38, head_h=0.24, head_w=0.16, head_pitch=-8,
                                  style="felid", muzzle=0.3, muzzle_r=0.4, ears=0.6, ear_shape="round",
                                  teeth=True, tail_len=0.3, tail_r=0.07, tail_sx=1.0, tail_droop=0.2, leg_r=0.11,
                                  fleg_r=0.13, feet="paw", family="mammal"),
    "mammoth": lambda: quadruped("mammoth", Hh=2.6, Hs=3.0, body_len=2.6, body_d=1.05, body_w=0.95, neck_len=0.5,
                                 neck_r=0.8, neck_angle=-10, head_len=1.1, head_h=0.9, head_w=0.6, head_pitch=-35,
                                 style="proboscid", muzzle=0.3, muzzle_r=0.4, ears=0.7, ear_shape="flap",
                                 trunk=1.0, dome=1.0, hump=1.0, teeth=False, tail_len=0.7, tail_r=0.12,
                                 tail_sx=1.0, tail_droop=0.3, leg_r=0.5, fleg_r=0.52, family="mammal"),
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
                                    rear_flipper=0.35, fluke=0.9, dorsal=0.45, sx=0.8, sy=1.0, family="fish", eye=2.2),
    "megalodon": lambda: marine("megalodon", length=12.0, torso_r=1.2, neck_len=0.1, neck_r=1.1, head_len=2.2,
                                head_r=0.95, snout_r=0.4, tail_len=4.0, tail_r=0.75, flipper=1.6, rear_flipper=0.6,
                                fluke=2.2, dorsal=1.4, sx=0.85, sy=1.0, family="fish", style="shark"),
    # ---------------- others
    "titanoboa": lambda: serpent("titanoboa", length=13.0, r_body=0.38, head_len=0.8, head_r=0.3),
    "spider": lambda: arthropod("spider", size=1.6),
    # ---------------- monsters (shared rigs + demonic parts/materials)
    "hellhound": lambda: quadruped("hellhound", Hh=1.05, Hs=1.15, body_len=1.05, body_d=0.27, body_w=0.19,
                                   neck_len=0.33, neck_r=0.14, neck_angle=18, head_len=0.4, head_h=0.24, head_w=0.14,
                                   head_pitch=-10, style="canid", muzzle=0.55, muzzle_r=0.4, ears=1.1, teeth=True,
                                   fang=0.6, tail_len=1.0, tail_r=0.1, tail_sx=1.0, tail_droop=0.15, leg_r=0.11,
                                   fleg_r=0.12, feet="paw", detail=3.0, family="mammal"),
    "shadowstalker": lambda: theropod("shadowstalker", H=1.5, body_len=1.4, body_d=0.35, body_w=0.26, neck_len=0.7,
                                      neck_r=0.13, neck_rise=35, head_len=0.5, head_h=0.2, head_w=0.1, snout_h=0.1,
                                      snout_w=0.04, tail_len=3.0, tail_r=0.17, leg_r=0.16, arm_len=1.3, arm_r=0.07,
                                      sickle=True, n_teeth=12, tooth_len=0.03, eye=0.7, detail=1.6, brow=0.8),
    "bonewyrm": lambda: serpent("bonewyrm", length=16.0, r_body=0.5, head_len=1.1, head_r=0.45),
    "riftspider": lambda: arthropod("riftspider", size=2.6),
    # ---------------- humanoids
    "human_m": lambda: humanoid("human_m", height=1.8, build=1.0),
    "human_f": lambda: humanoid("human_f", height=1.7, build=0.9, female=True),
    "goblin": lambda: humanoid("goblin", height=1.25, build=0.95, head_scale=1.25, ears=1.0, nose=1.8, goblin=True),
    "demon": lambda: humanoid("demon", height=2.3, build=1.25, head_scale=0.9, nose=0.7, demon=True),
}

RES = {"compy": 220, "human_m": 280, "human_f": 280, "goblin": 280, "demon": 280, "spider": 260, "riftspider": 260,
       "titanoboa": 260, "bonewyrm": 260, "pteranodon": 260, "argentavis": 260, "wyvern": 260, "mosasaurus": 260,
       "plesiosaurus": 260, "ichthyosaurus": 260, "megalodon": 260}

TRIS = {"trex": 26000, "spinosaurus": 26000, "carnotaurus": 22000, "parasaurolophus": 22000, "raptor": 18000,
        "atrociraptor": 18000, "dilophosaurus": 18000, "gallimimus": 16000, "pachycephalosaurus": 16000,
        "shadowstalker": 18000, "compy": 6000, "brontosaurus": 26000, "triceratops": 24000, "stegosaurus": 22000,
        "ankylosaurus": 22000, "sarcosuchus": 20000, "mammoth": 18000, "direwolf": 14000, "smilodon": 14000,
        "hellhound": 14000, "mosasaurus": 9000, "megalodon": 8000, "wyvern": 11000,
        "human_m": 14000, "human_f": 14000, "goblin": 12000, "demon": 14000, "spider": 6000, "riftspider": 6000}


def main():
    os.makedirs(OUT, exist_ok=True)
    ids = sys.argv[1:] or list(SPECIES.keys())
    for sid in ids:
        t = time.time()
        rig = SPECIES[sid]()
        tris = rig.build(OUT, target_tris=TRIS.get(sid, 16000), res=RES.get(sid, 300))
        print(f"{sid}: {tris} tris, {len(rig.bones)} bones, {time.time() - t:.1f}s", flush=True)


if __name__ == "__main__":
    main()
