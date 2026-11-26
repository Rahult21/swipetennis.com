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
  pointSplitSummary,
  splitStep,
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
  assert.match(s.feedback.reason, /Your shot landed long.*chance of missing the target/);
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

test("approach requires an in-play return and its arrow uses the incoming five-metre bounce", async () => {
  const {canApproach, steerPlayer} = await import("../src/practice-engine.ts");
  for (const depth of [4.99, 5.0, 6.1]) {
    const game = createPractice(settings);
    startPoint(game);
    assert.equal(canApproach(game, game.server), false);
    const f = game.flight, p = game.players[0];
    f.serve = false;
    f.landing = {x: 5,y: 23.77-depth};
    f.contact = {x: 5,y: f.landing.y+1.1};
    p.pos = { ...f.contact }; p.destination = { ...p.pos }; p.settled = 0.3;
    f.elapsed = f.duration-0.001;
    stepPractice(game, 1/60, () => 0.01);
    assert.equal(canApproach(game,0), true);
    assert.equal(game.flight.returnedShort, depth >= 5);
    game.flight.fault = "long";
    const before = {...p.destination};
    steerPlayer(game,0,{x: 3, y: 14});
    assert.deepEqual(p.destination,before);
    assert.equal(canApproach(game,0),false);
  }
});

test("clean first volley enables quick human feet only in the forecourt", async () => {
  const {quickNetFeet} = await import("../src/practice-engine.ts");
  const game = createPractice(settings);
  startPoint(game);
  const f = game.flight, p = game.players[0];
  f.serve = false; f.from = {x: 4,y: 0}; f.landing = {x: 4,y: 22}; f.fault = null;
  f.elapsed = 0.55*f.duration;
  p.pos = {x: 4,y: 15.2}; p.destination = {...p.pos};
  assert.equal(quickNetFeet(game,0),false);
  stepPractice(game,1/60,() => 0.01);
  assert.equal(quickNetFeet(game,0),true);
  assert.equal(quickNetFeet(game,1),false);
  p.pos.y = 21;
  stepPractice(game,1/60,() => 0.01);
  assert.equal(p.madeNetVolley,false);
});

test("the bot racket cue respects consecutive points and a completed-game cooldown", () => {
  const game = createPractice(settings);
  function win(roll) {
    startPoint(game);
    game.flight.hitter = 1;
    game.flight.fault = "long"; game.flight.elapsed = game.flight.duration*0.8;
    stepPractice(game,1/60,roll);
  }
  win(() => 0);
  assert.equal(game.racketReaction,false);
  win(() => 0.9);
  assert.equal(game.racketReaction,false);
  const rolls = [0.2,0.9];
  win(() => rolls.shift());
  assert.equal(game.racketReaction,true);
  assert.equal(game.reactionCooldown,3);
  while (game.phase !== "finished") {
    win(() => 0);
    assert.equal(game.racketReaction,false);
  }
  assert.equal(game.reactionCooldown,2);
});

test("a split around the far bounce improves the next placement and the result explains the actual miss", () => {
  for (const timed of [true, false]) {
    const game = createPractice(settings);
    startPoint(game);
    const player = game.players[0], flight = game.flight;
    flight.serve = false;
    flight.hitter = 0;
    flight.from = {x: 1, y: 22};
    flight.landing = {x: 7.6, y: 1};
    flight.elapsed = flight.duration * (timed ? 0.8 : 0.2);
    splitStep(game, 0);
    splitStep(game, 0);
    function receive() {
      const f = game.flight;
      game.rally++;
      f.hitter = 1;
      f.serve = false;
      f.fault = null;
      f.from = {x: 7.6, y: 1};
      f.contact = {x: 1.1, y: 22.5};
      f.landing = {x: 1.1, y: 21.4};
      f.elapsed = f.duration - 0.001;
      player.pos = {...f.contact};
      player.destination = {...f.contact};
      player.settled = 0.3;
      player.kind = "line";
      stepPractice(game, 1/60, () => 0.90);
    }
    receive();
    assert.equal(player.lastReturn.accuracy, timed ? 0.96 : 0.8);
    if (timed) {
      assert.equal(game.flight.fault, null);
      assert.match(pointSplitSummary(game), /80% → 96%/);
      receive();
    }
    assert.ok(game.flight.fault);
    game.flight.elapsed = 0.8 * game.flight.duration;
    stepPractice(game, 1/60, () => 0.4);
    assert.match(game.feedback.reason, /Your shot landed.*shorter side.*lower-percentage.*crosscourt/);
    assert.match(pointSplitSummary(game), /No timed split/);
  }
});

test("a timed split can cap placement at 100% but cannot reach a missing ball", () => {
  for (const reached of [true, false]) {
    const game = createPractice(settings);
    startPoint(game);
    splitStep(game, 0, 0.25);
    if (reached) {
      game.players[0].pos = {...game.flight.contact};
      game.players[0].destination = {...game.flight.contact};
      game.players[0].settled = 0.3;
    }
    game.flight.elapsed = game.flight.duration - 0.001;
    stepPractice(game, 1/60, () => 0.999);
    if (reached) {
      assert.equal(game.players[0].lastReturn.accuracy, 1);
      assert.match(pointSplitSummary(game), /Timed split.*100%/);
    } else {
      assert.equal(game.phase, "point");
      assert.match(pointSplitSummary(game), /Timed split · ball stayed out of reach/);
    }
  }
});
