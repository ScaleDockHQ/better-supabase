import { readdir } from "node:fs/promises";
import { resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { AppliedPlan, PlanFlags } from "../core/files.ts";

import { applyPlan, ExclusiveClash } from "../core/files.ts";
import { sqlPlan } from "../sql-layout.ts";
import { migrationFile } from "./migration-names.ts";

const ATTEMPTS = 5;

/**
 * Writes a migration under a stamp no other process holds. The name comes from
 * the folder as it is, the file is created exclusively, and a clash (another
 * tool took the stamp in between) reads the folder again and picks the next
 * one, so a concurrent `supabase db diff` never loses its file to this one.
 */
export async function writeMigration(
  config: ResolvedConfig,
  options: {
    readonly dir: string;
    readonly now: () => Date;
    readonly suffix: string;
    readonly contents: string;
    readonly regenerate: string;
    readonly flags: PlanFlags;
    readonly reuse?: boolean;
    /** Names to count besides the folder's, such as a reviewed set. */
    readonly existing?: readonly string[];
  },
): Promise<{ readonly path: string; readonly applied: AppliedPlan }> {
  for (let attempt = 1; ; attempt += 1) {
    const names: string[] = [
      ...(await readdir(resolve(config.root, options.dir)).catch(
        (): string[] => [],
      )),
      ...(options.existing ?? []),
    ];

    const path = `${options.dir}/${
      migrationFile(
        names,
        options.now(),
        options.suffix,
        options.contents,
        options.reuse ?? true,
      ).name
    }`;

    try {
      const applied = await applyPlan(
        sqlPlan(config, {
          regenerate: options.regenerate,
          files: [{ path, contents: options.contents, exclusive: true }],
        }),
        options.flags,
      );

      return { path, applied };
    } catch (error) {
      if (!(error instanceof ExclusiveClash) || attempt >= ATTEMPTS) {
        throw error;
      }
    }
  }
}
