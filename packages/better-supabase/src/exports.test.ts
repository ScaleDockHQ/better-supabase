import { readFile } from 'node:fs/promises';
import { describe, expect, it } from 'vitest';

import packageJson from '../package.json' with { type: 'json' };

const subpaths = Object.keys(packageJson.exports).filter(
  (key) => key !== './package.json' && key !== './schemas/*.json',
);

const entryOf = (subpath: string): string =>
  subpath === '.' ? 'index' : `${subpath.slice(2)}/index`;

/** Type-only exports declared in an entry file: `export type { A }`, `export interface B`, `export type * from`. */
function typeExports(source: string): string[] {
  const names = new Set<string>();
  for (const match of source.matchAll(/export\s+type\s*\{([^}]*)\}/g)) {
    for (const part of match[1]!.split(',')) {
      const name = part
        .trim()
        .split(/\s+as\s+/)
        .at(-1);
      if (name) names.add(name);
    }
  }
  for (const match of source.matchAll(/export\s*\{([^}]*)\}/g)) {
    for (const part of match[1]!.split(',')) {
      const inline = /^\s*type\s+(\S+)(?:\s+as\s+(\S+))?/.exec(part);
      if (inline) names.add(inline[2] ?? inline[1]!);
    }
  }
  for (const match of source.matchAll(
    /export\s+(?:declare\s+)?(?:interface|type)\s+([A-Za-z_$][\w$]*)/g,
  )) {
    names.add(match[1]!);
  }
  for (const match of source.matchAll(
    /export\s+type\s+\*\s+from\s+'([^']+)'/g,
  )) {
    names.add(`* from ${match[1]!}`);
  }
  return [...names].toSorted((a, b) => a.localeCompare(b));
}

describe('public API', () => {
  it('builds every subpath in package.json', async () => {
    const config = await readFile(
      new URL('../tsdown.config.ts', import.meta.url),
      'utf8',
    );
    for (const subpath of subpaths)
      expect(config).toContain(`'${entryOf(subpath)}'`);
  });

  it('matches the export snapshot', { timeout: 30_000 }, async () => {
    const api: Record<string, { values: string[]; types: string[] }> = {};
    for (const subpath of subpaths) {
      const file = new URL(`./${entryOf(subpath)}.ts`, import.meta.url);
      const module = (await import(file.href)) as Record<string, unknown>;
      api[subpath] = {
        values: Object.keys(module).toSorted((a, b) => a.localeCompare(b)),
        types: typeExports(await readFile(file, 'utf8')),
      };
    }
    await expect(`${JSON.stringify(api, null, 2)}\n`).toMatchFileSnapshot(
      '../api/exports.json',
    );
  });
});
