/**
 * Stops the local stacks of branches already merged into `main`, for this
 * checkout and its worktrees. Every running native stack holds shared memory
 * segments, and macOS allows 32 (`kern.sysv.shmmni`), so a few dozen idle
 * stacks make the next `supabase start` fail. Stopping keeps the stack's data;
 * `supabase stack list` still shows it. Without `--apply` it only lists them.
 * `--destroy` instead removes the stacks (data included) of merged branches and
 * of checkouts that no longer exist, in any state except one another process
 * holds. `--segments` prints the shared memory segments in use.
 */
import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import * as v from "valibot";

const StackList = v.looseObject({
  stacks: v.array(
    v.looseObject({
      id: v.string(),
      project_root: v.string(),
      branch_context: v.string(),
      owner: v.string(),
    }),
  ),
});

export type Stack = v.InferOutput<typeof StackList>["stacks"][number];

const BRANCH_REF = "refs/heads/";

/**
 * The running stacks under `roots` whose branch is in `merged`, never `main`
 * itself.
 */
export function prunableStacks(
  stacks: readonly Stack[],
  roots: readonly string[],
  merged: ReadonlySet<string>,
): Stack[] {
  const inRepo = (path: string): boolean =>
    roots.some((root) => path === root || path.startsWith(`${root}/`));

  return stacks.filter((stack) => {
    if (stack.owner !== "reachable" || !inRepo(stack.project_root)) {
      return false;
    }

    if (!stack.branch_context.startsWith(BRANCH_REF)) {
      return false;
    }

    const branch = stack.branch_context.slice(BRANCH_REF.length);

    return branch !== "main" && merged.has(branch);
  });
}

/**
 * The stacks `--destroy` removes: those of a merged branch, and those whose
 * checkout is gone, unless the stack is running for another reason (an owner
 * state other than `reachable` or `stopped` means a process may hold it).
 */
export function destroyableStacks(
  stacks: readonly Stack[],
  roots: readonly string[],
  merged: ReadonlySet<string>,
  exists: (path: string) => boolean,
): Stack[] {
  const inRepo = (path: string): boolean =>
    roots.some((root) => path === root || path.startsWith(`${root}/`));

  return stacks.filter((stack) => {
    if (!inRepo(stack.project_root)) {
      return false;
    }

    if (!exists(stack.project_root)) {
      return true;
    }

    const branch = stack.branch_context.startsWith(BRANCH_REF)
      ? stack.branch_context.slice(BRANCH_REF.length)
      : undefined;

    return branch !== undefined && branch !== "main" && merged.has(branch);
  });
}

/** How many shared memory segments `ipcs -m` lists (header lines excluded). */
export const countSegments = (ipcs: string): number =>
  ipcs.split("\n").filter((line) => /^m\s+\d+/.test(line)).length;

/** The worktree paths `git worktree list --porcelain` prints. */
export const worktreeRoots = (porcelain: string): string[] =>
  porcelain
    .split("\n")
    .filter((line) => line.startsWith("worktree "))
    .map((line) => line.slice("worktree ".length));

/**
 * The branch names `git branch --merged` prints, without the current-branch
 * marks.
 */
export const mergedBranches = (output: string): Set<string> =>
  new Set(
    output
      .split("\n")
      .map((line) => line.replace(/^[*+]?\s*/, "").trim())
      .filter((line) => line.length > 0),
  );

/** Whether the arguments ask to stop the stacks rather than list them. */
export const shouldApply = (args: readonly string[]): boolean =>
  args.includes("--apply");

/** Whether the arguments ask to destroy stacks. */
export const shouldDestroy = (args: readonly string[]): boolean =>
  args.includes("--destroy");

const run = (command: string, args: string[]): string =>
  execFileSync(command, args, {
    encoding: "utf-8",
    stdio: ["ignore", "pipe", "inherit"],
  });

function main(): void {
  const args = process.argv.slice(2);
  const apply = shouldApply(args);
  const destroy = shouldDestroy(args);

  if (args.includes("--segments")) {
    console.log(
      `${countSegments(run("ipcs", ["-m"]))} shared memory segments in use (macOS allows 32).`,
    );

    return;
  }

  const listed = run("pnpm", [
    "exec",
    "supabase",
    "stack",
    "list",
    "--output-format",
    "json",
  ]);

  const { stacks } = v.parse(
    StackList,
    JSON.parse(listed.slice(Math.max(listed.indexOf("{"), 0))),
  );

  const roots = worktreeRoots(run("git", ["worktree", "list", "--porcelain"]));
  const merged = mergedBranches(run("git", ["branch", "--merged", "main"]));

  if (destroy) {
    const doomed = destroyableStacks(stacks, roots, merged, existsSync);

    for (const stack of doomed) {
      console.log(
        `${apply ? "Destroying" : "Would destroy"} ${stack.branch_context} (${stack.project_root})`,
      );

      if (apply) {
        run("pnpm", [
          "exec",
          "supabase",
          "stack",
          "destroy",
          "--stack-id",
          stack.id,
        ]);
      }
    }

    if (doomed.length === 0) {
      console.log("No stack belongs to a merged branch or a missing checkout.");
    } else if (!apply) {
      console.log("Add `--apply` to destroy them. Their data is deleted.");
    }

    return;
  }

  const prunable = prunableStacks(stacks, roots, merged);

  if (prunable.length === 0) {
    console.log("No running stack belongs to a branch merged into main.");

    return;
  }

  for (const stack of prunable) {
    const branch = stack.branch_context.slice(BRANCH_REF.length);

    if (!apply) {
      console.log(`Would stop ${branch} (${stack.project_root})`);

      continue;
    }

    run("pnpm", ["exec", "supabase", "stop", "--stack-id", stack.id]);

    console.log(`Stopped ${branch} (${stack.project_root})`);
  }

  if (!apply) {
    console.log("Run `pnpm supabase:prune --apply` to stop them.");
  }
}

if (import.meta.main) {
  main();
}
