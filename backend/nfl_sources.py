"""
Adapter layer to unify nflreadpy (nflreadpy/nflverse) and nfl_data_py interfaces.

This module provides functions with the same names used in the repo's download script
so we can switch data providers without changing the rest of the code.

Strategy:
- Prefer nflreadpy (imported as nr) when available and implement the commonly used
  functions: import_pbp_data, import_weekly_data, import_seasonal_data, import_seasonal_rosters,
  import_weekly_rosters, import_snap_counts, import_injuries, import_ngs_data, import_ftn_data,
  import_sc_lines, import_schedules, import_ids, import_depth_charts, import_qbr
- If a function isn't available in nflreadpy or an import fails, fall back to nfl_data_py (the old provider)
  to preserve existing behavior.
- Functions accept the same parameters as the existing download_nfl_2025.py expects, but adapt them
  where necessary.

Note: nflreadpy API naming and args may differ; this adapter uses defensive checks and minimal mapping.
"""
from __future__ import annotations
import logging
from typing import List, Optional, Dict, Any

log = logging.getLogger(__name__)

# Try to import nflreadpy (nflverse). If not available, fall back to nfl_data_py.
try:
    import nflreadpy as nr
    NFLLIB = 'nflreadpy'
    log.info('Using nflreadpy as data source')
except Exception:
    nr = None
    NFLLIB = None

try:
    import nfl_data_py as ndp
    log.info('nfl_data_py available as fallback')
except Exception:
    ndp = None


# Helper to raise if no source available
def _no_source():
    raise RuntimeError('Neither nflreadpy nor nfl_data_py are available. Install one of them.')


def import_pbp_data(years: List[int], downcast: bool = True):
    """Import play-by-play data for years.

    Returns a single DataFrame (concatenated per-year) like nfl_data_py.import_pbp_data.
    """
    if nr is not None:
        try:
            # nflreadpy typically provides load_pbp or load_pbp_year: try common variants
            dfs = []
            for y in years:
                try:
                    df = nr.load_pbp(seasons=[y])
                except TypeError:
                    # some versions use load_pbp(year)
                    df = nr.load_pbp(y)
                dfs.append(df)
            import pandas as pd
            return pd.concat(dfs, ignore_index=True)
        except Exception as e:
            log.exception('nflreadpy import_pbp_data failed, will fallback: %s', e)
    if ndp is not None:
        return ndp.import_pbp_data(years=years, downcast=downcast)
    _no_source()


def import_weekly_data(years: List[int], downcast: bool = True):
    if nr is not None:
        try:
            import pandas as pd
            dfs = []
            # nflreadpy may expose weekly stats via load_weekly_pbp or load_weekly
            for y in years:
                try:
                    df = nr.load_weekly_stats(seasons=[y])
                except Exception:
                    try:
                        df = nr.load_weekly(seasons=[y])
                    except Exception:
                        df = None
                if df is not None:
                    dfs.append(df)
            if dfs:
                return pd.concat(dfs, ignore_index=True)
        except Exception as e:
            log.debug('nflreadpy weekly data attempt failed: %s', e)
    if ndp is not None:
        return ndp.import_weekly_data(years=years, downcast=downcast)
    _no_source()


def import_seasonal_data(years: List[int]):
    if nr is not None:
        try:
            import pandas as pd
            dfs = []
            for y in years:
                try:
                    df = nr.load_seasonal(seasons=[y])
                except Exception:
                    try:
                        df = nr.load_seasonal_stats(y)
                    except Exception:
                        df = None
                if df is not None:
                    dfs.append(df)
            if dfs:
                return pd.concat(dfs, ignore_index=True)
        except Exception as e:
            log.debug('nflreadpy seasonal attempt failed: %s', e)
    if ndp is not None:
        return ndp.import_seasonal_data(years=years)
    _no_source()


def import_seasonal_rosters(years: List[int], downcast: bool = True):
    if nr is not None:
        try:
            import pandas as pd
            dfs = []
            for y in years:
                try:
                    df = nr.load_rosters(seasons=[y])
                except Exception:
                    try:
                        df = nr.load_roster(season=y)
                    except Exception:
                        df = None
                if df is not None:
                    dfs.append(df)
            if dfs:
                return pd.concat(dfs, ignore_index=True)
        except Exception as e:
            log.debug('nflreadpy seasonal_rosters failed: %s', e)
    if ndp is not None:
        return ndp.import_seasonal_rosters(years=years)
    _no_source()


def import_weekly_rosters(years: List[int], downcast: bool = True):
    if nr is not None:
        try:
            import pandas as pd
            dfs = []
            for y in years:
                try:
                    df = nr.load_weekly_rosters(seasons=[y])
                except Exception:
                    try:
                        df = nr.load_rosters(seasons=[y])
                    except Exception:
                        df = None
                if df is not None:
                    dfs.append(df)
            if dfs:
                return pd.concat(dfs, ignore_index=True)
        except Exception as e:
            log.debug('nflreadpy weekly_rosters failed: %s', e)
    if ndp is not None:
        return ndp.import_weekly_rosters(years=years)
    _no_source()


def import_snap_counts(years: List[int]):
    if nr is not None:
        try:
            # nflreadpy may not have snap counts; fallback
            if hasattr(nr, 'load_snap_counts'):
                import pandas as pd
                dfs = []
                for y in years:
                    df = nr.load_snap_counts(seasons=[y])
                    dfs.append(df)
                return pd.concat(dfs, ignore_index=True)
        except Exception as e:
            log.debug('nflreadpy snap_counts failed: %s', e)
    if ndp is not None:
        return ndp.import_snap_counts(years=years)
    _no_source()


def import_injuries(years: List[int]):
    if nr is not None and hasattr(nr, 'load_injuries'):
        try:
            import pandas as pd
            dfs = []
            for y in years:
                df = nr.load_injuries(seasons=[y])
                dfs.append(df)
            return pd.concat(dfs, ignore_index=True)
        except Exception as e:
            log.debug('nflreadpy injuries failed: %s', e)
    # fallback: nfl_data_py has import_injuries
    if ndp is not None:
        return ndp.import_injuries(years=years)
    _no_source()


def import_ngs_data(kind: str, years: List[int]):
    """Next-Gen Stats loader. Try nfl_data_py first, then nflreadpy. Raises if neither provides data."""
    # Try nfl_data_py implementation first (more likely to exist)
    if ndp is not None and hasattr(ndp, 'import_ngs_data'):
        try:
            return ndp.import_ngs_data(kind, years=years)
        except Exception as e:
            log.debug('nfl_data_py import_ngs_data failed: %s', e)
    # Fallback to nflreadpy if available
    if nr is not None and hasattr(nr, 'load_ngs'):
        try:
            import pandas as pd
            dfs = []
            for y in years:
                df = nr.load_ngs(kind=kind, season=y)
                dfs.append(df)
            if dfs:
                return pd.concat(dfs, ignore_index=True)
        except Exception as e:
            log.debug('nflreadpy ngs attempt failed: %s', e)
    # If nothing works, raise so caller can handle
    raise RuntimeError('NGS import not available in nflreadpy or nfl_data_py for kind=%s' % kind)


# These provide graceful fallbacks (empty DataFrame) when the underlying provider doesn't expose them.

def import_depth_charts(years: List[int]):
    """Try to load depth charts; return empty DataFrame if not available."""
    import pandas as pd
    if nr is not None:
        try:
            if hasattr(nr, 'load_depth_charts'):
                dfs = []
                for y in years:
                    df = nr.load_depth_charts(seasons=[y])
                    dfs.append(df)
                return pd.concat(dfs, ignore_index=True)
            if hasattr(nr, 'load_depth_chart'):
                dfs = []
                for y in years:
                    df = nr.load_depth_chart(season=y)
                    dfs.append(df)
                return pd.concat(dfs, ignore_index=True)
        except Exception as e:
            log.debug('nflreadpy depth_charts attempt failed: %s', e)
    if ndp is not None and hasattr(ndp, 'import_depth_charts'):
        try:
            return ndp.import_depth_charts(years=years)
        except Exception as e:
            log.debug('nfl_data_py depth_charts failed: %s', e)
    # return empty frame
    return pd.DataFrame()


def import_qbr(years: List[int], level: str = 'nfl', frequency: str = 'season'):
    """Load QBR or return empty DataFrame if not available."""
    import pandas as pd
    # nflreadpy may not provide QBR; nfl_data_py might
    if ndp is not None and hasattr(ndp, 'import_qbr'):
        try:
            return ndp.import_qbr(years=years, level=level, frequency=frequency)
        except Exception as e:
            log.debug('nfl_data_py import_qbr failed: %s', e)
    # fallback to empty
    return pd.DataFrame()


def import_seasonal_pfr(stat: str, years: List[int]):
    """Seasonal PFR stats wrapper if available; otherwise empty DataFrame."""
    import pandas as pd
    if ndp is not None and hasattr(ndp, 'import_seasonal_pfr'):
        try:
            return ndp.import_seasonal_pfr(stat, years=years)
        except Exception as e:
            log.debug('nfl_data_py import_seasonal_pfr failed: %s', e)
    return pd.DataFrame()


def import_weekly_pfr(stat: str, years: List[int]):
    """Weekly PFR stats wrapper if available; otherwise empty DataFrame."""
    import pandas as pd
    if ndp is not None and hasattr(ndp, 'import_weekly_pfr'):
        try:
            return ndp.import_weekly_pfr(stat, years=years)
        except Exception as e:
            log.debug('nfl_data_py import_weekly_pfr failed: %s', e)
    return pd.DataFrame()


def import_ftn_data(years: List[int], columns=None, downcast: bool = True, thread_requests: bool = False):
    """FTN data wrapper (field-tracking data). Try nfl_data_py import if available; else empty DataFrame."""
    import pandas as pd
    if ndp is not None and hasattr(ndp, 'import_ftn_data'):
        try:
            return ndp.import_ftn_data(years=years, columns=columns, downcast=downcast, thread_requests=thread_requests)
        except Exception as e:
            log.debug('nfl_data_py import_ftn_data failed: %s', e)
    # try NGS loader as partial fallback
    try:
        return import_ngs_data(kind='ftn', years=years)
    except Exception:
        pass
    return pd.DataFrame()



# Generic passthroughs for other helper imports
def import_ids(columns=None, ids=None):
    if ndp is not None:
        return ndp.import_ids(columns=columns, ids=ids)
    if nr is not None and hasattr(nr, 'load_ids'):
        return nr.load_ids()
    _no_source()


def import_schedules(years: List[int]):
    if nr is not None and hasattr(nr, 'load_schedules'):
        try:
            import pandas as pd
            dfs = []
            for y in years:
                df = nr.load_schedules(seasons=[y])
                dfs.append(df)
            return pd.concat(dfs, ignore_index=True)
        except Exception as e:
            log.debug('nflreadpy schedules failed: %s', e)
    if ndp is not None:
        return ndp.import_schedules(years=years)
    _no_source()


def import_team_desc():
    if ndp is not None:
        return ndp.import_team_desc()
    if nr is not None and hasattr(nr, 'load_team_desc'):
        return nr.load_team_desc()
    _no_source()


# Add any additional wrappers as needed by the download script


if __name__ == '__main__':
    print('nfl sources adapter. Preferred:', NFLLIB)


# Additional wrappers for datasets referenced by download_nfl_2025.py but not yet implemented

def import_sc_lines(years: List[int]):
    """Scoring lines / betting lines wrapper."""
    import pandas as pd
    if ndp is not None and hasattr(ndp, 'import_sc_lines'):
        try:
            return ndp.import_sc_lines(years=years)
        except Exception as e:
            log.debug('nfl_data_py import_sc_lines failed: %s', e)
    # try nflreadpy-like names
    if nr is not None:
        try:
            dfs = []
            for y in years:
                if hasattr(nr, 'load_sc_lines'):
                    dfs.append(nr.load_sc_lines(seasons=[y]))
                elif hasattr(nr, 'load_scoring_lines'):
                    dfs.append(nr.load_scoring_lines(seasons=[y]))
            if dfs:
                return pd.concat(dfs, ignore_index=True)
        except Exception as e:
            log.debug('nflreadpy import_sc_lines attempt failed: %s', e)
    return pd.DataFrame()


def import_officials(years: List[int]):
    """Officials / referees wrapper."""
    import pandas as pd
    if ndp is not None and hasattr(ndp, 'import_officials'):
        try:
            return ndp.import_officials(years=years)
        except Exception as e:
            log.debug('nfl_data_py import_officials failed: %s', e)
    if nr is not None and hasattr(nr, 'load_officials'):
        try:
            dfs = []
            for y in years:
                dfs.append(nr.load_officials(seasons=[y]))
            return pd.concat(dfs, ignore_index=True)
        except Exception as e:
            log.debug('nflreadpy import_officials failed: %s', e)
    return pd.DataFrame()


def import_draft_picks(years: List[int]):
    """Draft picks wrapper."""
    import pandas as pd
    if ndp is not None and hasattr(ndp, 'import_draft_picks'):
        try:
            return ndp.import_draft_picks(years=years)
        except Exception as e:
            log.debug('nfl_data_py import_draft_picks failed: %s', e)
    if nr is not None and hasattr(nr, 'load_draft_picks'):
        try:
            dfs = []
            for y in years:
                dfs.append(nr.load_draft_picks(seasons=[y]))
            return pd.concat(dfs, ignore_index=True)
        except Exception as e:
            log.debug('nflreadpy import_draft_picks failed: %s', e)
    return pd.DataFrame()


def import_draft_values():
    """Draft values wrapper."""
    import pandas as pd
    if ndp is not None and hasattr(ndp, 'import_draft_values'):
        try:
            return ndp.import_draft_values()
        except Exception as e:
            log.debug('nfl_data_py import_draft_values failed: %s', e)
    if nr is not None and hasattr(nr, 'load_draft_values'):
        try:
            return nr.load_draft_values()
        except Exception as e:
            log.debug('nflreadpy import_draft_values failed: %s', e)
    return pd.DataFrame()


def import_combine_data(years: List[int], positions=None):
    """Combine / combine results wrapper."""
    import pandas as pd
    if ndp is not None and hasattr(ndp, 'import_combine_data'):
        try:
            return ndp.import_combine_data(years=years, positions=positions)
        except Exception as e:
            log.debug('nfl_data_py import_combine_data failed: %s', e)
    if nr is not None:
        try:
            dfs = []
            for y in years:
                if hasattr(nr, 'load_combine'):
                    dfs.append(nr.load_combine(seasons=[y]))
                elif hasattr(nr, 'load_combine_data'):
                    dfs.append(nr.load_combine_data(season=y))
            if dfs:
                return pd.concat(dfs, ignore_index=True)
        except Exception as e:
            log.debug('nflreadpy import_combine_data failed: %s', e)
    return pd.DataFrame()
