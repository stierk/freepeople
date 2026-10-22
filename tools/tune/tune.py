#!/usr/bin/env python
"""Hyperparameter tuner for Freisassen: Optuna TPE over headless Godot turbo runs. See README.md."""
import argparse, csv, json, math, os, statistics, subprocess, sys, threading
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parent.parent
DEFAULT_GODOT = Path(os.environ.get("USERPROFILE", "~")).expanduser() / ".godot_tools" / "Godot_v4.6.3-stable_win64_console.exe"

# ---------------------------------------------------------------- scoring (pure)

def seed_score(res, cfg, target_days):
    """Gated score of one run. res=None (crash/timeout) counts as a failed run scoring 0."""
    if not res:
        return 0.0
    if not res.get("survived"):
        return min(res.get("days", 0) / target_days, 0.999)
    return (1.0
            + cfg["w_pop"] * min(res.get("population", 0) / cfg["pop_max"], 1.0)
            + cfg["w_cov"] * (res.get("covered_avg", 0.0) / cfg["cov_max"])
            + cfg["w_trade"] * min(res.get("p2p_volume", 0.0) / (target_days * cfg["pop_ref"]), 1.0))

def candidate_score(scores, cfg):
    sd = statistics.pstdev(scores) if len(scores) > 1 else 0.0
    return statistics.fmean(scores) - cfg["std_penalty"] * sd

# ---------------------------------------------------------------- registry

def load_registry(params_dir, override_path):
    reg = {}
    for f in sorted(Path(params_dir).glob("*.json")):
        reg.update(json.loads(f.read_text(encoding="utf-8")))
    ov = {}
    if Path(override_path).exists():
        ov = json.loads(Path(override_path).read_text(encoding="utf-8"))
    excl = set(ov.get("exclude", []))
    space, fixed = {}, {}
    for name, p in reg.items():
        if name in excl:
            continue
        o = ov.get("ranges", {}).get(name, {})
        d = p["default"]
        if "fixed" in o:
            fixed[name] = o["fixed"]
            continue
        lo, hi = o.get("min", p.get("min")), o.get("max", p.get("max"))
        if lo is None or hi is None:
            if d == 0:
                print(f"WARNING: {name}: default 0 and no min/max, skipped", file=sys.stderr)
                continue
            a, b = sorted((d / 3, d * 3))
            lo, hi = (a if lo is None else lo), (b if hi is None else hi)
        scale = p.get("scale", "linear")
        if scale == "log" and lo <= 0:
            print(f"WARNING: {name}: log scale needs min>0, using linear", file=sys.stderr)
            scale = "linear"
        space[name] = dict(default=d, type=p.get("type", "float"), scale=scale, min=lo, max=hi)
    return space, fixed

def defaults_of(space):
    out = {}
    for n, s in space.items():
        v = min(max(s["default"], s["min"]), s["max"])
        out[n] = int(round(v)) if s["type"] == "int" else float(v)
    return out

def suggest(trial, space):
    out = {}
    for n, s in space.items():
        log = s["scale"] == "log"
        if s["type"] == "int":
            out[n] = trial.suggest_int(n, int(math.floor(s["min"])), int(math.ceil(s["max"])), log=log)
        else:
            out[n] = trial.suggest_float(n, float(s["min"]), float(s["max"]), log=log)
    return out

# ---------------------------------------------------------------- godot runs

_live = set()
_live_lock = threading.Lock()
STOP = threading.Event()

def kill_tree(proc):
    # The Godot console build can leave children behind; /T kills the whole tree.
    if os.name == "nt":
        subprocess.run(["taskkill", "/F", "/T", "/PID", str(proc.pid)], capture_output=True)
    else:
        proc.kill()

def build_cmd(args, params_path, result_path, seed, days, tag):
    return [str(args.godot), "--headless", "--path", str(PROJECT), "--",
            f"--turbo={days}", f"--turbo-seed={seed}", "--turbo-passive", f"--turbo-tag={tag}",
            f"--turbo-params={params_path}", f"--turbo-result={result_path}"]

def run_game(args, outdir, params, seed, days, tag):
    """Returns result dict or None (crash/timeout/stopped)."""
    outdir.mkdir(parents=True, exist_ok=True)
    pp, rp = outdir / f"{tag}.params.json", outdir / f"{tag}.result.json"
    pp.write_text(json.dumps(params), encoding="utf-8")
    rp.unlink(missing_ok=True)
    if STOP.is_set():
        return None
    proc = subprocess.Popen(build_cmd(args, pp, rp, seed, days, tag), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    with _live_lock:
        _live.add(proc)
    try:
        proc.wait(timeout=args.timeout)
    except subprocess.TimeoutExpired:
        print(f"WARNING: {tag} timed out after {args.timeout}s", file=sys.stderr)
    finally:
        kill_tree(proc)  # also after normal exit: Godot console can leave children
        with _live_lock:
            _live.discard(proc)
    try:
        return json.loads(rp.read_text(encoding="utf-8"))
    except Exception:
        if not STOP.is_set():
            print(f"WARNING: {tag} produced no result (exit {proc.returncode})", file=sys.stderr)
        return None

def evaluate(args, cfg, outdir, params, seeds, days, tag, on_screen=None):
    """Cheap screen of seeds[0] first (if on_screen), then full runs. Returns (score, per-seed list)."""
    if on_screen and days > cfg["screen_days"]:
        r = run_game(args, outdir, params, seeds[0], cfg["screen_days"], f"{tag}-screen")
        on_screen(seed_score(r, cfg, cfg["screen_days"]))
    results = [run_game(args, outdir, params, s, days, f"{tag}-s{s}") for s in seeds]
    scores = [seed_score(r, cfg, days) for r in results]
    per = [{**(r or {"failed": True}), "seed": s, "score": sc} for s, r, sc in zip(seeds, results, scores)]
    return candidate_score(scores, cfg), per

# ---------------------------------------------------------------- reporting

def report(study, space, fixed, args, cfg, outdir):
    import optuna
    done = [t for t in study.trials if t.state == optuna.trial.TrialState.COMPLETE]
    if not done:
        print("No completed trials; nothing to report.")
        return
    best = study.best_trial
    allp = {**fixed, **best.params}
    (outdir / "best_params.json").write_text(json.dumps(allp, indent=2), encoding="utf-8")
    cols = ["seed", "score", "survived", "days", "population", "deaths", "covered_avg", "p2p_volume"]
    with open(outdir / "top10.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["trial", "value", *space, "per_seed"])
        for t in sorted(done, key=lambda t: t.value, reverse=True)[:10]:
            w.writerow([t.number, t.value, *[t.params.get(n) for n in space],
                        json.dumps([{k: p.get(k) for k in cols} for p in t.user_attrs.get("per_seed", [])])])
    try:
        imp = optuna.importance.get_param_importances(study)
        (outdir / "importances.json").write_text(json.dumps(imp, indent=2), encoding="utf-8")
        print("Param importances:")
        for k, v in imp.items():
            print(f"  {k:32s} {v:.3f}")
    except Exception as e:
        print(f"(importances skipped: {e})")
    try:
        import optuna.visualization as ov
        ov.plot_optimization_history(study).write_html(str(outdir / "history.html"))
        ov.plot_parallel_coordinate(study).write_html(str(outdir / "parallel.html"))
    except Exception as e:
        print(f"(plots skipped: {e})")
    print(f"Best trial {best.number}: {best.value:.4f} -> {outdir / 'best_params.json'}")
    if args.no_validate or args.report_only or STOP.is_set():
        return
    vseeds = [int(x) for x in args.val_seeds.split(",")]
    base = {**fixed, **defaults_of(space)}
    print(f"Held-out validation on seeds {vseeds} ({args.days} days)...")
    with ThreadPoolExecutor(2) as ex:
        fb = ex.submit(evaluate, args, cfg, outdir / "runs", base, vseeds, args.days, "val-base")
        fv = ex.submit(evaluate, args, cfg, outdir / "runs", allp, vseeds, args.days, "val-best")
        (sb, pb), (sv, pv) = fb.result(), fv.result()
    for name, sc, per in (("baseline", sb, pb), ("best", sv, pv)):
        print(f"  {name:9s} score={sc:.4f}  " + " ".join(
            f"[{p['seed']}: {'ok' if p.get('survived') else 'dead'} d={p.get('days')} pop={p.get('population')} s={p['score']:.2f}]" for p in per))
    (outdir / "validation.json").write_text(json.dumps(dict(baseline=dict(score=sb, per_seed=pb), best=dict(score=sv, per_seed=pv)), indent=2), encoding="utf-8")

# ---------------------------------------------------------------- main

def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--study", default="freisassen")
    ap.add_argument("--storage", default=f"sqlite:///{(HERE / 'study.db').as_posix()}")
    ap.add_argument("--trials", type=int, default=30, help="new trials in this invocation")
    ap.add_argument("--jobs", type=int, default=3)
    ap.add_argument("--seeds", default="42,7,123", help="comma list, or an integer N = first N of 42,7,123,999,2024")
    ap.add_argument("--days", type=int, default=300)
    ap.add_argument("--val-seeds", default="1001,1002,1003")
    ap.add_argument("--no-validate", action="store_true")
    ap.add_argument("--godot", default=str(DEFAULT_GODOT))
    ap.add_argument("--params-dir", default=str(HERE / "params"))
    ap.add_argument("--ranges", default=str(HERE / "ranges_override.json"))
    ap.add_argument("--objective", default=str(HERE / "objective.json"))
    ap.add_argument("--timeout", type=int, default=None, help="per-run timeout seconds (default objective.json timeout_s)")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--report-only", action="store_true")
    args = ap.parse_args(argv)

    cfg = json.loads(Path(args.objective).read_text(encoding="utf-8"))
    args.timeout = args.timeout or cfg["timeout_s"]
    pool = [42, 7, 123, 999, 2024]
    seeds = pool[:int(args.seeds)] if args.seeds.isdigit() and int(args.seeds) <= len(pool) else [int(x) for x in args.seeds.split(",")]
    space, fixed = load_registry(args.params_dir, args.ranges)
    outdir = HERE / "out" / args.study

    if args.dry_run:
        print(f"Search space ({len(space)} params, fixed: {fixed}):")
        for n, s in space.items():
            print(f"  {n:32s} {s['type']:5s} {s['scale']:6s} [{s['min']:g}, {s['max']:g}] default={s['default']:g}")
        print(f"Seeds {seeds}, days {args.days}, jobs {args.jobs}, timeout {args.timeout}s. Trial 0 (defaults) commands:")
        pp, rp = outdir / "runs/<tag>.params.json", outdir / "runs/<tag>.result.json"
        print("  screen:", " ".join(build_cmd(args, pp, rp, seeds[0], cfg["screen_days"], "dry-screen")))
        for s in seeds:
            print("  full:  ", " ".join(build_cmd(args, pp, rp, s, args.days, f"dry-s{s}")))
        print("params:", json.dumps({**fixed, **defaults_of(space)}))
        return 0
    if not space:
        print("Empty search space (no registry files in --params-dir?)", file=sys.stderr)
        return 2
    if not Path(args.godot).exists():
        print(f"Godot not found: {args.godot}", file=sys.stderr)
        return 2

    import optuna
    optuna.logging.set_verbosity(optuna.logging.WARNING)
    outdir.mkdir(parents=True, exist_ok=True)
    study = optuna.create_study(study_name=args.study, storage=args.storage, load_if_exists=True, direction="maximize",
                                sampler=optuna.samplers.TPESampler(multivariate=True, seed=0),
                                pruner=optuna.pruners.MedianPruner(n_startup_trials=5, n_warmup_steps=0))
    lock = threading.Lock()
    if not args.report_only:
        if not study.trials:
            study.enqueue_trial(defaults_of(space))  # trial 0 = baseline
        remaining = [args.trials]

        def worker():
            while not STOP.is_set():
                with lock:
                    if remaining[0] <= 0:
                        return
                    remaining[0] -= 1
                    trial = study.ask()
                    params = suggest(trial, space)
                state, val = optuna.trial.TrialState.FAIL, None
                try:
                    def screen(sc):
                        with lock:
                            trial.report(sc, 1)
                            if trial.should_prune():
                                raise optuna.TrialPruned()
                    val, per = evaluate(args, cfg, outdir / "runs", {**fixed, **params}, seeds, args.days,
                                        f"{args.study}-t{trial.number}", screen)
                    if STOP.is_set():
                        continue  # interrupted mid-trial: leave it FAILED, don't pollute the study
                    trial.set_user_attr("per_seed", per)
                    state = optuna.trial.TrialState.COMPLETE
                    print(f"trial {trial.number}: {val:.4f}  per-seed " + " ".join(f"{p['score']:.2f}" for p in per), flush=True)
                except optuna.TrialPruned:
                    state, val = optuna.trial.TrialState.PRUNED, None
                    print(f"trial {trial.number}: pruned after screen", flush=True)
                except Exception as e:  # one broken trial must not end the study
                    print(f"WARNING: trial {trial.number} failed: {e!r}", file=sys.stderr)
                finally:
                    with lock:
                        study.tell(trial, val, state=state)

        ex = ThreadPoolExecutor(args.jobs)
        futs = [ex.submit(worker) for _ in range(args.jobs)]
        try:
            for f in futs:
                f.result()
        except KeyboardInterrupt:
            print("Interrupted: stopping runs (study is resumable)...", file=sys.stderr)
            STOP.set()
            with _live_lock:
                for p in list(_live):
                    kill_tree(p)
        finally:
            ex.shutdown(wait=True)
    report(study, space, fixed, args, cfg, outdir)
    return 0

if __name__ == "__main__":
    sys.exit(main())
