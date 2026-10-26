/**
 * Stops the local stacks of branches already merged into `main`, for this
 * checkout and its worktrees. Every running native stack holds shared memory
 * segments, and macOS allows 32 (`kern.sysv.shmmni`), so a few dozen idle
 * stacks make the next `supabase start` fail. Stopping keeps the stack's data;
 * `supabase stack list` still shows it. Without `--apply` it only lists them.
 */
import { execFileSync } from "node:child_process";
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

const run = (command: string, args: string[]): string =>
  execFileSync(command, args, {
    encoding: "utf-8",
    stdio: ["ignore", "pipe", "inherit"],
  });

function main(): void {
  const apply = shouldApply(process.argv.slice(2));

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
