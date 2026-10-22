import { chmod, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import type { StackDeps } from "../../../src/cli/commands/stack.ts";
import type { ConsentRequest } from "../../../src/cli/core/agent.ts";
import type { StackReport } from "../../../src/cli/stacks.ts";

import { runStackLs, runStackPrune } from "../../../src/cli/commands/stack.ts";
import { run } from "../../../src/cli/core/run.ts";
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

describe("stack edge cases", () => {
  const supabase =
    (calls: string[][], stdout = ""): StackDeps["supabase"] =>
    (args) => {
      calls.push([...args]);

      return Promise.resolve({
        code: stdout === "" ? 0 : 1,
        stdout,
        stderr: "",
      });
    };

  it("lists no stacks and no summary where segments can't be read", async () => {
    const result = await runStackLs("/code/app", env, {
      memory: () => Promise.resolve({ supported: false, segments: [] }),
      stacks: () => Promise.resolve([]),
      supabase: supabase([]),
    });

    expect(result.output).toBe("No managed stacks.");
  });

  it("shows a deleted branch and the segment count without a limit", async () => {
    const result = await runStackLs("/code/app", env, {
      memory: () =>
        Promise.resolve({
          supported: true,
          segments: [{ id: "1", pid: 1, stackId: "old" }],
        }),
      stacks: () =>
        Promise.resolve([stack({ id: "old", branchExists: false })]),
      supabase: supabase([]),
    });

    expect(result.output).toContain("branch deleted");
    expect(result.output).toContain("Shared memory segments: 1 in use.");
    expect(result.data).not.toHaveProperty("sharedMemory.limit");
  });

  it("prunes nothing when every stack is in use", async () => {
    const result = await runStackPrune("/code/app", {}, env, undefined, {
      ...deps(),
      stacks: () => Promise.resolve([stack({ id: "current", current: true })]),
    });

    expect(result.output).toBe("Nothing to prune.");
  });

  it("stops idle stacks without consent and reports a failure from stdout", async () => {
    const calls: string[][] = [];
    const consents: ConsentRequest[] = [];

    const result = await runStackPrune(
      "/code/app",
      { "stop-idle": true },
      env,
      (request) => consents.push(request),
      {
        ...deps(),
        stacks: () =>
          Promise.resolve([
            stack({ id: "idle", branch: "refs/heads/feature" }),
          ]),
        supabase: supabase(calls, "stop refused"),
      },
    );

    expect(consents).toEqual([]);
    expect(calls).toEqual([["stack", "stop", "--stack-id", "idle"]]);
    expect(result.error).toBe("supabase stack stop failed: stop refused");
  });
});

describe("stack commands through the CLI", () => {
  let dir: string;

  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), "bsb-stack-"));
  });

  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  const fakeSupabase = async (): Promise<string> => {
    const list = JSON.stringify({
      stacks: [
        {
          id: "gone",
          project_root: join(dir, "deleted-worktree"),
          name: "gone",
          branch_context: "refs/heads/old",
          runtime: "native",
          owner: "unavailable",
        },
      ],
    });

    const bin = join(dir, "supabase");

    await writeFile(
      bin,
      [
        "#!/bin/sh",
        `if [ "$1 $2" = "stack list" ]; then printf '%s' '${list}'; exit 0; fi`,
        `echo "$@" >> "${join(dir, "calls.log")}"`,
      ].join("\n"),
    );
    await chmod(bin, 0o755);

    return bin;
  };

  const io = { stdout: (): void => {}, stderr: (): void => {} };

  it("lists the stacks and destroys the one whose worktree is gone", async () => {
    const env = { SUPABASE_BIN: await fakeSupabase(), BSB_AGENT: "no" };

    const ls = await run(["dev", "stack", "ls", "--json", "--cwd", dir], {
      env,
      io,
    });

    expect(ls.code).toBe(0);
    expect(ls.stdout).toContain('"worktreeExists": false');

    const prune = await run(["dev", "stack", "prune", "--json", "--cwd", dir], {
      env,
      io,
    });

    expect(prune.code).toBe(0);
    expect(await readFile(join(dir, "calls.log"), "utf-8")).toBe(
      "stack destroy --stack-id gone\n",
    );
  });
});
