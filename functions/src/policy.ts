import moment from "moment-timezone";

export function isInQuietHours(tz: string, startHour: number, endHour: number, timestampMs?: number) {
  const now = timestampMs ?? Date.now();
  const hour = Number(moment.tz(now, tz).hour());
  if (startHour > endHour) {
    return hour >= startHour || hour < endHour;
  }
  return hour >= startHour && hour < endHour;
}

export function computeRefilledTokens(storedTokens: number, lastRefillAtMs: number, nowMs: number, capacity: number, refillIntervalMs: number, refillTokens: number) {
  const last = lastRefillAtMs || 0;
  const intervals = Math.floor((nowMs - last) / refillIntervalMs);
  const refill = Math.max(0, intervals) * refillTokens;
  const tokens = Math.min(capacity, (typeof storedTokens === 'number' ? storedTokens : capacity) + refill);
  const newLast = intervals > 0 ? last + intervals * refillIntervalMs : last;
  return { tokens, newLast, intervals };
}
