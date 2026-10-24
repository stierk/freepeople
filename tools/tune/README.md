# Freisassen hyperparameter tuner

Optuna TPE (SQLite, resumable) over headless Godot turbo runs. Reporting only: it never edits game source.

```
pip install -r tools/tune/requirements.txt
python tools/tune/tune.py --dry-run                       # search space + command lines
python tools/tune/tune.py --study v1 --trials 30 --jobs 3 # defaults: seeds 42,7,123, 300 days
python tools/tune/tune.py --study v1 --trials 30          # same command again = resume (Ctrl+C is safe)
python tools/tune/tune.py --study v1 --report-only        # regenerate reports
```

Options: `--seeds` (list, or N = first N of 42,7,123,999,2024), `--days`, `--jobs`, `--timeout` (per run, s),
`--storage`, `--godot` (needs the *console* build), `--params-dir`, `--val-seeds`, `--no-validate`.
Each run is a separate Godot process with its own `--turbo-tag`; a timed-out run is killed (process tree)
and a crashed or timed-out run scores 0 with a warning, not a study failure.

## Output (`tools/tune/out/<study>/`, git-ignored)
`best_params.json`, `top10.csv` (params + per-seed metrics), `importances.json`, `history.html` /
`parallel.html` (needs plotly), `validation.json`, `runs/` (per-run params + result JSONs). After the
search, baseline defaults and best are re-run on held-out seeds (`--val-seeds`, default 1001,1002,1003)
and compared in the console.

## Adding a parameter
Make the constant overridable via the `Tuning` autoload, then add it to a registry file
`tools/tune/params/<area>.json` (all files in the dir are merged):
```json
{"HUNT_SUCCESS_CHANCE": {"default": 0.5, "type": "float", "scale": "linear", "min": 0.1, "max": 0.9}}
```
Without min/max the range is [default/3, default*3]; default 0 requires explicit min/max (else skipped
with a warning). `ranges_override.json` overrides per name: `{"exclude": ["X"], "ranges": {"Y": {"min": 1, "max": 5}, "Z": {"fixed": 3}}}`.
A `fixed` value is passed to every run but not searched.

## Objective (`objective.json`)
Per seed, gated: if the village died, `score = days_survived / target_days` (< 1). If it survived:
`1 + w_pop*min(pop/pop_max,1) + w_cov*(covered_avg/cov_max) + w_trade*min(p2p_volume/(days*pop_ref),1)`.
Coverage rewards at least one holder per profession, not evenness. Candidate score = mean over seeds
- `std_penalty` * std. Trial 0 is the current defaults (baseline). The first seed is screened for
`screen_days` (100) and reported to a median pruner before the full runs.

## Caveats
- Noise: few seeds, chaotic sim; differences of a few hundredths are not real. Trust the held-out validation.
- The Crown is passive (`--turbo-passive`), so the baseline may collapse early and many trials score by days survived only.
- ~10 min per 300-day run: 30 trials x 3 seeds / 3 jobs is hours. Pruned trials cost only the screen.
- Parameters not yet read through `Tuning` have no effect; the tuner cannot tell.
- A Ctrl+C-interrupted trial is marked failed and re-sampled on resume.
