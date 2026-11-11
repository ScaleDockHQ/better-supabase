import { readdir, readFile } from "node:fs/promises";
import { resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type {
  InstalledBlock,
  BlockSqlFile,
  BlockSqlLayout,
} from "../../sql/index.ts";
import type { CommandResult } from "../core/io.ts";
import type { Paint } from "../style.ts";
import type { SqlFlags } from "./args.ts";
import type { Now } from "./migrations.ts";

import {
  buildModel,
  conflicts,
  duplicatePolicies,
  entityRenamePlan,
  moduleFileVersion,
  moduleTopics,
  PRELUDE_FUNCTIONS,
  PRELUDE_MODULE,
  sameBlockFile,
  SQL_MODULES,
  upgradePlan,
} from "../../sql/index.ts";
import { applyPlan, changeLines } from "../core/files.ts";
import { display } from "../core/io.ts";
import { fileDiff } from "../diff.ts";
import { migrationsDir, sqlPlan } from "../sql-layout.ts";
import { readSupabaseToml, sqlWorkflow } from "../supabase-toml.ts";
import { topicPolicyFile } from "../topic-policies.ts";
import { migrationFile } from "./migration-names.ts";
import {
  latestMigration,
  migrationInstances,
  migrationModules,
  MODULES_SUFFIX,
  renderModuleMigration,
  sameModuleMigration,
  writesMigrations,
} from "./module-migration.ts";
import { layoutFor } from "./providers.ts";
import { cacheOf, renderBlocksCached } from "./render-cache.ts";
import { nextStep, write } from "./write.ts";

/** The migration `upgrade` writes under pg-delta for steps a diff can't express. */
const REVIEWED_SUFFIX = "_better_supabase_reviewed_upgrade.sql";

const REVIEWED_HEADER = [
  "-- better-supabase upgrade: steps pg-delta can't express (renames, backfills, expression changes).",
  "-- Review them before you apply this migration; the module files hold everything else.",
  "-- destructive: reviewed",
].join("\n");

/**
 * Rewrites the module files of modules behind the current version, and writes
 * their upgrade steps (renames, backfills) as a migration that runs before the
 * one the schema diff creates.
 */
export async function upgrade(
  config: ResolvedConfig,
  args: SqlFlags,
  paint: Paint,
  now: Now,
): Promise<CommandResult> {
  if (config.blockNames.length === 0) {
    return {
      code: 0,
      output: "blocks is empty; nothing to upgrade.",
      data: { upgrades: [], stale: [] },
    };
  }

  const sqlLayout = await layoutFor(config, args, config.blockNames);

  const files = await renderBlocksCached(
    config,
    config.blockNames,
    sqlLayout,
    cacheOf(args),
  );

  const migrations = await writesMigrations(config);

  const {
    installed,
    stale,
    diffs,
    text,
    files: installedFiles,
  } = migrations
    ? await installedFromMigration(config, sqlLayout, files, paint)
    : await installedFromFiles(config, files, paint);

  const renames = entityRenamePlan(
    config.blockNames,
    installed.map((entry) => entry.module),
    text,
    sqlLayout,
    files,
  );

  if (renames.refused.length > 0) {
    return {
      code: 1,
      errorCode: "config_invalid",
      error: renames.refused.join("\n"),
    };
  }

  const plan = upgradePlan(installed, sqlLayout);
  const renamed = [...new Set(renames.steps.map((step) => step.module))];

  const problems = moduleFileProblems(
    installedFiles,
    !migrations && sqlLayout.rerunnable !== true,
  );

  const data = {
    upgrades: plan.map(({ module, from, to }) => ({ module, from, to })),
    ...(renamed.length > 0 ? { renames: renamed } : {}),
    stale,
    ...(problems.length > 0 ? { problems } : {}),
  };

  const current =
    plan.length === 0 &&
    stale.length === 0 &&
    renamed.length === 0 &&
    problems.length === 0;

  const behind = plan.map(
    (entry) =>
      `${entry.module} is at version ${String(entry.from)}; the current version is ${String(entry.to)}`,
  );

  if (args.check === true) {
    if (current) {
      return {
        code: 0,
        output: "SQL modules are at their current versions.",
        data,
      };
    }

    return {
      code: 1,
      errorCode: "check_failed",
      data,
      output: diffs.join("\n\n"),
      error: [
        ...behind,
        ...renamed.map(
          (module) => `${module} has entity renames to apply to its tables`,
        ),
        ...(stale.length > 0 ? [`Out of date: ${stale.join(", ")}.`] : []),
        ...problems,
        "Run `better-supabase upgrade`.",
      ].join("\n"),
    };
  }

  if (current) {
    return {
      code: 0,
      output: "SQL modules are at their current versions.",
      data,
    };
  }

  const lines: string[] = [];

  const renameSteps =
    renames.steps.length === 0
      ? []
      : [
          `-- Entity renames (blocks.<name>.entities) of ${renamed.join(", ")}.\n${renames.steps.map((step) => step.sql).join("\n")}`,
        ];

  const steps = [
    ...renameSteps,
    ...plan.flatMap((entry) =>
      entry.steps
        .filter((step) => step.sql !== "")
        .map(
          (step) =>
            `-- ${entry.module}: version ${String(step.from)} to ${String(step.from + 1)}. ${step.description}\n${step.sql}`,
        ),
    ),
  ];

  const dryRun = args["dry-run"] === true;

  if (steps.length > 0 && !migrations) {
    const dir = migrationsDir(config);

    const reviewed =
      sqlWorkflow(config, await readSupabaseToml(config.root)) === "pg-delta";

    // Under pg-delta the module files own every statement the diff can
    // express, so what is left (renames, backfills, expression changes) is a
    // hand migration that a person reviews before it runs.
    const contents = reviewed
      ? `${REVIEWED_HEADER}\n\n${steps.join("\n\n")}\n`
      : `-- better-supabase upgrade: steps that run before the schema diff.\n\n${steps.join("\n\n")}\n`;

    const existing: string[] = await readdir(resolve(config.root, dir)).catch(
      () => [],
    );

    const path = `${dir}/${migrationFile(existing, now(), reviewed ? REVIEWED_SUFFIX : "_better_supabase_block_upgrade.sql", contents).name}`;

    const applied = await applyPlan(
      sqlPlan(config, {
        regenerate: "better-supabase upgrade",
        files: [{ path, contents }],
      }),
      { "dry-run": dryRun },
    );

    lines.push(...changeLines(applied));
  }

  for (const module of renamed) {
    lines.push(`${module}: renamed after blocks.<name>.names`);
  }

  for (const entry of plan) {
    lines.push(
      `${entry.module}: version ${String(entry.from)} to ${String(entry.to)}`,
      ...entry.steps.map((step) => `  ${step.description}`),
    );
  }

  const written = await write(
    config,
    args,
    config.blockNames,
    sqlLayout,
    now,
    undefined,
    migrations ? steps : [],
  );

  lines.push(...written.lines);

  return {
    code: written.error === undefined ? 0 : 1,
    output: lines.join("\n"),
    ...(written.error === undefined
      ? {}
      : { error: written.error, errorCode: "file_conflict" as const }),
    // The problems are in the files this run replaced; a dry run still lists them.
    data:
      dryRun || written.error !== undefined
        ? data
        : Object.fromEntries(
            Object.entries(data).filter(([key]) => key !== "problems"),
          ),
    next: [await nextStep(config)],
  };
}

interface Installed {
  readonly installed: InstalledBlock[];
  /** Paths that differ from what this release writes. */
  readonly stale: string[];
  readonly diffs: string[];
  /** The installed files or migration, for their `@bsb-names` lines. */
  readonly text: string;
  /** The installed files with their paths; empty for a migration. */
  readonly files: readonly { readonly path: string; readonly text: string }[];
  /** Files a block wrote under its 0.14 name, which `upgrade` removes. */
}

/** The installed versions from the module files in `sql.dir`. */
async function installedFromFiles(
  config: ResolvedConfig,
  files: readonly BlockSqlFile[],
  paint: Paint,
): Promise<Installed> {
  const installed: InstalledBlock[] = [];
  const stale: string[] = [];
  const diffs: string[] = [];
  const texts: string[] = [];
  const paths: { path: string; text: string }[] = [];

  const read = (path: string): Promise<string | undefined> =>
    readFile(resolve(config.root, path), "utf-8").catch(() => undefined);

  for (const file of files) {
    if (file.kind === "data") {
      continue;
    }

    if (file.kind === "test" && SQL_MODULES[file.module]?.target !== "test") {
      continue;
    }

    const found = await read(file.path);

    if (found === undefined) {
      continue;
    }

    const current = found;

    texts.push(found);
    paths.push({ path: file.path, text: found });
    installed.push({
      module: file.instance ?? file.module,
      ...(file.instance === undefined ? {} : { block: file.module }),
      version: moduleFileVersion(current)?.version ?? 1,
    });

    if (!sameBlockFile(current, file.contents)) {
      const shown = display(config.root, file.path);
      stale.push(shown);
      diffs.push(fileDiff(shown, current, file.contents, paint));
    }
  }

  return { installed, stale, diffs, text: texts.join("\n"), files: paths };
}

/**
 * The installed versions from the `@bsb-block` lines of the newest module
 * migration.
 */
async function installedFromMigration(
  config: ResolvedConfig,
  sqlLayout: BlockSqlLayout,
  files: readonly BlockSqlFile[],
  paint: Paint,
): Promise<Installed> {
  const latest = await latestMigration(config, MODULES_SUFFIX);

  if (latest === undefined) {
    return { installed: [], stale: [], diffs: [], text: "", files: [] };
  }

  const text = latest.text;
  const versions = migrationModules(text);
  const blocks = migrationInstances(text);

  const installed = [...versions].map(([module, version]) => {
    const block = blocks.get(module);

    return { module, ...(block === undefined ? {} : { block }), version };
  });

  const topics = await topicPolicyFile(
    config,
    moduleTopics(config.blockNames, sqlLayout),
  );

  const expected = renderModuleMigration({
    files,
    ...(topics === undefined ? {} : { topics: topics.contents }),
  });

  return sameModuleMigration(latest.text, expected)
    ? { installed, stale: [], diffs: [], text: latest.text, files: [] }
    : {
        installed,
        stale: [latest.path],
        diffs: [fileDiff(latest.path, latest.text, expected, paint)],
        text: latest.text,
        files: [],
      };
}

/**
 * A line for each problem in the installed module files that a schema diff
 * would trip over: a helper the prelude defines that a module file also creates
 * (a file written before the prelude existed pastes the helpers it calls),
 * another object two module files both declare, a file that asks for
 * `transaction=false`, a top-level `insert`, and two policies that decide the
 * same way. Doctor reports the same findings as BS369 to BS375.
 */
function moduleFileProblems(
  files: readonly { readonly path: string; readonly text: string }[],
  declarative: boolean,
): string[] {
  const model = buildModel(files);

  const conflicting = conflicts(model).flatMap(({ declarations }) => {
    const first = declarations[0];

    if (
      first === undefined ||
      first.kind === "extension" ||
      first.kind === "schema"
    ) {
      return [];
    }

    const prelude =
      first.kind === "function" &&
      PRELUDE_FUNCTIONS.has(
        first.name.slice(first.name.indexOf(".") + 1).replace(/\/\d+$/, ""),
      );

    return declarations
      .filter(
        (each) =>
          each.owner.kind === "module" &&
          each.file !== first.file &&
          (!prelude || each.owner.name !== PRELUDE_MODULE),
      )
      .map((each) =>
        prelude
          ? `${each.file} declares ${first.name.replace(/\/\d+$/, "")}, which the prelude defines. Run \`better-supabase upgrade\`.`
          : `${each.file} declares the ${each.kind} ${each.name.replace(/\/\d+$/, "")}, which ${first.file} also declares.`,
      );
  });

  const perFile = [...model.files].flatMap(([path, parsed]) => [
    ...(parsed.outsideTransaction
      ? [`${path} asks for transaction=false. Remove the line.`]
      : []),
    ...parsed.inserts.map(
      (line) =>
        `${path}:${String(line)} inserts rows. Rows belong in the module's data file.`,
    ),
  ]);

  const drops = (declarative ? [...files] : []).flatMap(({ path, text }) =>
    text
      .split("\n")
      .flatMap((line, index) =>
        /^drop\s+event\s+trigger\b/iu.test(line)
          ? [
              `${path}:${String(index + 1)} drops an event trigger. A declarative file only declares it; run better-supabase upgrade to rewrite the file.`,
            ]
          : [],
      ),
  );

  const policies = duplicatePolicies(model).map(
    (group) =>
      `${group.table} has the policies ${group.names.join(" and ")}, which decide the same way.`,
  );

  return [...conflicting, ...perFile, ...drops, ...policies];
}
