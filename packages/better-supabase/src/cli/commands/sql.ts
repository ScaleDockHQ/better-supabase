import { existsSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';

import type { ResolvedConfig } from '../../config/index.ts';
import type { ParsedArgs } from '../args.ts';
import type { CommandResult } from '../io.ts';

import { resolveJsonSchema } from '../../config/index.ts';
import {
  type KitLayout,
  renderKit,
  resolveModules,
  sameKitFile,
  SQL_MODULES,
} from '../../sql/kit.ts';
import { flagBool, flagString } from '../args.ts';
import { display, writeIfChanged } from '../io.ts';
import { compiledReadSets } from '../read-sets.ts';
import { VERSION } from '../version.ts';

export const SQL_HELP = `Usage: better-supabase sql <list|add|sync|print> [modules...]

  list                 Modules and whether they are installed
  add <module...>      Write the modules (and what they need) to sql.dir
  sync [--check]       Rewrite the modules in sql.kit; --check fails when a file is stale
  print <module>       Print a module's SQL, e.g. to paste into a migration

Options
  --tests-dir <dir>    Where the pgtap module goes. Defaults to sql.testsDir.
  --dry-run            Show what would be written`;

/** Where and how `sql add` writes kit files for this config. */
export function kitLayout(
  config: ResolvedConfig,
  testsDir: string = config.sql.testsDir,
  readSets: KitLayout['readSets'] = [],
): KitLayout {
  return {
    dir: config.sql.dir,
    prefix: config.sql.prefix,
    testsDir,
    version: VERSION,
    readSets,
    realtimeTables: config.realtime.tables,
    grants: Object.entries(config.expose).flatMap(([table, roles]) => [
      { table, role: 'anon' as const, privileges: roles.anon },
      {
        table,
        role: 'authenticated' as const,
        privileges: roles.authenticated,
      },
    ]),
    jsonSchemas: Object.entries(config.json).flatMap(([key, entry]) => {
      if (!entry.schema) return [];
      const dot = key.lastIndexOf('.');
      return [
        {
          table: key.slice(0, dot),
          column: key.slice(dot + 1),
          schema: resolveJsonSchema(entry.schema),
        },
      ];
    }),
    ...(config.plugins.tenant
      ? { tenantColumn: config.plugins.tenant.column }
      : {}),
  };
}

function layout(config: ResolvedConfig, args: ParsedArgs): KitLayout {
  return kitLayout(config, flagString(args.flags, 'tests-dir'));
}

/** The layout, with `config.readSets` compiled when `names` includes `read-sets`. */
async function layoutFor(
  config: ResolvedConfig,
  args: ParsedArgs,
  names: readonly string[],
): Promise<KitLayout> {
  const needsReadSets = resolveModules(names).some(
    (module) => module.name === 'read-sets',
  );
  return kitLayout(
    config,
    flagString(args.flags, 'tests-dir'),
    needsReadSets ? await compiledReadSets(config) : [],
  );
}

async function write(
  config: ResolvedConfig,
  args: ParsedArgs,
  names: readonly string[],
): Promise<string[]> {
  const lines: string[] = [];
  const dryRun = flagBool(args.flags, 'dry-run');
  for (const file of renderKit(names, await layoutFor(config, args, names))) {
    const path = resolve(config.root, file.path);
    const shown = display(config.root, file.path);
    if (dryRun) {
      lines.push(`Would write ${shown} (${file.module})`);
      continue;
    }
    const wrote = await writeIfChanged(path, file.contents);
    lines.push(`${wrote ? 'Wrote' : 'Unchanged'} ${shown} (${file.module})`);
  }
  return lines;
}

export async function runSql(
  config: ResolvedConfig,
  args: ParsedArgs,
): Promise<CommandResult> {
  const [action, ...names] = args.rest;
  switch (action) {
    case 'list': {
      const files = new Map(
        renderKit(Object.keys(SQL_MODULES), layout(config, args)).map(
          (file) => [file.module, file.path],
        ),
      );
      const lines = Object.values(SQL_MODULES).map((module) => {
        const path = files.get(module.name)!;
        const installed = existsSync(resolve(config.root, path));
        const tracked = config.sql.kit.includes(module.name);
        const mark = installed ? (tracked ? '●' : '○') : ' ';
        const needs =
          module.requires.length > 0
            ? ` (needs ${module.requires.join(', ')})`
            : '';
        return `${mark} ${module.name.padEnd(15)} ${module.description}${needs}`;
      });
      return {
        code: 0,
        output: `${lines.join('\n')}\n\n● installed and in sql.kit   ○ installed, not in sql.kit`,
      };
    }
    case 'add': {
      if (names.length === 0) {
        return { code: 2, error: `Name at least one module.\n\n${SQL_HELP}` };
      }
      const unknown = names.filter((name) => !(name in SQL_MODULES));
      if (unknown.length > 0) {
        return {
          code: 2,
          error: `Unknown module ${unknown.join(', ')}. Available: ${Object.keys(SQL_MODULES).join(', ')}`,
        };
      }
      const lines = await write(config, args, names);
      const untracked = resolveModules(names)
        .map((module) => module.name)
        .filter((name) => !config.sql.kit.includes(name));
      if (untracked.length > 0) {
        lines.push(
          '',
          `Add them to your config so \`sql sync --check\` keeps them current:`,
          `  sql: { kit: [${[...config.sql.kit, ...untracked].map((name) => `'${name}'`).join(', ')}] }`,
        );
      }
      lines.push(
        '',
        'Then create a migration: supabase db diff -f better_supabase_kit',
      );
      return { code: 0, output: lines.join('\n') };
    }
    case 'sync': {
      if (config.sql.kit.length === 0) {
        return { code: 0, output: 'sql.kit is empty; nothing to sync.' };
      }
      if (!flagBool(args.flags, 'check')) {
        return {
          code: 0,
          output: (await write(config, args, config.sql.kit)).join('\n'),
        };
      }
      const stale: string[] = [];
      for (const file of renderKit(
        config.sql.kit,
        await layoutFor(config, args, config.sql.kit),
      )) {
        const current = await readFile(
          resolve(config.root, file.path),
          'utf8',
        ).catch(() => undefined);
        if (!sameKitFile(current, file.contents))
          stale.push(display(config.root, file.path));
      }
      return stale.length === 0
        ? { code: 0, output: 'SQL kit files are up to date.' }
        : {
            code: 1,
            error: `Out of date: ${stale.join(', ')}. Run \`better-supabase sql sync\`.`,
          };
    }
    case 'print': {
      const [name] = names;
      const module = name ? SQL_MODULES[name] : undefined;
      if (!module) {
        return {
          code: 2,
          error: `Name one module: ${Object.keys(SQL_MODULES).join(', ')}`,
        };
      }
      return { code: 0, output: module.sql };
    }
    case undefined:
      return { code: 2, error: SQL_HELP };
    default:
      return {
        code: 2,
        error: `Unknown sql action "${action}".\n\n${SQL_HELP}`,
      };
  }
}
