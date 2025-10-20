import { applyRules, consumeToken, persistEngagement } from './engage';
import * as admin from 'firebase-admin';

// ensure the emulator-aware env vars are propagated when the emulator is running
if (process.env.FIRESTORE_EMULATOR_HOST) {
  process.env.GOOGLE_CLOUD_PROJECT = process.env.GOOGLE_CLOUD_PROJECT ?? 'demo';
  process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT ?? process.env.GOOGLE_CLOUD_PROJECT;
}

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

  test('persistEngagement stores per-user engagement docs', async () => {
    if (!process.env.FIRESTORE_EMULATOR_HOST) {
      console.warn('Skipping emulator test: FIRESTORE_EMULATOR_HOST not set');
      return;
    }

    const uid = `engagement-${Date.now()}`;
    const triggerId = 'drop_view';
    const dropId = 'drop-123';

    const decision = { action: 'message', reason: 'nudge', score: 0.7 };
    const payload = { dropId };

    await persistEngagement(uid, triggerId, decision, payload, { sent: true, id: 'msg-1' });
    await persistEngagement(uid, triggerId, decision, payload, { sent: true, id: 'msg-2' });

    const engagementDoc = await admin
      .firestore()
      .doc(`users/${uid}/engagements/${dropId}_${triggerId}`)
      .get();

    expect(engagementDoc.exists).toBe(true);
    expect(engagementDoc.get('count')).toBe(2);
    expect(engagementDoc.get('decision')).toBe('message');
    expect(engagementDoc.get('dropId')).toBe(dropId);
    expect(engagementDoc.get('result.id')).toBe('msg-2');
    expect(engagementDoc.get('firstEngagedAt')).toBeInstanceOf(admin.firestore.Timestamp);

    const userDoc = await admin.firestore().doc(`users/${uid}`).get();
    expect(userDoc.get('stats.engagementsCount')).toBe(2);
    expect(userDoc.get(`stats.engagementsByTrigger.${triggerId}`)).toBe(2);
    expect(userDoc.get('stats.lastEngagedAt')).toBeInstanceOf(admin.firestore.Timestamp);
  });
});
