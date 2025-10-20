import { initializeTestEnvironment, RulesTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import fs from 'fs';
import path from 'path';

const projectId = 'demo';

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.warn('Skipping Firestore rules tests: FIRESTORE_EMULATOR_HOST not set');
}

describe('Firestore security rules', () => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    test.skip('requires Firestore emulator', () => {
      /* intentionally skipped */
    });
    return;
  }
  let testEnv: RulesTestEnvironment;

  beforeAll(async () => {
    const rulesPath = path.resolve(__dirname, '..', '..', 'firestore.rules');
    const rules = fs.readFileSync(rulesPath, 'utf8');
    testEnv = await initializeTestEnvironment({
      projectId,
      firestore: { rules },
    });
  });

  afterAll(async () => {
    await testEnv.cleanup();
  });

  afterEach(async () => {
    await testEnv.clearFirestore();
  });

  test('authenticated users can query public drops by geohash prefix', async () => {
    await testEnv.withSecurityRulesDisabled(async (context: any) => {
      const db = context.firestore();
      await db.collection('drops').doc('drop1').set({
        text: 'hello',
        authorId: 'author-1',
        visibility: 'public',
        geohash: '9q8yy1',
      });
    });

    const userDb = testEnv.authenticatedContext('reader-1').firestore();
    const query = userDb.collection('drops').orderBy('geohash').startAt('9q8').endAt('9q8\uf8ff');
    await assertSucceeds(query.get());
  });

  test('unauthenticated users cannot read drops', async () => {
    await testEnv.withSecurityRulesDisabled(async (context: any) => {
      await context.firestore().collection('drops').doc('drop2').set({
        text: 'secret',
        authorId: 'author-2',
        visibility: 'public',
        geohash: '9q8yy2',
      });
    });

    const anonDb = testEnv.unauthenticatedContext().firestore();
    const query = anonDb.collection('drops').orderBy('geohash').startAt('9q8').endAt('9q8\uf8ff');
    await assertFails(query.get());
  });

  test('users can create drops for themselves', async () => {
    const authed = testEnv.authenticatedContext('creator-1');
    const db = authed.firestore();

    await assertSucceeds(
      db.collection('drops').add({
        text: 'New drop',
        authorId: 'creator-1',
        visibility: 'public',
        geohash: '9q8zz0',
      })
    );
  });

  test('users cannot create drops for other authors', async () => {
    const authed = testEnv.authenticatedContext('creator-2');
    const db = authed.firestore();

    await assertFails(
      db.collection('drops').add({
        text: 'Impostor drop',
        authorId: 'someone-else',
        visibility: 'public',
        geohash: '9q8zz1',
      })
    );
  });
});
