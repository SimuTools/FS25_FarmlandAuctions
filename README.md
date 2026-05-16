# Farmland Auctions

**Farmland Auctions** fügt dem Landwirtschafts-Simulator 25 regelmäßige Feldversteigerungen hinzu.

Statt Flächen einfach direkt zu kaufen, können Felder über ein Auktionssystem ersteigert werden. Spieler können direkt auf dem versteigerten Feld mitbieten und sich so Land auf eine spannendere und dynamischere Weise sichern.

## Features

- Regelmäßige automatische Feldversteigerungen
- Direktes Bieten auf dem Feld über die **B-Taste**
- Jedes neue Gebot erhöht den aktuellen Auktionspreis
- Alternative Möglichkeit zum klassischen Landkauf
- Optionale NPC-Gebote
- Optionaler „Auktion Only“-Modus
- Sperren des normalen Standardkaufs, wenn Flächen nur per Auktion kaufbar sein sollen
- Multiplayer-Unterstützung
- Höfe können im Multiplayer gegeneinander bieten
- Konsolenbefehle zur Verwaltung von Auktionen

## Funktionsweise

Sobald eine Auktion aktiv ist, kann auf der betroffenen Fläche direkt geboten werden.

Dazu muss sich der Spieler auf der versteigerten Fläche befinden und die **B-Taste** drücken.  
Das aktuelle Gebot wird dadurch erhöht.

Im Multiplayer können verschiedene Höfe gegeneinander bieten. Der Hof mit dem höchsten Gebot gewinnt nach Ablauf der Auktion die Fläche.

## Mod-Einstellungen

Über die Mod-Einstellungen können verschiedene Optionen angepasst werden:

- NPC-Gebote aktivieren oder deaktivieren
- Festlegen, ob Flächen nur noch per Auktion gekauft werden können
- Normalen Standardkauf sperren, wenn der Auktion-Only-Modus aktiv ist

## Konsolenbefehle

Folgende Konsolenbefehle sind verfügbar:

```txt
faStartNow
```

Startet die nächste Auktion sofort.

```txt
faStartAuction <farmlandId>
```

Startet manuell eine Auktion für eine bestimmte Fläche.

```txt
faEndNow
```

Beendet die aktuell laufende Auktion sofort.

```txt
faCancelAuction
```

Bricht die aktuelle oder geplante Auktion ab.

```txt
faSetAuctionTime <min> <max>
```

Legt die minimale und maximale Auktionsdauer fest.

```txt
faSetStartInterval <min> <max>
```

Legt fest, nach welcher minimalen und maximalen Zeit die nächste Auktion startet.

## Multiplayer

Die Mod ist für den Multiplayer geeignet.

Im Multiplayer können mehrere Höfe auf dieselbe Fläche bieten. Dadurch entsteht ein direkter Wettbewerb um Land und der Feldkauf wird deutlich interessanter als beim normalen Sofortkauf.

## Auktion Only

Wenn der Auktion-Only-Modus aktiviert ist, können Flächen nicht mehr normal gekauft werden.

Der Standardkauf wird gesperrt und Land kann ausschließlich über Auktionen erworben werden.

## Changelog

### Version 1.0.0.1

- Multiplayer-Probleme behoben
- Zeitproblem behoben

### Version 1.0.0.0

- Erste Version der Mod
- Regelmäßige Feldversteigerungen hinzugefügt
- Bieten direkt auf dem Feld über die B-Taste
- NPC-Gebote hinzugefügt
- Auktion-Only-Modus hinzugefügt
- Konsolenbefehle zur Auktionsverwaltung hinzugefügt
- Multiplayer-Unterstützung hinzugefügt

## Hinweise

Diese Mod verändert das Kaufsystem für Farmlands und ist besonders für Server geeignet, die ein realistischeres und langfristigeres Wirtschaftssystem nutzen möchten.

Für ein faires Spielerlebnis im Multiplayer sollten die Einstellungen vor Serverstart passend festgelegt werden.
