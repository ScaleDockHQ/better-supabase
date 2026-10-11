import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { CommandResult } from "../io.ts";
import type { SqlFlags } from "./args.ts";
import type { Now } from "./migrations.ts";

import {
  moduleTopics,
  renderModules,
  sameModuleFile,
} from "../../sql/index.ts";
import { fileDiff } from "../diff.ts";
import { writeLine } from "../files.ts";
import { display, sameText } from "../io.ts";
import { type Paint } from "../style.ts";
import { topicPolicyFile } from "../topic-policies.ts";
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
