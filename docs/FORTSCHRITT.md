# Fortschritt & ehrliche Feature-Liste

Stand: 2026-10-05 · Godot 4.5.1-stable · Branch `claude/fervent-franklin-yjq54u`

Legende: ✅ umgesetzt (durch automatischen Test oder Screenshot geprüft) · 🟡 umgesetzt, aber vereinfacht/Platzhalter · ⚪ umgesetzt, nicht automatisch getestet · ❌ fehlt

## Prüfnachweise
- `tests/run_all.gd`: skriptgesteuerter Spieltest (Spieler wird über die Eingabe-Abstraktion gesteuert), 113 Prüfungen, lokal und in GitHub Actions: `ALL TESTS PASSED`.
- GitHub Actions (`.github/workflows/build.yml`): Import, Tests, Windows-Export, Upload als Artefakt `PrimalDominion-Windows` – erfolgreich gelaufen.
- Screenshots: nur unter Linux mit Software-Vulkan (lavapipe, Xvfb) aufgenommen, Rundgang `--shots`.
- **Nicht** geprüft: Start der EXE auf echtem Windows, Leistung/FPS auf der Zielhardware (RTX 4060 Ti), Langzeit-Balancing, Bedienung durch echte Spieler.

## Phase 1 – Kernregion Grünkrone
| Bereich | Status | Anmerkung |
|---|---|---|
| Neues Spiel (Name, Körper, 4 Startausrüstungen, 4 Schwierigkeiten + Einzelregeln) | ✅ | |
| Bewegung, Sprint, Ducken/Schleichen, Ausweichen, Schwimmen, Ego/Third-Person | ✅ | Klettern nur über Fähigkeit „Kletterer“ (Rang 2), ungetestet |
| Offene Welt 2048 × 2048 m, 5 Inseln, Biome, LOD-Gelände, Vegetation, Gras | ✅ | Kerninsel detailliert, andere Inseln dünner besetzt |
| Tag/Nacht, Wetter (Regen, Sturm, Dämonensturm), Hunger, Temperatur | ⚪ | |
| Sammeln (Hand/Werkzeug), Herstellen (102 Rezepte, Stationen, Qualität) | ✅ | |
| Kampf: Nah-/Fernkampf, Blocken, Zielerfassung, Fähigkeiten, Beute | ✅ | |
| 11 Elemente, 17 Zustände, 17 Element-Reaktionen | ✅ | |
| Zähmen: Betäuben + Füttern, Vertrauen (Schleichen + Füttern), Eier/Prägung, Rettung, Bindungsrune/Pakt | ✅ | Rettung/Pakt nur ⚪ |
| Gefährten: Befehle (Rad), Folgen/Warten/Angriff, Reiten, Direktsteuerung, Pfiff | ✅ | |
| Seelenkristall-Kapazität, Lager, Verletzungen, dauerhafter Tod (je nach Regel) | ⚪ | |
| Forschung (44 Projekte), Fähigkeitsbäume (12 Bäume, 60 Fähigkeiten) | ✅ | |
| Basisbau (34 Bauteile, Einrasten, Vorlagen, Lagerkisten-Verbund) | ✅ | |
| Genetik & Hybride (Genlabor, Brutstätte, Mutation, Stabilität) | ✅ | |
| Kernquest Akt I (Q1–Q8) mit Nebenquests, Entscheidung am Riss | ✅ | vollständig im Test durchgespielt (Dialog-/Aktionsebene) |
| Speichern/Laden (Auto, Schnell, 5 Plätze) | ✅ | |
| Einstellungen (Auflösung, Grafik, Lautstärken, Empfindlichkeit, FOV, Tastenbelegung) | ⚪ | |
| Tutorial-Hinweise, Kreaturenlexikon, Karte, Journal | ⚪ | |

## Phase 2 – Erweiterung
| Bereich | Status | Anmerkung |
|---|---|---|
| 31 Arten (Dinos, Säuger, Flug-, Meeres-, Monster) mit Rigs | 🟡 | Modelle prozedural aus Grundformen; Flügel/Flossen grob |
| Fraktionen (5) mit Ansehen, Handel, Reaktion auf Dämonengestalt | ✅ | |
| Siedlung: Bewohner, Aufgaben, Expeditionen | ✅ | einfache Simulation ohne sichtbare Arbeitsanimationen |
| Gebiete: Bündnis, Handel, Eroberung; Feldzug automatisch **oder** selbst mitkämpfen | ✅ | Mitkämpfen: Verteidiger erscheinen am Zielort; eigene Armee wird dort nicht gespawnt |
| Höhlen | 🟡 | nur Eingänge mit Hinweis „noch nicht begehbar“ |

## Phase 3 – Kampagne & erweiterte Systeme
| Bereich | Status | Anmerkung |
|---|---|---|
| Akt II (Aschenkamm, Wyvern) | 🟡 | gekürzt: eine Quest mit 4 Stufen |
| Akt III (Narbe, Herold, 4 Enden) | 🟡 | gekürzt: eine Quest, Bosskampf, Endentscheidung als Textbildschirm |
| Verzweigte Story über Pfadwerte (Beschützer/Eroberer/Dämon) | ⚪ | |
| Geheimer Dämonenpfad (siehe `GEHEIM_Daemonenpfad.md`) | ✅ | inkl. Dämonen-EP/-Stufen, Formeditor |
| Weitere Inseln mit eigenem Questinhalt | ❌ | Inseln existieren, haben aber nur wenige Orte |
| Koop-/Mehrspieler | ❌ | nur vorbereitet (Eingabe-Abstraktion `PlayerInput`) |
| Gamepad | ❌ | nur Maus/Tastatur |

## Bekannte Platzhalter / Vereinfachungen
- Menschen/Goblins wirken wie Gliederpuppen: keine Gesichtsdetails, Kleidung nur als Farbregionen, keine Haare als eigene Geometrie.
- Alle Animationen sind prozedural (Gangzyklen, Aktionen) – keine handanimierten Keyframes.
- Gegenstandssymbole sind farbige Kürzel-Plaketten statt Bildern.
- Musik und Sounds sind einfache Synthese, keine Sprachausgabe.
- Zwischensequenzen fehlen; Story läuft über Dialoge, Hinweise und Textfenster.
- Feldzüge werden abstrakt (Kräfteverhältnis) aufgelöst.

## Bekannte technische Hinweise
- Beim Beenden meldet Godot noch verwaiste Ressourcen (`ObjectDB instances leaked`) und einmalig „Lambda capture … was freed“ – ohne Auswirkung auf den Spielablauf, aber noch zu bereinigen.
- `godot --check-only` meldet Autoload-Namen fälschlich als unbekannt; maßgeblich ist der Testlauf.

## Nächste Schritte
1. Windows-Build auf echter Hardware starten, FPS messen, Grafikvoreinstellungen abstimmen.
2. Höhlen begehbar machen, weitere Inseln mit Quests füllen, Akt II/III ausbauen.
3. Humanoide Modelle und Flügel verbessern, Gegenstandsbilder rendern.
4. Gamepad-Unterstützung, Balancing über längere Spielzeit.
