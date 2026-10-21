import { describe, expect, it } from "vitest";

import type { RunProcess } from "../../src/cli/exec.ts";
import type { ManagedStack, StackReport } from "../../src/cli/stacks.ts";

import { parseEnv } from "../../src/cli/env.ts";
import {
  branchName,
  parseStackList,
  prunePlan,
  reportStacks,
} from "../../src/cli/stacks.ts";

const LIST = JSON.stringify({
  stacks: [
    {
      id: "aaa",
      project_root: "/code/app",
      name: "app",
      branch_context: "refs/heads/main",
      runtime: "native",
      owner: "reachable",
    },
    {
      id: "bbb",
      project_root: "/code/gone",
      name: "gone",
      branch_context: "detached",
      runtime: "native",
      owner: "unavailable",
    },
  ],
  message: "",
});

function stack(overrides: Partial<StackReport>): StackReport {
  return {
    id: "id",
    projectRoot: "/code/app",
    name: "app",
    branch: "refs/heads/main",
    runtime: "native",
    running: true,
    worktreeExists: true,
    branchExists: true,
    current: false,
    segments: 1,
    ...overrides,
  };
}

describe("parseStackList", () => {
  it("reads the stacks and their running state", () => {
    expect(parseStackList(`Listing stacks...\n${LIST}`)).toEqual([
      {
        id: "aaa",
        projectRoot: "/code/app",
        name: "app",
        branch: "refs/heads/main",
        runtime: "native",
        running: true,
      },
      {
        id: "bbb",
        projectRoot: "/code/gone",
        name: "gone",
        branch: "detached",
        runtime: "native",
        running: false,
      },
    ]);
  });

  it("rejects output without a stacks array", () => {
    expect(() => parseStackList("{}")).toThrow(/no stacks array/);
    expect(() => parseStackList("No stacks.")).toThrow(/no stacks array/);
    expect(() => parseStackList('{"stacks":{}}')).toThrow(/no stacks array/);
  });

  it("skips entries without an id and reads fields that aren't text as empty", () => {
    expect(
      parseStackList(
        JSON.stringify({
          stacks: [null, "aaa", { name: "no id" }, { id: "ccc", name: 7 }],
        }),
      ),
    ).toEqual([
      {
        id: "ccc",
        projectRoot: "",
        name: "",
        branch: "",
        runtime: "",
        running: false,
      },
    ]);
  });
});

describe("branchName", () => {
  it("strips refs/heads/ and keeps anything else", () => {
    expect(branchName("refs/heads/feat/a")).toBe("feat/a");
    expect(branchName("detached")).toBe("detached");
  });
});

describe("reportStacks", () => {
  it("marks the current stack, deleted branches, missing worktrees and segments", async () => {
    const stacks: ManagedStack[] = [
      { ...stack({}), id: "current" },
      { ...stack({}), id: "old", branch: "refs/heads/old" },
      { ...stack({}), id: "gone", projectRoot: "/code/gone" },
    ];

    const run: RunProcess = (_command, args) => {
      const [first, second, third, fourth] = args;

      const respond = (code: number, stdout = ""): ReturnType<RunProcess> =>
        Promise.resolve({ code, stdout, stderr: "" });

      if (second === "--symbolic-full-name") {
        return respond(0, "refs/heads/main\n");
      }

      if (second === "--show-toplevel") {
        return respond(0, "/code/app\n");
      }

      return first === "rev-parse" && third === "--quiet"
        ? respond(fourth === "refs/heads/old" ? 1 : 0)
        : respond(1);
    };

    const reports = await reportStacks(stacks, {
      root: "/code/app",
      env: parseEnv({}),
      run,
      exists: (path) => path !== "/code/gone",
      memory: {
        supported: true,
        segments: [
          { id: "1", pid: 1, stackId: "current" },
          { id: "2", pid: 2, stackId: "old" },
          { id: "3", pid: 3 },
        ],
      },
    });

    expect(
      reports.map(
        ({ id, current, branchExists, worktreeExists, segments }) => ({
          id,
          current,
          branchExists,
          worktreeExists,
          segments,
        }),
      ),
    ).toEqual([
      {
        id: "current",
        current: true,
        branchExists: true,
        worktreeExists: true,
        segments: 1,
      },
      {
        id: "old",
        current: false,
        branchExists: false,
        worktreeExists: true,
        segments: 1,
      },
      {
        id: "gone",
        current: false,
        branchExists: undefined,
        worktreeExists: false,
        segments: 0,
      },
    ]);
  });
});

describe("prunePlan", () => {
  const stacks = [
    stack({ id: "current", current: true }),
    stack({ id: "gone", worktreeExists: false, branchExists: undefined }),
    stack({ id: "deleted", branchExists: false, running: false }),
    stack({ id: "idle" }),
    stack({ id: "stopped", running: false }),
  ];

  it("destroys stacks whose worktree or branch is gone and never the current one", () => {
    expect(
      prunePlan(stacks, { stopIdle: false }).map(
        ({ stack: s, action, reason }) => [s.id, action, reason],
      ),
    ).toEqual([
      ["gone", "destroy", "worktree-missing"],
      ["deleted", "destroy", "branch-deleted"],
    ]);
  });

  it("stops other running stacks with stopIdle", () => {
    expect(
      prunePlan(stacks, { stopIdle: true }).map(({ stack: s, action }) => [
        s.id,
        action,
      ]),
    ).toEqual([
      ["gone", "destroy"],
      ["deleted", "destroy"],
      ["idle", "stop"],
    ]);
  });
});
