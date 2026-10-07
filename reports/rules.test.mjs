// Firestore rules test: run with `npm run test:rules` (needs Java for the emulator).
import { test, before, after, beforeEach } from "node:test";
import { readFileSync } from "node:fs";
import { initializeTestEnvironment, assertFails, assertSucceeds } from "@firebase/rules-unit-testing";
import { doc, setDoc, getDoc, deleteDoc, serverTimestamp } from "firebase/firestore";

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-klyc-box",
    firestore: { rules: readFileSync(new URL("./firestore.rules", import.meta.url), "utf8") },
  });
});
after(async () => env.cleanup());
beforeEach(async () => env.clearFirestore());

const good = () => ({ appid: 440, works: true, rating: 4, chip: "M4", macos: "15.1", engine: "wine 10", renderer: "dxmt", note: "ok", updatedAt: serverTimestamp() });
const as = (uid) => env.authenticatedContext(uid).firestore();

test("a signed-in player writes their own valid report", async () => {
  await assertSucceeds(setDoc(doc(as("u1"), "reports/440_u1"), good()));
});
test("a player can update their own report", async () => {
  const db = as("u1");
  await assertSucceeds(setDoc(doc(db, "reports/440_u1"), good()));
  await assertSucceeds(setDoc(doc(db, "reports/440_u1"), { ...good(), rating: 2 }));
});
test("anonymous (signed out) cannot write", async () => {
  await assertFails(setDoc(doc(env.unauthenticatedContext().firestore(), "reports/440_u1"), good()));
});
test("cannot write under another player's id", async () => {
  await assertFails(setDoc(doc(as("u2"), "reports/440_u1"), good()));
});
test("document id must match the appid", async () => {
  await assertFails(setDoc(doc(as("u1"), "reports/999_u1"), good()));
});
test("nobody can read reports, not even the author", async () => {
  await assertSucceeds(setDoc(doc(as("u1"), "reports/440_u1"), good()));
  await assertFails(getDoc(doc(as("u1"), "reports/440_u1")));
  await assertFails(getDoc(doc(as("u2"), "reports/440_u1")));
});
test("rating must be 1 to 5", async () => {
  await assertFails(setDoc(doc(as("u1"), "reports/440_u1"), { ...good(), rating: 0 }));
  await assertFails(setDoc(doc(as("u1"), "reports/440_u1"), { ...good(), rating: 6 }));
  await assertFails(setDoc(doc(as("u1"), "reports/440_u1"), { ...good(), rating: 4.5 }));
});
test("types are checked", async () => {
  await assertFails(setDoc(doc(as("u1"), "reports/440_u1"), { ...good(), works: "yes" }));
  await assertFails(setDoc(doc(as("u1"), "reports/440_u1"), { ...good(), appid: "440" }));
});
test("note is limited to 200 characters", async () => {
  await assertSucceeds(setDoc(doc(as("u1"), "reports/440_u1"), { ...good(), note: "a".repeat(200) }));
  await assertFails(setDoc(doc(as("u1"), "reports/440_u1"), { ...good(), note: "a".repeat(201) }));
});
test("unknown fields are refused", async () => {
  await assertFails(setDoc(doc(as("u1"), "reports/440_u1"), { ...good(), email: "a@b.c" }));
});
test("missing required fields are refused", async () => {
  const { rating, ...noRating } = good();
  await assertFails(setDoc(doc(as("u1"), "reports/440_u1"), noRating));
});
test("updatedAt must be the server time, not a client value", async () => {
  await assertFails(setDoc(doc(as("u1"), "reports/440_u1"), { ...good(), updatedAt: new Date("2020-01-01") }));
});
test("a player can delete their own report, not another's", async () => {
  await assertSucceeds(setDoc(doc(as("u1"), "reports/440_u1"), good()));
  await assertFails(deleteDoc(doc(as("u2"), "reports/440_u1")));
  await assertSucceeds(deleteDoc(doc(as("u1"), "reports/440_u1")));
});
test("every other collection is closed", async () => {
  await assertFails(setDoc(doc(as("u1"), "other/x"), { a: 1 }));
  await assertFails(getDoc(doc(as("u1"), "other/x")));
});
