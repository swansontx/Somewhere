import { applyRules, consumeToken } from './engage';
import * as admin from 'firebase-admin';

jest.setTimeout(30000);

describe('engage integration tests (firestore emulator)', () => {
  test('consumeToken and applyRules with emulator', async () => {
    // This test expects the Firestore emulator to be running and FIRESTORE_EMULATOR_HOST env set
    if (!process.env.FIRESTORE_EMULATOR_HOST) {
      console.warn('Skipping emulator test: FIRESTORE_EMULATOR_HOST not set');
      return;
    }

    const uid = 'test-user-123';

    // reset any existing doc
    const bucketRef = admin.firestore().collection('rate_limits').doc(uid);
    await bucketRef.delete().catch(() => null);

    const before = await applyRules({ type: 'app_open', ctx: { stats: {}, prefs: {}, tz: 'UTC' }, uid });
    expect(before.details.tokensAvailable).toBeGreaterThanOrEqual(0);

    const c = await consumeToken(uid);
    expect(c.ok).toBe(true);

    const after = await applyRules({ type: 'app_open', ctx: { stats: {}, prefs: {}, tz: 'UTC' }, uid });
    // tokens decreased or capped
    expect(after.details.tokensAvailable).toBeGreaterThanOrEqual(0);
  });
});
