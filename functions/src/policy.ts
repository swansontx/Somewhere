export function computeRefilledTokens(storedTokens: number, lastRefillAtMs: number, nowMs: number, capacity: number, refillIntervalMs: number, refillTokens: number) {
  const last = lastRefillAtMs || 0;
  const intervals = Math.floor((nowMs - last) / refillIntervalMs);
  const refill = Math.max(0, intervals) * refillTokens;
  const tokens = Math.min(capacity, (typeof storedTokens === 'number' ? storedTokens : capacity) + refill);
  const newLast = intervals > 0 ? last + intervals * refillIntervalMs : last;
  return { tokens, newLast, intervals };
}
