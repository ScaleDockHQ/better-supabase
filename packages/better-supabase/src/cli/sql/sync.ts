import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { CommandResult } from "../core/io.ts";
import type { Paint } from "../style.ts";
import type { SqlFlags } from "./args.ts";
import type { Now } from "./migrations.ts";

import {
  type ModuleLayout,
  moduleTopics,
  renderModules,
  sameModuleFile,
} from "../../sql/index.ts";
import { applyPlan, changeLines, planResult } from "../core/files.ts";
import { display } from "../core/io.ts";
import { fileDiff } from "../diff.ts";
import { migrationsDir, sqlPlan } from "../sql-layout.ts";
import { topicPolicyFile } from "../topic-policies.ts";
import {
  latestMigration,
  MODULES_SUFFIX,
  renderModuleMigration,
  sameModuleMigration,
  writesMigrations,
} from "./module-migration.ts";
import { layoutFor } from "./providers.ts";
import { moduleFile, staleModuleTests, write } from "./write.ts";

export async function syncModules(
  config: ResolvedConfig,
  args: SqlFlags,
  paint: Paint,
  now: Now,
): Promise<CommandResult> {
  const topics = await topicPolicyFile(
    config,
    config.blockNames.length === 0
      ? []
      : moduleTopics(
          config.blockNames,
          await layoutFor(config, args, config.blockNames),
        ),
  );

  const hasSql =
    config.blockNames.length > 0 || Object.keys(config.appTables).length > 0;

  if (!hasSql && topics === undefined) {
    return {
      code: 0,
      output: "blocks is empty; nothing to sync.",
      data: { blocks: [] },
    };
  }

  if (await writesMigrations(config)) {
    const sqlLayout = await layoutFor(config, args, config.blockNames);

    if (args.check === true) {
      return checkModuleMigration(config, sqlLayout, paint, topics?.contents);
    }

    const lines = await write(config, args, config.blockNames, sqlLayout, now);

    return {
      code: 0,
      output: lines.join("\n"),
      data: { blocks: config.blockNames },
    };
  }

  const sqlLayout = await layoutFor(config, args, config.blockNames);

  const topicsFile =
    topics === undefined ? [] : [{ ...topics, note: "topics" }];

  if (args.check !== true) {
    const lines = hasSql
      ? await write(config, args, config.blockNames, sqlLayout, now)
      : [];

    if (topics !== undefined) {
      lines.push(
        ...changeLines(
          await applyPlan(
            {
              root: config.root,
              regenerate: "better-supabase sql sync",
              files: topicsFile,
            },
            { "dry-run": args["dry-run"] },
          ),
        ),
      );
    }

    return {
      code: 0,
      output: lines.join("\n"),
      data: { blocks: config.blockNames },
    };
  }

  const rendered = renderModules(config.blockNames, sqlLayout);

  const plan = sqlPlan(config, {
    regenerate: "better-supabase sql sync",
    files: [...rendered.map((file) => moduleFile(file)), ...topicsFile],
    remove: await staleModuleTests(
      config,
      config.blockNames,
      sqlLayout,
      rendered,
    ),
  });

  return planResult(plan, await applyPlan(plan, { check: true }, paint), {
    data: { blocks: config.blockNames },
  });
}

/**
 * `sql sync --check` under the migrations workflow: the newest module migration
 * against what `sql sync` would write.
 */
async function checkModuleMigration(
  config: ResolvedConfig,
  sqlLayout: ModuleLayout,
  paint: Paint,
  topics: string | undefined,
): Promise<CommandResult> {
  const files = renderModules(config.blockNames, sqlLayout);

  const expected = renderModuleMigration({
    files,
    ...(topics === undefined ? {} : { topics }),
  });

  const latest = await latestMigration(config, MODULES_SUFFIX);

  const stale: string[] = (
    await staleModuleTests(config, config.blockNames, sqlLayout, files)
  ).map((path) => display(config.root, path));

  const diffs: string[] = stale.map(
    (path) => `${path} is no longer written; \`sql sync\` removes it.`,
  );

  for (const file of files.filter((entry) => entry.kind === "test")) {
    const current = await readFile(
      resolve(config.root, file.path),
      "utf-8",
    ).catch(() => undefined);

    if (!sameModuleFile(current, file.contents)) {
      const shown = display(config.root, file.path);
      stale.push(shown);
      diffs.push(fileDiff(shown, current, file.contents, paint));
    }
  }

  if (!sameModuleMigration(latest?.text, expected)) {
    const shown =
      latest?.path ?? `${migrationsDir(config)}/<stamp>${MODULES_SUFFIX}`;

    stale.push(shown);
    diffs.push(fileDiff(shown, latest?.text, expected, paint));
  }

  return stale.length === 0
    ? {
        code: 0,
        output: "SQL module migration is up to date.",
        data: { stale },
      }
    : {
        code: 1,
        data: { stale },
        output: diffs.join("\n\n"),
        error: `Out of date: ${stale.join(", ")}. Run \`better-supabase sql sync\`, then \`supabase migration up\`.`,
        errorCode: "check_failed",
      };
}
