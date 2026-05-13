# meter2

## Codex App Actions

Configure these two run actions in the Codex app for this workspace:

1. `Run Meter2`
Command:
```bash
./scripts/run_meter2.sh
```

2. `Test Meter2`
Command:
```bash
./scripts/test_meter2.sh
```

Equivalent Make targets are available for shorter agent and terminal commands:

```bash
make build
make release-build
make analyze
make test
make run
make clean
```

## CSV Import Examples

Wide CSV files use one date column plus one value column per meter:

```csv
Date,Kitchen,Bath
2026-05-01,1200.5,340.2
2026-05-15,1242.8,352.9
```

Long CSV files use one row per reading:

```csv
Date,Meter,Value,Note
2026-05-01,Kitchen,1200.5,Initial reading
07.05.2026,Bath,340.2,German date-only input
```

## CSV Export Format

Exports use one row per reading and can be imported again:

```csv
Date,Meter,Value,Unit,Note
2026-05-01,Kitchen,1200.5,kWh,Initial reading
2026-05-01 14:30,Bath,340.2,m3,Manual check
```

## PDF Reports

The app can export or print plain PDF reports for the selected meter or all active meters. Reports are text/table based and include meter metadata, period statistics, forecast and cost summaries, insufficient-data states, and recent readings.
