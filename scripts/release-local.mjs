#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const project = resolve(dirname(fileURLToPath(import.meta.url)), '..');
// An explicit override is authoritative: never fall back if it is missing.
const override = process.env.PERSONAL_RELEASE_TOOLS;
let tools = override !== undefined ? resolve(override) : resolve(project, '../release-tools');
if (override === undefined && !existsSync(join(tools, 'bin/release.mjs'))) {
  const common = spawnSync('git', ['--no-optional-locks', 'rev-parse', '--git-common-dir'], {
    cwd: project, encoding: 'utf8', shell: false,
  });
  if (common.status === 0) {
    const canonical = dirname(resolve(project, common.stdout.trim()));
    tools = resolve(canonical, '../release-tools');
  }
}
const entry = join(tools, 'bin/release.mjs');
if (override === '' || !existsSync(entry)) {
  console.error('Local release tools are missing. Install the release-tools sibling checkout with pnpm install --frozen-lockfile, or set PERSONAL_RELEASE_TOOLS to its directory.');
  process.exit(1);
}
// Pin validation happens in the standalone wrapper before loading engine code.
try {
  const configPath = join(project, '.release-local.json');
  const engine = existsSync(configPath) ? JSON.parse(readFileSync(configPath, 'utf8')).engine : undefined;
  if (engine !== undefined) {
    if (!engine || Object.keys(engine).sort().join(',') !== 'commit,version' || !/^[a-f0-9]{40}$/.test(engine.commit) || typeof engine.version !== 'string') throw new Error('Invalid engine pin');
    const git = (...args) => {
      const r = spawnSync('git', ['--no-optional-locks', ...args], { cwd: tools, encoding: 'utf8', shell: false });
      if (r.status !== 0) throw new Error('Pinned engine must be a Git checkout');
      return r.stdout.trim();
    };
    if (git('rev-parse', '--show-toplevel') !== resolve(tools)) throw new Error('Engine path must be its checkout root');
    if (git('rev-parse', 'HEAD') !== engine.commit) throw new Error('Engine commit pin mismatch');
    if (git('status', '--porcelain', '--untracked-files=all')) throw new Error('Pinned engine tree must be clean');
    const pkg = JSON.parse(readFileSync(join(tools, 'package.json'), 'utf8'));
    if (pkg.version !== engine.version) throw new Error('Engine version pin mismatch');
    const semver = createRequire(join(tools, 'package.json'))('semver');
    if (typeof pkg.engines?.node !== 'string' || !semver.satisfies(process.version, pkg.engines.node)) throw new Error('Running Node does not satisfy pinned engine engines.node');
  }
} catch (error) {
  console.error(`Release engine pin rejected: ${error.message}`);
  process.exit(1);
}
const result = spawnSync(process.execPath, [entry, ...process.argv.slice(2), '--cwd', project], { stdio: 'inherit', cwd: project });
if (result.error) console.error(result.error.message);
if (result.signal) console.error(`Release command terminated by ${result.signal}`);
process.exitCode = result.status ?? 1;
