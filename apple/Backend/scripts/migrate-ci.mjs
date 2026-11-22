import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {resolve} from 'node:path';

export function shouldMigrate(env) {
  return env.WORKERS_CI === '1' && env.WORKERS_CI_BRANCH === 'main';
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  if (shouldMigrate(process.env)) {
    console.log('Applying pending swipetennisdb migrations before production deployment.');
    const root = fileURLToPath(new URL('../../../', import.meta.url));
    const result = spawnSync(process.execPath, [resolve(root, 'node_modules/wrangler/bin/wrangler.js'),
      'd1', 'migrations', 'apply', 'swipetennisdb', '--remote', '--config', resolve(root, 'wrangler.jsonc')],
      {stdio: 'inherit', cwd: root, env: {...process.env, CI: 'true'}});
    if (result.error) console.error(result.error.message);
    process.exit(result.status ?? 1);
  } else {
    console.log('Skipping remote D1 migrations: this is not a Cloudflare main-branch build.');
  }
}
