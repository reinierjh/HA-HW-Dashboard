$ErrorActionPreference = 'Stop'

# ============================================================
# HomeWizard batterijen - RTE (round-trip efficiency)
# Hybride aanpak (DB-vriendelijk, purge_keep_days blijft laag):
#   24h, 7d      -> rolling windows via statistics-platform + SOC-correctie
#                  (past ruim binnen 7 dagen ruwe history)
#   weekly etc.  -> kalenderperiodes via utility_meter (last_period).
#                  utility_meter herstelt last_period uit eigen restore-data,
#                  heeft dus GEEN lange ruwe history nodig.
# SOC-correctie (alleen 24h/7d): RTE = export / (import - dE) * 100
#   dE = (SoC_eind - SoC_begin)/100 * capaciteit
#   positief dE (netto geladen) => deel van import blijft in accu => noemer kleiner.
# Capaciteit per batterij: 2,473 kWh bruikbaar (4x = 9,89 kWh).
# ============================================================

$batteries = @(
  @{ Id = 1; Import = 'sensor.plug_in_battery_1_energy_import'; Export = 'sensor.plug_in_battery_1_energy_export'; Soc = 'sensor.plug_in_battery_1_state_of_charge' },
  @{ Id = 2; Import = 'sensor.plug_in_battery_2_energy_import'; Export = 'sensor.plug_in_battery_2_energy_export'; Soc = 'sensor.plug_in_battery_2_state_of_charge' },
  @{ Id = 3; Import = 'sensor.plug_in_battery_3_energy_import'; Export = 'sensor.plug_in_battery_3_energy_export'; Soc = 'sensor.plug_in_battery_3_state_of_charge' },
  @{ Id = 4; Import = 'sensor.plug_in_battery_4_energy_import'; Export = 'sensor.plug_in_battery_4_energy_export'; Soc = 'sensor.plug_in_battery_4_state_of_charge' }
)

$roll = @(
  @{ Key = '24h'; Age = 'hours: 24' },
  @{ Key = '7d';  Age = 'days: 7' }
)

$meters = @(
  @{ Key = 'weekly';    Cycle = 'weekly' },
  @{ Key = 'monthly';   Cycle = 'monthly' },
  @{ Key = 'quarterly'; Cycle = 'quarterly' },
  @{ Key = 'yearly';    Cycle = 'yearly' }
)

# Volgorde voor het dashboard: 24h, 7d, weekly, monthly, quarterly, yearly
$periods = @(
  @{ Key = '24h';  Type = 'roll'  },
  @{ Key = '7d';   Type = 'roll'  },
  @{ Key = 'weekly';    Type = 'meter' },
  @{ Key = 'monthly';   Type = 'meter' },
  @{ Key = 'quarterly'; Type = 'meter' },
  @{ Key = 'yearly';    Type = 'meter' }
)

$capPerBattery = 2.473   # kWh bruikbare opslag per batterij

function Write-Utf8NoBom {
  param([string]$Path, [string]$Content)
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

$outDir = 'C:\source\repos\HA-HW-Dashboard'
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

# ---------------------------------------------------------------- PACKAGE bestand
$pkg = New-Object System.Collections.Generic.List[string]
$pkg.Add('# HomeWizard batterijen - RTE (round-trip efficiency)')
$pkg.Add('# Hybride: 24h/7d rolling + SOC-correctie (statistics), weekly..yearly kalender (utility_meter)')
$pkg.Add('# Werkt zonder lange recorder-retentie (purge_keep_days kan laag blijven, bv. 7 dagen).')
$pkg.Add('# Plaats dit bestand in config/packages/ en voeg toe aan configuration.yaml:')
$pkg.Add('#   homeassistant:')
$pkg.Add('#     packages: !include_dir_named packages')
$pkg.Add('homewizard_rte_package:')
$pkg.Add('')
$pkg.Add('  sensor:')
foreach ($b in $batteries) {
  foreach ($w in $roll) {
    $pkg.Add('    - platform: statistics')
    $pkg.Add("      entity_id: $($b.Import)")
    $pkg.Add("      name: batt$($b.Id)_import_$($w.Key)")
    $pkg.Add('      state_characteristic: sum_differences')
    $pkg.Add('      max_age:')
    $pkg.Add("        $($w.Age)")
    $pkg.Add('    - platform: statistics')
    $pkg.Add("      entity_id: $($b.Export)")
    $pkg.Add("      name: batt$($b.Id)_export_$($w.Key)")
    $pkg.Add('      state_characteristic: sum_differences')
    $pkg.Add('      max_age:')
    $pkg.Add("        $($w.Age)")
    $pkg.Add('    - platform: statistics')
    $pkg.Add("      entity_id: $($b.Soc)")
    $pkg.Add("      name: batt$($b.Id)_soc_delta_$($w.Key)")
    $pkg.Add('      state_characteristic: change')
    $pkg.Add('      max_age:')
    $pkg.Add("        $($w.Age)")
  }
}
$pkg.Add('')
$pkg.Add('  utility_meter:')
foreach ($b in $batteries) {
  foreach ($m in $meters) {
    $pkg.Add("    batt$($b.Id)_import_$($m.Key):")
    $pkg.Add("      source: $($b.Import)")
    $pkg.Add("      cycle: $($m.Cycle)")
    $pkg.Add("    batt$($b.Id)_export_$($m.Key):")
    $pkg.Add("      source: $($b.Export)")
    $pkg.Add("      cycle: $($m.Cycle)")
  }
}
$pkg.Add('')
$pkg.Add('  template:')
$pkg.Add('    - sensor:')
foreach ($b in $batteries) {
  foreach ($w in $roll) {
    $impId = "sensor.batt$($b.Id)_import_$($w.Key)"
    $expId = "sensor.batt$($b.Id)_export_$($w.Key)"
    $socId = "sensor.batt$($b.Id)_soc_delta_$($w.Key)"
    $pkg.Add("        - name: batt$($b.Id)_rte_$($w.Key)")
    $pkg.Add("          unique_id: batt$($b.Id)_rte_$($w.Key)")
    $pkg.Add('          state_class: measurement')
    $pkg.Add("          unit_of_measurement: '%'")
    $pkg.Add('          icon: mdi:battery-charging-outline')
    $pkg.Add('          state: >-')
    $pkg.Add("            {% set i = states('$impId') | float(0) %}")
    $pkg.Add("            {% set e = states('$expId') | float(0) %}")
    $pkg.Add("            {% set s = states('$socId') | float(0) %}")
    $pkg.Add("            {% set de = s / 100 * $capPerBattery %}")
    $pkg.Add('            {% set den = i - de %}')
    $pkg.Add('            {% if den > 0 %}')
    $pkg.Add('              {% set rte = e / den * 100 %}')
    $pkg.Add('              {% if rte > 100 %}{{ 100.0 }}{% elif rte < 0 %}{{ 0.0 }}{% else %}{{ rte | round(1) }}{% endif %}')
    $pkg.Add('            {% else %}unknown{% endif %}')
  }
  foreach ($m in $meters) {
    $impId = "sensor.batt$($b.Id)_import_$($m.Key)"
    $expId = "sensor.batt$($b.Id)_export_$($m.Key)"
    $pkg.Add("        - name: batt$($b.Id)_rte_$($m.Key)")
    $pkg.Add("          unique_id: batt$($b.Id)_rte_$($m.Key)")
    $pkg.Add('          state_class: measurement')
    $pkg.Add("          unit_of_measurement: '%'")
    $pkg.Add('          icon: mdi:battery-charging-outline')
    $pkg.Add('          state: >-')
    $pkg.Add("            {% set i = state_attr('$impId', 'last_period') | float(0) %}")
    $pkg.Add("            {% set e = state_attr('$expId', 'last_period') | float(0) %}")
    $pkg.Add('            {% if i > 0 %}{{ (e / i * 100) | round(1) }}{% else %}unknown{% endif %}')
  }
}

foreach ($w in $roll) {
  $imps = ($batteries | ForEach-Object { "states('sensor.batt$($_.Id)_import_$($w.Key)') | float(0)" }) -join ' + '
  $exps = ($batteries | ForEach-Object { "states('sensor.batt$($_.Id)_export_$($w.Key)') | float(0)" }) -join ' + '
  $socs = ($batteries | ForEach-Object { "states('sensor.batt$($_.Id)_soc_delta_$($w.Key)') | float(0)" }) -join ' + '
  $pkg.Add("        - name: totaal_rte_$($w.Key)")
  $pkg.Add("          unique_id: totaal_rte_$($w.Key)")
  $pkg.Add('          state_class: measurement')
  $pkg.Add("          unit_of_measurement: '%'")
  $pkg.Add('          icon: mdi:chart-donut')
  $pkg.Add('          state: >-')
  $pkg.Add("            {% set i = $imps %}")
  $pkg.Add("            {% set e = $exps %}")
  $pkg.Add("            {% set s = $socs %}")
  $pkg.Add("            {% set de = s / 100 * $capPerBattery %}")
  $pkg.Add('            {% set den = i - de %}')
  $pkg.Add('            {% if den > 0 %}')
  $pkg.Add('              {% set rte = e / den * 100 %}')
  $pkg.Add('              {% if rte > 100 %}{{ 100.0 }}{% elif rte < 0 %}{{ 0.0 }}{% else %}{{ rte | round(1) }}{% endif %}')
  $pkg.Add('            {% else %}unknown{% endif %}')
}

foreach ($m in $meters) {
  $imps = ($batteries | ForEach-Object { "state_attr('sensor.batt$($_.Id)_import_$($m.Key)', 'last_period') | float(0)" }) -join ' + '
  $exps = ($batteries | ForEach-Object { "state_attr('sensor.batt$($_.Id)_export_$($m.Key)', 'last_period') | float(0)" }) -join ' + '
  $pkg.Add("        - name: totaal_rte_$($m.Key)")
  $pkg.Add("          unique_id: totaal_rte_$($m.Key)")
  $pkg.Add('          state_class: measurement')
  $pkg.Add("          unit_of_measurement: '%'")
  $pkg.Add('          icon: mdi:chart-donut')
  $pkg.Add('          state: >-')
  $pkg.Add("            {% set i = $imps %}")
  $pkg.Add("            {% set e = $exps %}")
  $pkg.Add('            {% if i > 0 %}{{ (e / i * 100) | round(1) }}{% else %}unknown{% endif %}')
}
$pkg.Add('')
$pkg.Add('# ============================================================')
$pkg.Add('# TOELICHTING')
$pkg.Add('# ============================================================')
$pkg.Add('# 24h/7d: rolling windows via statistics-platform, met SOC-correctie:')
$pkg.Add('#   RTE = export / (import - dE) * 100,  dE = (SoC_eind - SoC_begin)/100 * 2,473 kWh')
$pkg.Add('#   Dit corrigeert voor het feit dat de accu aan het begin/einde van het venster')
$pkg.Add('#   niet even gevuld hoeft te zijn (was de oorzaak van bizar hoge waarden).')
$pkg.Add('#')
$pkg.Add('# weekly..yearly: kalenderperiodes via utility_meter. last_period wordt door de')
$pkg.Add('#   meter zelf bijgehouden en na een restart hersteld uit de restore-data in de DB,')
$pkg.Add('#   dus zonder lange ruwe history -> werkt ook met purge_keep_days: 7.')
$pkg.Add('#   Over zulke lange periodes is SOC-correctie niet nodig (grensafwijking is')
$pkg.Add('#   verwaarloosbaar t.o.v. de totale doorloop).')
$pkg.Add('#')
$pkg.Add('# Let op: er zijn GEEN 30d/90d/365d rolling windows mogelijk met een korte')
$pkg.Add('# recorder-retentie (de statistics-sensor leest alleen ruwe history).')
$pkg.Add('#')
$pkg.Add('# Verwijder na de eerste installatie eventueel oude entity-registraties')
$pkg.Add('# (*_rte_30d/90d/365d en *_soc_delta_30d/90d/365d) als die niet meer bestaan:')
$pkg.Add('#   Instellingen > Apparaten en diensten > Entiteiten > Verwijderen')
Write-Utf8NoBom (Join-Path $outDir 'homewizard_rte_package.yaml') ($pkg -join "`n")

# ---------------------------------------------------------------- dashboard
$dash = New-Object System.Collections.Generic.List[string]
$dash.Add('views:')
$dash.Add('  - title: RTE overzicht')
$dash.Add('    path: rte_overzicht')
$dash.Add('    type: sections')
$dash.Add('    sections:')

foreach ($b in $batteries) {
$dash.Add('      - type: grid')
$dash.Add('        cards:')
$dash.Add('          - type: heading')
$dash.Add("            heading: Batterij $($b.Id)")
$dash.Add('            heading_style: title')
foreach ($p in $periods) {
  $dash.Add('          - type: sensor')
  $dash.Add("            entity: sensor.batt$($b.Id)_rte_$($p.Key)")
  $dash.Add("            name: RTE $($p.Key)")
  $dash.Add("            unit: '%'")
}
}

$dash.Add('      - type: grid')
$dash.Add('        cards:')
$dash.Add('          - type: heading')
$dash.Add('            heading: Totaal')
$dash.Add('            heading_style: title')
foreach ($p in $periods) {
  $dash.Add('          - type: sensor')
  $dash.Add("            entity: sensor.totaal_rte_$($p.Key)")
  $dash.Add("            name: RTE $($p.Key)")
  $dash.Add("            unit: '%'")
}

foreach ($p in $periods) {
  $dash.Add('      - type: grid')
  $dash.Add('        cards:')
  $dash.Add('          - type: custom:apexcharts-card')
  $dash.Add("            header: { show: true, title: 'RTE $($p.Key)' }")
switch ($p.Key) {
    '24h'      { $dash.Add('            graph_span: 45d')     }
    '7d'       { $dash.Add('            graph_span: 90d')     }
    'weekly'   { $dash.Add('            graph_span: 300d')    }
    'monthly'  { $dash.Add('            graph_span: 12month') }
    'quarterly'{ $dash.Add('            graph_span: 24month') }
    'yearly'   { $dash.Add('            graph_span: 5year')   }
  }
  $duration = '1d'
  $dash.Add('            yaxis:')
  $dash.Add('              - min: 0')
  $dash.Add('                max: 110')
  $dash.Add('            series:')
  foreach ($b in $batteries) {
    $dash.Add("              - entity: sensor.batt$($b.Id)_rte_$($p.Key)")
    $dash.Add("                name: Batterij $($b.Id)")
    $dash.Add('                group_by:')
    $dash.Add('                  func: last')
    $dash.Add("                  duration: $duration")
  }
  $dash.Add('              - entity: sensor.totaal_rte_' + $p.Key)
  $dash.Add('                name: Totaal')
  $dash.Add('                group_by:')
  $dash.Add('                  func: last')
  $dash.Add("                  duration: $duration")
}

$dash.Add('      - type: grid')
$dash.Add('        cards:')
$dash.Add('          - type: markdown')
$dash.Add('            content: >-')
$dash.Add('              **RTE** = round-trip efficiency: (ontladen kWh / laden kWh) x 100%.')
$dash.Add('              <br>24h & 7d: rolling windows met SOC-correctie (rekent accu-energie mee).')
$dash.Add('              <br>Weekly t/m yearly: kalenderperiodes via utility_meter (last period).')

Write-Utf8NoBom (Join-Path $outDir 'rte_dashboard.yaml') ($dash -join "`n")

# ---------------------------------------------------------------- opruimen oude bestanden
$stale = @(Join-Path $outDir 'rec_config.yaml')
foreach ($f in $stale) { if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force } }

Write-Host "Klaar. Output in: $outDir"
Get-ChildItem $outDir | Select-Object Name, Length