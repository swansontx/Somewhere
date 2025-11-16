from pathlib import Path
import os

BASE_DIR = Path('.')
DATA_DIR = BASE_DIR / 'data'
OUTPUTS = BASE_DIR / 'outputs'
NFLDATA = BASE_DIR / 'nfl_data_2025_csv'
BACKEND_DIR = BASE_DIR / 'backend'


def get_api_key(name: str = 'ODDS_API_KEY'):
    # prefer env var
    val = os.environ.get(name)
    if val:
        return val
    # fallback file for odds api
    if name == 'ODDS_API_KEY':
        kfile = BACKEND_DIR / '.odds_api_key'
        if kfile.exists():
            return kfile.read_text().strip()
    return None
