# Fortschritt & ehrliche Feature-Liste

Stand: 2026-10-06 · Godot 4.5.1-stable · Branch `claude/fervent-franklin-yjq54u`

Legende: ✅ umgesetzt (durch automatischen Test oder Screenshot geprüft) · 🟡 umgesetzt, aber vereinfacht/Platzhalter · ⚪ umgesetzt, nicht automatisch getestet · ❌ fehlt

## Prüfnachweise
- `tests/run_all.gd`: skriptgesteuerter Spieltest (Spieler wird über die Eingabe-Abstraktion gesteuert), 129 Prüfungen (inkl. Menü-Zentrierung, Höhlen, Gamepad-Belegung, Gegenstandsbilder), lokal und in GitHub Actions: `ALL TESTS PASSED`.
- GitHub Actions (`.github/workflows/build.yml`): Import, Tests, Windows-Export, Upload als Artefakt `PrimalDominion-Windows` – erfolgreich gelaufen.
- Screenshots: nur unter Linux mit Software-Vulkan (lavapipe, Xvfb) aufgenommen, Rundgang `--shots`.
- **Nicht** geprüft: Start der EXE auf echtem Windows, Leistung/FPS auf der Zielhardware (RTX 4060 Ti), Langzeit-Balancing, Bedienung durch echte Spieler.

## Phase 1 – Kernregion Grünkrone
| Bereich | Status | Anmerkung |
|---|---|---|
| Neues Spiel (Name, Körper, 4 Startausrüstungen, 4 Schwierigkeiten + Einzelregeln) | ✅ | |
| Bewegung, Sprint, Ducken/Schleichen, Ausweichen, Schwimmen, Ego/Third-Person | ✅ | Klettern nur über Fähigkeit „Kletterer“ (Rang 2), ungetestet |
| Offene Welt 2048 × 2048 m, 5 Inseln, Biome, LOD-Gelände, Vegetation, Gras | ✅ | ≈34.000 Pflanzen/Felsen (24 Typen inkl. Varianten, Stämme, Stümpfe, Felsnadeln, Findlinge); Kerninsel detailliert, andere Inseln dünner besetzt |
| Gelände-Texturen (8 Schichten, 2048² Albedo + Normal/Rauheit/Höhe), Höhenüberblendung, Anti-Kachel-Mischung, Triplanar an Hängen | ✅ | prozedural gemalt (Grashalme, Laub, Gesteinsschichten, Sandrippel, Risse …); Rinde 1024², Blattatlas 2048² |
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
| 31 Arten (Dinos, Säuger, Flug-, Meeres-, Monster) mit Rigs | ✅ | Anatomisch modelliert (u. a. Tyrannosaurus-Kastenschädel, Wolf/Säbelzahn-Köpfe, Zahnreihen, Lider, Krallen, Osteoderme), Köpfe mit feinerem Raster; Fell/Flaum per Shell-Rendering (Wolf, Säbelzahn, Mammut, Höllenhund, Raptoren, Argentavis); Flughäute/Schwungfedern der Flugtiere noch flach |
| Fraktionen (5) mit Ansehen, Handel, Reaktion auf Dämonengestalt | ✅ | |
| Siedlung: Bewohner, Aufgaben, Expeditionen | ✅ | einfache Simulation ohne sichtbare Arbeitsanimationen |
| Gebiete: Bündnis, Handel, Eroberung; Feldzug automatisch **oder** selbst mitkämpfen | ✅ | Mitkämpfen: Verteidiger erscheinen am Zielort; eigene Armee wird dort nicht gespawnt |
| Höhlen | ✅ | 2 begehbare Höhlen (Wurzelhöhle, Weißzahnhöhle): Kammern, Gänge, Tropfsteine, leuchtende Kristalle/Pilze, Beute, Höhlenkreaturen; Speichern in der Höhle legt den Spieler an den Eingang |

## Phase 3 – Kampagne & erweiterte Systeme
| Bereich | Status | Anmerkung |
|---|---|---|
| Akt II (Aschenkamm, Wyvern) | 🟡 | gekürzt: eine Quest mit 4 Stufen |
| Akt III (Narbe, Herold, 4 Enden) | 🟡 | gekürzt: eine Quest, Bosskampf, Endentscheidung als Textbildschirm |
| Verzweigte Story über Pfadwerte (Beschützer/Eroberer/Dämon) | ⚪ | |
| Geheimer Dämonenpfad (siehe `GEHEIM_Daemonenpfad.md`) | ✅ | inkl. Dämonen-EP/-Stufen, Formeditor |
| Weitere Inseln mit eigenem Questinhalt | ❌ | Inseln existieren, haben aber nur wenige Orte |
| Koop-/Mehrspieler | ❌ | nur vorbereitet (Eingabe-Abstraktion `PlayerInput`) |
| Gamepad | 🟡 | Xbox-Belegung fest hinterlegt (nicht umbelegbar), Menüs per Steuerkreuz/A/B; nur ohne echtes Gamepad getestet (Belegung per Test geprüft) |

## Bekannte Platzhalter / Vereinfachungen
- Menschen: anatomische Gesichter mit Lidern, Nase, Lippen, Ohren; Hände mit Fingern; Haar und Augenbrauen als Shell-Haar; Kleidung (Tunika, Hose, Gürtel, Stiefel) über glatte Masken mit erhabenen Säumen – keine echte Stoffsimulation, Finger ohne eigene Knochen.
- Kreaturen und Pflanzen sind vollständig prozedural erzeugt (keine Bildhauerei/Texturen von Hand); Detailgrad begrenzt durch Rastergröße (~3–4 cm bei großen Tieren).
- Alle Animationen sind prozedural (Gangzyklen, Aktionen) – keine handanimierten Keyframes.
- Gegenstandsbilder sind prozedural gemalte 2D-Symbole (keine Renderings der 3D-Modelle).
- Musik und Sounds sind einfache Synthese, keine Sprachausgabe.
- Zwischensequenzen fehlen; Story läuft über Dialoge, Hinweise und Textfenster.
- Feldzüge werden abstrakt (Kräfteverhältnis) aufgelöst.

## Bekannte technische Hinweise
- Der letzte Testlauf endet ohne Engine-Fehlermeldungen; frühere Meldung „Lambda capture … was freed“ wurde durch WeakRef behoben (kann bei anderen verzögerten Treffern noch vereinzelt auftreten, harmlos).
- `godot --check-only` meldet Autoload-Namen fälschlich als unbekannt; maßgeblich ist der Testlauf.

## Nächste Schritte
1. Windows-Build auf echter Hardware starten, FPS messen, Grafikvoreinstellungen abstimmen.
2. Weitere Inseln mit Quests füllen, Akt II/III ausbauen.
3. Flügel (Schwungfedern) und Rüstungsmodelle als eigene Meshes.
4. Gamepad auf echter Hardware testen, Balancing über längere Spielzeit.
