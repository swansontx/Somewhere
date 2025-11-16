from typing import List, Dict, Any
from itertools import combinations


def american_to_decimal(a):
    try:
        a = int(a)
    except Exception:
        return None
    if a > 0:
        return 1.0 + a / 100.0
    else:
        return 1.0 + 100.0 / (-a)


def suggest_parlays(selections: List[Dict[str, Any]], max_legs: int = 6, top_k: int = 20):
    if not selections:
        return {'selected': [], 'parlay_suggestions': []}
    out = []
    for s in selections:
        model_prob = s.get('model_prob')
        mprice = s.get('market_price')
        dec = american_to_decimal(mprice) if mprice is not None else None
        ev = None
        if dec and model_prob is not None:
            ev = model_prob * dec - 1.0
        out.append({**s, 'decimal': dec, 'ev_per_1': ev})
    out_sorted = sorted(out, key=lambda x: (x['ev_per_1'] is None, -(x['ev_per_1'] or 0)))
    max_legs = min(max_legs, len(out_sorted))
    combos = []
    for r in range(1, max_legs + 1):
        for combo in combinations(out_sorted, r):
            probs = [c.get('model_prob') or 0 for c in combo]
            market_dec = [c.get('decimal') or 0 for c in combo]
            joint_prob = 1.0
            for p in probs:
                joint_prob *= p
            payout = 1.0
            for d in market_dec:
                payout *= d if d else 1.0
            ev = joint_prob * payout - 1.0
            combos.append({'legs': [c.get('player') for c in combo], 'implied_payout': payout, 'joint_prob': joint_prob, 'ev_per_1': ev})
    combos_sorted = sorted(combos, key=lambda x: -x['ev_per_1'] if x['ev_per_1'] is not None else 0)
    return {'selected': out_sorted, 'parlay_suggestions': combos_sorted[:top_k]}
