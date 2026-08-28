# AGENTS.md

## Unieke IDs verplicht (sensor.yaml/HA-packages)

- **Altijd** een `unique_id` toevoegen aan elke sensor die gegenereerd wordt:
  statistics-platform sensoren, utility_meter-entries én template-sensoren.
  Anders kan HA de entity niet beheren vanuit de UI ("does not have a unique ID").
- Gebruik vaste, voorspelbare names: `batt<Id>_<type>_<periode>` en `totaal_<type>_<periode>`.

## Aanpak RTE (vastgelegd met gebruiker)

- Hybride: 24h/7d rolling via statistics-platform met SOC-correctie
  (`RTE = export/(import - dE) * 100`, `dE = SoC_delta/100 * 2,473 kWh`).
  Weekly..yearly via utility_meter `last_period`.
- Zolang recorder-retentie kort is (purge_keep_days), geen 30d/90d/365d rolling
  windows aanbieden (statistics-sensor leest alleen ruwe history).
- Utility_meter RTE: fallback op de lopende periode (`states(...)`) zolang
  `last_period` nog leeg is (eerste periode nog niet omwentelde).

## Output-regels

- Gegenereerde YAML altijd ASCII-only, UTF-8 zonder BOM
  (PowerShell 5.1 leest BOM-loze .ps1 als ANSI -> mojibake bij non-ASCII).
- Bij wijzigingen: `generate.ps1` draaien, daarna commit + push naar `origin/master`
  (separate commit per afgeronde (deel)taak, geen secrets).