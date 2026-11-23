import type { DoctorContext, FindingInput } from "./rules.ts";

import {
  blockSqlVersion,
  moduleFileVersion,
  SQL_MODULES,
} from "../../sql/index.ts";
import { migrationCommand } from "../supabase-config.ts";
import { moduleFiles } from "./module-files.ts";
import { workflowOf } from "./shared.ts";

/**
 * The block files and `better_supabase.blocks` rows older than the module
 * version this release ships (BS311).
 */
export async function moduleVersionsBehind(
  context: DoctorContext,
): Promise<FindingInput[]> {
  const findings: FindingInput[] = [];
  const upgrade = "Run `better-supabase upgrade`";

  for (const { file, path, installed, behind } of await moduleFiles(context)) {
    if (!behind || installed === undefined) {
      continue;
    }

    findings.push({
      message: `${path} has ${file.instance ?? file.module} version ${String(installed)}; this release ships version ${String(moduleFileVersion(file.contents)?.version ?? 1)}. ${upgrade}, then \`${migrationCommand(workflowOf(context))}\`.`,
      target: path,
      location: { file: path, line: 1 },
    });
  }

  const db = context.database;

  if (!db || "skipped" in db || context.config.blockNames.length === 0) {
    return findings;
  }

  let rows: { name: string; version: number }[];

  try {
    rows = await db.query("select name, version from better_supabase.blocks");
  } catch {
    try {
      rows = await db.query(
        "select name, version from better_supabase.modules",
      );
    } catch {
      return findings;
    }
  }

  for (const row of rows) {
    const module = SQL_MODULES[row.name];

    if (!module || !context.config.blockNames.includes(row.name)) {
      continue;
    }

    const version = blockSqlVersion(module);

    if (row.version >= version) {
      continue;
    }

    findings.push({
      message: `The database has ${row.name} version ${String(row.version)}; this release ships version ${String(version)}. ${upgrade} and apply the migrations it prints.`,
      target: `better_supabase.blocks.${row.name}`,
    });
  }

  return findings;
}
