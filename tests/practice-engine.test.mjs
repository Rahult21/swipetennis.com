import test from "node:test";
import assert from "node:assert/strict";
import {
  createPractice,
  startPoint,
  stepPractice,
  contactChance,
  movePlayer,
  redZone,
  recoverySpot,
  PROFILES,
} from "../src/practice-engine.ts";

const settings = { mode: "bot", profile: "baseline", difficulty: "easy" };
function readyReturn(difficulty, randomValue) {
  const s = createPractice({ ...settings, difficulty });
  startPoint(s);
  const p = s.players[0];
  p.pos = { ...s.flight.contact };
  p.destination = { ...p.pos };
  p.settled = 0.4;
  s.flight.elapsed = s.flight.duration - 0.01;
  stepPractice(s, 0.02, () => randomValue);
  return s;
}

test("balanced on-time contact implements exactly the requested probabilities", () => {
  for (const [difficulty, expected] of [
    ["easy", 1],
    ["medium", 0.9],
    ["tough", 0.8],
  ]) {
    assert.equal(contactChance(difficulty, 0.2, 0.5, 0, false), expected);
    assert.equal(contactChance(difficulty, 0.2, 0.5, 0, true), expected);
    const outcomes = Array.from({ length: 100 }, (_, i) =>
      readyReturn(difficulty, (i + 0.5) / 100),
    );
    assert.equal(
      outcomes.filter((s) => !s.flight.fault).length,
      expected * 100,
    );
  }
});

test("late, running and stretched contacts lose margin, particularly at a risky target", () => {
  assert.ok(
    contactChance("easy", 0, 1.2, 5, true) <
      contactChance("easy", 0, 1.2, 5, false),
  );
  assert.ok(contactChance("easy", 0, 0.4, 0, false) < 1);
  assert.equal(contactChance("easy", 1, 1.36, 0, false), 0);
});

test("movement accelerates, respects the speed cap and brakes without teleporting", () => {
  const p = createPractice(settings).players[0];
  p.destination = { x: 9, y: 13 };
  const before = { ...p.pos };
  movePlayer(p, 1 / 60, 6);
  assert.ok(Math.hypot(p.pos.x - before.x, p.pos.y - before.y) < 0.01);
  for (let i = 0; i < 600; i++) {
    movePlayer(p, 1 / 60, 6);
    assert.ok(Math.hypot(p.velocity.x, p.velocity.y) <= 6.000001);
  }
  assert.ok(
    Math.hypot(p.pos.x - p.destination.x, p.pos.y - p.destination.y) < 0.03,
  );
});

test("a late frame cannot teleport a player across the court", () => {
  const s = createPractice(settings);
  startPoint(s);
  s.players[0].destination = { x: -1, y: 13 };
  const before = { ...s.players[0].pos };
  stepPractice(s, 20);
  assert.ok(
    Math.hypot(s.players[0].pos.x - before.x, s.players[0].pos.y - before.y) <
      0.1,
  );
});

test("unreachable balls always produce an explained miss and award the opponent", () => {
  const s = createPractice(settings);
  startPoint(s);
  s.flight.elapsed = s.flight.duration - 0.01;
  stepPractice(s, 0.02);
  assert.equal(s.phase, "point");
  assert.deepEqual(s.score, [0, 1]);
  assert.match(s.feedback.reason, /beyond the 1.35 m reach/);
  const score = [...s.score];
  stepPractice(s, 0.04);
  assert.deepEqual(s.score, score);
});

test("an execution error travels to its endpoint and explains the cause", () => {
  const s = readyReturn("tough", 0.99);
  assert.equal(s.flight.fault, "long");
  for (let i = 0; i < 200 && s.phase === "live"; i++) stepPractice(s, 0.02);
  assert.equal(s.phase, "point");
  assert.match(s.feedback.title, /missed long/);
  assert.match(s.feedback.reason, /timing error/);
});

test("red zones include lines and short-angle corners while deep central targets have margin", () => {
  assert.equal(redZone({ x: 0.4, y: 2 }), true);
  assert.equal(redZone({ x: 4, y: 0.4 }), true);
  assert.equal(redZone({ x: 1.5, y: 8 }), true);
  assert.equal(redZone({ x: 3, y: 2 }), false);
});

test("recovery bisects opponent angles and responds to their position", () => {
  const a = recoverySpot(0, { x: 0.5, y: 2 });
  const b = recoverySpot(0, { x: 7.7, y: 2 });
  assert.notEqual(a.x, b.x);
  assert.ok(a.x > 2 && a.x < 6.23);
  assert.ok(a.y > 23.77);
});

test("serve-and-volley approaches while baseline and retriever stay back", () => {
  for (const profile of Object.keys(PROFILES)) {
    const s = createPractice({ ...settings, profile });
    startPoint(s);
    assert.equal(s.approach, profile === "volley");
    if (profile === "volley") assert.equal(s.players[1].destination.y, 8);
    if (profile === "retriever") assert.equal(s.players[1].destination.y, -1.7);
  }
});

test("two-player mode does not overwrite the second player movement with bot decisions", () => {
  const s = createPractice({ ...settings, mode: "local" });
  s.score = [1, 0];
  startPoint(s);
  s.players[1].destination = { x: 7, y: 1 };
  for (let i = 0; i < 40; i++) stepPractice(s, 0.02);
  assert.deepEqual(s.players[1].destination, { x: 7, y: 1 });
});

test("practice needs a two-point lead and ends with a clear terminal state", () => {
  const s = createPractice(settings);
  s.score = [6, 6];
  startPoint(s);
  s.flight.elapsed = s.flight.duration - 0.01;
  stepPractice(s, 0.02);
  assert.equal(s.phase, "point");
  assert.deepEqual(s.score, [6, 7]);
  startPoint(s);
  s.flight.fault = "long";
  s.flight.elapsed = s.flight.duration;
  stepPractice(s, 0.02);
  assert.deepEqual(s.score, [6, 8]);
  assert.equal(s.phase, "finished");
  startPoint(s);
  assert.equal(s.phase, "finished");
});

test("bot red-zone winners receive tactical reassurance and red-zone misses earn credit", () => {
  for (const fault of [null, "wide"]) {
    const s = createPractice(settings);
    startPoint(s);
    s.flight.red = true;
    s.flight.fault = fault;
    s.flight.explanation = "A stretched contact left little margin.";
    s.flight.elapsed = s.flight.duration;
    stepPractice(s, 0.02);
    assert.equal(s.feedback.tone, "positive");
    assert.match(
      s.feedback.tip,
      fault ? /high-risk red-zone shot/ : /high-risk shot/,
    );
  }
});
