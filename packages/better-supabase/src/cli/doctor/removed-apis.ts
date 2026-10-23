import type { DoctorContext, FindingInput, Rule } from "./rules.ts";

import {
  BLOCK_EXPORT_RENAMES,
  BLOCK_SUBPATH_RENAMES,
  PLUGIN_SUBPATH_RENAMES,
  SPEC_SUBPATH_RENAMES,
} from "../codemod-block-renames.ts";

const SPECIFIER = /from\s+["']better-supabase\/([\w./-]+)["']/g;

const NAMED_IMPORT =
  /import\s+(?:type\s+)?\{([^}]*)\}\s+from\s+["']better-supabase(?:\/[\w./-]+)?["']/g;

/** Names 0.15 removed without a one-to-one replacement, with what replaces them. */
const REMOVED_NAMES: readonly { pattern: RegExp; replacement: string }[] = [
  {
    pattern: /\b(?:sectionAction|recordServer|defineRecordFeature)\b/,
    replacement:
      "the generated record type (`bsb.record(<type>Record)` from `@/lib/supabase/records/<type>`)",
  },
  {
    pattern: /["'][@~]?\/?[\w/]*supabase\/features\//,
    replacement: "the generated `records/<type>` file",
  },
  {
    pattern:
      /\b(?:fileMaintenance|updateMaintenance|listMaintenance|maintenanceRequestInputSchema)\b/,
    replacement: 'a tasks instance (`block: "tasks"`) and its client',
  },
  {
    pattern: /\bpass_credit_entries\b/,
    replacement: "`credits(passId)` on the ledger",
  },
  {
    pattern: /\.blockRouter\(/,
    replacement:
      "`bsb.router(defineApi(betterSupabase, options))`, which routes every block instance and table",
  },
  {
    pattern: /\brequireTenant\b/,
    replacement: "`requireOrganization` (`bsb codemod 0.15` renames it)",
  },
  {
    pattern:
      /["']better-supabase\/(?:blocks\/[\w-]+\/(?:react|vue|svelte|solid)|chat-sdk\/react)["']/,
    replacement:
      "the block's React hooks from the registry (`npx shadcn add @better-supabase/use-<block>`), or `useBlockController(create<Block>Controller, options)` from `better-supabase/vue`, `/svelte` or `/solid`",
  },
  {
    pattern: /["']better-supabase\/powersync\/react["']|\buseWatch\b/,
    replacement:
      "`engine: powersyncEngine(database, { connector })` on the client and the generated data hooks; `useSyncStatus()` and `useConflicts()` come from `better-supabase/react`",
  },
  {
    pattern: /\bsqliteTables\b/,
    replacement:
      "`powersyncEngine(database)`, which refreshes the hooks that read a changed table",
  },
  {
    pattern: /["']better-supabase\/expo-sqlite["']|\bexpoSqliteExecutor\b/,
    replacement:
      "`sqliteEngine(expoSqliteDatabase(db))` from `better-supabase/sqlite`, passed as the client's `engine`",
  },
  {
    pattern:
      /["']better-supabase\/tanstack-db\/supabase["']|\bsupabaseCollection\b/,
    replacement:
      "`collectionOptions` from `better-supabase/tanstack-db`, with `tanstackDbEngine({ collections })` and `live: realtimeChanges(...)` for Realtime",
  },
];

function lineAt(text: string, index: number): number {
  return text.slice(0, index).split("\n").length;
}

function renamedSubpath(subpath: string): string | undefined {
  if (Object.hasOwn(BLOCK_SUBPATH_RENAMES, subpath)) {
    return `better-supabase/${BLOCK_SUBPATH_RENAMES[subpath]}`;
  }

  if (Object.hasOwn(PLUGIN_SUBPATH_RENAMES, subpath)) {
    const to = PLUGIN_SUBPATH_RENAMES[subpath];

    return to ? `better-supabase/${to}` : "better-supabase";
  }

  if (Object.hasOwn(SPEC_SUBPATH_RENAMES, subpath)) {
    return `better-supabase/${SPEC_SUBPATH_RENAMES[subpath]}`;
  }

  return undefined;
}

/**
 * App code that still imports a subpath or name 0.15 renamed or removed
 * (BS418).
 */
function removedApis(context: DoctorContext): FindingInput[] {
  const findings: FindingInput[] = [];

  for (const file of context.sources) {
    for (const match of file.text.matchAll(SPECIFIER)) {
      const subpath = match[1] ?? "";
      const to = renamedSubpath(subpath);

      if (to !== undefined) {
        findings.push({
          message: `${file.path} imports \`better-supabase/${subpath}\`, which 0.15 renamed to \`${to}\`. Run \`bsb codemod 0.15\`.`,
          target: `${file.path}:${subpath}`,
          location: { file: file.path, line: lineAt(file.text, match.index) },
        });
      }
    }

    for (const match of file.text.matchAll(NAMED_IMPORT)) {
      const names = (match[1] ?? "")
        .split(",")
        .map((name) =>
          name
            .trim()
            .replace(/^type\s+/, "")
            .split(/\s+as\s+/)[0]
            ?.trim(),
        )
        .filter((name): name is string => Boolean(name));

      for (const name of names) {
        if (Object.hasOwn(BLOCK_EXPORT_RENAMES, name)) {
          findings.push({
            message: `${file.path} imports \`${name}\`, which 0.15 renamed to \`${BLOCK_EXPORT_RENAMES[name]}\`. Run \`bsb codemod 0.15\`.`,
            target: `${file.path}:${name}`,
            location: { file: file.path, line: lineAt(file.text, match.index) },
          });
        }
      }
    }

    for (const { pattern, replacement } of REMOVED_NAMES) {
      const match = pattern.exec(file.text);

      if (match) {
        findings.push({
          message: `${file.path} uses \`${match[0].replaceAll(/["']/g, "")}\`, which 0.15 removed. Use ${replacement} instead.`,
          target: `${file.path}:${match[0]}`,
          location: { file: file.path, line: lineAt(file.text, match.index) },
        });
      }
    }
  }

  return findings;
}

export const REMOVED_API_RULES: readonly Rule[] = [
  {
    code: "BS418",
    severity: "warning",
    title: "Code uses an API that 0.15 renamed or removed",
    description:
      "0.15 renamed blocks and their subpaths, turned the built-in plugins into block extensions, moved the OpenAPI, AsyncAPI, Arazzo and Overlay subpaths into `better-supabase/spec` and replaced record features with record types. `better-supabase codemod 0.15` rewrites the renames; the removed APIs need the replacement the finding names.",
    check: removedApis,
  },
];
