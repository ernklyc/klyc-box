// The app talks to Firestore over REST, not the SDK. This posts the exact request body the Swift
// code produces (fixtures/commit-body.json, checked by CommunityReportTests) to the emulator that
// runs the real rules, as a signed-in player. Run with `npm run test:rules`.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const host = process.env.FIRESTORE_EMULATOR_HOST;
const fixture = readFileSync(new URL("./fixtures/commit-body.json", import.meta.url), "utf8")
  .replaceAll("test-proj", "demo-klyc-box");

const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
const token = (uid) => `${b64({ alg: "none", typ: "JWT" })}.${b64({ user_id: uid, sub: uid, iss: "https://securetoken.google.com/demo-klyc-box", aud: "demo-klyc-box", firebase: { sign_in_provider: "anonymous" } })}.`;

async function commit(body, uid) {
  const res = await fetch(`http://${host}/v1/projects/demo-klyc-box/databases/(default)/documents:commit`, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...(uid ? { Authorization: `Bearer ${token(uid)}` } : {}) },
    body,
  });
  return res.status;
}
const forUid = (uid) => fixture.replaceAll("440_UID", `440_${uid}`);

test("the app's own request body is accepted by the real rules for the signed-in owner", async () => {
  assert.equal(await commit(forUid("abc"), "abc"), 200);
});
test("the same body is refused for another player, and without a sign-in", async () => {
  assert.equal(await commit(forUid("abc"), "someone-else"), 403);
  assert.equal(await commit(forUid("abc"), null), 403);
});
test("a client-supplied time instead of the server transform is refused", async () => {
  const body = JSON.parse(forUid("abc"));
  delete body.writes[0].updateTransforms;
  body.writes[0].update.fields.updatedAt = { timestampValue: "2020-01-01T00:00:00Z" };
  assert.equal(await commit(JSON.stringify(body), "abc"), 403);
});
test("the app's delete request body removes the player's own report only", async () => {
  const del = (uid, owner) => JSON.stringify({ writes: [{ delete: `projects/demo-klyc-box/databases/(default)/documents/reports/440_${owner}` }] });
  assert.equal(await commit(forUid("abc"), "abc"), 200);
  assert.equal(await commit(del("zzz", "abc"), "zzz"), 403);
  assert.equal(await commit(del("abc", "abc"), "abc"), 200);
});
