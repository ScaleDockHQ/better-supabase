import { existsSync } from "node:fs";

import type { CliEnv } from "./env.ts";
import type { SharedMemoryUsage } from "./shm.ts";

import { CliError } from "./core/errors.ts";
import { type RunProcess, runProcess, supabaseCli } from "./exec.ts";

/** One stack from `supabase stack list`, as the Supabase CLI persists it. */
export interface ManagedStack {
  readonly id: string;
  readonly projectRoot: string;
  readonly name: string;
  /** `refs/heads/<branch>`, or `detached`. */
  readonly branch: string;
  readonly runtime: string;
  /** The stack's supervisor answers (`owner: reachable`). */
  readonly running: boolean;
}

export interface StackReport extends ManagedStack {
  readonly worktreeExists: boolean;
  /** Undefined for a detached checkout or when git can't tell. */
  readonly branchExists: boolean | undefined;
  /** This checkout's stack. */
  readonly current: boolean;
  /** System V segments its postmaster holds. */
  readonly segments: number;
}

export type PruneReason = "worktree-missing" | "branch-deleted" | "idle";

export interface PruneAction {
  readonly stack: StackReport;
  readonly action: "destroy" | "stop";
  readonly reason: PruneReason;
}

function textField(record: Record<string, unknown>, key: string): string {
  const value = record[key];

  return typeof value === "string" ? value : "";
}

/** Parses `supabase stack list --output-format json`. */
export function parseStackList(stdout: string): readonly ManagedStack[] {
  const start = stdout.indexOf("{");

  const parsed: unknown =
    start === -1 ? undefined : JSON.parse(stdout.slice(start));

  if (
    typeof parsed !== "object" ||
    parsed === null ||
    !("stacks" in parsed) ||
    !Array.isArray(parsed.stacks)
  ) {
    throw new CliError(
      "supabase_cli_failed",
      "supabase stack list printed no stacks array.",
    );
  }

  return parsed.stacks.flatMap((entry: unknown): ManagedStack[] => {
    if (typeof entry !== "object" || entry === null) {
      return [];
    }

    const record = { ...entry };
    const id = textField(record, "id");

    return id === ""
      ? []
      : [
          {
            id,
            projectRoot: textField(record, "project_root"),
            name: textField(record, "name"),
            branch: textField(record, "branch_context"),
            runtime: textField(record, "runtime"),
            running: textField(record, "owner") === "reachable",
          },
        ];
  });
}

export async function listStacks(
  root: string,
  env: CliEnv,
): Promise<readonly ManagedStack[]> {
  const result = await supabaseCli(
    ["stack", "list", "--output-format", "json"],
    root,
    env,
  );

  if (result.code !== 0) {
    throw new CliError(
      "supabase_cli_failed",
      `supabase stack list failed: ${(result.stderr || result.stdout).trim()}`,
    );
  }

  return parseStackList(result.stdout);
}

async function git(
  args: readonly string[],
  cwd: string,
  env: CliEnv,
  run: RunProcess,
): Promise<{ readonly code: number; readonly stdout: string }> {
  const result = await run("git", args, cwd, env);

  return { code: result.code, stdout: result.stdout.trim() };
}

export interface ReportOptions {
  readonly root: string;
  readonly env: CliEnv;
  readonly memory?: SharedMemoryUsage;
  readonly run?: RunProcess;
  readonly exists?: (path: string) => boolean;
}

/** Adds what `stack ls` shows to each stack: worktree, branch, segments, current. */
export async function reportStacks(
  stacks: readonly ManagedStack[],
  options: ReportOptions,
): Promise<readonly StackReport[]> {
  const run = options.run ?? runProcess;
  const exists = options.exists ?? existsSync;

  const head = await git(
    ["rev-parse", "--symbolic-full-name", "HEAD"],
    options.root,
    options.env,
    run,
  );

  const top = await git(
    ["rev-parse", "--show-toplevel"],
    options.root,
    options.env,
    run,
  );

  const counts = new Map<string, number>();

  for (const segment of options.memory?.segments ?? []) {
    if (segment.stackId !== undefined) {
      counts.set(segment.stackId, (counts.get(segment.stackId) ?? 0) + 1);
    }
  }

  return Promise.all(
    stacks.map(async (stack): Promise<StackReport> => {
      const worktreeExists =
        stack.projectRoot !== "" && exists(stack.projectRoot);

      let branchExists: boolean | undefined;

      if (worktreeExists && stack.branch.startsWith("refs/")) {
        const verify = await git(
          ["rev-parse", "--verify", "--quiet", stack.branch],
          stack.projectRoot,
          options.env,
          run,
        );

        branchExists = verify.code === 0;
      }

      const inThisCheckout =
        stack.projectRoot === options.root ||
        (top.code === 0 && stack.projectRoot.startsWith(`${top.stdout}/`)) ||
        stack.projectRoot === top.stdout;

      return {
        ...stack,
        worktreeExists,
        branchExists,
        current:
          inThisCheckout && head.code === 0 && stack.branch === head.stdout,
        segments: counts.get(stack.id) ?? 0,
      };
    }),
  );
}

/**
 * The stacks `stack prune` acts on. A stack whose worktree or branch is gone
 * is destroyed; with `stopIdle`, a running stack of another checkout or
 * branch is only stopped, so its data stays.
 */
export function prunePlan(
  stacks: readonly StackReport[],
  options: { readonly stopIdle: boolean },
): readonly PruneAction[] {
  return stacks.flatMap((stack): PruneAction[] => {
    if (stack.current) {
      return [];
    }

    if (!stack.worktreeExists) {
      return [{ stack, action: "destroy", reason: "worktree-missing" }];
    }

    if (stack.branchExists === false) {
      return [{ stack, action: "destroy", reason: "branch-deleted" }];
    }

    if (options.stopIdle && stack.running) {
      return [{ stack, action: "stop", reason: "idle" }];
    }

    return [];
  });
}

export function branchName(branch: string): string {
  return branch.startsWith("refs/heads/")
    ? branch.slice("refs/heads/".length)
    : branch;
}
