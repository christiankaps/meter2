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
