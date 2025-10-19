import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";

admin.initializeApp();
const db = admin.firestore();

export const postEvent = async (req: any, res: any) => {
  try {
    const { uid, type, ts, payload } = req.body ?? {};
    if (!uid || !type) throw new Error("uid and type required");

    await db.collection("events").add({ uid, type, payload: payload ?? null, createdAt: admin.firestore.Timestamp.now() });

    const ctx = await loadContext(uid);
    const policy = applyRules({ type, ctx });
    if (policy.blocked) return res.json({ ok: true, decision: "none", reason: policy.reason });

    const decision = await askGooseAgent({ uid, type, ctx });
    await persistDecision(uid, type, decision);

    const result = await routeAction(uid, decision);
    return res.json({ ok: true, result });
  } catch (e:any) {
    console.error(e);
    res.status(500).json({ ok: false, error: e.message });
  }
};

async function loadContext(uid: string) {
  const userDoc = await db.doc(`users/${uid}`).get();
  const stats = userDoc.exists ? (userDoc.get("stats") ?? {}) : {};
  const prefs = userDoc.exists ? (userDoc.get("prefs") ?? {}) : {};
  return { stats, prefs, tz: userDoc.exists ? (userDoc.get("profile.tz") ?? "UTC") : "UTC" };
}

function applyRules({ type, ctx }: { type: string; ctx: any }) {
  const now = Date.now();
  const last = ctx.stats?.lastEngagedAt ?? 0;
  const rateLimited = now - last < 1000 * 60 * 30; // 30m

  // naive tz-aware quiet hours check
  const quietHours = ctx.prefs?.quietHours ?? { start: 22, end: 8 }; // 22:00 - 08:00 default
  const userOffsetHours = 0; // TODO: compute from tz
  const hour = new Date(now + userOffsetHours * 3600 * 1000).getUTCHours();
  const inQuiet = quietHours.start > quietHours.end ? (hour >= quietHours.start || hour < quietHours.end) : (hour >= quietHours.start && hour < quietHours.end);

  const quiet = inQuiet;
  return { blocked: rateLimited || quiet, reason: rateLimited ? "rate_limit" : quiet ? "quiet_hours" : undefined };
}

async function askGooseAgent(input: any) {
  // stubbed LLM logic; replace with HTTP call to Goose agent runtime
  if (input.type === "app_open" && (input.ctx.stats?.dropsCount ?? 0) === 0) {
    return { action: "message", body: "Got a thought to drop? Try a one-liner—tap + to post.", reason: "nudge_first_drop", score: 0.66 };
  }
  return { action: "none", reason: "not_applicable", score: 0.2 };
}

async function persistDecision(uid: string, type: string, decision: any) {
  await db.collection("engage_decisions").add({
    uid,
    triggerId: type,
    decision: decision.action,
    score: decision.score ?? null,
    reason: decision.reason ?? null,
    createdAt: admin.firestore.Timestamp.now(),
  });
}

async function routeAction(uid: string, decision: any) {
  if (decision.action === "message" && decision.body) {
    const msgRef = await db.collection("messages").add({
      uid,
      channel: "inbox",
      body: decision.body,
      meta: { intent: decision.reason },
      sentAt: admin.firestore.Timestamp.now(),
    });
    return { sent: true, id: msgRef.id };
  }
  if (decision.action === "task" && decision.runAt) {
    await db.collection("tasks").add({ uid, kind: "follow_up", runAt: admin.firestore.Timestamp.fromMillis(decision.runAt), status: "scheduled" });
    return { scheduled: true };
  }
  return { skipped: true };
}
