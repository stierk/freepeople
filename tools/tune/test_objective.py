"""Plain-python asserts for the scoring function: python tools/tune/test_objective.py"""
import json
from pathlib import Path
import tune

cfg = json.loads((Path(__file__).parent / "objective.json").read_text())
D = 300
assert tune.seed_score(dict(survived=False, days=150), cfg, D) == 0.5
assert tune.seed_score(None, cfg, D) == 0.0
assert tune.seed_score(dict(survived=False, days=300), cfg, D) < 1  # gate: death never beats survival
ok = dict(survived=True, population=32, covered_avg=7, p2p_volume=1e9)
assert abs(tune.seed_score(ok, cfg, D) - (1 + cfg["w_pop"] + cfg["w_cov"] + cfg["w_trade"])) < 1e-9
low = dict(survived=True, population=1, covered_avg=1, p2p_volume=0)
assert 1 < tune.seed_score(low, cfg, D) < tune.seed_score(ok, cfg, D)
assert tune.candidate_score([2, 2, 2], cfg) == 2
assert abs(tune.candidate_score([1, 3], cfg) - (2 - cfg["std_penalty"])) < 1e-9
print("ok")
