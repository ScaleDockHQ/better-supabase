import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { CommandResult } from "../io.ts";
import type { SqlFlags } from "./args.ts";
import type { Now } from "./migrations.ts";

import {
  type ModuleLayout,
  moduleTopics,
  renderModules,
  sameModuleFile,
} from "../../sql/index.ts";
import { fileDiff } from "../diff.ts";
import { writeLine } from "../files.ts";
import { display, sameText } from "../io.ts";
import { migrationsDir } from "../sql-layout.ts";
import { type Paint } from "../style.ts";
import { topicPolicyFile } from "../topic-policies.ts";
import {
  latestMigration,
  MODULES_SUFFIX,
  renderModuleMigration,
  sameModuleMigration,
  writesMigrations,
} from "./module-migration.ts";
import { layoutFor } from "./providers.ts";
import { staleModuleTests, write } from "./write.ts";

export async function syncModules(
  config: ResolvedConfig,
  args: SqlFlags,
  paint: Paint,
  now: Now,
): Promise<CommandResult> {
  const topics = await topicPolicyFile(
    config,
    config.sql.moduleNames.length === 0
      ? []
      : moduleTopics(
          config.sql.moduleNames,
          await layoutFor(config, args, config.sql.moduleNames),
        ),
  );
  if (config.sql.moduleNames.length === 0 && topics === undefined) {
    return { code: 0, output: "sql.modules is empty; nothing to sync." };
  }
  if (await writesMigrations(config)) {
    const sqlLayout = await layoutFor(config, args, config.sql.moduleNames);
    if (args.check === true)
      return checkModuleMigration(config, sqlLayout, paint, topics?.contents);
    const lines = await write(
      config,
      args,
      config.sql.moduleNames,
      sqlLayout,
      now,
    );
    return { code: 0, output: lines.join("\n") };
  }
  if (args.check !== true) {
    const lines =
      config.sql.moduleNames.length === 0
        ? []
        : await write(
            config,
            args,
            config.sql.moduleNames,
            await layoutFor(config, args, config.sql.moduleNames),
            now,
          );
    if (topics !== undefined) {
      const shown = display(config.root, topics.path);
      if (args["dry-run"] === true) lines.push(`Would write ${shown} (topics)`);
      else {
        lines.push(
          (
            await writeLine(
              resolve(config.root, topics.path),
              topics.contents,
              shown,
              " (topics)",
            )
          ).line,
        );
      }
    }
    return { code: 0, output: lines.join("\n") };
  }
  const sqlLayout = await layoutFor(config, args, config.sql.moduleNames);
  const files: { path: string; contents: string; topics?: true }[] = [
    ...renderModules(config.sql.moduleNames, sqlLayout),
    ...(topics === undefined ? [] : [{ ...topics, topics: true as const }]),
  ];
  const stale: string[] = (
    await staleModuleTests(
      config,
      config.sql.moduleNames,
      sqlLayout,
      renderModules(config.sql.moduleNames, sqlLayout),
    )
  ).map((path) => display(config.root, path));
  const diffs: string[] = stale.map(
    (path) => `${path} is no longer written; \`sql sync\` removes it.`,
  );
  for (const file of files) {
    const current = await readFile(
      resolve(config.root, file.path),
      "utf8",
    ).catch(() => undefined);
    if (
      file.topics
        ? !sameText(current, file.contents)
        : !sameModuleFile(current, file.contents)
    ) {
      const shown = display(config.root, file.path);
      stale.push(shown);
      diffs.push(fileDiff(shown, current, file.contents, paint));
    }
  }
  return stale.length === 0
    ? { code: 0, output: "SQL module files are up to date." }
    : {
        code: 1,
        output: diffs.join("\n\n"),
        error: `Out of date: ${stale.join(", ")}. Run \`better-supabase sql sync\`.`,
      };
}

/** `sql sync --check` under the migrations workflow: the newest module migration against what `sql sync` would write. */
async function checkModuleMigration(
  config: ResolvedConfig,
  sqlLayout: ModuleLayout,
  paint: Paint,
  topics: string | undefined,
): Promise<CommandResult> {
  const files = renderModules(config.sql.moduleNames, sqlLayout);
  const expected = renderModuleMigration({
    files,
    ...(topics === undefined ? {} : { topics }),
  });
  const latest = await latestMigration(config, MODULES_SUFFIX);
  const stale: string[] = (
    await staleModuleTests(config, config.sql.moduleNames, sqlLayout, files)
  ).map((path) => display(config.root, path));
  const diffs: string[] = stale.map(
    (path) => `${path} is no longer written; \`sql sync\` removes it.`,
  );
  for (const file of files.filter((entry) => entry.kind === "test")) {
    const current = await readFile(
      resolve(config.root, file.path),
      "utf8",
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
    ? { code: 0, output: "SQL module migration is up to date." }
    : {
        code: 1,
        output: diffs.join("\n\n"),
        error: `Out of date: ${stale.join(", ")}. Run \`better-supabase sql sync\`, then \`supabase migration up\`.`,
      };
}
