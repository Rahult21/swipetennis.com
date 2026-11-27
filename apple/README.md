# SwipeTennis for iPhone & iPad

SwipeTennis uses RealityKit for its 3D court and athletes, SpriteKit for court gestures and overlays, and SwiftUI for its iPhone and iPad screens. Open **SwipeTennis.xcodeproj**, select the **SwipeTennis** scheme, and run on an iPhone or iPad simulator. Requires Xcode 15 or later and iOS 17 or later; developed with Xcode 27.2. Gameplay runs natively. Apple sign-in and Coachability standings use the Cloudflare Worker/D1 service in **Backend**; follow [the deployment instructions](Backend/README.md) before signing in. Once signed in, completed points queue on the device when offline.

For a physical device, choose your Apple development team under Signing & Capabilities and use a unique bundle identifier if needed. The project deliberately contains no personal signing team. The app has not been submitted to TestFlight or the App Store.

## What carries over

| Website experience | Native app |
| --- | --- |
| Cream / forest / sage / tennis-yellow identity, serif headlines | Court home, native tab navigation, matching court graphics |
| Manual and swipe scoring | Both modes, switchable during a match |
| Names and default player | Match setup and saved profile; legacy UTR fields are retained only for archive compatibility |
| Four/six games, best of three, two sets + match tiebreak | Complete scoring engine with deuce, advantage, serving order, set and match points |
| First/second serve, ace, faults, winners, errors, shot position | Manual buttons and editable trace confirmation |
| Trace pauses, service-box checking, rally-end inference | Native drag gesture, 250 ms bounce capture, inferred results reviewed before scoring |
| Undo, point journal, scoring callouts | Full retained event log, reconstructive undo, live scoreboard |
| Match history, player filter, statistics, reports | Local JSON archive, journal, statistics and iOS ShareLink |
| Point-by-point replay, speed controls, demonstration | Court traces, reconstructed scores, scrubber, 0.5× / 1× / 2×, animated tutorial |
| Bot / local practice; easy / medium / tough | Native real-time practice and independent multi-touch for two players |
| Five bot styles and four shot choices | Baseline, aggressive, serve-and-volley, all-court, retriever; crosscourt, line, angle, lob |
| Footwork, reach, settling, recovery, red-zone risk, coaching | Swift port with fixed 120 Hz simulation; per-point explanations and contact statistics |
| First to seven, win by two; pause/restart | Practice defaults to a six-game advantage set; seven-point tiebreak is optional. Pause, restart, and rematch remain available. |

Completed matches archive automatically. Closing an unfinished match also keeps it in the journal. Active matches survive termination. On the practice court, the result card’s × advances to the next point. The courtside × pauses play and asks whether to save and leave, leave without saving, or cancel. Play & practice offers one saved match on this device to the account that played it. Resuming restores the rally and score. Starting a new match replaces the save. Website browser storage is not automatically imported or synchronized.

## Native play

- **Player & kit and Stroke studio.** On the Court tab, open Player & kit to choose an athlete, change clothing and view the kit from any angle. Stroke studio shows the actual serve, running return, forehand, backhand and volley at half speed. Drag across the court to orbit, freeze the load, contact or finish, or export the stroke as a video. The four-chapter Quick start in How to play uses footage from the same court and adds the touch gestures.

- **ST ranking:** Every account starts at **ST 4t** on a 1–10 scale. The tentative marker lasts for three completed online human matches. Opponent strength and the share of tiebreak points won change the rating; bots, practice, manual scoring, forfeits and disconnects never do. Account and cup screens show ST and human W/L, and completed human brackets show before/after rating changes. A 7–1 win earns more than 7–5 against the same opponent; outperforming the expected point share can raise ST even after a loss, and underperforming can lower it after a win. This is a UTR-inspired ST formula, not an official UTR rating. ST does not grant stronger shots or faster movement.

- **Quick Cup and Tour:** Invite friends to a four- or eight-player draw, find an ST opponent, or join the weekly Open in your division. Empty tournament seats receive labeled AI players near an entrant’s ST. A human rematch needs both players. Each player can review the last point at half speed and share its shot map before tapping Next point. Career shows seasonal results, recent ratings, head-to-head records, club ladders and a permanent trophy cabinet. [Service details](Backend/README.md#quick-cup).
- **Guest play and academy:** Quick play opens a tiebreak without sign-in. The daily challenge starts at a pressure score against a recurring rival and saves the first outcome per UTC day on this device. Custom court setup unlocks through the five academy foundations. Players can choose their strongest skill and preferred style for drill recommendations.

- **Match powers**. Each pair of consecutive point wins against the opponent awards one random power if the slot is empty. Tap the small button at bottom right to commit the power. Overhead Smash sets up a lob when needed. Rally Smash plays an inside-out forehand or a two-handed backhand. On Demand Ace uses the blue target on your next serve. Replay opens just before the winning stroke.

- **Guided shot demo:** Home → Learn & improve → Guided on-court demo (also available from the illustrated guide toolbar). Fifteen native court drills begin with rally/recovery and recovery/split-step practice, followed by crosscourt, line, angle, center lob, drop, slice, approach-and-volley, overhead, first/second-serve returns, and wide/T/body serves. Each of the first two drills requires four consecutive return/recovery exchanges for one clean attempt; the split drill also requires a new tap after reaching white, within 3 m of the far bounce on every exchange. Training feeds start 20% faster than the original demo and progressively approach match timing across the 15 skills. Six clean attempts in a row master each skill; already-earned mastery remains complete. Master the first five skills to unlock Take the court. Missed attempts retry automatically. Mastered skills disappear, and the demo automatically starts the next unfinished skill after a brief success message. Progress saves atomically on this iPhone per Apple account; guest progress can be claimed once on sign-in. The demo is available before sign-in, never uploads Coachability points, and supports pause/resume, Reduce Motion, and VoiceOver court actions. Apple sign-in remains required for match play.
- **Names and tennis scoring:** default names are You and Opponent, with optional saved custom names. Practice defaults to one set with 0/15/30/40, deuce, advantage, and games; six games wins with a two-game margin, continuing in games at 6–6. A seven-point, win-by-two tiebreak is an explicit setup choice. The scoreboard separates games from points and indicates the server. Regular games retain the same server, with deuce/ad service courts alternating each point; tiebreak serving follows the one-then-two-point sequence.
- **Clear results:** the point overlay and courtside billboard name who won the point, game, set, or chosen tiebreak. A short explanation identifies a missed shot or an unreachable ball, with technical probability/distance diagnostics removed from the result. Completed sets show their final games and offer Play again. New manually scored matches default to best of three sets, with set and match tiebreaks chosen explicitly; existing saved matches retain their scoring rules.
- **SpriteKit:** perspective court, animated players and racket swings, ball flight arcs, bounce shadows, trails, and contact / target / coverage guides. Frames request up to 120 Hz, while simulation timing remains fixed. Low Power Mode requests 60 Hz.
- **Player movement.** Both athletes plant their support foot in court coordinates as the other foot shuffles, crosses over, or makes a final adjustment. Forehands load the outside leg, turn the hips and shoulders, release the racket, and finish across the body. A forward swipe starts an approach. The approaching player plants for the split and takes a compact first volley. The live figures and replay athletes share the same poses and ball contact.
- **Split-step placement.** A timed split within three metres of the far bounce, or during the last 0.3 seconds of the opponent’s serve motion, raises placement accuracy on your next return by 20% relative to its usual chance, capped at 100%. The point result shows the final shot’s split timing beside the CP breakdown. On an error, it explains the miss and whether changing direction took the ball toward the shorter side.
- **Winning-shot replay.** The decisive stroke plays automatically at half speed. Tap Skip for the point result. Replay point on the result card opens the same shot with You, Opponent and Neutral cameras, a timeline and a shareable court diagram. A completed match ends with a net handshake.
- **Native 3D court.** Pick an arena in Play & practice and an athlete, outfit and headwear in Player & kit. Landscape places the practice scoreboard beside the court. Drag from your half to aim blue, then tap to serve. A faint purple landing target follows a shot swipe from your player. The four-part Quick start film opens on first launch and stays available on the home screen.
- **Serve placement and preparation.** Tap or drag blue in the service box. Within one second of releasing blue, touch either linear gauge behind your baseline. Speed is on your left and Spin on your right. Tap or drag the needle to low, medium, or high. Once you start adjusting, take your time. Tapping your side to serve clears both gauges. The opponent’s serve shows read-only gauges at the far end. In local two-player matches, the gauges face the server. The first serve defaults to high speed and low spin. The second defaults to low speed and high spin. Faster serves shorten the return window and risk faults. Topspin increases clearance and kick while slowing the ball. A second fault awards the receiver the point. Yellow tracks the receiving position.
- **Serve motion:** the ball starts in the non-racket hand, rises through a toss, and meets the overhead string bed after a knee bend and leg drive. The server jumps at contact, follows through, lands inside the baseline on the lead leg, and recovers with the rear leg trailing. The landing is part of the service motion; continuing to net still requires the human's forward swipe. Both ends share the same motion and contact clock. A single compact courtside strip keeps the court size fixed through aim, toss, and rally.
- **Movement and aim:** a short swipe toward yellow/gold starts receiving; toward white starts recovery. An 8-point directional swipe commits the full run immediately, without waiting for finger-up. It can start on your player when that run has not been queued. Once running, use a fresh swipe from the player to select Line (forward), Crosscourt (diagonal), Angle (sideways), or Lob (backward). A touch cannot both move and select a shot. Taps never start or redirect a run: they split step, serve, or select an in-position volley/overhead into open space. Swings still connect automatically at the ball. A new forward court swipe after contact approaches the net. Gesture epochs prevent late input affecting another exchange; both player perspectives and Quick Cup use the same controls.
- **On-time contact:** the yellow outline projects the actual 0.85 m contact zone. Human players inside it when the ball arrives get a clean automatic return, including behind the baseline, with no settling requirement. Stretched contacts outside the zone can still miss. Simulation, racket preparation, and ball presentation use the same contact window; groundstrokes fire after the bounce as the ball enters reach. Quick exchanges flow out of the preceding follow-through. Outgoing faults have no receiving guide, and their point result names the winner.
- **Fault flight and point timing:** net, wide, and long shots remain visible through their actual impact. A red circle marks the exact net contact or out bounce for 0.3 seconds, and the full fault trail stays visible while the ball drops back from the net or rebounds outside the lines. Point-result cards and score announcements normally wait 0.75 seconds after the point ends; an occasional opponent racket gesture lasts within a two-second result delay. After two consecutive points won against the bot, a quiet “C’mon!” and the gesture can occur, with a random two- or three-game cooldown. Scoring occurs once at impact; dead balls cannot be returned. Pause freezes this presentation, and starting the next point clears it. Reduce Motion suppresses the trail while retaining the impact marker and timing.
- **Recovery position:** the white guide sits on the player's baseline. Its horizontal position mirrors the opponent's contact point across court, limited to 3 ft (0.9144 m) from the baseline center. Swiping toward white and the accessibility Recover action use the same location.
- **Rally placement and footwork.** For either player, a clean crosscourt groundstroke lands seven times in eight, a line shot or redirection four times in five, and a short angle twice in three. Stretching can reduce the chance of a clean contact. Difficulty still schedules occasional forced opponent errors every 4–8, 6–12, or 10–16 ordinary returns on Easy, Medium, or Hard. A shot behind a running opponent reduces their top speed to 60% for that chase. Guided feeds, touch-shot drills, and earned winners retain their special behavior.
- **All-court training:** enabled by default, with a switch in practice setup. A clean line shot can produce a controlled defensive lob. The netward guide appears only after a successful return of a rally ball that bounced at least 5 m inside the baseline. The player must swipe forward on the court after contact to initiate the approach; choosing Line alone never starts a run. Approach movement also works after other shots and with training off. A further swipe toward yellow positions the player for the reply. Swipe toward white to leave the attack. An approach plants at the far bounce. Baseline recovery requires a tap at white within 3 m of the far bounce.
- **Net finishing:** the simulation recognizes a reachable descending lob for an overhead, lower airborne contacts for volleys, and ordinary groundstrokes after the bounce. The overhead has a raised racket and pointing preparation; volleys have compact strokes and faster flights. With no explicit aim, a net finish targets the open half of the opponent's court. After the first successful volley inside the service line, the human player can move at twice normal speed. Movement swipes have 1.8× sensitivity. Returning behind the service line or starting a new point resets the boost.
- **Courtside billboard:** one compact strip contains live finger/arrow/target coaching, player names, games, tennis points, the server indicator, leave, help, and pause. The separate scoreboard and both control pads are removed. The light on-court hand demonstrates receive, approach, and recovery gestures once each, at most three appearances per practice screen. Full spoken accessibility labels remain available. Reduce Motion, guide preferences, and touch dismissal are respected.
- **Illustrated guide:** tap ? to pause play and open the bundled 7-page vector PDF in native PDFKit. Court diagrams, one-finger hands, and short captions explain every on-court tap and swipe, including where to start the gesture. Previous/Next, PDF page gestures, pinch zoom, and Share are available. Done returns to the court and restores the previous play/pause state. The shareable copy is `output/pdf/CourtGuide.pdf`; regenerate both copies with `generate_court_guide.py` using ReportLab.
- **Surfaces:** grass plays faster with a lower visual bounce; clay slows flights and raises the bounce; hard court sits between them. This remains an assisted-swing tactical simulation, not a calibrated biomechanics model.
- **Core Haptics:** separate racket-impact and bounce patterns with UIKit fallback. Unsupported hardware continues without requiring haptics.
- **AVFoundation:** a short real recorded tennis forehand (`hit.wav`) plays for every shot, with preloaded overlapping voices and court-position panning. Grunts, alternate stroke effects, landing thumps, bounce audio, and random pitch variation have been removed. Court bounces retain haptic feedback. The final hit can finish after a point; pausing or leaving stops audio. An activated playback session makes impacts audible in Silent Mode. Initial gain remains 3/10; saved mute/volume choices persist and device volume buttons control loudness. Optional spoken score announcements remain available.
- **Core Motion:** opt-in tilt movement, calibrated when play starts/resumes. Touch controls remain available. Disabled when motion hardware is unavailable; local two-player uses touch/controllers.
- **Game Controller:** connected extended gamepads, left stick movement and A/B/X/Y for crosscourt/line/angle/lob; two controllers can control local players.
- **Hardware keyboard:** WASD + Z/X/C/V for player one; arrow keys + 1/2/3/4 for player two. Movement retains acceleration and braking.
- **Accessibility:** native form controls, labeled buttons, manual scoring alternative to tracing, VoiceOver court actions, Reduce Motion support, system fonts. Live spatial gameplay still requires timing; it is not a fully nonvisual tennis game.
- **Lifecycle:** pause on interruptions/backgrounding, stop motion and sounds, disable idle sleep only while the practice screen is active. Portrait iPhone and iPad layouts.

Physical-device validation is still needed for haptic feel, tilt calibration, Bluetooth controllers, speaker/headphone balance, and sustained ProMotion performance. Simulator tests cannot establish these hardware qualities. AR, Apple Watch, Game Center matchmaking, iCloud sync, widgets, and Live Activities are not implemented. These would be separate product features and, in several cases, require Apple account/capability configuration.

## Coachability and accounts

- Each applicable opportunity earns +2 when followed or −1 when missed. New opportunities can score again within the same tennis point; duplicate callbacks cannot. The first six rules cover short-ball approaches, behind-baseline center lobs, first-serve returns at the server, second-serve returns inside/on the rise, first-serve wide then crosscourt, and following deliberate direction changes to net.
- A short ball bounces at least 5 metres inside the baseline; the same predicate controls CP rule 1 and the gold contact ring. Approaches require a forward command and at least 0.5 m of progress, or existing net coverage. No missed-approach penalty is issued when a point ends within 0.35 seconds, before a reasonable response is possible.
- Serve-return rules take priority over the rally lob rule. Straight-up swipes return a first serve toward the server; straight-down rally swipes aim a center lob. The coach switches from movement to shot guidance once the yellow run is queued, then offers an approach cue when relevant.
- Rule 7 evaluates all eligible baseline exchanges once at point end: actually reach the white recovery zone, then tap anywhere on court before the next return. CP does not require a narrow opponent-contact timing window, and an arrival tap still counts during the hop animation cooldown. Every completed sequence earns a single +2 bonus; any missed sequence costs −1 once. An unanswered shot, opponent fault, or intentional net attack is not a baseline recovery opportunity. A point with no eligible exchanges receives no rule-7 award.
- The home screen retains its introduction and Play button, and lists all seven conditions before the leaderboard.
- The home leaderboard shows personal-best CP per completed point, game, or set. Each category shows up to ten players, with gold/silver/bronze trophies for the first three. Empty standings use clearly marked example entries (point 4–1, game 10–6, set 31–21); examples are not stored in D1.
- Public names retain only the first five characters of the Apple email username before @. Legacy profiles need one verified Apple sign-in refresh; their unknown characters are never inferred. Apple-verified subject IDs stay private. Local two-player sessions do not upload rankings.
- Sign in with Apple is required before entering practice. The Worker must be deployed at `swipetennis.com/api/` first. Real Apple authentication and remote D1 writes require that user deployment; local tests use fictional accounts and do not replace that end-to-end check.

## Structure

- `SwipeTennis/Core`: platform-independent match rules, trace classification, practice simulation.
- `SwipeTennis/Game`: SpriteKit rendering, touch/controller input, frame clock and practice session.
- `SwipeTennis/Views`: SwiftUI home, scorer, tutorial, replay, journal, setup, game and settings.
- `SwipeTennis/Services`: local persistence, Apple sign-in, Keychain tokens, account-owned offline result queue, and device feedback.
- `Backend`: Cloudflare Worker, D1 schema/configuration, local API tests, deployable bundle, and user deployment instructions.
- `Tests`: Swift Package unit tests for rules, persistence encoding and physics invariants.
- `SwipeTennisUITests`: Xcode UI tests for scoring persistence and practice flow.
- `Assets.xcassets`, `hit.wav`: app icon and the recorded ball-on-racket sound. Audio provenance and processing are in `AudioSources/README.md`; `generate_audio.py` prepares the bundled excerpt from that source.
- `SwipeTennis/CourtGuide.pdf`: bundled illustrated native help; `output/pdf/CourtGuide.pdf` is the shareable copy.
- `PrivacyInfo.xcprivacy`: local preferences API declaration and linked account/email/gameplay collection for app functionality; no tracking.
- `generate_project.py`: deterministic Xcode project generator; run after adding source/resource files. Xcode is sufficient to open and build the checked-in project.

## Validation commands

```sh
cd apple
swift test
xcodebuild -project SwipeTennis.xcodeproj -scheme SwipeTennis \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
# Substitute an installed simulator from `xcrun simctl list devices available`.
xcodebuild -project SwipeTennis.xcodeproj -scheme SwipeTennis \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO test
```

The original website source was reviewed alongside the live site. Native rule tests cover deuce/advantage, faults, both match formats, tiebreak service order, long-match undo, line tolerances, movement caps, all bot profiles, and surface pace.

Apple references: [SpriteView](https://developer.apple.com/documentation/spritekit/spriteview), [Core Haptics](https://developer.apple.com/documentation/corehaptics/), [Game Controller](https://developer.apple.com/documentation/gamecontroller/gccontroller), [ProMotion](https://developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays).

## Verification record — November 12, 2026

- Final iPhone Simulator build: **passed**, including native keyboard controls.
- Unsigned physical-iOS build: **passed** before the final keyboard-input addition; physical hardware was not connected.
- Swift core regression suite: **11 tests passed, 0 failures**.
- Native home and match-setup screens were visually inspected. `Screenshots/scorer.png` records the native setup form.
- XCUITest scoring/relaunch and practice suites were attempted but did **not** complete. Simulator accessibility snapshot/keyboard requests stalled, and a separate practice run stalled in runner startup. The runs were stopped; no UI-test pass is claimed.
- Gameplay UI, iPad/small-phone layouts, physical haptics, tilt, controllers, hardware keyboard, audio balance, and sustained frame rate still need device QA before release.
- The original website files were not changed. All added implementation files are in `apple`.

## Player-animation verification — November 21, 2026

- Signed physical-iOS build passed.
- Core regression suite: **17 tests passed, 0 failures**, including mirrored backhands, stance stability, swing continuity, racket contact alignment, volleys, and serves.
- Forehand, two-handed backhand, and mirrored opponent poses were rendered from the production SpriteKit figure and visually inspected at preparation, contact, and follow-through.
- The signed update was installed and launched on iPhone16pro-RT over Wi-Fi.
- Hardware feel and sustained frame rate still require hands-on play.

## Guide and gesture verification — November 21, 2026

- Signed physical-iOS build passed.
- Core regression suite: **21 tests passed, 0 failures**. Added gesture checks for preserving movement during an aim swipe, release-to-move, crossing back over the net, and independent local-player inputs.
- Setup, live hints, and the courtside coach explain the receive → aim → automatic contact → recover sequence.
- Installed over Wi-Fi on iPhone16pro-RT. Automatic launch was blocked because the phone was locked; open SwipeTennis after unlocking.

## Recovery and Easy-mode verification — November 21, 2026

- Signed physical-iOS build and core regression suite passed: **28 tests, 0 failures**.
- Added checks for baseline placement, exact 3 ft bounds, crosscourt mirroring, the Recover control, crosscourt targets across all styles, one missed return per four across points, point scoring, and isolation from human/local-player and other-difficulty accuracy.
- Installed over Wi-Fi on iPhone16pro-RT. The phone was locked, so automatic launch was blocked; unlock and open SwipeTennis to play.

## Contact and swing-timing verification — November 21, 2026

- Signed physical-iOS build and core regression suite passed: **40 tests, 0 failures**.
- Added regressions for inside/on/behind-baseline contact on both ends at every difficulty; running arrivals without settling; movement into yellow at 30/60/120 simulation steps per second; the entire guide boundary; prompt groundstroke and volley contact; out-ball scoring; late arrivals; and frames crossing the contact window.
- Animation regressions cover recovery flowing into the next preparation and using elapsed physics time on the impact frame. Visual smoothness on hardware still needs hands-on play.
- Installed and launched on iPhone16pro-RT over Wi-Fi.

## All-court coaching sources

The five gameplay additions are adaptations of coaching principles and the requested repeatable drill, rather than a published ranked list. No endorsement is implied. The reliable defensive lob is a training behavior; ordinary points can develop differently.

1. **Directional approach control:** clean line approaches and deliberate direction changes support an attacking game. Rick Macci discusses all-around attacking players and finishing at net in [The New Volley Paradigm](https://www.tennisplayer.net/article/the-new-volley-paradigm/).
2. **Follow the ball and cover the court:** the approach follows the shot into a position that covers the opponent's return angles. Macci's [Closers](https://dev.tennisresources.com/closers/) emphasizes reacting with the feet, moving through volleys, and closing in a V pattern.
3. **Split step:** any court tap triggers a ready bounce. The far bounce sets the split timing. A court tap after reaching white counts toward CP when the outgoing ball is within 3 m of its landing point. An already queued run continues during a split tap. [Macci's split-step lesson](https://www.tennisresources.com/timing-the-split-step/) describes timing the hop before the opponent hits.
4. **Volley and overhead preparation:** compact volleys use bent knees and a raised racket, informed by [Macci's volley-preparation lesson](https://www.tennisresources.com/keeping-the-racquet-eye-level/). Lob tracking and overhead preparation also draw on the USTA's [Let's Play Tennis](https://s3.amazonaws.com/ustaassets/assets/801/15/lets_play_tennis%21__2nd_edition_proof.pdf), overhead section.
5. **Finish in available space and learn the sequence:** the open-court target, tactical counters, and live billboard make approach → split → intercept → finish observable and repeatable. These are game-design adaptations of the attacking-play and footwork material above.

Saved practice settings decode the new option without discarding old matches. All-court training can be disabled. Ordinary Easy returns remain crosscourt, with the current difficulty-based randomized error schedule covered by regression tests.

## All-court training and billboard verification — November 21, 2026

- Core regression suite: **49 tests passed, 0 failures**. The complete clean line approach → reachable defensive lob → open-court overhead sequence passes for all five opponent styles from both court sides, including checks on the opponent's movement speed.
- Additional coverage includes manual movement overrides, baseline recovery, training opt-out, flick direction, saved-settings migration, overhead contact height, court coverage, and contextual billboard instructions.
- Final signed physical-iOS and iPhone Simulator builds passed. The device app's code signature was verified.
- Visually inspected the native setup, ready overlay, and live gameplay on the iPhone simulator. Fixed the billboard's intrinsic height so it remains a compact strip above the court, with room reserved for two lines of guidance and no overlap with the ball, players, or targets.
- Installed and launched the update on iPhone16pro-RT over Wi-Fi. Physical-device timing, touch feel, and animation smoothness still need hands-on play.

## Scoring reference

The regular game, advantage-set, and optional tiebreak rules follow the [USTA scoring guide](https://www.usta.com/en/home/improve/tips-and-instruction/national/tennis-scoring-rules.html). Practice uses an advantage set by default to keep tiebreaks optional, as requested.

## Names, results, and tennis scoring verification — November 21, 2026

- **59 core tests passed, 0 failures**, covering names, old settings, custom-name persistence, deuce/advantage, game/set results, 6–6 continuing without a tiebreak, service order and court alternation, explicitly chosen tiebreaks, duplicate-award protection, restart, and legacy manual-match rules/undo.
- Final signed iPhone and Simulator builds passed, and code-signature verification passed.
- Visually verified You/Opponent labels, separate games/points columns, the scoring setup, and a completed point showing Opponent at 15 with a plain-language winner, reason, score, and next-step message. The billboard and court remain visible.
- Installed on iPhone16pro-RT over Wi-Fi. Automatic launch was blocked by the locked phone; unlock and open SwipeTennis to play the update.

## Player-controlled movement and varied errors — November 21, 2026

- **67 core tests passed, 0 failures**. Coverage includes movement-vs-shot gesture intent, no approach without a player command, explicit positioning for a lob, manual recovery, the three-demonstration session limit, cross-point randomized error intervals, all four error types, one opportunity counted per flight, and protected practice lobs.
- The complete approach/lob/overhead sequence passes across all five opponent styles from both sides after explicit approach and receive swipes. A fast volley reply is covered so a receive swipe can stop the old approach route at yellow.
- Final Simulator and signed physical-iOS builds passed; device signature verification passed.
- Visually checked the native setup descriptions, live yellow movement path, and light translucent one-finger guide in the iPhone simulator. The white icon is rendered into its SpriteKit texture so its tint remains visible, and crowded receive/recovery labels were removed.
- Installed on iPhone16pro-RT over Wi-Fi. The phone was locked, so automatic launch was blocked; unlock and open SwipeTennis to play the update. Hands-on touch feel and sustained performance still need physical-device play.

## Swipe controls and visual coaching — November 21, 2026

- **70 core tests passed, 0 failures**. Coverage includes movement-only court swipes, shot-only pad swipes, yellow/white target taps, repeat-tap cooldown, manual split timing, approach after any shot, both local players, and down-the-line aim from the actual contact position.
- Simulator and signed physical-iOS builds passed; device code-signature verification passed.
- Visually verified the setup's explicit opponent-only playing-style heading and explanation. The simulator stopped before the live gesture-pad and billboard visual check completed; their layout and physical touch feel still need hands-on review.
- Installed and launched the updated native app on iPhone16pro-RT over Wi-Fi.

## Serve placement, motion, and sound — November 21, 2026

- **82 core tests passed, 0 failures**. New cases cover both servers and deuce/ad boxes, distinct Wide/Center/Body placements, bounded custom targets, smoothly linked blue/yellow positions, target freezing during toss, unlimited human preparation, opponent timing/variation, receiving controls, clean on-time serve returns, no serve volleys, jump/contact continuity, landing inside both baselines, and increasing exertion cues in long rallies. Existing rally/scoring tests advance through the actual serve preparation and toss.
- Final Simulator and signed physical-iOS builds passed; code-signature verification passed. All 12 bundled audio assets match their sources and are short, non-clipping mono PCM files.
- Visually checked the native serve pad, Wide selection, direct blue-target dragging, yellow-target movement, tap-to-position, serve release, and automatic return on the simulator. Fixed a layout shift by reserving the same height for serve and rally controls, then verified that the court stayed fixed through contact.
- Rendered the production player figure at six serve stages for both ends and inspected the toss arm, racket drop, airborne contact, trailing leg, landing, and recovery. Sound quality, speaker balance, and physical touch feel still need hands-on device play.
- Installed and launched this update on iPhone16pro-RT over Wi-Fi.


## Full court and illustrated guide — November 21, 2026

- **90 core tests passed, 0 failures.** Added coverage for shot-origin gestures, mirrored far-player input, fixed touch intent, stale shot rejection, gestures spanning the serve toss, movement after contact, a single queued tap-to-serve, and aim changes cancelling a pending serve.
- Final Simulator and signed physical-iOS builds passed; device code-signature verification passed. The obsolete shot/serve-pad views and project references were removed.
- Visually checked the expanded court, compact games/points score and server indicator, direct blue-target dragging with linked yellow movement, tap-to-serve, automatic return, guide opening, Next-page navigation, and return to the unpaused court in the iPhone simulator.
- Rendered and inspected all 10 final PDF pages. Both bundles contain the same final PDF. PDF pinch/page-swipe feel and new player-origin shot aiming still need hands-on device play; Next/Previous offer explicit page navigation.
- Installed and launched the final update on iPhone16pro-RT over Wi-Fi.


## Fault trajectories and delayed results — November 21, 2026

- **97 core tests passed, 0 failures.** New tests cover full pre-impact flight, exact net intersection, both sides and sidelines, post-impact ball motion, 0.3-second markers and 0.75-second result delays at 30/60/120 Hz, one award per point, delayed normal-winner results, and reset at the next serve.
- Every opponent style and difficulty was exercised with seeded random returns to verify net, wide, and long faults. Existing tests still cover all four error types, randomized Easy 4–8 / Medium 6–12 / Hard 10–16 intervals, real missed chases, and protected training lobs.
- Final Simulator and signed physical-iOS builds passed, and the device code signature verified.
- Rendered the production court/player/ball/marker nodes with an offscreen macOS compatibility harness. Inspected net, wide, and long faults before impact, at +0.15 seconds with the red circle, and at +0.40 seconds with the circle gone and the ball still visible. Physical touch feel and frame pacing remain hands-on checks.
- Installed and launched the final update on iPhone16pro-RT over Wi-Fi.

## Coachability, audio and cloud verification — November 21, 2026

- **107 native core tests passed, 0 failures**, including all six Coachability rules, overlapping +4 rewards, missed opportunities, first/second serves, center-lob aim, duplicate suppression, and shot guidance while running.
- Signed iPhone and Simulator builds passed with Sign in with Apple capability. Device code-signature verification passed. The final app points to `https://swipetennis.com/api/`.
- **8 backend unit tests and 20 website tests passed.** Actual local Worker/D1 integration verified auth rejection, nonce creation, score recomputation, game/set completion, personal-best retention, upload idempotency, account isolation, masked public records, logout and cascading account deletion.
- All 13 revised PDF pages were rendered and visually inspected. The native home leaderboard, visible Play button, trophies, masked identifiers and per-set switching were visually verified in Simulator. Audio session activation and 3/10 initial gain are implemented; speaker/headphone sound balance still needs hands-on listening.
- Cloudflare backend code was published to GitHub `main` at `e6c3cb863654b210074812c1e8d70486a828d91a`. The existing `swipetennis-com` Workers Build completed successfully. The live `/api/health`, all three D1-backed example leaderboards, and Apple single-use challenge endpoint returned successful responses. No real Apple account was created by testing.
- Automatic D1 migration execution is part of Cloudflare main-branch builds. Local builds and other branches skip production migrations. Only backend/deployment files were pushed; native Xcode sources remain in this workspace.
- The final native app was installed over Wi-Fi on iPhone16pro-RT. Automatic launch was blocked because the phone was locked. Unlock and open SwipeTennis, then complete Sign in with Apple. Actual Apple login, result upload from physical play, touch feel and audio loudness remain user checks.

## Landing rules, recovery consistency and email masks — November 21, 2026

- Kept the landing introduction and Play button; added all seven Coachability conditions. Native home and rule-card content were reviewed in Simulator, including the seventh rule and its net-approach exemption.
- **114 core tests passed, 0 failures.** Recovery tests require real arrival at white followed by a timed split, evaluate the whole point once, reject tap-only/reversed-order/early-bounce sequences, preserve a failed cycle after later successes, exempt actual net approaches and net shots, ignore unanswered shots and opponent faults, and reset at the next point.
- **10 backend tests and local Worker/D1 integration passed**, including rule-7 totals/duplicate rejection and a migration that preserves existing accounts and scores. Email masks now use characters before @ only. Existing suffixes were hidden by migration and refresh with the next Apple sign-in; the app refreshes the stored profile and offers Refresh Apple sign-in when needed.
- Final signed iPhone and Simulator builds passed. All 14 guide pages were rendered and inspected; the source, shareable PDF, and both built app resources have identical SHA-256 hashes.
- Backend commit `7a6ed59c09d18802da26bc63ec18cda70324e32f` was pushed to GitHub main. Cloudflare's build/deployment succeeded; the live API reports rulesVersion 2, and the migrated public leaderboard retained the existing score with the old domain suffix hidden.
- Installed the final native update on iPhone16pro-RT over Wi-Fi. Physical gesture feel still requires hands-on play.

## Subtle missed-opportunity feedback and home guide — November 22, 2026

- Every missed Coachability opportunity produces a soft red ring at your player’s feet for 0.85 seconds, plus an amber rule/correction in the existing courtside coach strip for 2.4 seconds. The court and score keep their size; play is never paused and touches pass through. Simultaneous misses queue individually, including misses at point end. The ring only fades when Reduce Motion is enabled.
- Rule 7 warns during baseline exchanges after the 0.12-second post-contact split window closes, distinguishing failure to reach white from failure to split. Each failed exchange can warn once, but the whole-point rule still deducts only once. Successful recovery and real net approaches remain exempt from warnings; opponent faults do not trigger them.
- A collapsed How to play card sits above the Coachability rules. It uses the existing native PDF reader with page buttons and a full-screen reader that opens at the selected page.
- Replaced the synthetic impact with a 200 ms CC0 recording of a real tennis forehand. No voices, bounce audio, landing audio, artificial pitch variation or tonal synthesis. Initial volume remains 3/10.


## Touch shots and point-streak reactions — November 22, 2026

- **Drop shot:** swipe toward yellow, lift the finger, then draw a quick closed circle (either direction) before contact. This preserves the queued run, expires with the incoming ball and selects one soft shot just over the net. The circle is accepted within 0.9 seconds; slow, incomplete and tiny loops are ignored. A compact stroke and low second bounce distinguish it from a drive.
- **Crosscourt slice:** before contact, drag from either actual net post to the opposite baseline corner on your own side. This reserved gesture leaves movement unchanged and selects a slower, lower crosscourt shot. Its target is calculated from the actual contact position. Ordinary player-origin shot swipes retain their existing meanings.
- **Opponent replies:** every drop is chased, with exactly one randomized failed chase per group of 3 (Easy), 4 (Medium) or 5 (Hard). Successful pickups return a deep center lob. Slices receive sufficient flight time to be returned at every level. These protected replies do not consume the ordinary opponent-error schedule.
- **Streak reactions:** after two consecutive points won by you, the opponent slumps, shakes their head and makes a restrained frustrated gesture. After two or more consecutive losses, a random affirmation from the supplied 26 appears as centered cream serif lettering directly on your court for **4-8 seconds before the result card**, based on reading length, at most **once per tennis game**. Consecutive displayed affirmations cannot repeat. The cap belongs to the game in which the point began, including game-ending points. Pause freezes the display; Reduce Motion removes the head shake.
- **Guide:** pages 15–16 illustrate the two new gestures, separating the white finger path from the yellow ball trajectory. Both the collapsed home reader and the court’s ? reader use the same 16-page PDF.
- **Validation:** 130 core tests passed. New regressions cover both circle directions, arming and expiry, mirrored net-post gestures, low drop bounces, slower slices, real chase/return simulation for every opponent style and difficulty, all 26 random affirmations, the once-per-game cap, streak resets and two-second result timing at 30/60/120 Hz. Device and simulator builds succeeded. Rendered and inspected all guide pages, opened both new pages in native PDFKit, and inspected short/long affirmations and player reactions using the production drawing code offscreen. Physical gesture comfort still benefits from hands-on play.


## Randomized tactics, CP explanations and compact guide — November 22, 2026

- Home Play & practice is a full-width card with the same inset and minimum height as How to play.
- CP rule 1 uses the incoming rally ball's **bounce** at least 5 m inside the baseline, excluding serves and faults. The contact ring becomes thick gold, pulsing at 1 Hz between 60% and 100% opacity. Reduce Motion keeps it steady. Net interception of a deep ball does not turn it into a short-ball opportunity.
- Every ordinary bot return independently samples a short ball with probability 1/3 (Easy), 1/5 (Medium), or 1/7.5 (Hard). Valid short-ball contacts are at least 5 m inside, giving the player an approach opportunity. No repeating sequence or per-point reset predicts the next short ball.
- A player-commanded approach triggers a single randomized opponent reply per incoming shot: Easy 2/3 soft volley feed and 1/3 miss; Medium 35% soft feed, 15% miss, 25% lob and 25% passing shot; Hard 20% soft feed, 5% miss, 37.5% lob and 37.5% passing shot. Pressure errors vary among net, wide, long and an unreachable chase when distance permits. Soft feeds travel slower; passes target the open side with more pace. Existing reached-drop-shot deep lobs remain intact.
- Player names come from the first five Apple-email username characters. The full address is neither shown nor stored. Existing masked accounts can use Refresh Apple sign-in in the Coachability account card; IDs, pending results and personal bests are preserved. The API name update was pushed to GitHub main for Cloudflare deployment; no D1 schema migration is necessary.
- Point-result cards list each +2/-1 and its reason. Short lists are fully visible; longer lists scroll with a hint. Reasons include actual missed returns, non-wide serves, missed white recovery, and missing the split tap before the next return.
- The guide is rewritten as **7 pages**, with all court taps, shot gestures and combinations on the first **3**. Subsequent pages explain the 5 m gold cue, all seven CP rules, random opponent tactics, and result/score controls. Both native PDFKit entry points share this guide.
- Validation: **137 core tests** and **10 API tests** passed, plus local Worker/D1 integration covering privacy, existing account IDs, scoring validation and personal-best preservation. Device and simulator builds and visual checks are recorded in /tmp/swipetennis-tactics-* logs and previews.

- Final deployment: Cloudflare health returned rulesVersion 3 after GitHub commit `8cf2bfb`; the signed native update was installed on the paired iPhone. The home cards and the three gesture-summary pages were visually verified in Simulator.

## Latest control refinements

- Positioning Lab starts with a full-width **Take the court · Default settings** quick-play button. It uses the default Easy baseline opponent, grass surface, all-court training, and normal tennis scoring; the lower button starts with the configured choices. Both preserve the Apple account requirement.
- The setup no longer describes opponent error intervals or difficulty-specific reply behavior. The illustrated How to Play guide remains unchanged.
- Rule 4 credits a clean second-serve return made from the yellow contact zone inside the baseline, including the back edge and later valid contact. It does not impose an additional flight-progress cutoff. Tapping a target without arriving does not earn CP.
- Rule 7 allows a split tap anywhere before the next return after recovering to white. Miss feedback waits until the return or point ending, so an opportunity still available never produces a premature red warning. Net-approach exemptions and the once-per-point award remain intact.
- Validation: 143 core tests passed, followed by 10 focused court-control tests with stricter repeated-tap movement/return checks. Signed device and simulator builds succeeded. Native simulator review confirmed the top button, default selection, and the existing Apple sign-in flow. Bundled guide hash remains unchanged.
- Device deployment: installed successfully over Wi-Fi on iPhone16pro-RT. Automatic launch was denied because the phone was locked; unlock and open SwipeTennis to use the update.

## Court affirmation refresh

- Affirmations use centered Georgia italic text, a small gold author credit, and a feathered shadow over the actual court instead of a rectangular panel. Text fits the available court area and fades gently; Reduce Motion shows stable lettering.
- A random smiling emoji follows each quote. The quote and emoji are chosen once per display, with no immediate repeat of either. The existing two-loss trigger and maximum of one affirmation per game remain.
- Reading duration includes a brief settling interval, grows with the quote and author length, and stays between four and eight seconds. The point result waits for that duration. Ordinary results and opponent frustration retain their existing timing.
- Validation: 145 core tests passed, including 4-8 second result timing at 30/60/120 Hz and all random smile choices. All 26 quotes were checked in 78 native SpriteKit layouts across compact phone, standard phone, and iPad sizes. Short/long court previews and the guide timing note were visually inspected. Signed iPhone and simulator builds succeeded.
- Deployment: the final native build installed and launched successfully on iPhone16pro-RT over Wi-Fi.

## Streaming affirmations and tap to continue

- The court quote now appears progressively, keeping its final line positions stable. The smile and author credit complete the reveal. Reduce Motion shows the complete text immediately.
- Tap anywhere on the court during typing or reading to show the result immediately. A small hint by the net explains the action. The four-to-eight-second automatic timeout and once-per-game limit remain.
- Only a new tap begun during the affirmation can dismiss it; an existing rally gesture finishing late cannot. Skipping does not award another point, alter CP, serve, or start the next rally. Pause and help still pause the sequence.
- Validation: 148 core tests passed. Tests cover Unicode-safe progressive reveal, completion before timeout, Reduce Motion, skipping while typing or reading, unchanged scores/CP, and ordinary result delays. Native offscreen SpriteKit samples confirmed stable line positions, the final emoji reveal, and a tap hint clear of the net. Device and simulator builds passed; the guide was regenerated and its changed page inspected.
- Deployment: installed and launched the final streaming/tap update successfully on iPhone16pro-RT over Wi-Fi.


## Native iOS interface refresh — November 22, 2026

- Replaced the page-like home layout and oversized serif headings with system typography, native grouped lists, navigation titles, SF Symbols, and standard tab/navigation controls. The introduction, collapsible guide, seven CP rules, and Top 10 leaderboard remain available.
- Practice setup now uses a native Form with segmented difficulty/surface controls, a pushed opponent-style picker, and standard quick-play and configured-play buttons. Apple sign-in appears in a native sheet and remains required for production practice.
- Ready, pause, and point results use native medium/large sheets. Coachability reasons are readable list rows; result progression remains explicit, while dismissing a paused sheet resumes play.
- Refreshed the match scorer, match reports, replays, account screen, and illustrated-guide navigation with native lists, toolbars, menus, share controls, and buttons. The seven-page guide remains PDFKit; gameplay remains SpriteKit.
- Semantic colors now follow the device’s light/dark appearance. System text styles support Dynamic Type. Court toolbar controls have at least 44-point touch targets; optional tilt, game controllers, haptics, VoiceOver actions, sound, and Reduce Motion remain intact.
- Validation: all 148 native core tests passed. iPhone and Simulator builds passed; the signed device app passed code-signature verification. The native home, practice form, and pushed opponent-style picker were visually checked in Simulator. An isolated gameplay UI fixture also built successfully; further interaction review was limited by Device Hub connection/AX errors. Production authentication was not changed.
- Deployment: the redesigned app installed successfully on iPhone16pro-RT over Wi-Fi. Automatic launch timed out; installation was confirmed separately.


## Short-ball pace, quick point recap, and out-ball chase — November 22, 2026

- Human players run at up to 9 m/s (1.5x the usual 6 m/s) when receiving a clean rally ball in the existing short-ball zone, at least 5 metres inside the baseline. Acceleration and braking adjust smoothly; normal receives, serves, faults, and opponent speed retain their existing rules.
- Point results use the compact dark-green overlay again. Winner, tennis score, CP total, per-rule gains/misses, and Next point share one card. Repeated opportunities group into at most seven rows without canceling away the visible positive/negative amounts. Details opens the full event history; ready and pause controls retain native sheets. An oversized-accessibility-text fallback remains available.
- Wide and long incoming balls retain a faint yellow circle that accepts a short directional swipe through the bounce/result delay. Swipes can continue the chase after impact; taps do not move the player. No chase line is drawn, no dead ball can be returned, and score/CP remain finalized. The red impact marker and affirmation tap-to-dismiss behavior are preserved.
- Kept the 85 cm sideline risk shading unchanged. Added an illustrated explanation of these strips and the out-ball circle on page 8, updated short-ball pace on page 4, and described the compact recap on page 7. Both guide entry points and sharing use the eight-page PDF.
- Validation: **155 core tests passed**, including 30/60/120 Hz short-ball returns, the 1.5x speed cap, exclusions, out-ball movement before/after impact, unchanged scoring/contact counts, and lossless CP aggregation. Signed iPhone and Simulator builds passed; code signature and bundled/shareable PDF hashes match.
- Visual review: iOS ImageRenderer artifacts of the production SwiftUI card show all seven rule summaries in 548 points at 370-point width, and the compact variant in 475.5 points at 343-point width. The normal three-action recap is 327.5 points tall. Production SpriteKit offscreen renders verified visible 30%-opacity out-ball circles with the chase path hidden. Revised guide pages 4, 7, and 8 were rendered and inspected. Device Hub remained unavailable for an interactive walkthrough.
- Deployment: installed and launched the final app successfully on iPhone16pro-RT over Wi-Fi.

## Guided shot mastery — November 22, 2026

- Added the native Guided on-court demo inside How to play and a demo shortcut in the guide toolbar. Thirteen drills demonstrate the gesture before asking the player to try it. Baseline feeds alternate sides; approach-and-volley requires a separate forward swipe after contact. Serve drills require dragging blue to the indicated placement before tapping to serve.
- Every drill evaluates deliberate input, contact, and the actual landing. Three consecutive clean attempts earn mastery. Misses give specific feedback, reset only that drill's streak, and retry automatically. Mastered drills leave the list and Continue sequence. Players can pause, leave, and resume unfinished progress.
- Progress is saved atomically to Application Support per Apple user; guest progress is claimed once on sign-in. Duplicate attempt results and demonstration runs cannot increase mastery. Demo play creates no Coachability events, match scores, or leaderboard submissions. Production match authentication remains unchanged.
- Validation: **162 core tests passed**, covering all 13 demonstrations at 30/60/120 Hz, both baseline feed sides, actual learner inputs, wrong directions/gestures, missed approaches, wrong serve placement, first-serve targeting, streak reset, duplicate handling, account isolation, and persisted mastery. Offscreen renders of the production court code verified the gesture paths and target rings; the compact-screen lob guide was adjusted to keep the whole hand visible. Interactive simulator review was unavailable because Device Hub stayed on the startup screen.
- Deployment: final iPhone and Simulator builds succeeded, the device code signature passed verification, and the corrected app installed successfully on iPhone16pro-RT over Wi-Fi. Automatic launch was denied because the iPhone was locked; open SwipeTennis after unlocking it.

## Home navigation cleanup — November 22, 2026

- Learn & improve now lists Guided on-court demo first, How to play second, and How to earn Coachability Points third. The demo opens directly from its own row; the two instructional sections retain their collapsible layout.
- Removed the redundant Take the court / Default settings shortcut from practice setup. The persistent bottom Take the court button uses the selected settings.
- Validation and delivery: the signed iPhone build and code-signature check passed. Installed and launched the combined update successfully on iPhone16pro-RT over Wi-Fi.


## Rally foundations and court unlock — November 22, 2026

- Added Rally & recovery and Recover & split step as skills 1 and 2. Each clean attempt requires all six returns and recoveries, including the final recovery. The second skill additionally requires a new court tap after physically reaching white on each exchange; tapping white while still running toward it does not count. Any court location can supply the subsequent split tap.
- Kept real movement, contact windows, ball flight, and opponent movement. Animated hands cue yellow, then white, then a fresh split tap. The on-court header shows completed exchanges out of six alongside the three-attempt mastery indicator.
- Take the court unlocks only after mastery of these two foundations plus crosscourt, down the line, and short angle. The setup screen explains the lock and links directly to the guided demo. The requirement is rechecked when starting play and after Apple sign-in. Optional skills cannot substitute for one of the first five. Existing saved shot mastery is preserved, and Continue prioritizes unfinished required skills.
- Validation: **166 core tests passed**, covering all 15 demonstrations at 30/60/120 Hz, six-exchange completion, omitted final recovery, early versus post-arrival split taps, any-location split taps, exact prerequisite matching, progress reload, and legacy progress compatibility. The signed device build and Simulator build-for-testing succeeded; the latter compiled the updated onboarding UI test without running its interactions.
- Visual review: offscreen renders of the production SpriteKit court confirmed the white recovery ring, its tap cue, and the distinct after-arrival split instruction on a compact court. Installed and launched the update successfully on iPhone16pro-RT over Wi-Fi.


## Shorter drills and automatic progression — November 23, 2026

- Mastery now requires two consecutive clean attempts (2/2). Rally/recovery and recovery/split attempts require four exchanges instead of six; the final recovery and post-arrival split remain required. All counters, success messages, instructions, and VoiceOver labels use the shared targets.
- Existing two-attempt streaks now qualify as mastered. Existing three-attempt mastery remains valid and displays as 2/2. The first five specific skills still unlock Take the court.
- The demo now automatically advances 1.8 seconds after mastery, with a Next skill button for immediate advancement. A stable presented flow replaces only the lesson and creates a fresh session; callbacks from the previous lesson cannot skip or replace the new one. Pausing or leaving cancels pending automatic advancement. Finishing the last skill returns to the completed progress screen.
- Validation: **168 core tests passed**, including four-exchange completion, final recovery, two-attempt mastery, old progress compatibility, complete lesson progression, skipped mastered lessons, and duplicate advancement callbacks. The signed iPhone build and signature verification passed.
- Runtime check: an isolated harness using the production demo session/store verified two-attempt mastery, a live fresh court after stopping the previous session, automatic retry, and continued play in the next skill. The final app installed and launched successfully on iPhone16pro-RT over Wi-Fi.


## Progressive demo ball pace — November 23, 2026

- The first rally skill uses 1.2× the former demo ball speed for both incoming and outgoing flights (3.8 seconds becomes approximately 3.17 seconds). Later skills progressively remove training slowdown using their fixed curriculum position, ending at the normal match flight duration. Retrying a skill keeps its pace consistent.
- Match timing comes from the existing launch physics for the same shot and court settings, so lobs, slices, volleys, and serves retain their different speeds. Shots that already used normal match pace remain at that pace. Serve-aim and toss preparation, player movement speed, four-exchange attempts, and two-attempt mastery remain unchanged.
- Demonstration shot cues adapt to the shorter flight time, avoiding late volleys at advanced pace. The guide introduction explains that pace builds toward match play.
- Validation: **171 core tests passed**, including every skill on both feed sides at 30/60/120 Hz, all eight flight legs of the first four-exchange rally, monotonic progression, the match-speed ceiling and endpoint, progressive serve returns, and unchanged final-serve match timing. The signed iPhone build and code-signature verification passed.
- Delivery: installed successfully on iPhone16pro-RT over Wi-Fi. Automatic launch was denied because the phone was locked; the installed update is ready to open after unlocking.


## Six-attempt mastery — November 23, 2026

- Every unfinished guided skill now requires six consecutive clean attempts (6/6). The existing shared target updates the lesson list, six progress indicators, result messages, instructions, and VoiceOver labels together.
- Preserved previously earned mastery so completed skills remain hidden. New progress stores an explicit completion flag; unfinished streaks of two through five remain unfinished across relaunches. Account/guest merges prioritize earned mastery over a larger unfinished streak.
- Validation: **173 core tests passed**, including all 15 skills requiring their sixth clean attempt, partial-progress round trips, six-attempt automatic progression, legacy completion preservation, and guest/account merge behavior. The signed iPhone build and code-signature verification passed.
- Delivery: installed successfully on iPhone16pro-RT over Wi-Fi. Automatic launch was blocked by the phone's lock screen; open SwipeTennis after unlocking.
