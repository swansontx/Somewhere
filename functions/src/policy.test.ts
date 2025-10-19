import { isInQuietHours, computeRefilledTokens } from './policy';

describe('policy helpers', () => {
  test('quiet hours crossing midnight', () => {
    // 23:00 in PST (America/Los_Angeles)
    const tz = 'America/Los_Angeles';
    const ts = new Date('2025-10-19T23:00:00-07:00').getTime();
    expect(isInQuietHours(tz, 22, 8, ts)).toBe(true);
  });

  test('quiet hours not in range', () => {
    const tz = 'UTC';
    const ts = new Date('2025-10-19T10:00:00Z').getTime();
    expect(isInQuietHours(tz, 22, 8, ts)).toBe(false);
  });

  test('token refill calculation', () => {
    const now = 1000 * 60 * 60 * 5; // arbitrary
    const res = computeRefilledTokens(1, 0, now, 5, 1000 * 60, 1);
    expect(res.tokens).toBeGreaterThanOrEqual(1);
  });
});
