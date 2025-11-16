import json
from pathlib import Path
from app.config import OUTPUTS

CACHE_DIR = OUTPUTS


def latest_file(glob_pattern: str):
    files = sorted(CACHE_DIR.glob(glob_pattern))
    return files[-1] if files else None


def save_json(name: str, data, suffix=None):
    from time import strftime
    t = strftime('%Y%m%d_%H%M%S')
    filename = f"{name}_{t}.json" if suffix is None else f"{name}_{suffix}.json"
    p = CACHE_DIR / filename
    p.write_text(json.dumps(data, default=str))
    return p


def load_json(path_or_name: str):
    p = Path(path_or_name)
    if p.exists():
        return json.loads(p.read_text())
    # allow passing a glob name
    p = latest_file(path_or_name)
    if p:
        return json.loads(p.read_text())
    return None
