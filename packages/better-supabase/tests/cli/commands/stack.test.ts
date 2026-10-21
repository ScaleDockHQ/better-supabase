import { describe, expect, it } from "vitest";

import type { ConsentRequest } from "../../../src/cli/core/agent.ts";
import type { StackReport } from "../../../src/cli/stacks.ts";

import {
  runStackLs,
  runStackPrune,
  type StackDeps,
} from "../../../src/cli/commands/stack.ts";
import { parseEnv } from "../../../src/cli/env.ts";

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

const STACKS = [
  stack({ id: "current", current: true }),
  stack({ id: "gone", worktreeExists: false, branchExists: undefined }),
  stack({ id: "idle", branch: "refs/heads/feature" }),
];

function deps(calls: string[][] = [], code = 0): StackDeps {
  return {
    memory: () =>
      Promise.resolve({
        supported: true,
        limit: 32,
        segments: [
          { id: "1", pid: 1, stackId: "current" },
          { id: "2", pid: 2 },
        ],
      }),
    stacks: () => Promise.resolve(STACKS),
    supabase: (args) => {
      calls.push([...args]);

      return Promise.resolve({
        code,
        stdout: "",
        stderr: code === 0 ? "" : "boom",
      });
    },
  };
}

const env = parseEnv({});

describe("stack ls", () => {
  it("lists the stacks with the segment use", async () => {
    const result = await runStackLs("/code/app", env, deps());

    expect(result.code).toBe(0);
    expect(result.output).toContain(
      "current  main  /code/app  (running, this checkout, 1 segment(s))",
    );
    expect(result.output).toContain("worktree gone");
    expect(result.output).toContain("Shared memory segments: 2 of 32 in use.");
    expect(result.data).toMatchObject({
      sharedMemory: { supported: true, used: 2, limit: 32, unattributed: 1 },
    });
  });
});

describe("stack prune", () => {
  it("prints the plan and changes nothing with --dry-run", async () => {
    const calls: string[][] = [];

    const result = await runStackPrune(
      "/code/app",
      { "dry-run": true, "stop-idle": true },
      env,
      () => {},
      deps(calls),
    );

    expect(calls).toEqual([]);
    expect(result.output).toBe(
      "Destroy gone (its worktree is gone)\nStop idle (it is running for another branch or checkout)",
    );
  });

  it("asks for consent, then destroys before it stops", async () => {
    const calls: string[][] = [];
    const consents: ConsentRequest[] = [];

    const result = await runStackPrune(
      "/code/app",
      { "stop-idle": true },
      env,
      (request) => consents.push(request),
      deps(calls),
    );

    expect(result.code).toBe(0);
    expect(consents).toEqual([
      {
        effect: "stack-destroy",
        detail: "stack prune destroys 1 stack(s) and their data",
      },
    ]);
    expect(calls).toEqual([
      ["stack", "destroy", "--stack-id", "gone"],
      ["stack", "stop", "--stack-id", "idle"],
    ]);
  });

  it("stops nothing without --stop-idle and reports a failing destroy", async () => {
    const calls: string[][] = [];

    const result = await runStackPrune(
      "/code/app",
      {},
      env,
      () => {},
      deps(calls, 1),
    );

    expect(calls).toEqual([["stack", "destroy", "--stack-id", "gone"]]);
    expect(result).toMatchObject({ code: 1, errorCode: "supabase_cli_failed" });
  });
});
