from app.core import cache
from app.config import OUTPUTS
import subprocess
import logging

log = logging.getLogger(__name__)


def recompute_projections():
    """Run the existing script to regenerate projections and copy/move outputs to canonical filenames."""
    log.info('Starting recompute_projections')
    # call existing script (scripts/generate_projections.py)
    try:
        subprocess.run(['python3', 'scripts/generate_projections.py'], check=True)
    except Exception as e:
        log.exception('Recompute projections failed: %s', e)
        return False
    # find latest projections file and create a symlink or copy to canonical
    files = sorted(OUTPUTS.glob('projections_*.csv'))
    if files:
        latest = files[-1]
        canonical = OUTPUTS / 'projections_latest.csv'
        try:
            if canonical.exists() or canonical.is_symlink():
                canonical.unlink()
            canonical.symlink_to(latest.name)
        except Exception:
            # fallback to copy
            import shutil
            shutil.copy(latest, canonical)
    log.info('Recompute complete')
    return True
