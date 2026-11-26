import {verifyAppleToken, randomToken, digest} from './apple-auth.mjs';
import {maskEmail, publicPlayerName, validatePoint, validateSequence, demoEntries} from './rules.mjs';
import {career, clubAction, findDraw, rematchDraw} from './tour.mjs';
import {validCode} from './cup-rules.mjs';
import {ratingFor, tentativeMatches, ratingAlgorithm} from './st-ratings.mjs';
const json = (value, status = 200) => Response.json(value, {status, headers: {'Cache-Control': 'no-store','X-Content-Type-Options': 'nosniff'}});
const fail = (status, message) => Object.assign(new Error(message), {status});
async function body(request) {
  if (Number(request.headers.get('content-length') ?? 0) > 256000) throw fail(413, 'Request too large');
  const reader = request.body?.getReader();
  if (!reader) throw fail(400, 'Missing JSON');
  const chunks = []; let size = 0;
  while (true) {
    const {done, value} = await reader.read();
    if (done) break;
    size += value.length;
    if (size > 256000) { await reader.cancel(); throw fail(413, 'Request too large'); }
    chunks.push(value);
  }
  const bytes = new Uint8Array(size); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  const text = new TextDecoder().decode(bytes);
  try { return JSON.parse(text); } catch { throw fail(400, 'Invalid JSON'); }
}
async function user(request, env) {
  const auth = request.headers.get('Authorization') ?? '';
  if (!/^Bearer [a-f0-9]{64}$/.test(auth)) throw fail(401, 'Sign in with Apple to continue');
  const row = await env.DB.prepare('SELECT u.id, u.email_mask FROM auth_sessions s JOIN users u ON u.id=s.user_id WHERE s.token_hash=? AND s.expires_at>?')
    .bind(await digest(auth.slice(7)), Date.now()).first();
  if (!row) throw fail(401, 'Please sign in with Apple again');
  return row;
}
function fromRow(row, format) {
  return validatePoint({id: row.id, sessionID: row.session_id, pointIndex: row.point_index,
    gameIndex: row.game_index, winner: row.winner, format, events: JSON.parse(row.events),
    gameCompleted: !!row.game_complete, setCompleted: !!row.set_complete});
}
export default {
  async fetch(request, env) {
    try {
      const url = new URL(request.url), path = url.pathname;
      if (env.API_LIMITER && request.method !== 'GET') {
        const key = request.headers.get('Authorization')?.startsWith('Bearer ')
          ? await digest(request.headers.get('Authorization'))
          : 'signin:' + (request.headers.get('CF-Connecting-IP') ?? 'local');
        if (!(await env.API_LIMITER.limit({key})).success) throw fail(429, 'Please wait a minute and retry');
      }
      if (path === '/health' && request.method === 'GET') return json({ok: true, rulesVersion: 3});
      if (path === '/cups/capabilities' && request.method === 'GET') return json({version: 2, players: 4, drawSizes: [2,4,8], liveInvites: true,
        stRankings: true, stTentativeMatches: tentativeMatches, stRatingAlgorithm: ratingAlgorithm});
      if (path === '/career' && request.method === 'GET') return json(await career(env.DB, (await user(request,env)).id));
      if (path === '/club' && request.method === 'POST') {
        const account = await user(request,env);
        return json(await clubAction(env.DB, account.id, await body(request)));
      }
      if (path === '/cups' || path.startsWith('/cups/')) {
        const account = await user(request, env);
        account.stRating = await ratingFor(env.DB, account.id);
        const roomRequest = (code, action, payload) => {
          const headers = {'X-Cup-User': JSON.stringify(account)};
          if (request.headers.get('Upgrade')) headers.Upgrade = request.headers.get('Upgrade');
          if (payload !== undefined) headers['Content-Type'] = 'application/json';
          return env.CUPS.get(env.CUPS.idFromName(code)).fetch(new Request(`https://cup${action}`, {
            method: payload === undefined ? 'GET' : 'POST', headers,
            body: payload === undefined ? undefined : JSON.stringify(payload)}));
        };
        const modern = request.headers.get('X-Cup-Version') === '3';
        const index = code => env.DB.prepare('INSERT OR IGNORE INTO cup_memberships VALUES(?,?,?)').bind(account.id, code, Date.now()).run();
        if (path === '/cups/find' && request.method === 'POST') {
          const data = await body(request);
          const cup = await findDraw(env.DB, account, roomRequest, data);
          await index(cup.code);
          return json(cup);
        }
        if (path === '/cups/rematch' && request.method === 'POST') {
          const cup = await rematchDraw(account, roomRequest, await body(request));
          await index(cup.code);
          return json(cup);
        }
        if (path === '/cups' && request.method === 'GET') {
          const rows = await env.DB.prepare('SELECT cup_code FROM cup_memberships WHERE user_id=? ORDER BY joined_at DESC LIMIT 20').bind(account.id).all();
          const cups = await Promise.all(rows.results.map(async row => {
            const response = await roomRequest(row.cup_code, '/');
            return response.ok ? response.json() : null;
          }));
          return json({cups: cups.filter(cup => cup && (modern || (cup.size ?? 4) === 4))});
        }
        if (path === '/cups' && request.method === 'POST') {
          const data = await body(request);
          if (!/^[a-f0-9-]{36}$/i.test(data.requestID ?? '')) throw fail(400, 'Missing cup request ID.');
          const seed = await digest(account.id + ':' + data.requestID);
          const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
          const code = Array.from({length: 8}, (_, i) => alphabet[parseInt(seed.slice(i * 2, i * 2 + 2), 16) % alphabet.length]).join('');
          const count = await env.DB.prepare('SELECT COUNT(*) AS n FROM cup_memberships WHERE user_id=? AND joined_at>?').bind(account.id, Date.now() - 86400000).first();
          if (count.n >= 20) throw fail(429, 'You have joined twenty cups today. Try again tomorrow.');
          const response = await roomRequest(code, '/create', {level:data.level, surface:data.surface, title:data.title, name:data.name, size:modern && data.size === 8 ? 8 : 4, adaptive:data.adaptive === true, code});
          if (response.ok) await env.DB.prepare('INSERT OR IGNORE INTO cup_memberships VALUES(?,?,?)').bind(account.id, code, Date.now()).run();
          return response;
        }
        const route = path.match(/^\/cups\/([A-Z2-9]{8})(\/.*)?$/);
        if (!route || !validCode(route[1])) throw fail(404, 'Check the eight-character invite code.');
        const action = route[2] ?? '/';
        const write = ['/join', '/ready', '/start', '/leave'].includes(action);
        if (!write && action !== '/' && !/^\/matches\/(quarter-[1-4]|semi-[12]|final)\/socket$/.test(action)) throw fail(404, 'Not found');
        if ((write && request.method !== 'POST') || (!write && request.method !== 'GET')) throw fail(405, 'Method not allowed');
        const response = await roomRequest(route[1], action, write ? {...await body(request),clientVersion:modern ? 3 : 2} : undefined);
        if (response.ok && action === '/join') {
          await env.DB.prepare('INSERT OR IGNORE INTO cup_memberships VALUES(?,?,?)').bind(account.id, route[1], Date.now()).run();
        }
        return response;
      }
      if (path === '/auth/challenge' && request.method === 'POST') {
        const id = crypto.randomUUID(), nonce = randomToken();
        await env.DB.batch([
          env.DB.prepare('DELETE FROM auth_challenges WHERE expires_at<?').bind(Date.now()),
          env.DB.prepare('INSERT INTO auth_challenges VALUES(?,?,?)').bind(id, nonce, Date.now() + 300000)
        ]);
        return json({id, nonce});
      }
      if (path === '/auth/apple' && request.method === 'POST') {
        const data = await body(request);
        const challenge = await env.DB.prepare('SELECT * FROM auth_challenges WHERE id=? AND expires_at>?').bind(String(data.challengeId), Date.now()).first();
        if (!challenge) throw fail(401, 'Sign-in expired. Please try again.');
        let claims;
        try { claims = await verifyAppleToken(data.identityToken, {audience: env.APPLE_CLIENT_ID, nonce: challenge.nonce}); }
        catch { throw fail(401, 'Apple identity could not be verified'); }
        const used = await env.DB.prepare('DELETE FROM auth_challenges WHERE id=?').bind(challenge.id).run();
        if (used.meta.changes !== 1) throw fail(401, 'Sign-in was already used');
        const id = crypto.randomUUID(), emailMask = maskEmail(claims.email);
        await env.DB.prepare('INSERT INTO users VALUES(?,?,?,?) ON CONFLICT(apple_sub) DO UPDATE SET email_mask=excluded.email_mask')
          .bind(id, claims.sub, emailMask, Date.now()).run();
        const account = await env.DB.prepare('SELECT id,email_mask FROM users WHERE apple_sub=?').bind(claims.sub).first();
        const token = randomToken();
        await env.DB.prepare('INSERT INTO auth_sessions VALUES(?,?,?)').bind(await digest(token), account.id, Date.now() + 30 * 86400000).run();
        return json({token, userID: account.id, emailMask: account.email_mask, stRating: await ratingFor(env.DB, account.id)});
      }
      if (path === '/me' && request.method === 'GET') {
        const account = await user(request, env);
        return json({userID: account.id, emailMask: account.email_mask, stRating: await ratingFor(env.DB, account.id)});
      }
      if (path === '/me' && request.method === 'DELETE') {
        const account = await user(request, env);
        const cups = await env.DB.prepare('SELECT cup_code FROM cup_memberships WHERE user_id=?').bind(account.id).all();
        for (const row of cups.results) {
          const response = await env.CUPS.get(env.CUPS.idFromName(row.cup_code)).fetch(new Request('https://cup/delete-account', {
            method: 'POST', headers: {'X-Cup-User': JSON.stringify(account), 'Content-Type': 'application/json'}, body: '{}'}));
          if (!response.ok && ![403, 404].includes(response.status)) throw fail(503, 'Could not remove your cup profile. Please retry.');
        }
        await env.DB.prepare('DELETE FROM users WHERE id=?').bind(account.id).run();
        return json({deleted: true});
      }
      if (path === '/auth/logout' && request.method === 'POST') {
        await user(request, env);
        await env.DB.prepare('DELETE FROM auth_sessions WHERE token_hash=?').bind(await digest(request.headers.get('Authorization').slice(7))).run();
        return json({ok: true});
      }
      if (path === '/points' && request.method === 'POST') {
        const account = await user(request, env), data = await body(request);
        if (!Array.isArray(data.points) || data.points.length < 1 || data.points.length > 50) throw fail(400, 'Send 1 to 50 completed points');
        let points;
        try { points = data.points.map(validatePoint); } catch (error) { throw fail(400, error.message); }
        const statements = [];
        for (const sessionID of new Set(points.map(p => p.sessionID))) {
          const incoming = points.filter(p => p.sessionID === sessionID).sort((a, b) => a.pointIndex - b.pointIndex);
          const session = await env.DB.prepare('SELECT * FROM play_sessions WHERE id=?').bind(sessionID).first();
          if (session && (session.user_id !== account.id || session.format !== incoming[0].format)) throw fail(409, 'Session does not match this account');
          const rows = await env.DB.prepare('SELECT * FROM coach_points WHERE session_id=? ORDER BY point_index').bind(sessionID).all();
          const existing = rows.results.map(row => fromRow(row, session?.format ?? incoming[0].format));
          const all = [...existing];
          for (const point of incoming) {
            const old = all.find(p => p.pointIndex === point.pointIndex || p.id === point.id);
            if (old) {
              if (JSON.stringify(old) !== JSON.stringify(point)) throw fail(409, 'A completed point cannot be changed');
            } else all.push(point);
          }
          all.sort((a, b) => a.pointIndex - b.pointIndex);
          try { validateSequence(all); } catch (error) { throw fail(409, error.message); }
          if (!session) statements.push(env.DB.prepare('INSERT INTO play_sessions VALUES(?,?,?)').bind(sessionID, account.id, incoming[0].format));
          for (const point of all.filter(p => !existing.some(old => old.id === p.id))) {
            statements.push(env.DB.prepare('INSERT INTO coach_points VALUES(?,?,?,?,?,?,?,?,?,?,?)')
              .bind(point.id, account.id, sessionID, point.pointIndex, point.gameIndex, point.winner,
                point.cp, JSON.stringify(point.events), +point.gameCompleted, +point.setCompleted, Date.now()));
          }
        }
        if (statements.length) await env.DB.batch(statements);
        return json({accepted: points.map(p => p.id)});
      }
      if (path === '/leaderboard' && request.method === 'GET') {
        const metric = url.searchParams.get('metric') ?? 'point';
        if (!['point','game','set'].includes(metric)) throw fail(400, 'Unknown leaderboard');
        const scoreQuery = metric === 'point' ? 'SELECT user_id,cp AS score FROM coach_points'
          : metric === 'game' ? 'SELECT user_id,SUM(cp) AS score FROM coach_points GROUP BY session_id,game_index,user_id HAVING MAX(game_complete)=1'
          : 'SELECT user_id,SUM(cp) AS score FROM coach_points GROUP BY session_id,user_id HAVING MAX(set_complete)=1';
        const rows = await env.DB.prepare(`SELECT u.id,u.email_mask AS emailMask,MAX(s.score) AS score FROM (${scoreQuery}) s JOIN users u ON u.id=s.user_id GROUP BY u.id ORDER BY score DESC,u.id ASC LIMIT 10`).all();
        const count = await env.DB.prepare('SELECT COUNT(*) AS n FROM coach_points').first();
        const isDemo = count.n === 0;
        return json({metric, isDemo, entries: isDemo ? demoEntries(metric)
          : rows.results.map(row => ({...row, emailMask: publicPlayerName(row.emailMask)}))});
      }
      return json({error: 'Not found'}, 404);
    } catch (error) {
      return json({error: error.status ? error.message : 'Service unavailable. Please retry.'}, error.status ?? 503);
    }
  }
};
