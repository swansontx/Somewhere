import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";
import axios from "axios";
import moment from "moment-timezone";

admin.initializeApp();
const db = admin.firestore();

export const postEvent = async (req: any, res: any) => {
  try {
    const { uid, type, ts, payload } = req.body ?? {};
    if (!uid || !type) throw new Error("uid and type required");

    await db.collection("events").add({ uid, type, payload: payload ?? null, createdAt: admin.firestore.Timestamp.now() });

    const ctx = await loadContext(uid);
    const policy = await applyRules({ type, ctx, uid });
    if (policy.blocked) return res.json({ ok: true, decision: "none", reason: policy.reason });

    const decision = await askGooseAgent({ uid, type, ctx });
    await persistDecision(uid, type, decision);

    const result = await routeAction(uid, decision);
    return res.json({ ok: true, result });
  } catch (e: any) {
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

function toMillis(v: any) {
  if (!v && v !== 0) return 0;
  if (typeof v === "number") return v;
  if (v.toMillis && typeof v.toMillis === "function") return v.toMillis();
  return Date.parse(String(v)) || 0;
}

async function applyRules({ type, ctx, uid }: { type: string; ctx: any; uid: string }) {
  const now = Date.now();
  const last = toMillis(ctx.stats?.lastEngagedAt) ?? 0;
  const rateLimited = now - last < 1000 * 60 * 30; // 30m

  // tz-aware quiet hours using moment-timezone
  const tz = ctx.tz ?? process.env.DEFAULT_TZ ?? "UTC";
  const quietHoursPref = ctx.prefs?.quietHours ?? { start: parseInt(process.env.DEFAULT_QUIET_START || "22"), end: parseInt(process.env.DEFAULT_QUIET_END || "8") };
  const start = Number(quietHoursPref.start ?? 22);
  const end = Number(quietHoursPref.end ?? 8);
  const hour = Number(moment.tz(now, tz).hour());
  const inQuiet = start > end ? (hour >= start || hour < end) : (hour >= start && hour < end);

  // daily cap check (messages in last 24h)
  const cap = Number(process.env.DAILY_CAP ?? 2);
  let messagesCount = 0;
  try {
    const since = admin.firestore.Timestamp.fromMillis(now - 24 * 3600 * 1000);
    const snap = await db.collection("messages").where("uid", "==", uid).where("sentAt", ">=", since).get();
    messagesCount = snap.size;
  } catch (err) {
    console.warn("failed to count messages for daily cap check", err);
  }
  const capExceeded = messagesCount >= cap;

  const quiet = inQuiet;
  const blocked = rateLimited || quiet || capExceeded;
  const reason = rateLimited ? "rate_limit" : quiet ? "quiet_hours" : capExceeded ? "daily_cap" : undefined;
  return { blocked, reason, details: { rateLimited, quiet, capExceeded, messagesCount, cap } };
}

async function askGooseAgent(input: any) {
  // Call external Goose agent runtime if configured
  const url = process.env.GOOSE_AGENT_URL;
  const apiKey = process.env.GOOSE_API_KEY;
  if (url) {
    try {
      const resp = await axios.post(url, { input }, { headers: apiKey ? { Authorization: `Bearer ${apiKey}` } : undefined, timeout: 3000 });
      if (resp.data) return resp.data;
    } catch (e: any) {
      console.warn("Goose agent call failed:", e.message);
      // fallthrough to heuristic
    }
  }

  // fallback heuristic
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
