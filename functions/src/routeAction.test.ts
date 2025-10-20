import type { firestore as FirestoreNamespace } from 'firebase-admin';

describe('routeAction firestore interactions', () => {
  let collectionMock: jest.Mock;
  let timestampNowMock: jest.Mock;
  let timestampFromMillisMock: jest.Mock;

  beforeEach(() => {
    jest.resetModules();

    collectionMock = jest.fn();
    timestampNowMock = jest.fn(() => ({ seconds: 0, nanoseconds: 0 }));
    timestampFromMillisMock = jest.fn((ms: number) => ({ seconds: Math.floor(ms / 1000), nanoseconds: 0 }));

    jest.doMock('firebase-admin', () => {
      const firestoreInstance = { collection: collectionMock };
      const firestoreFn = jest.fn(() => firestoreInstance) as unknown as typeof FirestoreNamespace;
      (firestoreFn as any).Timestamp = {
        now: timestampNowMock,
        fromMillis: timestampFromMillisMock,
      };
      return {
        initializeApp: jest.fn(),
        firestore: firestoreFn,
      };
    });
  });

  afterEach(() => {
    jest.dontMock('firebase-admin');
    jest.resetModules();
  });

  test('routes message actions into the inbox collection', async () => {
    const addMock = jest.fn().mockResolvedValue({ id: 'msg123' });
    collectionMock.mockImplementation((name: string) => {
      if (name === 'messages') {
        return { add: addMock };
      }
      throw new Error(`Unexpected collection ${name}`);
    });

    const module = await import('./engage');
    const result = await module.routeAction('user-1', {
      action: 'message',
      body: 'Hello there',
      reason: 'nudge',
    });

    expect(addMock).toHaveBeenCalledWith({
      uid: 'user-1',
      channel: 'inbox',
      body: 'Hello there',
      meta: { intent: 'nudge' },
      sentAt: expect.any(Object),
    });
    expect(result).toEqual({ sent: true, id: 'msg123' });
    expect(timestampNowMock).toHaveBeenCalled();
  });

  test('routes task actions into the scheduled tasks collection', async () => {
    const addMock = jest.fn().mockResolvedValue({ id: 'task789' });
    collectionMock.mockImplementation((name: string) => {
      if (name === 'tasks') {
        return { add: addMock };
      }
      throw new Error(`Unexpected collection ${name}`);
    });

    const module = await import('./engage');
    const runAt = Date.now() + 60000;
    const result = await module.routeAction('user-2', {
      action: 'task',
      runAt,
    });

    expect(addMock).toHaveBeenCalledWith({
      uid: 'user-2',
      kind: 'follow_up',
      runAt: expect.any(Object),
      status: 'scheduled',
    });
    expect(timestampFromMillisMock).toHaveBeenCalledWith(runAt);
    expect(result).toEqual({ scheduled: true });
  });

  test('skips unknown actions without touching Firestore', async () => {
    const module = await import('./engage');
    const result = await module.routeAction('user-3', { action: 'none' });

    expect(collectionMock).not.toHaveBeenCalled();
    expect(result).toEqual({ skipped: true });
  });
});
