import {test} from 'node:test';
import assert from 'node:assert/strict';
import {shouldMigrate} from '../scripts/migrate-ci.mjs';
import site from '../src/site-worker.mjs';

test('only Cloudflare production builds apply remote migrations', () => {
  assert.equal(shouldMigrate({WORKERS_CI: '1', WORKERS_CI_BRANCH: 'main'}), true);
  for (const env of [{}, {CI: 'true'}, {WORKERS_CI: '1'}, {WORKERS_CI_BRANCH: 'main'},
    {WORKERS_CI: '1', WORKERS_CI_BRANCH: 'codex/preview'}, {WORKERS_CI: '0', WORKERS_CI_BRANCH: 'main'}]) {
    assert.equal(shouldMigrate(env), false);
  }
});

test('API routing leaves website assets intact', async () => {
  const env = {ASSETS: {fetch: request => new Response(`asset:${new URL(request.url).pathname}`)}};
  assert.deepEqual(await (await site.fetch(new Request('https://swipetennis.com/api/health'), env)).json(),
    {ok: true, rulesVersion: 1});
  assert.equal(await (await site.fetch(new Request('https://swipetennis.com/'), env)).text(), 'asset:/');
  assert.equal(await (await site.fetch(new Request('https://swipetennis.com/assets/site.css'), env)).text(), 'asset:/assets/site.css');
});
