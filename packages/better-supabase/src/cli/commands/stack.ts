import type { ConsentRequest } from "../core/agent.ts";
import type { AnyCommand, CliOptions } from "../core/command.ts";
import type { CommandResult } from "../core/io.ts";
import type { CliEnv } from "../env.ts";
import type { SharedMemoryUsage } from "../shm.ts";
import type { PruneAction, StackReport } from "../stacks.ts";

import { defineCliCommand } from "../core/command.ts";
import { commandMeta } from "../core/manifest.ts";
import { supabaseCli } from "../exec.ts";
import { readSharedMemory } from "../shm.ts";
import { branchName, listStacks, prunePlan, reportStacks } from "../stacks.ts";

export interface StackDeps {
  readonly stacks: (
    root: string,
    env: CliEnv,
    memory: SharedMemoryUsage,
  ) => Promise<readonly StackReport[]>;
  readonly memory: (root: string, env: CliEnv) => Promise<SharedMemoryUsage>;
  readonly supabase: (
    args: readonly string[],
    root: string,
    env: CliEnv,
  ) => Promise<{
    readonly code: number;
    readonly stdout: string;
    readonly stderr: string;
  }>;
}

const DEFAULT_DEPS: StackDeps = {
  memory: (root, env) => readSharedMemory(root, env),
  stacks: async (root, env, memory) =>
    reportStacks(await listStacks(root, env), { root, env, memory }),
  supabase: (args, root, env) => supabaseCli(args, root, env),
};

function memoryLine(memory: SharedMemoryUsage): string | undefined {
  if (!memory.supported) {
    return undefined;
  }

  const used = String(memory.segments.length);

  return memory.limit === undefined
    ? `Shared memory segments: ${used} in use.`
    : `Shared memory segments: ${used} of ${String(memory.limit)} in use.`;
}

function stackLine(stack: StackReport): string {
  const notes = [
    stack.running ? "running" : "stopped",
    ...(stack.current ? ["this checkout"] : []),
    ...(stack.worktreeExists ? [] : ["worktree gone"]),
    ...(stack.branchExists === false ? ["branch deleted"] : []),
    ...(stack.segments > 0 ? [`${String(stack.segments)} segment(s)`] : []),
  ];

  return `${stack.id}  ${branchName(stack.branch)}  ${stack.projectRoot}  (${notes.join(", ")})`;
}

function memoryData(memory: SharedMemoryUsage): Record<string, unknown> {
  return {
    supported: memory.supported,
    used: memory.segments.length,
    ...(memory.limit === undefined ? {} : { limit: memory.limit }),
    unattributed: memory.segments.filter(
      (segment) => segment.stackId === undefined,
    ).length,
  };
}

/** Lists the Supabase CLI's managed stacks with the state `stack prune` acts on. */
export async function runStackLs(
  root: string,
  env: CliEnv,
  deps: StackDeps = DEFAULT_DEPS,
): Promise<CommandResult> {
  const memory = await deps.memory(root, env);
  const stacks = await deps.stacks(root, env, memory);
  const summary = memoryLine(memory);

  return {
    code: 0,
    output: [
      ...(stacks.length === 0 ? ["No managed stacks."] : stacks.map(stackLine)),
      ...(summary === undefined ? [] : ["", summary]),
    ].join("\n"),
    data: { stacks, sharedMemory: memoryData(memory) },
  };
}

const PRUNE_ARGS = {
  "stop-idle": {
    type: "boolean",
    description:
      "Also stop running stacks of other branches and checkouts (their data stays)",
  },
  "dry-run": {
    type: "boolean",
    description:
      "Print the stacks it would destroy or stop, and change nothing",
  },
} as const;

type PruneFlags = CliOptions<typeof PRUNE_ARGS>;

function actionLine(action: PruneAction): string {
  const why = {
    "worktree-missing": "its worktree is gone",
    "branch-deleted": `branch ${branchName(action.stack.branch)} is deleted`,
    idle: "it is running for another branch or checkout",
  }[action.reason];

  const verb = action.action === "destroy" ? "Destroy" : "Stop";

  return `${verb} ${action.stack.id} (${why})`;
}

/**
 * Destroys stacks whose worktree or branch is gone and, with `--stop-idle`,
 * stops the running stacks of other branches, which frees their shared memory
 * segments.
 */
export async function runStackPrune(
  root: string,
  args: PruneFlags,
  env: CliEnv,
  requireConsent: (request: ConsentRequest) => void = () => {},
  deps: StackDeps = DEFAULT_DEPS,
): Promise<CommandResult> {
  const memory = await deps.memory(root, env);

  const plan = prunePlan(await deps.stacks(root, env, memory), {
    stopIdle: args["stop-idle"] === true,
  });

  if (plan.length === 0) {
    return { code: 0, output: "Nothing to prune.", data: { actions: [] } };
  }

  const actions = plan.map((action) => ({
    id: action.stack.id,
    action: action.action,
    reason: action.reason,
  }));

  if (args["dry-run"] === true) {
    return {
      code: 0,
      output: plan.map(actionLine).join("\n"),
      data: { actions, dryRun: true },
    };
  }

  const destroy = plan.filter((action) => action.action === "destroy");
  const stop = plan.filter((action) => action.action === "stop");

  if (destroy.length > 0) {
    requireConsent({
      effect: "stack-destroy",
      detail: `stack prune destroys ${String(destroy.length)} stack(s) and their data`,
    });
  }

  for (const [verb, group] of [
    ["destroy", destroy],
    ["stop", stop],
  ] as const) {
    if (group.length === 0) {
      continue;
    }

    // The Supabase CLI refuses to destroy without --yes; requireConsent above
    // already has the user's answer.
    const result = await deps.supabase(
      [
        "stack",
        verb,
        ...group.flatMap((action) => ["--stack-id", action.stack.id]),
        ...(verb === "destroy" ? ["--yes"] : []),
      ],
      root,
      env,
    );

    if (result.code !== 0) {
      return {
        code: 1,
        errorCode: "supabase_cli_failed",
        error: `supabase stack ${verb} failed: ${(result.stderr || result.stdout).trim()}`,
        data: { actions },
      };
    }
  }

  return {
    code: 0,
    output: plan.map(actionLine).join("\n"),
    data: { actions, dryRun: false },
  };
}

export const stackLsCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("dev stack ls"),
  args: {},
  run: (_args, { config, env, log }) =>
    log.progress("Reading the managed stacks", () =>
      runStackLs(config.root, env),
    ),
});

export const stackPruneCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("dev stack prune"),
  args: PRUNE_ARGS,
  run: (args, { config, env, log, requireConsent }) =>
    log.progress("Pruning the managed stacks", () =>
      runStackPrune(config.root, args, env, requireConsent),
    ),
});
