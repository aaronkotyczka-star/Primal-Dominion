# Projektüberblick

## Technik
- Godot 4.5.1-stable, GDScript, Forward+ (Vulkan), Jolt Physics, 1920×1080 Standardauflösung.
- Alle Szenen werden im Code aufgebaut (`scenes/main.tscn` enthält nur `src/main.gd`).
- Inhalte werden offline per Python erzeugt (`tools/`) und als Dateien eingecheckt; Godot-Importcache (`.godot/`) und Builds sind per `.gitignore` ausgeschlossen.
- Git LFS ist nicht nötig: größte Dateien sind die Gelände-Texturarrays (≈ 9 MB und 7 MB) und die Höhenkarte (4 MB), alles deutlich unter GitHubs 50/100-MB-Grenzen.

## Verzeichnisse
| Pfad | Inhalt |
|---|---|
| `src/autoload/` | Globale Dienste: `EventBus`, `DB` (lädt `data/*.json`), `Settings`, `GameState` (gesamter Spielstand als Dictionary), `SaveSystem`, `Audio` |
| `src/core/` | Rig-Bibliothek (Mesh/Skelett/Skin zur Laufzeit), Effekte, Waffen-/Rüstungsmodelle, Screenshot-Rundgang |
| `src/actors/` | Spieler (Eingabe-Abstraktion, Kamera, Kampf), Kreatur + KI, NPC, Kampfwerte (`Combatant`), Projektile, prozeduraler Animator |
| `src/systems/` | Regeln ohne Szenenbezug: Inventar, Herstellen, Forschung, Fähigkeiten, Genetik, Zähmung, Ausrüstung, Fähigkeits-Ausführung, Dialoge/Handel, Quests, Fraktionen, Siedlung/Gebiete/Feldzüge |
| `src/world/` | Gelände (LOD-Chunks), Vegetation, Gras, Himmel/Wetter, Spawner, Bausystem, Siedlungen/Orte, Begegnungen/Story-Ereignisse |
| `src/ui/` | HUD, Fenster (Inventar, Herstellen, Kreaturen, Genlabor, Forschung, Fähigkeiten, Journal, Lexikon, Karte, Dialog, Lager, Basis, Einstellungen), UI-Kit |
| `shaders/` | Kreatur (triplanar, Regionen, Muster, Verderbnis), Gelände (Texturarray, 8 Schichten), Wasser, Himmel, Laub, Fels, Membran |
| `data/` | Generierte JSON-Daten (Arten, Gegenstände, Rezepte, Gebäude, Elemente, Reaktionen, Fähigkeiten, Forschung, Quests, Dialoge …) |
| `assets/` | Generierte Modelle (`creatures/`, `parts/`, `flora/`: `.bin` + `.json`), Texturen, Welt, Audio |
| `tools/` | Generatoren (`assetgen/`), Datenquellen (`data_src/` → `build_data.py`), Hilfsskripte |
| `tests/` | `run_all.gd` (skriptgesteuerter Spieltest), `visual/` |
| `.github/workflows/build.yml` | CI: Import, Tests, Windows-Export, Artefakt-Upload |

## Inhalte regenerieren
```
cd tools/assetgen
python3 gen_creatures.py && python3 gen_parts.py && python3 gen_flora.py
python3 gen_textures.py            # optional einzelne Teile: terrain build_strips
python3 gen_world.py && python3 gen_audio.py
cd .. && python3 build_data.py     # data/*.json aus data_src/*.py
```
Benötigt: Python 3, numpy, scipy, scikit-image, pyfqmr, pillow, soundfile.

## Wichtige Abläufe
- **Start:** `main.gd` → Menü → `GameState.new_game()` → `World` baut Gelände, Orte, Spawner, Spieler → HUD/UI.
- **Spielstand:** `GameState.state` (reines Dictionary) wird binär gespeichert (`store_var`), Metadaten als JSON. Plätze: Automatisch (alle 5 Min.), Schnell (F5/F9), 5 manuelle Plätze.
- **Kreaturen:** Datensatz (`GameState.state.creatures`) mit Genen, Werten, Bindung, Verletzungen; Szenen-Knoten werden nur für Kreaturen in der Nähe/im Gefolge erzeugt.
- **Eingabe:** Der Spieler liest nur `PlayerInput.intent` – Tests (und später Netzwerk-/KI-Quellen) können ihn steuern.
- **Kommandozeile:** `--autostart` (direkt neues Spiel), `--kit=<id>`, `--test=run_all`, `--shots=<ordner>`.
