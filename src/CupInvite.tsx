import { useState } from "react";
import "./cup.css";

export default function CupInvite() {
  const segment = window.location.pathname.split("/")[2] || "";
  const code = /^[A-HJ-NP-Z2-9]{8}$/i.test(segment) ? segment.toUpperCase() : null;
  const [message, setMessage] = useState("");
  const invalid = Boolean(segment) && !code;
  async function copyCode() {
    if (!code) return;
    try { await navigator.clipboard.writeText(code); setMessage("Cup code copied."); }
    catch { setMessage("Select the code above to copy it, then paste it into Quick Cup in the app."); }
  }
  return <div className="cup-page">
    <header className="cup-header"><a className="wordmark" href="/" aria-label="SwipeTennis home"><span className="brand-ball" aria-hidden="true"/>swipe<span>tennis</span><span className="brand-period">.</span></a><span>QUICK CUP</span></header>
    <main className="cup-invite">
      <div className="cup-art" aria-hidden="true">
        <div className="cup-draw"><span>You</span><span>A friend</span><span>Open spot</span><span>Open spot</span></div>
        <svg viewBox="0 0 200 140" fill="none"><path d="M54 18h92v32c0 35-19 53-46 53S54 85 54 50V18Z" stroke="currentColor" strokeWidth="5"/><path d="M54 29H28v13c0 23 11 35 31 35m87-48h26v13c0 23-11 35-31 35M100 104v25m-28 3h56" stroke="currentColor" strokeWidth="5" strokeLinecap="round"/><circle cx="100" cy="55" r="16" fill="currentColor"/><path d="M87 44c12 7 14 18 11 26m13-28c-12 7-14 18-11 28" stroke="#183d30" strokeWidth="2"/></svg>
        <p>FOUR PLAYERS. ONE TROPHY.</p>
      </div>
      <section className="cup-copy" aria-labelledby="cup-heading">
        <p className="cup-eyebrow">YOUR NEXT RIVALRY STARTS HERE</p>
        <h1 id="cup-heading">{invalid ? "Check your invite." : code ? <>You’re invited<br/>to the <em>court.</em></> : <>A little competition.<br/><em>A lot to play for.</em></>}</h1>
        <p>{invalid ? "This invite code doesn’t look right. Ask your friend to share their eight-character cup code again." : "Two rounds to the trophy. Play your friends, with clearly labeled AI opponents filling open spots at your cup’s playing level."}</p>
        {code && <div className="cup-code"><span>YOUR CUP CODE</span><strong>{code}</strong><button type="button" onClick={copyCode}>Copy code</button></div>}
        {!invalid && <a className="cup-open" href={code ? `swipetennis://cup/${code}` : "swipetennis://cups"}>Open SwipeTennis</a>}
        <p className="cup-requirement">Quick Cup is played in the SwipeTennis app on iPhone or iPad. The app must already be installed. {code ? "You can also open Quick Cup in the app and enter this code." : "Open Quick Cup from the Court tab to create or join a cup."}</p>
        <p className="cup-message" role="status">{message}</p>
        <div className="cup-rules"><span>First to 7 · Win by 2</span><span>Friends + AI</span><span>No match powers</span></div>
        <a className="cup-home" href="/">Explore SwipeTennis on the web</a>
      </section>
    </main>
    <footer className="cup-footer">Bring your friends. Find your rhythm. See you on court.</footer>
  </div>;
}
