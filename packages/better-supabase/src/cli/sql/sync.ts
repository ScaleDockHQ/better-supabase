import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { BlockSqlLayout } from "../../sql/index.ts";
import type { CommandResult } from "../core/io.ts";
import type { Paint } from "../style.ts";
import type { SqlFlags } from "./args.ts";
import type { Now } from "./migrations.ts";
import type { SqlWrite } from "./write.ts";

import { moduleTopics, renderBlocks, sameBlockFile } from "../../sql/index.ts";
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
import { orphanedBlockFiles } from "./orphans.ts";
import { layoutFor } from "./providers.ts";
import {
  guardedRemoval,
  moduleFile,
  staleModuleTests,
  write,
} from "./write.ts";

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

    const written = await write(
      config,
      args,
      config.blockNames,
      sqlLayout,
      now,
    );

    return {
      code: written.error === undefined ? 0 : 1,
      output: written.lines.join("\n"),
      ...(written.error === undefined
        ? {}
        : { error: written.error, errorCode: "file_conflict" as const }),
      data: { blocks: config.blockNames },
    };
  }

  const sqlLayout = await layoutFor(config, args, config.blockNames);

  const topicsFile =
    topics === undefined ? [] : [{ ...topics, note: "topics" }];

  if (args.check !== true) {
    const written: SqlWrite = hasSql
      ? await write(config, args, config.blockNames, sqlLayout, now)
      : { lines: [] };

    const lines = [...written.lines];

    if (topics !== undefined) {
      lines.push(
        ...changeLines(
          await applyPlan(
            {
              root: config.root,
              regenerate: "better-supabase upgrade",
              files: topicsFile,
            },
            { "dry-run": args["dry-run"] },
          ),
        ),
      );
    }

    return {
      code: written.error === undefined ? 0 : 1,
      output: lines.join("\n"),
      ...(written.error === undefined
        ? {}
        : { error: written.error, errorCode: "file_conflict" as const }),
      data: { blocks: config.blockNames },
    };
  }

  const rendered = renderBlocks(config.blockNames, sqlLayout);

  const plan = sqlPlan(config, {
    regenerate: "better-supabase upgrade",
    files: [...rendered.map((file) => moduleFile(file)), ...topicsFile],
    remove: [
      ...new Set([
        ...(await orphanedBlockFiles(
          config,
          sqlLayout,
          new Set(rendered.map((file) => file.path)),
        )),
        ...(await staleModuleTests(
          config,
          config.blockNames,
          sqlLayout,
          rendered,
        )),
      ]),
    ].map((path) => guardedRemoval(path)),
  });

  return planResult(
    plan,
    await applyPlan(plan, { check: true, force: args.force === true }, paint),
    { data: { blocks: config.blockNames } },
  );
}

/**
 * `upgrade --check` under the migrations workflow: the newest module migration
 * against what `upgrade` would write.
 */
async function checkModuleMigration(
  config: ResolvedConfig,
  sqlLayout: BlockSqlLayout,
  paint: Paint,
  topics: string | undefined,
): Promise<CommandResult> {
  const files = renderBlocks(config.blockNames, sqlLayout);

  const expected = renderModuleMigration({
    files,
    ...(topics === undefined ? {} : { topics }),
  });

  const latest = await latestMigration(config, MODULES_SUFFIX);

  const stale: string[] = (
    await staleModuleTests(config, config.blockNames, sqlLayout, files)
  ).map((path) => display(config.root, path));

  const diffs: string[] = stale.map(
    (path) => `${path} is no longer written; \`upgrade\` removes it.`,
  );

  for (const file of files.filter((entry) => entry.kind === "test")) {
    const current = await readFile(
      resolve(config.root, file.path),
      "utf-8",
    ).catch(() => undefined);

    if (!sameBlockFile(current, file.contents)) {
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
        error: `Out of date: ${stale.join(", ")}. Run \`better-supabase upgrade\`, then \`supabase migration up\`.`,
        errorCode: "check_failed",
      };
}
