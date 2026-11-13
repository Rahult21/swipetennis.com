import assert from "node:assert/strict";
import test from "node:test";

import {
  classifyFinalShot,
  classifyServe,
  isSinglesLanding,
  selectServeLanding,
  validateServeLanding,
} from "../src/tennis-rules.ts";

test("deuce-court serve must land in the diagonally opposite left service box", () => {
  assert.deepEqual(validateServeLanding({ x: 30, y: 60 }, true), { valid: true, reason: "legal" });
  assert.deepEqual(validateServeLanding({ x: 70, y: 60 }, true), { valid: false, reason: "wrong-box" });
});

test("ad-court serve must land in the diagonally opposite right service box", () => {
  assert.deepEqual(validateServeLanding({ x: 70, y: 60 }, false), { valid: true, reason: "legal" });
  assert.deepEqual(validateServeLanding({ x: 30, y: 60 }, false), { valid: false, reason: "wrong-box" });
});

test("service-box lines count as in", () => {
  assert.equal(validateServeLanding({ x: 12, y: 45 }, true).valid, true);
  assert.equal(validateServeLanding({ x: 50, y: 60 }, true).valid, true);
  assert.equal(validateServeLanding({ x: 50, y: 60 }, false).valid, true);
  assert.equal(validateServeLanding({ x: 88, y: 45 }, false).valid, true);
});

test("serve faults distinguish net, long, wide, and wrong service box", () => {
  assert.equal(validateServeLanding({ x: 30, y: 100 }, true).reason, "net");
  assert.equal(validateServeLanding({ x: 30, y: 30 }, true).reason, "long");
  assert.equal(validateServeLanding({ x: 5, y: 60 }, true).reason, "wide");
  assert.equal(validateServeLanding({ x: 70, y: 60 }, true).reason, "wrong-box");
});

test("only an invalid second serve is a double fault", () => {
  assert.equal(classifyServe(1, { x: 70, y: 60 }, true).kind, "first-fault");
  assert.equal(classifyServe(2, { x: 70, y: 60 }, true).kind, "double-fault");
  assert.equal(classifyServe(2, { x: 30, y: 60 }, true).kind, "legal");
});

test("finger-up location overrides an earlier slowdown marker for a serve", () => {
  const earlyPause = { x: 70, y: 60 };
  const legalFingerUp = { x: 30, y: 60 };
  assert.equal(selectServeLanding(earlyPause, legalFingerUp, 1), legalFingerUp);
  assert.equal(classifyServe(2, selectServeLanding(earlyPause, legalFingerUp, 1), true).kind, "legal");
});

test("singles lines count as in and alleys are out", () => {
  assert.equal(isSinglesLanding({ x: 12, y: 8 }), true);
  assert.equal(isSinglesLanding({ x: 88, y: 152 }), true);
  assert.equal(isSinglesLanding({ x: 5, y: 60 }), false);
  assert.equal(isSinglesLanding({ x: 95, y: 100 }), false);
});

test("return and rally endings produce tennis-correct winners", () => {
  assert.deepEqual(classifyFinalShot(1, { x: 40, y: 120 }, false), { winner: "hitter", outcome: "Return winner" });
  assert.deepEqual(classifyFinalShot(1, { x: 4, y: 120 }, true), { winner: "opponent", outcome: "Return error" });
  assert.deepEqual(classifyFinalShot(2, { x: 40, y: 60 }, false), { winner: "hitter", outcome: "Winner" });
  assert.deepEqual(classifyFinalShot(2, { x: 95, y: 60 }, false), { winner: "opponent", outcome: "unforced error" });
  assert.deepEqual(classifyFinalShot(2, { x: 95, y: 60 }, true), { winner: "opponent", outcome: "forced error" });
});
