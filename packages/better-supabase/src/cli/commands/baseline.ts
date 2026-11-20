import type { ApplyResult } from "../baseline/apply.ts";
import type { BuildResult } from "../baseline/build.ts";
import type { VerifyResult } from "../baseline/verify.ts";
import type { AnyCommand, CliOptions } from "../core/command.ts";
import type { CommandResult } from "../core/io.ts";

import { applyBaseline } from "../baseline/apply.ts";
import { buildBaseline } from "../baseline/build.ts";
import { baselineContext, stackInfo } from "../baseline/stack.ts";
import { verifyBaseline } from "../baseline/verify.ts";
import { isLocalDatabaseUrl } from "../core/agent.ts";
import { defineCliCommand } from "../core/command.ts";
import { CliError } from "../core/errors.ts";
import { commandMeta } from "../core/manifest.ts";

const BUILD_ARGS = {
  "with-seed": {
    type: "boolean",
    description:
      "Include the seeded rows and the storage objects of the seed files and the buckets' objects_path",
  },
  out: {
    type: "string",
    description:
      "Folder that holds one folder per key (default node_modules/.cache/better-supabase/baseline)",
    valueHint: "dir",
  },
  force: {
    type: "boolean",
    description: "Build again even when a baseline covers these migrations",
  },
  verify: {
    type: "boolean",
    description:
      "Restore the result into a fresh stack and compare it with the replay",
  },
} as const;

const APPLY_ARGS = {
  "with-seed": {
    type: "boolean",
    description:
      "Include the seeded rows and the storage objects of the seed files and the buckets' objects_path",
  },
  from: {
    type: "string",
    description:
      "Folder that holds the baselines (default node_modules/.cache/better-supabase/baseline)",
    valueHint: "dir",
  },
} as const;

type Context = Parameters<typeof baselineContext>;

const seconds = (ms: number | undefined): string =>
  `${((ms ?? 0) / 1000).toFixed(1)} s`;

function timingLines(timings: Readonly<Record<string, number>>): string[] {
  return Object.entries(timings).map(
    ([step, ms]) => `  ${step}: ${seconds(ms)}`,
  );
}

/** Builds the baseline artifact on scratch stacks. */
async function runBaselineBuild(
  args: CliOptions<typeof BUILD_ARGS>,
  context: Context,
): Promise<CommandResult> {
  const result: BuildResult = await buildBaseline(baselineContext(...context), {
    withSeed: args["with-seed"] === true,
    out: args.out,
    force: args.force === true,
    verify: args.verify === true,
  });

  return {
    code: 0,
    output: [
      result.cached
        ? `Baseline ${result.key.slice(0, 12)} already covers these migrations.`
        : `Built baseline ${result.key.slice(0, 12)} in ${result.dir}.`,
      ...(result.verified ? ["Verified against a full replay."] : []),
      ...timingLines(result.timings),
    ].join("\n"),
    data: { ...result },
  };
}

/** Loads the baseline into this checkout's empty stack. */
async function runBaselineApply(
  args: CliOptions<typeof APPLY_ARGS>,
  context: Context,
): Promise<CommandResult> {
  const ctx = baselineContext(...context);
  const stack = await stackInfo(ctx);

  if (!isLocalDatabaseUrl(stack.dbUrl)) {
    throw new CliError(
      "invalid_value",
      "baseline apply only fills a local database.",
    );
  }

  const result: ApplyResult = await applyBaseline(ctx, {
    from: args.from,
    withSeed: args["with-seed"] === true,
    target: {
      dbUrl: stack.dbUrl,
      storage:
        stack.apiUrl !== undefined && stack.serviceKey !== undefined
          ? { apiUrl: stack.apiUrl, serviceKey: stack.serviceKey }
          : undefined,
      migrate: () => ctx.supabase(["migration", "up"], ctx.root, ctx.env),
    },
  });

  const total = Object.values(result.timings).reduce((a, b) => a + b, 0);

  return {
    code: 0,
    output: [
      result.mode === "baseline"
        ? `Loaded baseline ${(result.key ?? "").slice(0, 12)}, then ran ${String(result.pending.length)} newer migration(s).`
        : `Ran every migration (${result.reason ?? "no baseline"}).`,
      ...(result.seed === "none" ? [] : [`Seeds: ${result.seed}.`]),
      ...timingLines(result.timings),
      `  total: ${seconds(total)}`,
    ].join("\n"),
    data: { ...result },
  };
}

/** Restores the baseline into a fresh stack and compares it with the replay. */
async function runBaselineVerify(
  args: CliOptions<typeof APPLY_ARGS>,
  context: Context,
): Promise<CommandResult> {
  const result: VerifyResult = await verifyBaseline(
    baselineContext(...context),
    { out: args.from, withSeed: args["with-seed"] === true },
  );

  return {
    code: 0,
    output: `Baseline ${result.key.slice(0, 12)} restores to the same catalog, digest and row counts as a full replay.`,
    data: { ...result },
  };
}

export const baselineBuildCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("baseline build"),
  args: BUILD_ARGS,
  run: (args, { config, env, log }) =>
    runBaselineBuild(args, [
      config.root,
      env,
      (line) => {
        log.info(line);
      },
    ]),
});

export const baselineApplyCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("baseline apply"),
  args: APPLY_ARGS,
  run: (args, { config, env, log }) =>
    runBaselineApply(args, [
      config.root,
      env,
      (line) => {
        log.info(line);
      },
    ]),
});

export const baselineVerifyCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("baseline verify"),
  args: APPLY_ARGS,
  run: (args, { config, env, log }) =>
    runBaselineVerify(args, [
      config.root,
      env,
      (line) => {
        log.info(line);
      },
    ]),
});
