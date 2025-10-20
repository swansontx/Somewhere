import { computeRefilledTokens } from './policy';

describe('policy helpers', () => {
  test('token refill calculation', () => {
    const now = 1000 * 60 * 60 * 5; // arbitrary
    const res = computeRefilledTokens(1, 0, now, 5, 1000 * 60, 1);
    expect(res.tokens).toBeGreaterThanOrEqual(1);
  });
});
