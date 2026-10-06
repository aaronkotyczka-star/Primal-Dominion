# Quellen & Lizenzen

## Eigene Inhalte

Sämtliche Spielinhalte wurden für dieses Projekt neu erzeugt – es wurden **keine** fremden Modelle, Texturen, Sounds, Musikstücke oder Texte übernommen und keine kostenpflichtigen Assets oder Dienste genutzt.

| Inhalt | Erzeugt durch |
|---|---|
| Kreaturen- und Humanoid-Modelle inkl. Skelett & Skinning (31 Rigs) | `tools/assetgen/sdfrig.py`, `families.py`, `heads.py`, `humans.py`, `gen_creatures.py` (Signed-Distance-Felder → Marching Cubes → Glättung/Reduktion) |
| Modulare Körperteile (Hörner, Kämme, Flügel, Sättel …) | `tools/assetgen/gen_parts.py` |
| Pflanzen, Felsen, Kristalle | `tools/assetgen/gen_flora.py` |
| Texturen (Haut, Fell-Strähnen, Stoff, Leder, Rinde, Blätter, 8 Geländematerialien, Holzplanken, Mauerwerk, Stroh) | `tools/assetgen/gen_textures.py` (prozedurales Rauschen/Voronoi/Malroutinen) |
| Gegenstandsbilder (158) | `tools/assetgen/gen_icons.py` (gemalte Vektorformen mit Pillow) |
| Höhlen | `tools/assetgen/gen_caves.py` (SDF-Kammern/Gänge → Marching Cubes) |
| Welt (Höhenkarte, Biome, Vegetation, Orte) | `tools/assetgen/gen_world.py` |
| Soundeffekte, Ambiente, Musik | `tools/assetgen/gen_audio.py` (prozedurale Synthese) |
| Spieldaten, Story, Dialoge | `tools/data_src/*.py` → `data/*.json` |
| Shader | `shaders/*.gdshader` |
| Icon | `assets/icon.svg` |

Lizenz des Projekts: Es liegt (noch) keine Lizenzdatei bei. Ohne ausdrückliche Lizenz behält der Repository-Inhaber alle Rechte; die Wahl einer Lizenz (z. B. MIT für Code, CC BY 4.0 für Inhalte) ist eine Entscheidung des Inhabers.

## Fremdsoftware

| Software | Verwendung | Lizenz |
|---|---|---|
| [Godot Engine 4.5.1](https://godotengine.org) | Engine, im exportierten Spiel enthalten | MIT – © Juan Linietsky, Ariel Manzur und Godot-Mitwirkende. Enthaltene Drittbibliotheken (u. a. Jolt Physics – MIT, FreeType, HarfBuzz, Vulkan-Loader) sind in Godots `COPYRIGHT.txt` aufgeführt. |
| Godot-Standardschrift (Open Sans) | Rückfallschrift der UI, falls keine Systemschrift (Georgia/DejaVu Serif …) gefunden wird | SIL Open Font License 1.1 |
| Python 3, NumPy, SciPy | Asset-Erzeugung (nur Entwicklungszeit, nicht im Spiel) | PSF / BSD-3-Clause |
| scikit-image | Marching Cubes | BSD-3-Clause |
| pyfqmr | Netzreduktion | MIT |
| Pillow | Bildausgabe | MIT-CMU (HPND) |
| soundfile / libsndfile | Audio-Ausgabe (OGG/WAV) | BSD-3-Clause / LGPL-2.1 (nur Werkzeug, nicht im Spiel enthalten) |
| GitHub Actions: `actions/checkout`, `actions/cache`, `actions/upload-artifact` | CI | MIT |

Systemschriften (Georgia, Palatino Linotype, DejaVu Serif …) werden nur genutzt, wenn sie auf dem Rechner installiert sind; sie werden nicht mitgeliefert.
