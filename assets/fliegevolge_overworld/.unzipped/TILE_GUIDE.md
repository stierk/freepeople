# Tile-Zuordnung & Worldbuilding-Guide — `fliegevolge_overworld`

Tile-Größe: **16×16 px**, lückenloses Raster (kein Margin/Spacing).
Koordinaten werden als **Tile `[col,row]`** *und* als **Pixel-Rect `[x,y,w,h]`** angegeben.
Umrechnung: `x = col*16`, `y = row*16`. Mehrkachel-Sprite `[c0,r0,c1,r1] → [c0*16, r0*16, (c1-c0+1)*16, (r1-r0+1)*16]`.

| Sheet (key) | Datei | Pixel | Raster (Spalten × Zeilen) |
|---|---|---|---|
| `base` | BaseSet.png | 640×640 | 40 × 40 |
| `farm` | Farmlands.png | 304×224 | 19 × 14 |
| `vik` | Vikings.png | 384×320 | 24 × 20 |

> Maschinenlesbar: `manifest.json` enthält jeden Eintrag mit `sheet`, `source_file`, `tile_box`, `pixel_rect`, `tiles_wide/high` und einem bereits **ausgeschnittenen PNG** (`sprites/<key>.png`). Ideal zum direkten Übernehmen.

---

## 1 · Angefragte Gebäude → Empfehlung

### Rathaus (3 Stufen)
Eine sauber eskalierende Progression. Stufe I bewusst klein, II/III sind echte Prunkbauten (3×2 Tiles).

| Stufe | key | Sheet | Tile-Box | Pixel-Rect | Größe |
|---|---|---|---|---|---|
| I – einfach | `rathaus_1_einfach` | base | `[27,31]` | `[432,496,16,16]` | 1×1 |
| II – Verbesserung | `rathaus_2_verbesserung` | farm | `[4,9,6,10]` | `[64,144,48,32]` | 3×2 |
| III – Endstufe | `rathaus_3_endstufe` | farm | `[7,9,9,10]` | `[112,144,48,32]` | 3×2 |

**Alternative Endstufen** (falls „mächtiger“ gewünscht):
- `rathaus_3_alt_burg` — komplette Steinburg, base `[32,30,37,39]` → `[512,480,96,160]` (6×10). Plus Rundtürme (s. Geldspeicher) als Eck-Bauteile.
- `rathaus_3_alt_kirche` — Kirche mit Turm/Kreuz, base `[30,36,30,39]` → `[480,576,16,64]` (1×4).

### Holzfällerhütte (+ Bäume)
| key | Sheet | Tile-Box | Pixel-Rect |
|---|---|---|---|
| `holzfaellerhuette` (Rundhütte m. Rauch) | vik | `[19,12]` | `[304,192,16,16]` |
| `holzfaellerhuette_alt` (offene Scheune) | farm | `[9,11]` | `[144,176,16,16]` |

**Bäume für die Karte:**
- `baum_eiche_gross` — base `[21,21,22,23]` → `[336,336,32,48]` (üppige Laubbäume; Region `[21,18]`–`[23,24]` enthält mehrere Varianten)
- `baum_kiefer` — base `[21,18,22,20]` → `[336,288,32,48]` (Nadel-/Dunkelwald)
- `baum_farm` — farm `[15,7,16,8]` → `[240,112,32,32]` (Reihe `[15,7]`–`[18,12]` = viele Einzelbäume)
- `baum_vik` — vik `[21,11,21,12]` → `[336,176,16,32]`
- `busch_hecke` — farm `[12,11,14,11]` (Heckenreihen zum Wald-Auffüllen)

### Sägewerk
| key | Sheet | Tile-Box | Pixel-Rect |
|---|---|---|---|
| `saegewerk` (Langhaus, offene Front) | vik | `[15,9,17,14]` | `[240,144,48,96]` |
| `holzstapel` (Brennholz) | farm | `[9,13]` | `[144,208,16,16]` |
| `holz_baumstaemme` (gestapelte Stämme) | base | `[23,27,23,29]` | `[368,432,16,48]` |

Tipp: Sägewerk = Langhaus + ein paar `holzstapel`/`holz_baumstaemme` als Deko drumherum.

### Farmhaus → Windmühle
> **Wichtig: In keinem der drei Sheets existiert eine Windmühle.** Es gibt keine Mühlen-, Flügel- oder Rotor-Grafik.

Beste Stellvertreter:
| key | Sheet | Tile-Box | Pixel-Rect |
|---|---|---|---|
| `farmhaus` (Cottage m. Kamin) | farm | `[1,12,2,13]` | `[16,192,32,32]` |
| `farmhaus_alt` | farm | `[0,12,1,13]` | `[0,192,32,32]` |

Dazu Felder direkt daneben (Farmlands-Acker-Autotiles, Region `[0,0]`–`[14,5]`: Saat-/Wachstums-/Pflugstadien). Wenn unbedingt ein „Turm-Mühle“-Look gewünscht ist, käme optisch am ehesten der Wikinger-Wachturm (`geldspeicher_alt_wachturm`) als Mühlenkörper in Frage — aber ohne Flügel. Ehrliche Empfehlung: Farmhaus + Acker statt erzwungener Mühle.

### Steinhauer / Mine (+ Steine & abbaubare Steine)
| key | Sheet | Tile-Box | Pixel-Rect | Hinweis |
|---|---|---|---|---|
| `steinhauer_schmelze` | vik | `[20,17,23,17]` | `[320,272,64,16]` | **4 Animations-Frames** (Feuerglut), Rauch oben `[20,16]`–`[23,16]`, Rauchfahnen unten `[20,18]`–`[23,19]` |
| `felsbrocken_grau` | base | `[6,21,9,23]` | `[96,336,64,48]` | große, abbaubare Felsen |
| `felsbrocken_braun` | base | `[6,24,9,26]` | `[96,384,64,48]` | abbaubare Felsen (Variante) |
| `steinklippe_grau` | base | `[10,21,11,23]` | `[160,336,32,48]` | senkrechte Klippenwand (braun: `[10,24]`–`[11,26]`) |
| `steine_streu_grau` | base | `[12,21,20,23]` | `[192,336,144,48]` | gestreute Steine in absteigender Größe |
| `steine_streu_braun` | base | `[12,24,20,26]` | `[192,384,144,48]` | dito, braun |

> Es gibt **kein dediziertes Minen-/Höhleneingangs-Tile.** Eine „Mine“ baust du als Komposition: kleine Hütte (`steinhauer_schmelze` oder eine Rundhütte) **am Fuß einer `steinklippe`**, umringt von `felsbrocken`. Stein-Boden zum Unterlegen: base `[6,3]`–`[9,5]` (graues Geröll-Autotile).

### Fischerhütte
| key | Sheet | Tile-Box | Pixel-Rect |
|---|---|---|---|
| `fischerhuette` (Rundhütte m. Fenstern) | vik | `[19,11]` | `[304,176,16,16]` |
| `steg_pfaehle` (Dalben im Wasser) | vik | `[20,14,23,15]` | `[320,224,64,32]` |
| `jetty_planken` (Holzsteg auf Wasser) | base | `[0,27,1,27]` | `[0,432,32,16]` |
| `boot_klein` | vik | `[0,18,1,19]` | `[0,288,32,32]` |
| `boot_segel` | vik | `[8,18,9,19]` | `[128,288,32,32]` |

Komposition: Hütte an der Küste + Steg ins Wasser + 1 Boot.

### Lagerplatz Baumaterialien
| key | Sheet | Tile-Box | Pixel-Rect |
|---|---|---|---|
| `lager_kisten` (Kisten/Fässer/Holz) | base | `[23,25,23,29]` | `[368,400,16,80]` |
| `lager_kistenstapel` (Holzwand-/Kistenstapel) | vik | `[20,0,23,5]` | `[320,0,64,96]` |
| `faesser_gestapelt` | farm | `[16,4,18,6]` | `[256,64,48,48]` |
| `saecke` (Getreide/Sandsäcke) | farm | `[15,4,15,5]` | `[240,64,16,32]` |

### Lagerplatz Lebensmittel → Marktplatz mit Ständen
| key | Sheet | Tile-Box | Pixel-Rect |
|---|---|---|---|
| `marktstand_offen` | farm | `[10,9,11,10]` | `[160,144,32,32]` |
| `marktstand_offen2` | farm | `[10,12,11,12]` | `[160,192,32,16]` |
| `marktstand_streifen` (Orange-Markise) | farm | `[7,11]` | `[112,176,16,16]` |
| `marktstand_klein` | farm | `[3,11]` | `[48,176,16,16]` |
| `zelt_streifen` (Blau-Weiß-Zelt) | vik | `[19,15,19,16]` | `[304,240,16,32]` |
| `gemuese_tomaten` | farm | `[8,12]` | `[128,192,16,16]` |
| `gemuese_moehren` | farm | `[9,12]` | `[144,192,16,16]` |

Markt = mehrere Stände auf gepflastertem/erdigem Boden + Gemüse-Deko als „Auslage“ davor. Ein Vogelscheuchen-Tile (farm `[8,11]`) und Brunnen (s.u.) passen als Center-Piece.

### Geldspeicher
> **Kein Münz-/Gold-Tile vorhanden.** Treasury am besten über ein massives, solides Steinbauwerk darstellen.

| key | Sheet | Tile-Box | Pixel-Rect |
|---|---|---|---|
| `geldspeicher_turm` (Rundturm) | base | `[38,33]` (Spalte `[38]`–`[39]`, Reihen `[31]`–`[39]` = mehrere Türme) | `[608,528,16,64]` |
| `geldspeicher_alt_wachturm` | vik | `[18,8,18,15]` | `[288,128,16,128]` |

Alternativ die komplette Steinburg (`rathaus_3_alt_burg`) als zentrale Schatzkammer.

---

## 2 · Worldbuilding — verfügbare Elemente

### 2.1 Böden / Terrain (BaseSet — „Blob“-Autotiles)
Jeder Bodentyp liegt als **abgerundeter Blob-Block** vor (Füllung + alle Kanten + Innen-/Außenecken in einem Cluster). Daraus liest ein Autotiler die 4-/8-bit-Nachbarschaftsmaske ab.

| Bodentyp | Anker (Tile) | Eignung |
|---|---|---|
| Gras (mittel-grün) | `[6,0]`–`[9,2]` / `[10,0]`–`[14,2]` | Standard-Grasland, Wiesen |
| Dunkles Gras / Waldboden | dunkelgrüne Blobs in `[6,0]`-Reihe | Wald-Untergrund |
| Trockengras (gelb) | `[6,6]`–`[9,11]` | Steppe, Sommer, Savanne |
| Lehm / Acker (orange-braun) | `[6,12]`–`[9,14]` | Felder, Wege, Ödland |
| Stein-/Geröllboden (grau) | `[6,3]`–`[9,5]` / `[10,3]`–`[14,5]` | Steinbruch, Mine, Plätze |
| Schnee / weiße Flecken | `[2,6]`–`[3,13]` | Winter-/Hochgebirgszone |
| Gras-Plateau m. Felskante | `[6,15]`–`[9,17]` | Höhenstufen / Klippen |
| Gras-Detail (Blumen/Pilze) | `[4,0]`–`[4,3]` | Streudeko über Gras |
| Sand (Vikings) | vik `[0,0]`–`[9,2]` | Strand, Wüste |
| Lehm-auf-Sand | vik `[0,3]`–`[13,5]` | Wüstenpfade |

### 2.2 Wasser
- **BaseSet:** volle Blob-Autotiles für drei Ränder — Gras-Ufer `[21,0]`–`[35,5]`, Sand/Hell-Ufer `[21,6]`–`[35,11]`, Lehm-Ufer `[21,12]`–`[35,17]`. Plus Fluss-/Strömungs-Tiles `[0,18]`–`[3,20]`.
- **Vikings:** zwei Tiefen — Flachwasser `[0,6]`–`[13,11]`, Tiefwasser `[0,12]`–`[13,17]` (satteres Blau, für Küstenabstufung).
- **Deko:** Seerosen/Wasserpflanzen base `[0,22]`–`[3,27]`, Schilf `[0,21]`–`[3,21]`, Trittsteine `[0,28]`–`[3,29]`, Brunnen `[4,23,4,24]`.

### 2.3 Wald & Steinbruch (Biome-Bausteine)
- **Wald:** große Laubbäume base `[21,18]`–`[23,24]`, Nadelwald-Cluster `[21,18]`–`[23,20]`, plus Wald-Kronen-Massen (gerundete Hecken-Blobs) `[5,18]`–`[20,20]` zum Füllen großer Flächen. Einzelbäume aus Farmlands/Vikings für Streuung.
- **Steinbruch:** Stein-Boden-Autotile + `felsbrocken` (abbaubar) + `steinklippe` (Wände) + gestreute `steine`. Ergibt ohne dediziertes Tile einen glaubhaften Bruch.

### 2.4 Klimazonen / Biome — Mischrezepte
| Zone | Boden | Wasser | Vegetation | Bauten |
|---|---|---|---|---|
| Gemäßigt (Default) | Gras grün | BaseSet Gras-Ufer | Laubbäume, Hecken | Farmlands-Dörfer |
| Wald | dunkles Gras | – | Kiefern + Eichen dicht | Holzfäller, Sägewerk |
| Steppe/Sommer | Trockengras | – | wenig Bäume | Felder, Marktstände |
| Küste/Wikinger | Sand | Vikings Flach+Tief | Vikings-Bäume | Fischerhütte, Boote, Stege |
| Gebirge/Bruch | Stein-/Geröllboden | – | kahl | Mine, Felsen, Burg |
| Winter (optional) | Schnee-Flecken | Gras-Ufer (als Eis umfärben) | Kiefern | Steinbauten |

---

## 3 · Animation

**Was bereits als Frames vorliegt:**
- **Steinhauer-Schmelze / Feueröfen (Vikings):** 4 horizontale Frames `[20,17]`–`[23,17]` (flackernde Glut). Aufsteigender Rauch als separate Frames in der Kachel **darüber** `[20,16]`–`[23,16]` und **darunter** `[20,18]`–`[23,19]`. → Frame-Index alle ~150–200 ms zyklisch durchschalten. Damit ist jede „produzierende“ Hütte animierbar.
- **Schornsteinrauch (klein, grau):** als Puff auf einzelnen Häuserdächern (z. B. base `[29,31]`-Variante, vik-Rundhütte `[19,12]`). Eignet sich als Overlay-Sprite, das man über jedes Gebäude legen und vertikal scrollen/ein-/ausblenden kann.

**Was selbst animiert werden muss (Einzelframe-Tiles):**
- **Wasser:** Die Wasser-Tiles sind statisch (eine Phase). Drei gängige Wege:
  1. **UV-/Offset-Scroll:** Wasserfläche minimal in X/Y verschieben (1–2 px Loop) → günstigste „Wellen“-Illusion.
  2. **Palette-/Frame-Swap:** zwischen BaseSet-Wasser und Vikings-Wasser (anderer Blauton) langsam überblenden, oder eine zweite, leicht versetzte Kopie als Frame B erzeugen.
  3. **Schaum-Linien:** die hellen Foam-Pixel der Uferkanten per Sinus leicht pulsieren lassen.
- **Bäume/Hecken:** sanftes „Sway“ über einen kleinen Shear/Skew der oberen Pixelzeilen (kein zusätzliches Tile nötig).
- **Gebäude allgemein:** „lebendig“ wirken sie über das Schornstein-Overlay (s.o.) und Lichtflackern (Fenster/Türöffnung leicht aufhellen).

---

## 4 · Wege & wie sie verbunden werden

Es gibt **keine eigenständige „Straßen“-Linie**, sondern Wege entstehen aus den **Boden-Blob-Autotiles** (Lehm `[6,12]`–`[9,14]`, Geröll `[6,3]`–`[9,5]`, oder ein Trockengras-Pfad), die in das umgebende Gras „eingeschnitten“ werden.

**Verbindungslogik (Blob-/47-Tile-Autotiling):**
- Jeder Block enthält: Vollfüllung (innen), 4 gerade Kanten, 4 Außenecken, 4 Innenecken — teils auch Diagonal-/Engstellen-Varianten.
- Der Tilemap-Algorithmus bestimmt pro Zelle eine **8-Nachbarschafts-Bitmaske** (N, NE, E, SE, S, SW, W, NW) und wählt das passende Rand-/Eck-Tile.
- **Praxis in einer City-Builder-Engine (z. B. Godot/Phaser/Unity):**
  - Godot `TileSet` → **Terrain/Terrain-Set** anlegen, die Blob-Kacheln als Peering-Bits markieren, dann mit „Connect“-Modus malen — Wege/Flüsse verbinden sich automatisch.
  - Generisch: 16-/47-Index-Lookup-Tabelle (Maske → Tile-Koordinate). Für 4-bit (nur N/E/S/W) reichen 16 Tiles; die Blobs hier liefern genug Varianten auch für 47-bit.
- **Kreuzungen/Abzweige:** ergeben sich automatisch aus der Maske; keine Spezialkacheln nötig.
- **Brücken über Wasser:** `jetty_planken` (base `[0,27,1,27]`) bzw. Wikinger-Stege als manuelle Overlay-Tiles dort setzen, wo ein Weg Wasser quert.
- **Überlagerung:** Wege immer als eigene Layer-/Terrain-Ebene über dem Basis-Gras zeichnen, damit der Autotiler die Gras-Kante sauber rendert.

**Bodenart ↔ Untergrund-Empfehlung für Wege:**
| Weg-Typ | Tile-Quelle | passt zu |
|---|---|---|
| Feldweg / Dorf | Lehm-Autotile `[6,12]`–`[9,14]` | Gras, Acker |
| Pflaster / Platz | Geröll-/Steinboden `[6,3]`–`[9,5]` | Stadt, Markt, Burg |
| Trampelpfad | Trockengras-Blob `[6,6]`–`[9,11]` | Steppe, Wald |
| Wüstenpfad | Lehm-auf-Sand (vik) `[0,3]`–`[13,5]` | Küste, Wüste |

---

## 5 · Lücken (ehrlich)
- **Windmühle:** nicht vorhanden → Farmhaus + Acker empfohlen.
- **Münzen/Gold:** nicht vorhanden → Geldspeicher als Steinturm/Burg.
- **Minen-/Höhleneingang:** nicht vorhanden → als Komposition (Hütte + Klippe + Felsen) bauen.
- **Wasser-Animationsframes:** nur Einzelphase → per Scroll/Swap selbst animieren.

---

## 6 · Für den Claude-Code-Agenten
- `manifest.json` ist die Single Source of Truth: pro Asset `sheet`, `source_file`, `tile_box [c0,r0,c1,r1]`, `pixel_rect [x,y,w,h]`, `tiles_wide/high`, `asset` (vorgeschnittenes PNG in `sprites/`).
- Zum Rendern aus dem Original-Sheet: `ctx.drawImage(sheet, x, y, w, h, destX, destY, w*scale, h*scale)` mit `imageSmoothingEnabled=false`.
- Mehrkachel-Bauten als ein Sprite mit Footprint `tiles_wide × tiles_high` platzieren (Kollisions-/Belegungsraster entsprechend).
- Autotile-Sets (Boden/Wasser) NICHT als Einzelsprites behandeln, sondern als Terrain-Sets registrieren (Anker-Koordinaten in Abschnitt 2/4).
