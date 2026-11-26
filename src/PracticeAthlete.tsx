import clips from "./practice-poses.json";
import { interceptPoint, type Practice, type Side } from "./practice-engine";

type Frame = typeof clips.rest;
const joint = Object.fromEntries(clips.joints.map((name, i) => [name, i]));

function mix(a: Frame, b: Frame, t: number): Frame {
  return {
    t: a.t + (b.t-a.t)*t, heel: a.heel + (b.heel-a.heel)*t,
    joints: a.joints.map((p, i) => p.map((n, axis) => n + (b.joints[i][axis]-n)*t)),
  };
}
function sample(frames: Frame[], t: number) {
  const i = frames.findIndex(frame => frame.t >= t);
  if (i < 0) return frames[frames.length-1];
  if (i === 0) return frames[0];
  return mix(frames[i-1], frames[i], (t-frames[i-1].t)/(frames[i].t-frames[i-1].t));
}

function pose(game: Practice, side: Side, serveLead: number, reduceMotion: boolean) {
  const f = game.flight;
  if (!f || game.phase === "ready") return clips.rest;
  if (game.phase !== "live") {
    if (side === 1 && game.racketReaction) {
      const frame = sample(clips.reaction, game.resultElapsed);
      return reduceMotion ? mix(clips.rest, frame, 0.32) : frame;
    }
    return mix(clips.ready, clips.rest, Math.min(1, game.resultElapsed / 0.35));
  }
  if (serveLead > 0 && side !== f.hitter) return mix(clips.rest, clips.ready, Math.min(1, (0.74-serveLead)/0.26));
  if (f.hitter === side) {
    const frames = f.serve ? clips.serve : f.volley ? (f.backhand ? clips.backVolley : clips.foreVolley)
      : f.backhand ? clips.backhand : clips.forehand;
    return sample(frames, f.elapsed - serveLead);
  }
  if (f.fault) return clips.ready;
  const target = interceptPoint(game, side), player = game.players[side].pos;
  const back = (target.x-player.x)*(side === 0 ? 1 : -1) < 0;
  const volley = target.y !== f.contact.y;
  const impactTime = volley ? f.duration * 0.8 * (target.y-f.from.y)/(f.landing.y-f.from.y) : f.duration;
  const remaining = Math.max(0, impactTime - f.elapsed);
  if (Math.hypot(target.x-player.x, target.y-player.y) > 1.4 + remaining * 6) return clips.ready;
  return sample(volley ? (back ? clips.backVolley : clips.foreVolley) : back ? clips.backhand : clips.forehand, -remaining);
}

export function PracticeAthlete({ game, side, serveLead, reduceMotion }: {
  game: Practice; side: Side; serveLead: number; reduceMotion: boolean;
}) {
  const frame = pose(game, side, serveLead, reduceMotion), player = game.players[side];
  const sign = side === 0 ? 1 : -1;
  const kit = side === 0 ? "#a8d9e4" : "#efb27e", skin = side === 0 ? "#cd987c" : "#a56f53";
  const stride = game.phase === "live" && !reduceMotion
    ? Math.min(1, Math.hypot(player.velocity.x, player.velocity.y)/4) * Math.sin(game.time*17) : 0;
  function point(name: string) {
    const [x,h,z] = frame.joints[joint[name]];
    const leg = name.endsWith("Shoe") ? 1 : name.endsWith("Knee") ? 0.5 : 0;
    const step = (name.startsWith("left") ? 1 : -1) * stride * leg;
    return {x: sign*(x + z*0.10)/1000 + player.velocity.x*step*0.028,
      y: (-h*0.83-sign*z*0.55)/1000 + player.velocity.y*step*0.022 - Math.max(0,step)*0.07};
  }
  function path(names: string[]) { return names.map(name => { const p = point(name); return p.x+","+p.y; }).join(" "); }
  const head = point("head"), hand = point("grip"), strings = point("strings");
  const tilt = Math.atan2(strings.y-hand.y, strings.x-hand.x)*180/Math.PI;
  const relaxed = frame.heel / 1000;
  return <g transform={`translate(${player.pos.x} ${player.pos.y})`} pointerEvents="none" aria-hidden="true" strokeLinecap="round" strokeLinejoin="round">
    <ellipse cy=".03" rx=".39" ry=".12" fill="#0c211c55"/>
    {["left","right"].map(s => {
      const foot = point(s+"Shoe");
      return <g key={s}>
        <polyline points={path([s+"Hip",s+"Knee",s+"Shoe"])} fill="none" stroke={skin} strokeWidth=".14"/>
        <path d={`M${foot.x-0.065} ${foot.y-0.02-relaxed*0.15}l0.15 ${0.02+relaxed*0.18}`} stroke="#edf0e4" strokeWidth=".105"/>
      </g>;
    })}
    {["left","right"].map(s => {
      const hip = point(s+"Hip"), knee = point(s+"Knee");
      return <line key={s} x1={hip.x} y1={hip.y} x2={(hip.x+knee.x)/2} y2={(hip.y+knee.y)/2} stroke="#243c47" strokeWidth=".225"/>;
    })}
    <polygon points={path(["leftHip","leftShoulder","rightShoulder","rightHip"])} fill={kit} stroke={kit} strokeWidth=".14"/>
    <polyline points={path(["leftHip","leftShoulder","rightShoulder"])} fill="none" stroke="#fff6" strokeWidth=".042"/>
    <circle cx={head.x} cy={head.y} r=".135" fill={skin}/>
    <path d={`M${head.x-0.111} ${head.y-0.045}q0.07 -0.14 0.219 -0.02`} stroke="#38332e" fill="none" strokeWidth=".076"/>
    {["left","right"].map(s => <polyline key={s} points={path([s+"Shoulder",s+"Elbow",s === "right" ? "grip" : "leftHand"])} fill="none" stroke={skin} strokeWidth=".099"/>)}
    <line x1={hand.x} y1={hand.y} x2={strings.x} y2={strings.y} stroke="#353f43" strokeWidth=".043"/>
    <ellipse cx={strings.x} cy={strings.y} rx=".172" ry=".115" transform={`rotate(${tilt} ${strings.x} ${strings.y})`} fill="#d6f4ea44" stroke="#e7ead4" strokeWidth=".035"/>
  </g>;
}
