import { test } from "node:test";
import assert from "node:assert/strict";
import { aggregate } from "./aggregate.mjs";

const r = (appid, works, rating) => ({ appid, works, rating });

test("totals per game, rounded", () => {
  const out = aggregate([r(1, true, 5), r(1, true, 4), r(1, false, 2), r(1, true, 4)]);
  assert.deepEqual(out.games[1], { reports: 4, works: 3, worksShare: 0.75, rating: 3.8 });
});

test("a game with fewer than the minimum is not published", () => {
  const out = aggregate([r(7, true, 5), r(7, true, 5), r(8, true, 3), r(8, false, 1), r(8, true, 2)]);
  assert.equal(out.games[7], undefined, "two reports stay private");
  assert.equal(out.games[8].reports, 3);
});

test("malformed reports are ignored, not counted", () => {
  const out = aggregate([r(1, true, 5), r(1, true, 5), r(1, true, 5), { appid: "1", works: true, rating: 5 }, r(1, "yes", 5), r(1, true, 9), r(1, true, 0), r(-3, true, 5), null ?? {}]);
  assert.equal(out.games[1].reports, 3);
  assert.deepEqual(Object.keys(out.games), ["1"]);
});

test("no reports gives an empty file", () => {
  assert.deepEqual(aggregate([]).games, {});
});

test("the minimum can be raised", () => {
  const out = aggregate([r(1, true, 5), r(1, true, 5), r(1, true, 5)], 5);
  assert.deepEqual(out.games, {});
});

test("an account that floods the collection is ignored, honest players still count", async () => {
  const { MAX_REPORTS_PER_PLAYER } = await import("./aggregate.mjs");
  const flood = Array.from({ length: MAX_REPORTS_PER_PLAYER + 1 }, (_, i) => ({ appid: 1000 + i, works: true, rating: 5, uid: "spam" }));
  const honest = ["a", "b", "c"].map((uid) => ({ appid: 7, works: true, rating: 4, uid }));
  const out = aggregate([...flood, ...honest]);
  assert.deepEqual(Object.keys(out.games), ["7"]);
  assert.equal(out.games[7].reports, 3);
});
