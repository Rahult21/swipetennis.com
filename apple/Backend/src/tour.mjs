import {cupError, division, displayName, validCode} from './cup-rules.mjs';
import {publicPlayerName} from './rules.mjs';
import {digest} from './apple-auth.mjs';

const day = 86400000;
function weekStart(now) {
  const midnight = Math.floor(now/day)*day;
  return midnight - ((new Date(midnight).getUTCDay()+6)%7)*day;
}
async function codeFor(seed) {
  const hash = await digest(seed);
  return Array.from({length:8}, (_, i) => 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'[parseInt(hash.slice(2*i,2*i+2),16)%32]).join('');
}
async function read(response) {
  const value = await response.json();
  if (!response.ok) throw cupError(response.status,value.error || 'Draw unavailable.');
  return value;
}
export async function findDraw(db, account, room, data) {
  const now = Date.now(), weekly = data.mode === 'weekly';
  const band = division(account.stRating.points), week = weekStart(now);
  const pool = [weekly ? week : 'duel',band].join('/');
  const size = weekly ? 8 : 2;
  // Publish only initialized rooms. A conditional insert elects one lobby when
  // multiple entrants arrive together. Unlisted candidate rooms expire normally.
  let candidate;
  for (let attempt=0; attempt<4; attempt++) {
    const row = await db.prepare('SELECT * FROM tour_draws WHERE pool=?').bind(pool).first();
    if (row && row.expires > now) {
      const response = await room(row.code,'/join',{name:data.name,clientVersion:3});
      if (response.ok) {
        const existing = await read(response);
        if (['playing','lobby'].includes(existing.status)) return existing;
      }
      if (!response.ok && ![404,409].includes(response.status)) return read(response);
    }
    if (row) await db.prepare('DELETE FROM tour_draws WHERE pool=? AND code=?').bind(pool,row.code).run();
    if (!candidate) {
      const code = await codeFor(crypto.randomUUID());
      candidate = await read(await room(code,'/create',{code,size,divisionLocked:true, adaptive:true, level:'medium',surface:weekly ? ['grass','clay','hard'][Math.floor(week/(7*day))%3] : 'hard',
        eventWeek:weekly ? week : undefined, name:data.name,title:weekly ? band+' Weekly Open' : band+' Match'}));
    }
    const result = await db.prepare('INSERT OR IGNORE INTO tour_draws VALUES(?,?,?)').bind(pool,candidate.code,candidate.expiresAt).run();
    if (result.meta.changes) return candidate;
  }
  throw cupError(409,'The draw just filled. Find another opponent.');
}
export async function rematchDraw(account,room,data) {
  if (!validCode(data.code)) throw cupError(400,'Unknown draw.');
  const source = await read(await room(data.code,'/'));
  const match = source.matches.find(m => m.id === data.match && m.status === 'complete' && m.playerIDs.includes(account.id));
  if (!match || !match.playerIDs.every(id => source.participants.some(p=>p.id===id && p.kind==='human'))) throw cupError(403,'Choose a completed human match.');
  const code = await codeFor('rematch/'+source.code+'/'+match.id);
  const response = await room(code,'/create',{code,size:2,title:'Rematch',surface:source.surface,level:source.level,
    adaptive:true,restrictedTo:match.playerIDs,name:source.participants.find(p=>p.id===account.id).name});
  const cup = response.status === 409
    ? await read(await room(code,'/join',{clientVersion:3}))
    : await read(response);
  await read(await room(source.code,'/rematch-offer',{match:match.id}));
  return cup;
}
export async function clubAction(db,id,data) {
  if (data.action === 'leave') {
    await db.prepare('DELETE FROM tour_members WHERE user_id=?').bind(id).run();
    return {ok:true};
  }
  if (!['join','create'].includes(data.action)) throw cupError(400,'Unknown club action.');
  if (await db.prepare('SELECT 1 FROM tour_members WHERE user_id=?').bind(id).first()) throw cupError(409,'Leave your current club first.');
  if (data.action === 'create') {
    if (!String(data.name ?? '').trim()) throw cupError(400,'Enter a club name.');
    const code = await codeFor(crypto.randomUUID());
    await db.batch([db.prepare('INSERT INTO tour_clubs VALUES(?,?)').bind(code,displayName(data.name)),
      db.prepare('INSERT INTO tour_members VALUES(?,?)').bind(id,code)]);
  } else {
    const code = String(data.code ?? '').trim().toUpperCase();
    if (!validCode(code) || !await db.prepare('SELECT 1 FROM tour_clubs WHERE code=?').bind(code).first()) throw cupError(404,'Check the club invite code.');
    await db.prepare('INSERT INTO tour_members VALUES(?,?)').bind(id,code).run();
  }
  return {ok:true};
}
export async function career(db,id,now=Date.now()) {
  const rows = async (sql,...args) => (await db.prepare(sql).bind(...args).all()).results;
  const history = `WITH mine AS (SELECT created_at,CASE WHEN player0=?1 THEN player1 ELSE player0 END opponent,
    CASE WHEN (player0=?1 AND winner=0) OR (player1=?1 AND winner=1) THEN 1 ELSE 0 END win,
    CASE WHEN player0=?1 THEN after0 ELSE after1 END rating FROM st_results WHERE applied=1 AND (player0=?1 OR player1=?1)) `;
  const date = new Date(now), quarter = Math.floor(date.getUTCMonth()/3);
  const seasonStart = Date.UTC(date.getUTCFullYear(),3*quarter,1);
  const [trophies,rivals,trend,summary,club] = await Promise.all([
    rows('SELECT code,title,division,size,won_at AS wonAt FROM tour_trophies WHERE owner=? ORDER BY won_at DESC',id),
    rows(history+'SELECT opponent AS id,u.email_mask AS name, SUM(win) wins,COUNT(*)-SUM(win) losses FROM mine JOIN users u ON u.id=opponent GROUP BY opponent ORDER BY COUNT(*) DESC,opponent',id),
    rows(history+'SELECT created_at AS time,rating FROM mine ORDER BY created_at DESC LIMIT 30',id),
    db.prepare(history+`SELECT COUNT(*) matches, COUNT(DISTINCT CAST(created_at/86400000 AS INTEGER)) activeDays,
      COUNT(CASE WHEN created_at>=?2 THEN 1 END) seasonMatches, COALESCE(SUM(CASE WHEN created_at>=?2 THEN win ELSE 0 END),0) seasonWins FROM mine`).bind(id,seasonStart).first(),
    db.prepare('SELECT c.* FROM tour_clubs c JOIN tour_members m ON m.club=c.code WHERE m.user_id=?').bind(id).first()
  ]);
  const ladder = club ? await rows(`SELECT u.id,u.email_mask name,COALESCE(r.points,4) rating FROM tour_members m JOIN users u ON m.user_id=u.id
    LEFT JOIN st_ratings r ON r.user_id=u.id WHERE m.club=? ORDER BY rating DESC,u.id`,club.code) : [];
  for (const player of [...rivals,...ladder]) player.name = publicPlayerName(player.name);
  return {trophies,rivals,trend:trend.reverse(),summary,club,ladder,season:date.getUTCFullYear()+' · Season '+(quarter+1)};
}
