#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, lstatSync } from 'node:fs';

const directory = '.release-local';
const status = spawnSync('git', ['status', '--porcelain'], { encoding: 'utf8' });
if (status.status !== 0 || status.stdout.trim()) {
  throw new Error('Source releases require a clean committed tree; use the development build provenance for uncommitted patches.');
}
if (existsSync(directory) && (!lstatSync(directory).isDirectory() || lstatSync(directory).isSymbolicLink())) {
  throw new Error('The source archive directory must be a real directory');
}
mkdirSync(directory, { recursive: true });
const output = `${directory}/source.tar.gz`;
if (existsSync(output)) throw new Error('Preserve the existing source archive before building a different release');
const result = spawnSync('git', ['archive', '--format=tar.gz', `--output=${output}`, 'HEAD'], { stdio: 'inherit' });
if (result.error) console.error(result.error.message);
process.exitCode = result.status ?? 1;
