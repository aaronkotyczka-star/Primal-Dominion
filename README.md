# Primal Dominion

Düsteres 3D-Open-World-Rollenspiel über Dinosaurier, Monster, Zähmung, Kreuzung, Forschung, Handwerk, Siedlungen und Gebietseroberung.
Engine: **Godot 4.5.1-stable** (GDScript, Forward+, Jolt Physics). Alle Inhalte (Modelle, Texturen, Welt, Audio, Texte) sind im Projekt selbst erzeugt.

> Stand: spielbarer Prototyp / Vertical Slice. Was fertig, vereinfacht oder noch offen ist, steht ehrlich in [docs/FORTSCHRITT.md](docs/FORTSCHRITT.md).

## Download (Windows)

Es gibt keine fertigen Builds im Repository. Der Windows-Build entsteht automatisch per GitHub Actions:

1. Im Repository auf **Actions** → Workflow **Build & Test** → den neuesten erfolgreichen Lauf (grüner Haken) öffnen.
2. Unten unter **Artifacts** `PrimalDominion-Windows` herunterladen (ZIP, ca. 70 MB; Download nur mit GitHub-Login möglich; Artefakte werden nach 30 Tagen gelöscht).
3. ZIP entpacken. `PrimalDominion.exe` und `PrimalDominion.pck` müssen im selben Ordner liegen.
4. `PrimalDominion.exe` starten.

Hinweise:
- Die EXE ist nicht signiert. Windows SmartScreen kann warnen → „Weitere Informationen“ → „Trotzdem ausführen“.
- Benötigt eine Vulkan-fähige Grafikkarte mit aktuellem Treiber (Zielsystem: Windows 11, RTX 4060 Ti). Leistung auf echter Windows-Hardware wurde **nicht** gemessen.
- Spielstände: `%APPDATA%\Godot\app_userdata\Primal Dominion\saves\`, Einstellungen in `settings.cfg` daneben.

## Aus dem Quellcode starten

1. [Godot 4.5.1-stable](https://godotengine.org/download/archive/4.5.1-stable/) (Standard-Version, nicht .NET) herunterladen.
2. Godot öffnen → **Importieren** → `project.godot` dieses Repos wählen → beim ersten Öffnen werden Texturen/Audio importiert (dauert einige Minuten).
3. **F5** startet das Spiel.

Selbst exportieren: Export-Vorlagen 4.5.1 installieren, dann `Projekt → Exportieren → Windows Desktop`.
Kommandozeile: `godot --headless --export-release "Windows Desktop" build/windows/PrimalDominion.exe`

## Steuerung (Standard, im Spiel unter Einstellungen → Steuerung änderbar)

| Aktion | Taste |
|---|---|
| Bewegen | W A S D |
| Springen / beim Fliegen steigen | Leertaste |
| Sprinten | Umschalt |
| Ducken / schleichen / beim Fliegen sinken | Strg |
| Ausweichen | C |
| Angriff / Blocken bzw. Zielen | Linke / Rechte Maustaste |
| Interagieren, sammeln, aufsteigen, füttern | E |
| Fähigkeiten 1–4 | R, F, G, Z |
| Schnellleiste 1–6 | 1–6 |
| Befehlsrad für Gefährten (halten) | Q |
| Alle Gefährten zu dir rufen (Pfiff) | Tab |
| Zielerfassung | T |
| Ego-/Third-Person-Ansicht | V |
| Gefährten direkt steuern | X |
| Baumodus / Bauteil drehen | B / R |
| Inventar, Questjournal, Fähigkeiten | I, J, K |
| Karte, Lexikon, Forschung | M, L, P |
| Kreaturen, Herstellen | H, U |
| Schnellspeichern / Schnellladen | F5 / F9 |
| Pause / Menü | Esc |

**Gamepad** (Xbox-Belegung, fest zusätzlich zu Maus/Tastatur): linker Stick bewegen, rechter Stick Kamera, A springen, B ausweichen, X interagieren, Y Befehlsrad, RT Angriff, LT Blocken/Zielen, LB Zielerfassung, RB Fähigkeit 1, L3 sprinten, R3 ducken, Steuerkreuz ↑ → ↓ Schnellleiste 1–3, ← Pfiff, Back Inventar, Start Pause. In Menüs: Steuerkreuz + A/B.

Einstellungen: Auflösung, Fenstermodus, VSync, FPS-Limit, Grafikqualität, Renderskalierung, Sichtweite, Sichtfeld (FOV), Mausempfindlichkeit, Y-Invertierung, getrennte Lautstärken, Tastenbelegung, Tutorial-Hinweise.

## Spielstart

Neues Spiel → Name, Körper, Startausrüstung (Jäger, Kämpfer, Gelehrter, Bestienhüter) und Schwierigkeit (Leicht, Normal, Schwer, Brutal, Regeln einzeln anpassbar).
Du strandest an der Küste von Grünkrone. Die Hauptquest führt nach Morgengrau zu Ilsa Varn. Tutorial-Hinweise erklären Grundlagen beim ersten Auftreten.

## Projektstruktur

Kurzüberblick in [docs/PROJEKT.md](docs/PROJEKT.md). Fortschritt und ehrliche Feature-Liste in [docs/FORTSCHRITT.md](docs/FORTSCHRITT.md). Quellen und Lizenzen in [CREDITS.md](CREDITS.md).

## Tests

- Automatische Tests: `godot --headless --path . -- --autostart --test=run_all` (Ausgabe endet mit `ALL TESTS PASSED`).
- Screenshot-Rundgang (benötigt GPU bzw. Software-Vulkan): `godot --path . -- --autostart --shots=<ordner>`.
- GitHub Actions führt bei jedem Push Import, Tests und den Windows-Export aus.

## Lizenz

Code und alle selbst erzeugten Inhalte: siehe [CREDITS.md](CREDITS.md). Keine Online-Konten, keine Mikrotransaktionen, keine Cloud-Abhängigkeit.
