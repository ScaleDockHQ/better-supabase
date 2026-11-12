import { describe, expect, it } from "vitest";

import type { Stack } from "./supabase-prune.ts";

import {
  mergedBranches,
  countSegments,
  destroyableStacks,
  prunableStacks,
  shouldApply,
  worktreeRoots,
} from "./supabase-prune.ts";

const stack = (
  id: string,
  root: string,
  branch: string,
  owner = "reachable",
): Stack => ({
  id,
  project_root: root,
  branch_context: branch === "detached" ? branch : `refs/heads/${branch}`,
  owner,
});

describe("prunableStacks", () => {
  const roots = ["/code/repo", "/code/repo-feature"];
  const merged = new Set(["main", "feat/done", "fix/old"]);

  it("stops running stacks of merged branches in this repo and its worktrees", () => {
    const stacks = [
      stack("a", "/code/repo", "feat/done"),
      stack("b", "/code/repo-feature/apps/web", "fix/old"),
      stack("c", "/code/repo", "feat/open"),
      stack("d", "/code/repo", "main"),
      stack("e", "/code/other", "feat/done"),
      stack("f", "/code/repo", "fix/old", "unavailable"),
      stack("g", "/code/repo", "detached"),
      stack("h", "/code/repo-other", "feat/done"),
    ];

    expect(
      prunableStacks(stacks, roots, merged).map((entry) => entry.id),
    ).toEqual(["a", "b"]);
  });
});

describe("shouldApply", () => {
  it("only lists the stacks unless --apply is passed", () => {
    expect(shouldApply([])).toBe(false);
    expect(shouldApply(["--dry-run"])).toBe(false);
    expect(shouldApply(["--apply"])).toBe(true);
  });
});

describe("git output", () => {
  it("reads the worktree roots", () => {
    expect(
      worktreeRoots(
        "worktree /code/repo\nHEAD abc\nbranch refs/heads/main\n\nworktree /code/repo-feature\nHEAD def\n",
      ),
    ).toEqual(["/code/repo", "/code/repo-feature"]);
  });

  it("reads the merged branches without the current-branch marks", () => {
    expect([...mergedBranches("  feat/done\n* main\n+ fix/old\n")]).toEqual([
      "feat/done",
      "main",
      "fix/old",
    ]);
  });
});

describe("destroyableStacks", () => {
  const stack = (id: string, root: string, branch: string) => ({
    id,
    project_root: root,
    branch_context: branch,
    owner: "reachable",
  });

  it("takes merged branches and missing checkouts, never main", () => {
    const stacks = [
      stack("a", "/r", "refs/heads/done"),
      stack("b", "/r/wt", "refs/heads/open"),
      stack("c", "/r/gone", "refs/heads/open"),
      stack("d", "/r", "refs/heads/main"),
      stack("e", "/elsewhere", "refs/heads/done"),
    ];

    expect(
      destroyableStacks(
        stacks,
        ["/r", "/r/wt", "/r/gone"],
        new Set(["done", "main"]),
        (path) => path !== "/r/gone",
      ).map((entry) => entry.id),
    ).toEqual(["a", "c"]);
  });
});

describe("countSegments", () => {
  it("counts segment rows only", () => {
    const output =
      "IPC status\nShared Memory:\nT ID KEY MODE\nm 1 0x0 --rw\nm 2 0x0 --rw\n";

    expect(countSegments(output)).toBe(2);
  });
});
