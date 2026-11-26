import {completedScore, cupError, createCup, joinCup, startCup, recordResult, forfeitMatch, publicCup} from './cup-rules.mjs';
import {eligibleSTMatch, settleSTMatch, ratingFor} from './st-ratings.mjs';

const json = (value, status = 200) => Response.json(value, {status, headers: {'Cache-Control': 'no-store'}});
const reconnectWindow = 60000;

// One durable room serializes each cup's roster, bracket and match results. Native
// peers relay controls through it; the first human in a match owns its simulation.
// Ratings are settled by the service; the court simulation remains peer-authoritative.
export class CupRoom {
  constructor(ctx, env) {
    this.ctx = ctx; this.env = env; this.cup = null;
    ctx.blockConcurrencyWhile(async () => { this.cup = await ctx.storage.get('cup') ?? null; });
  }
  sockets(matchID) {
    return this.ctx.getWebSockets().filter(ws => ws.readyState === 1 && (!matchID || ws.deserializeAttachment()?.matchID === matchID));
  }
  send(ws, value) { try { ws.send(JSON.stringify(value)); } catch { /* Close is handled by the presence deadline. */ } }
  broadcast(value, matchID) { for (const ws of this.sockets(matchID)) this.send(ws, value); }
  async save() {
    this.cup.version++;
    await this.ctx.storage.put('cup', this.cup);
  }
  async announce() {
    // Persist the finished match before the external transaction, so a room restart
    // can retry safely even if D1 committed and its response was lost.
    await this.save();
    await this.settleRatings();
    this.broadcast({type: 'cup', cup: publicCup(this.cup)});
  }
  async settleRatings() {
    let changed = false;
    for (const game of this.cup.matches.filter(game => !game.stSettled && eligibleSTMatch(this.cup, game))) {
      try {
        game.ratingChanges = await settleSTMatch(this.env.DB, this.cup, game);
        for (const id of game.playerIDs) {
          this.cup.participants.find(p => p.id === id).stRating = await ratingFor(this.env.DB, id);
        }
        game.stSettled = true; changed = true;
      } catch {
        // Keep the bracket usable during a transient database outage, then retry.
        await this.ctx.storage.setAlarm(Date.now() + 30000);
      }
    }
    if (this.pendingTrophy()) {
      try {
        await this.env.DB.prepare('INSERT OR IGNORE INTO tour_trophies SELECT ?,id,?,?,?,? FROM users WHERE id=?')
          .bind(this.cup.code,this.cup.title,this.cup.division ?? 'Open',this.cup.size ?? 4,
            this.cup.finishedAt ?? Date.now(),this.cup.championID).run();
        this.cup.archived = true; changed = true;
      } catch { await this.ctx.storage.setAlarm(Date.now() + 30000); }
    }
    if (changed) await this.save();
  }
  pendingTrophy() {
    return this.cup.status === 'complete' && this.cup.size !== 2 && !this.cup.archived &&
      this.cup.participants.some(p => p.id === this.cup.championID && p.kind === 'human');
  }
  humans(game) { return game.playerIDs.filter(id => this.cup.participants.find(p => p.id === id)?.kind === 'human'); }
  connected(game) { return new Set(this.sockets(game.id).map(ws => ws.deserializeAttachment().userID)); }
  async presence(game) {
    if (game.status === 'complete') return;
    const online = this.connected(game), humans = this.humans(game), now = Date.now();
    game.missingSince ??= {};
    for (const id of humans) {
      if (online.has(id)) delete game.missingSince[id];
      else game.missingSince[id] ??= now;
    }
    // Both players must be connected. Never substitute a bot into a human's match.
    const deadline = Object.values(game.missingSince).length ? Math.min(...Object.values(game.missingSince)) + reconnectWindow : null;
    this.broadcast({type: 'presence', matchID: game.id, ready: humans.every(id => online.has(id)),
      connected: [...online], deadline}, game.id);
    const point = game.snapshot?.scoring?.points?.reduce((a, b) => a + b, 0) ?? 0;
    if (humans.every(id => online.has(id)) && game.advancePoint === point
      && (!game.snapshot || ['ready', 'point'].includes(game.snapshot.phase))) {
      this.broadcast({type: 'advance', point}, game.id);
    }
    await this.save();
    await this.schedule();
  }
  async schedule() {
    const deadlines = this.cup.matches.flatMap(m => this.cup.status === 'playing' && m.status === 'live'
      ? Object.values(m.missingSince ?? {}).map(time => time + reconnectWindow) : []);
    if (this.pendingTrophy() || this.cup.matches.some(game => !game.stSettled && eligibleSTMatch(this.cup, game))) deadlines.push(Date.now() + 30000);
    await this.ctx.storage.setAlarm(Math.max(Date.now() + 1000, Math.min(this.cup.expiresAt, ...deadlines)));
  }
  async fetch(request) {
    return this.ctx.blockConcurrencyWhile(async () => {
      try {
        const user = JSON.parse(request.headers.get('X-Cup-User') || 'null');
        if (!user?.id) throw cupError(401, 'Sign in to play a cup.');
        const path = new URL(request.url).pathname;
        const data = request.method === 'POST' ? await request.json() : {};
        if (path === '/create') {
          if (this.cup?.hostID === user.id) return json(publicCup(this.cup));
          if (this.cup) throw cupError(409, 'This invite code is already in use. Please retry.');
          this.cup = createCup(data.code, user, data);
          await this.save(); await this.schedule();
          return json(publicCup(this.cup));
        }
        if (!this.cup) throw cupError(404, 'Cup not found. Check the eight-character invite code.');
        if (Date.now() >= this.cup.expiresAt && !['complete', 'cancelled', 'expired'].includes(this.cup.status)) {
          this.cup.status = 'expired'; await this.announce();
        }
        if (path === '/join') {
          if (this.cup.size === 8 && data.clientVersion !== 3) throw cupError(409, 'Update SwipeTennis for eight-player cups.');
          joinCup(this.cup, user, data);
          if (this.cup.size === 2 && this.cup.participants.length === 2 && this.cup.status === 'lobby') {
            this.cup.participants.forEach(p => { p.ready = true; });
            startCup(this.cup, this.cup.hostID);
          }
          await this.announce();
          return json(publicCup(this.cup));
        }
        const member = this.cup.participants.find(p => p.id === user.id);
        if (!member) throw cupError(403, 'Join this cup with its invite code first.');
        if (path === '/' && request.method === 'GET') {
          await this.settleRatings();
          return json(publicCup(this.cup));
        }
        if (path === '/rematch-offer' && request.method === 'POST') {
          const game = this.cup.matches.find(m => m.id === data.match && m.status === 'complete' && m.playerIDs.includes(user.id));
          if (!game || this.humans(game).length !== 2) throw cupError(403, 'This match cannot offer a rematch.');
          if (!game.rematchRequestedBy) { game.rematchRequestedBy = user.id; await this.announce(); }
        } else if (path === '/ready') {
          if (this.cup.status !== 'lobby') throw cupError(409, 'The draw has already started.');
          member.ready = data.ready === true; await this.announce();
        } else if (path === '/start') {
          startCup(this.cup, user.id); await this.announce();
        } else if (path === '/leave' || path === '/delete-account') {
          if (this.cup.status === 'lobby') {
            this.cup.participants = this.cup.participants.filter(p => p.id !== user.id);
            if (this.cup.hostID === user.id) this.cup.status = 'cancelled';
          } else {
            member.withdrawn = true;
            for (const game of [...this.cup.matches]) forfeitMatch(this.cup, game, user.id);
          }
          if (path === '/delete-account') member.name = 'Deleted player';
          for (const ws of this.sockets().filter(ws => ws.deserializeAttachment().userID === user.id)) ws.close(1000, 'Left cup');
          await this.announce();
        } else {
          const socketRoute = path.match(/^\/matches\/(quarter-[1-4]|semi-[12]|final)\/socket$/);
          if (!socketRoute || request.headers.get('Upgrade')?.toLowerCase() !== 'websocket') throw cupError(404, 'Not found');
          const game = this.cup.matches.find(m => m.id === socketRoute[1]);
          if (!game?.playerIDs.includes(user.id)) throw cupError(403, 'This match belongs to other players.');
          if (this.cup.status !== 'playing' || game.status === 'complete') throw cupError(409, 'This match has ended.');
          const pair = new WebSocketPair(), [client, server] = Object.values(pair);
          for (const ws of this.sockets(game.id).filter(ws => ws.deserializeAttachment().userID === user.id)) ws.close(1000, 'Reconnected on another connection');
          this.ctx.acceptWebSocket(server);
          server.serializeAttachment({userID: user.id, matchID: game.id, expiresAt: Date.now() + 1800000,
            window: Date.now(), count: 0});
          game.status = 'live'; game.startedAt ??= Date.now();
          this.send(server, {type: 'welcome', cup: publicCup(this.cup), matchID: game.id,
            side: game.playerIDs.indexOf(user.id), authority: game.authorityID === user.id, snapshot: game.snapshot ?? null});
          await this.presence(game);
          return new Response(null, {status: 101, webSocket: client});
        }
        return json(publicCup(this.cup));
      } catch (error) { return json({error: error.status ? error.message : 'Cup unavailable. Please retry.'}, error.status ?? 503); }
    });
  }
  async webSocketMessage(ws, raw) {
    return this.ctx.blockConcurrencyWhile(async () => {
      try {
        const meta = ws.deserializeAttachment(), now = Date.now();
        if (!meta || now > meta.expiresAt) { ws.close(1008, 'Please reconnect'); return; }
        if (typeof raw !== 'string' || raw.length > 128000) throw cupError(413, 'Match message too large.');
        if (now - meta.window >= 1000) { meta.window = now; meta.count = 0; }
        if (++meta.count > 90) { ws.close(1008, 'Too many match messages'); return; }
        ws.serializeAttachment(meta);
        const game = this.cup.matches.find(m => m.id === meta.matchID), message = JSON.parse(raw);
        if (!game || game.status === 'complete' || this.cup.status !== 'playing') return;
        if (message.type === 'ping') { this.send(ws, {type: 'pong'}); return; }
        if (message.type === 'forfeit') {
          forfeitMatch(this.cup, game, meta.userID); await this.announce(); return;
        }
        const allHere = this.humans(game).every(id => this.connected(game).has(id));
        if (!allHere) return;
        if (message.type === 'input') {
          if (!message.input || JSON.stringify(message.input).length > 2000) throw cupError(400, 'Invalid control.');
          for (const peer of this.sockets(game.id).filter(peer => peer.deserializeAttachment().userID === game.authorityID)) {
            this.send(peer, {type: 'input', side: game.playerIDs.indexOf(meta.userID), input: message.input});
          }
        } else if (message.type === 'next') {
          const point = game.snapshot?.scoring?.points?.reduce((a, b) => a + b, 0) ?? 0;
          if (message.point !== point || game.advancePoint === point) return;
          if (game.snapshot && !['ready', 'point'].includes(game.snapshot.phase)) return;
          game.nextReady ??= [];
          if (!game.nextReady.includes(meta.userID)) game.nextReady.push(meta.userID);
          if (this.humans(game).every(id => game.nextReady.includes(id))) {
            if (this.humans(game).length === 2) game.ratedPlayStarted = true;
            game.nextReady = []; game.advancePoint = point;
            this.broadcast({type: 'advance', point}, game.id); await this.save();
          }
        } else if (message.type === 'snapshot') {
          if (meta.userID !== game.authorityID) throw cupError(403, 'Only the match host can send court state.');
          const state = message.snapshot;
          if (!state || !Array.isArray(state.players) || state.players.length !== 2 || !state.players.every(p =>
            p.pos && Number.isFinite(p.pos.x) && Number.isFinite(p.pos.y)) || state.scoring?.format !== 'Tiebreak'
            || !Array.isArray(state.scoring.points) || state.scoring.points.length !== 2
            || !state.scoring.points.every(n => Number.isSafeInteger(n) && n >= 0 && n <= 1000)
            || !['ready', 'serving', 'serveFault', 'live', 'point', 'finished'].includes(state.phase)
            || state.settings?.tournament !== true || state.settings.local !== (this.humans(game).length === 2)) {
            throw cupError(400, 'Invalid court state.');
          }
          const previous = game.snapshot?.scoring?.points ?? [0, 0];
          const change = state.scoring.points.map((n, i) => n - previous[i]);
          if (change.some(n => n < 0) || change[0] + change[1] > 1) throw cupError(409, 'Court score is out of sequence.');
          const total = previous[0] + previous[1];
          const scored = change[0] + change[1] > 0;
          if (!scored && ['serving','serveFault','live'].includes(state.phase) && game.advancePoint !== total) {
            throw cupError(409, 'Waiting for both players to advance.');
          }
          if (scored && (game.advancePoint !== total || !['point','finished'].includes(state.phase))) {
            throw cupError(409, 'Both players must advance before scoring a point.');
          }
          if (completedScore(state.scoring.points) !== (state.phase === 'finished')) {
            throw cupError(409, 'Match phase and tiebreak result disagree.');
          }
          if (scored) game.nextReady = [];
          game.snapshot = state; game.score = state.scoring.points;
          for (const peer of this.sockets(game.id).filter(peer => peer !== ws)) this.send(peer, message);
          if (state.phase === 'finished') {
            recordResult(this.cup, game.id, meta.userID, state.scoring.points); await this.announce();
          } else if (change[0] + change[1] > 0 || now - (game.lastSavedAt ?? 0) >= 2000) {
            game.lastSavedAt = now; await this.save();
          }
        }
      } catch (error) { this.send(ws, {type: 'error', message: error.status ? error.message : 'Match connection could not be updated.'}); }
    });
  }
  async webSocketClose(ws) {
    return this.ctx.blockConcurrencyWhile(async () => {
      const game = this.cup?.matches.find(m => m.id === ws.deserializeAttachment()?.matchID);
      if (game) {
        const id = ws.deserializeAttachment()?.userID;
        if (!this.connected(game).has(id)) game.nextReady = (game.nextReady ?? []).filter(ready => ready !== id);
        await this.presence(game);
      }
    });
  }
  async webSocketError(ws) { try { ws.close(1011, 'Reconnect to resume'); } catch {} await this.webSocketClose(ws); }
  async alarm() {
    return this.ctx.blockConcurrencyWhile(async () => {
      if (!this.cup) return;
      await this.settleRatings();
      if (Date.now() >= this.cup.expiresAt) {
        if (!['complete', 'cancelled'].includes(this.cup.status)) this.cup.status = 'expired';
        await this.announce();
        for (const ws of this.sockets()) ws.close(1000, 'Cup closed');
        // Retain results for 30 days, then remove the room and its account index.
        if (Date.now() >= this.cup.expiresAt + 30 * 86400000 && !this.pendingTrophy() && !this.cup.matches.some(g => !g.stSettled && eligibleSTMatch(this.cup,g))) {
          await this.env.DB.prepare('DELETE FROM cup_memberships WHERE cup_code=?').bind(this.cup.code).run();
          await this.ctx.storage.deleteAll(); this.cup = null;
        } else await this.ctx.storage.setAlarm(this.pendingTrophy() || this.cup.matches.some(game => !game.stSettled && eligibleSTMatch(this.cup, game))
          ? Date.now() + 30000 : this.cup.expiresAt + 30 * 86400000);
        return;
      }
      for (const game of [...this.cup.matches].filter(m => m.status === 'live')) {
        const online = this.connected(game);
        const absent = this.humans(game).filter(id => !online.has(id) && Date.now() - (game.missingSince?.[id] ?? Date.now()) >= reconnectWindow);
        if (absent.length === 1) forfeitMatch(this.cup, game, absent[0], 'disconnect');
        else if (absent.length > 1) {
          // With nobody present, stop the cup instead of inventing a winner.
          this.cup.status = 'cancelled';
          for (const ws of this.sockets()) ws.close(1000, 'Both players left');
        }
      }
      await this.announce(); await this.schedule();
    });
  }
}
