import {
  useEffect,
  useRef,
  useState,
  type PointerEvent,
  type KeyboardEvent,
} from "react";
import {
  COURT,
  LEVELS,
  PROFILES,
  aimPosition,
  createPractice,
  interceptPoint,
  other,
  ownPosition,
  playerName,
  presetAim,
  recoverySpot,
  redZone,
  startPoint,
  stepPractice,
  type Difficulty,
  type Profile,
  type Settings,
  type ShotKind,
  type Side,
  type Vec,
} from "./practice-engine";
import "./practice.css";

const shotNames: Record<ShotKind, string> = {
  cross: "Deep crosscourt",
  line: "Down the line",
  angle: "Short angle",
  lob: "High lob",
};
const movement = {
  w: [0, -1],
  s: [0, 1],
  a: [-1, 0],
  d: [1, 0],
  ArrowUp: [0, -1],
  ArrowDown: [0, 1],
  ArrowLeft: [-1, 0],
  ArrowRight: [1, 0],
};
const shotKeys: Record<string, [Side, ShotKind]> = {
  z: [0, "cross"],
  x: [0, "line"],
  c: [0, "angle"],
  v: [0, "lob"],
  i: [1, "cross"],
  o: [1, "line"],
  p: [1, "angle"],
  "[": [1, "lob"],
};

export default function PracticeCourt({ visible }: { visible: boolean }) {
  const [settings, setSettings] = useState<Settings>({
    mode: "bot",
    profile: "baseline",
    difficulty: "easy",
  });
  const state = useRef(createPractice(settings));
  const [, render] = useState(0);
  const [paused, setPaused] = useState(false);
  const court = useRef<SVGSVGElement>(null);
  const keys = useRef(new Set<string>());
  const pointers = useRef(
    new Map<number, { side: Side; destination: Vec; aiming: boolean }>(),
  );
  const current = state.current;
  const active = current.phase === "live";
  const update = () => render((value) => value + 1);

  useEffect(() => {
    if (!visible) {
      keys.current.clear();
      if (state.current.phase === "live") setPaused(true);
      return;
    }
    let animation = 0;
    let last = 0;
    let accumulated = 0;
    let paint = 0;
    function frame(now: number) {
      const elapsed = last ? Math.min((now - last) / 1000, 0.1) : 0;
      last = now;
      if (!paused) {
        accumulated += elapsed;
        while (accumulated >= 1 / 60) {
          for (const side of [0, 1] as Side[]) {
            if (side === 1 && state.current.settings.mode === "bot") continue;
            let dx = 0;
            let dy = 0;
            for (const key of keys.current) {
              if ((side === 0) !== !key.startsWith("Arrow")) continue;
              const direction = movement[key as keyof typeof movement];
              if (direction) {
                dx += direction[0];
                dy += direction[1];
              }
            }
            const p = state.current.players[side];
            if (dx || dy)
              p.destination = ownPosition(side, {
                x: p.pos.x + dx * 2,
                y: p.pos.y + dy * 2,
              });
          }
          stepPractice(state.current, 1 / 60);
          accumulated -= 1 / 60;
        }
        if (now - paint > 30 && state.current.phase !== "ready") {
          render((value) => value + 1);
          paint = now;
        }
      }
      animation = requestAnimationFrame(frame);
    }
    animation = requestAnimationFrame(frame);
    const loseFocus = () => {
      keys.current.clear();
      pointers.current.clear();
      if (state.current.phase === "live") setPaused(true);
    };
    const visibility = () => {
      if (document.hidden) loseFocus();
    };
    window.addEventListener("blur", loseFocus);
    document.addEventListener("visibilitychange", visibility);
    return () => {
      cancelAnimationFrame(animation);
      window.removeEventListener("blur", loseFocus);
      document.removeEventListener("visibilitychange", visibility);
    };
  }, [paused, visible]);

  function configure(next: Settings) {
    setSettings(next);
    state.current = createPractice(next);
    update();
  }
  function chooseShot(side: Side, kind: ShotKind) {
    const p = state.current.players[side];
    p.kind = kind;
    p.aim = presetAim(side, kind, p.pos);
    update();
  }
  function onKey(event: KeyboardEvent, down: boolean) {
    if (
      event.target instanceof HTMLInputElement ||
      event.target instanceof HTMLSelectElement
    )
      return;
    const key = event.key.length === 1 ? event.key.toLowerCase() : event.key;
    if (!(key in movement) && !(key in shotKeys)) return;
    event.preventDefault();
    if (!down) {
      keys.current.delete(key);
      if (key in movement) {
        const side = key.startsWith("Arrow") ? 1 : 0;
        const stillMoving = [...keys.current].some(
          (k) => k in movement && k.startsWith("Arrow") === (side === 1),
        );
        if (!stillMoving)
          state.current.players[side].destination = {
            ...state.current.players[side].pos,
          };
      }
      return;
    }
    if (key in movement) keys.current.add(key);
    const shot = shotKeys[key];
    if (shot && (shot[0] === 0 || settings.mode === "local"))
      chooseShot(...shot);
  }
  function coordinate(event: PointerEvent<SVGSVGElement>): Vec {
    const point = new DOMPoint(event.clientX, event.clientY);
    const matrix = event.currentTarget.getScreenCTM();
    return matrix
      ? point.matrixTransform(matrix.inverse())
      : { x: 4.115, y: 24 };
  }
  function pointerDown(event: PointerEvent<SVGSVGElement>) {
    if (!active || paused) return;
    event.currentTarget.focus({ preventScroll: true });
    event.currentTarget.setPointerCapture(event.pointerId);
    const point = coordinate(event);
    const side: Side = settings.mode === "bot" || point.y > COURT.net ? 0 : 1;
    pointers.current.set(event.pointerId, {
      side,
      destination: { ...state.current.players[side].destination },
      aiming: false,
    });
    applyPointer(side, point);
  }
  function applyPointer(side: Side, point: Vec) {
    const own = side === 0 ? point.y > COURT.net : point.y < COURT.net;
    if (own) state.current.players[side].destination = ownPosition(side, point);
    else {
      state.current.players[side].aim = aimPosition(side, point);
      state.current.players[side].kind = "cross";
    }
    update();
  }
  function pointerMove(event: PointerEvent<SVGSVGElement>) {
    const pointer = pointers.current.get(event.pointerId);
    if (pointer && !paused) {
      const point = coordinate(event);
      const acrossNet =
        pointer.side === 0 ? point.y < COURT.net : point.y > COURT.net;
      if (acrossNet && !pointer.aiming) {
        state.current.players[pointer.side].destination = pointer.destination;
        pointer.aiming = true;
      }
      if (pointer.aiming) {
        state.current.players[pointer.side].aim = aimPosition(
          pointer.side,
          point,
        );
        state.current.players[pointer.side].kind = "cross";
      } else applyPointer(pointer.side, point);
    }
  }
  function pointerUp(event: PointerEvent<SVGSVGElement>) {
    const pointer = pointers.current.get(event.pointerId);
    if (pointer && !paused) pointerMove(event);
    pointers.current.delete(event.pointerId);
  }
  function nextPoint() {
    keys.current.clear();
    startPoint(state.current);
    setPaused(false);
    update();
    court.current?.focus({ preventScroll: true });
  }
  function restart() {
    if (
      active &&
      !window.confirm("End this practice and choose a new opponent?")
    )
      return;
    state.current = createPractice(settings);
    setPaused(false);
    keys.current.clear();
    update();
  }
  const incomingSide = current.flight ? other(current.flight.hitter) : 0;
  const target = current.flight ? interceptPoint(current, incomingSide) : null;
  const recovery = current.flight
    ? recoverySpot(current.flight.hitter, current.flight.contact)
    : null;
  const ballHeight = current.flight
    ? Math.sin(
        (Math.min(0.8, current.flight.elapsed / current.flight.duration) /
          0.8) *
          Math.PI,
      ) *
      current.flight.loft *
      0.55
    : 0;

  return (
    <section
      className="practice"
      onKeyDown={(event) => onKey(event, true)}
      onKeyUp={(event) => onKey(event, false)}
    >
      <header className="practice-heading">
        <div>
          <p className="eyebrow">THE POSITIONING LAB</p>
          <h2>
            Win the space.
            <br />
            <em>The points will follow.</em>
          </h2>
        </div>
        <p>
          Read the ball early. Move with purpose. Learn which shots are worth
          asking your opponent to hit.
        </p>
      </header>
      {current.phase === "ready" && (
        <section className="practice-setup" aria-label="Practice settings">
          <div className="practice-options">
            <fieldset>
              <legend>Play against</legend>
              <div className="practice-segments">
                {(["bot", "local"] as const).map((mode) => (
                  <button
                    key={mode}
                    aria-pressed={settings.mode === mode}
                    onClick={() => configure({ ...settings, mode })}
                  >
                    {mode === "bot"
                      ? "A coaching bot"
                      : "Another player · local"}
                  </button>
                ))}
              </div>
            </fieldset>
            <fieldset>
              <legend>Difficulty</legend>
              <div className="practice-segments">
                {(["easy", "medium", "tough"] as Difficulty[]).map(
                  (difficulty) => (
                    <button
                      key={difficulty}
                      aria-pressed={settings.difficulty === difficulty}
                      onClick={() => configure({ ...settings, difficulty })}
                    >
                      {difficulty}
                      <small>
                        {Math.round(LEVELS[difficulty].accuracy * 10)}/10
                        on-time shots
                      </small>
                    </button>
                  ),
                )}
              </div>
            </fieldset>
          </div>
          {settings.mode === "bot" && (
            <fieldset className="profile-picker">
              <legend>Choose a playing style</legend>
              <div>
                {(
                  Object.entries(PROFILES) as [
                    Profile,
                    (typeof PROFILES)[Profile],
                  ][]
                ).map(([key, profile]) => (
                  <button
                    key={key}
                    aria-pressed={settings.profile === key}
                    onClick={() => configure({ ...settings, profile: key })}
                  >
                    <span className="profile-mark" aria-hidden="true">
                      {key === "baseline"
                        ? "↔"
                        : key === "aggressive"
                          ? "↗"
                          : key === "volley"
                            ? "↑"
                            : key === "allcourt"
                              ? "✣"
                              : "↶"}
                    </span>
                    <strong>{profile.name}</strong>
                    <span>{profile.description}</span>
                  </button>
                ))}
              </div>
            </fieldset>
          )}
          <p className="practice-note">
            {settings.mode === "local"
              ? "Two players share this screen. Player 1 uses WASD and Z/X/C/V. Player 2 uses arrow keys and I/O/P/[. On touchscreens, each player starts their gesture on their own half."
              : "Tap your half to move. Tap the far half to aim, or swipe across the net. You can also move with WASD and select shots with Z/X/C/V."}
          </p>
        </section>
      )}
      <div className="practice-layout">
        <div className="practice-play">
          <div className="practice-score">
            <div>
              <span className="player-dot" /> {playerName(current, 0)}{" "}
              <b>{current.score[0]}</b>
            </div>
            <span className="score-divider">:</span>
            <div>
              <b>{current.score[1]}</b> {playerName(current, 1)}{" "}
              <span className="player-dot opponent" />
            </div>
          </div>
          <div className="practice-status">
            <span>{settings.difficulty} · First to 7, win by 2</span>
            <span>
              {current.rally
                ? `${current.rally} shots · ${current.lastContact}`
                : "Footwork practice"}
            </span>
          </div>
          <div className="practice-court-wrap">
            <svg
              ref={court}
              className="practice-court"
              viewBox="-2.2 -3.2 12.63 30.17"
              role="img"
              aria-label="Interactive practice court. Tap your half to move, swipe across the net to aim. Keyboard players use the movement and shot controls below."
              tabIndex={0}
              onPointerDown={pointerDown}
              onPointerMove={pointerMove}
              onPointerUp={pointerUp}
              onPointerCancel={(event) =>
                pointers.current.delete(event.pointerId)
              }
            >
              <rect
                x="-2.2"
                y="-3.2"
                width="12.63"
                height="30.17"
                rx=".35"
                fill="#213f35"
              />
              <rect width="8.23" height="23.77" fill="#49725b" />
              <g className="practice-red">
                <rect width=".85" height="23.77" />
                <rect x="7.38" width=".85" height="23.77" />
                <rect width="8.23" height=".8" />
                <rect y="22.97" width="8.23" height=".8" />
                <rect x=".85" y="6.885" width="1.15" height="10" />
                <rect x="6.23" y="6.885" width="1.15" height="10" />
              </g>
              <g fill="none" stroke="#eeefe1" strokeWidth=".055">
                <rect width="8.23" height="23.77" />
                <path d="M0 5.485H8.23M0 18.285H8.23M4.115 5.485V18.285M3.9 0H4.33M3.9 23.77H4.33" />
              </g>
              <path d="M-1 11.885H9.23" stroke="#f9f6dc" strokeWidth=".11" />
              <path d="M-1 12.08H9.23" stroke="#162b2466" strokeWidth=".16" />
              <text x="4.115" y="-2.3" className="court-label">
                {playerName(current, 1)}
              </text>
              <text x="4.115" y="26.1" className="court-label">
                {playerName(current, 0)}
              </text>
              {active && recovery && (
                <g className="coverage-marker">
                  <circle cx={recovery.x} cy={recovery.y} r=".75" />
                  <text x={recovery.x} y={recovery.y + 1.15}>
                    RECOVER
                  </text>
                </g>
              )}
              {active && current.flight && (
                <>
                  <path
                    d={`M${current.flight.from.x} ${current.flight.from.y}L${current.flight.landing.x} ${current.flight.landing.y}`}
                    stroke="#e6eea544"
                    strokeWidth=".045"
                    strokeDasharray=".2 .2"
                    fill="none"
                  />
                  <circle
                    cx={current.flight.landing.x}
                    cy={current.flight.landing.y}
                    r=".22"
                    fill="none"
                    stroke="#e1ea8f"
                    strokeWidth=".055"
                  />
                  {target && (
                    <g>
                      <circle
                        cx={target.x}
                        cy={target.y}
                        r=".65"
                        className="contact-marker"
                      />
                      <text
                        x={target.x}
                        y={target.y + 1}
                        className="contact-label"
                      >
                        MEET HERE
                      </text>
                    </g>
                  )}
                </>
              )}
              {current.players.map((p, index) => (
                <g key={index}>
                  {active && (
                    <>
                      <path
                        d={`M${p.pos.x} ${p.pos.y}L${p.destination.x} ${p.destination.y}`}
                        stroke={index ? "#edc69266" : "#a5dbe366"}
                        strokeDasharray=".13 .13"
                        strokeWidth=".04"
                      />
                      <circle
                        cx={p.destination.x}
                        cy={p.destination.y}
                        r=".13"
                        fill="none"
                        stroke={index ? "#edc692" : "#a5dbe3"}
                        strokeWidth=".05"
                      />
                    </>
                  )}
                  {p.aim && (
                    <g
                      stroke={redZone(p.aim) ? "#ffb3a2" : "#d9ed90"}
                      strokeWidth=".055"
                    >
                      <circle cx={p.aim.x} cy={p.aim.y} r=".32" fill="none" />
                      <path
                        d={`M${p.aim.x - 0.5} ${p.aim.y}h1M${p.aim.x} ${p.aim.y - 0.5}v1`}
                      />
                    </g>
                  )}
                  <ellipse
                    cx={p.pos.x}
                    cy={p.pos.y + 0.15}
                    rx=".45"
                    ry=".27"
                    fill="#0c282d66"
                  />
                  <circle
                    cx={p.pos.x}
                    cy={p.pos.y}
                    r=".38"
                    fill={index ? "#e3b77c" : "#a8d9e4"}
                    stroke="#f5f3df"
                    strokeWidth=".07"
                  />
                  <text
                    x={p.pos.x}
                    y={p.pos.y + 0.12}
                    className="player-number"
                  >
                    {index + 1}
                  </text>
                  <ellipse
                    cx={p.pos.x + 0.53}
                    cy={p.pos.y + (index ? 0.1 : -0.1)}
                    rx=".13"
                    ry=".25"
                    fill="none"
                    stroke="#f5f3df"
                    strokeWidth=".045"
                  />
                </g>
              ))}
              <circle
                cx={current.ball.x}
                cy={current.ball.y + 0.12}
                r=".12"
                fill="#12251c66"
              />
              <circle
                cx={current.ball.x}
                cy={current.ball.y - ballHeight}
                r=".14"
                fill="#eafc6c"
                stroke="#fff9"
                strokeWidth=".025"
              />
            </svg>
            {(current.phase !== "live" || paused) && (
              <div className="court-overlay">
                <span>
                  {paused
                    ? "Take a breath"
                    : current.phase === "finished"
                      ? `${current.score[0] > current.score[1] ? playerName(current, 0) : playerName(current, 1)} wins`
                      : current.phase === "ready"
                        ? "Feet first. Then the shot."
                        : "Take the lesson into the next point."}
                </span>
                {!paused &&
                  (current.phase === "point" ||
                    current.phase === "finished") && (
                    <div className="point-explanation">
                      <p>{current.feedback.reason}</p>
                      <p>{current.feedback.tip}</p>
                    </div>
                  )}
                <button
                  className="practice-primary"
                  onClick={
                    paused
                      ? () => setPaused(false)
                      : current.phase === "finished"
                        ? restart
                        : nextPoint
                  }
                >
                  {paused
                    ? "Resume practice"
                    : current.phase === "ready"
                      ? "Start practice"
                      : current.phase === "finished"
                        ? "New practice"
                        : "Next point"}{" "}
                  →
                </button>
              </div>
            )}
          </div>
          <div className="court-key">
            <span>
              <i className="key-contact" /> Contact point
            </span>
            <span>
              <i className="key-recovery" /> Recovery position
            </span>
            <span>
              <i className="key-risk" /> Red zone · less margin
            </span>
          </div>
          <div className="practice-actions">
            <button
              disabled={!active}
              onClick={() => setPaused((value) => !value)}
            >
              {paused ? "Resume" : "Pause"}
            </button>
            <button onClick={restart} disabled={current.phase === "ready"}>
              Change opponent / restart
            </button>
          </div>
        </div>
        <aside className="practice-sidebar">
          <section
            className={`coach-card ${current.feedback.tone}`}
            aria-live="polite"
            aria-atomic="true"
          >
            <p className="eyebrow">COURTSIDE COACH</p>
            <h3>{current.feedback.title}</h3>
            <p>{current.feedback.reason}</p>
            <div className="coach-tip">{current.feedback.tip}</div>
          </section>
          <section className="shot-controls">
            <h3>Your next shot</h3>
            <p>
              Aim before contact. The swing happens when you reach the ball.
            </p>
            {([0, 1] as Side[])
              .filter((side) => side === 0 || settings.mode === "local")
              .map((side) => (
                <fieldset key={side}>
                  <legend>
                    {settings.mode === "local"
                      ? `Player ${side + 1} · ${side === 0 ? "WASD" : "arrow keys"} to move`
                      : "WASD to move · tap or drag on your half"}
                  </legend>
                  <div>
                    {(Object.keys(shotNames) as ShotKind[]).map(
                      (kind, index) => (
                        <button
                          key={kind}
                          aria-pressed={current.players[side].kind === kind}
                          onClick={() => chooseShot(side, kind)}
                        >
                          <span>{shotNames[kind]}</span>
                          <kbd>
                            {side === 0
                              ? ["Z", "X", "C", "V"][index]
                              : ["I", "O", "P", "["][index]}
                          </kbd>
                        </button>
                      ),
                    )}
                  </div>
                  <button
                    className="recover-button"
                    disabled={!active}
                    onClick={() => {
                      const f = state.current.flight;
                      state.current.players[side].destination = recoverySpot(
                        side,
                        f?.hitter === side
                          ? f.contact
                          : state.current.players[other(side)].pos,
                      );
                      update();
                    }}
                  >
                    Move to recovery position ↶
                  </button>
                </fieldset>
              ))}
          </section>
          <section className="practice-insight">
            <h3>Position earns consistency.</h3>
            <p>
              <strong>
                {Math.round(LEVELS[settings.difficulty].accuracy * 100)}%
                on-time success
              </strong>{" "}
              on {settings.difficulty}. Arrive within 0.85 m, settle for 0.18
              seconds, and slow below 2.2 m/s. Late, running, or stretched
              contact has a lower chance.
            </p>
            <p>
              These are long-run probabilities. Player speed is capped at 6 m/s,
              with gradual acceleration and braking. Swiping faster never moves
              a player faster.
            </p>
            <p>
              Red zones are the lines and short-angle corners. Invite the
              opponent to take that risk while you protect the higher-percentage
              space.
            </p>
            <div className="balance-stat">
              <strong>
                {current.balanced[0]} / {current.attempts[0]}
              </strong>
              <span>
                balanced contacts{" "}
                {settings.mode === "local" ? "· Player 1" : ""}
              </span>
            </div>
          </section>
          <details className="practice-history">
            <summary>
              Point-by-point coaching ({current.history.length})
            </summary>
            {current.history.length ? (
              current.history.map((feedback, i) => (
                <article key={`${i}-${feedback.title}`}>
                  <strong>{feedback.title}</strong>
                  <p>{feedback.reason}</p>
                  <p>{feedback.tip}</p>
                </article>
              ))
            ) : (
              <p>Your latest eight point reviews will appear here.</p>
            )}
          </details>
        </aside>
      </div>
      <p className="practice-disclosure">
        A positioning simulation with assisted swings and an automatic opening
        serve. This practice session stays in this tab.{" "}
        {settings.mode === "local"
          ? "Local two-player play uses one shared device."
          : "Bot profiles model playing tendencies; individual shots include variation."}
      </p>
    </section>
  );
}
