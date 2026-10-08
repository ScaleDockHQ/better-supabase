import { beforeEach, describe, expect, it, vi } from "vitest";

import type { BuilderStartCall } from "../../src/blocks/workflow-builder/workflow-builder.ts";

import {
  executeGraph,
  type GraphStepCall,
} from "../../src/blocks/workflow-builder/executor.ts";
import { fakeRuntime, GRAPH } from "../blocks/workflow-builder/fixture.ts";

const start = vi.fn(async (..._args: unknown[]) => ({ runId: "wrun_new" }));
const listRuns = vi.fn(
  async (_params: unknown): Promise<{ data: { runId: string }[] }> => ({
    data: [],
  }),
);
const world = { analytics: { runs: { list: listRuns } } };
let attempt = 1;

vi.mock("workflow/api", () => ({ start }));
vi.mock("workflow/runtime", () => ({ getWorld: async () => world }));
vi.mock("workflow", () => ({
  getWorkflowMetadata: () => ({ workflowRunId: "wrun_7" }),
  getStepMetadata: () => ({ attempt }),
}));

const {
  compileGraph,
  compiledGraphOf,
  DYNAMIC_SOURCE_MAX_BYTES,
  DYNAMIC_WORKFLOWS_ENV,
  graphStarter,
  nodeRunReporter,
} = await import("../../src/workflow-sdk/builder/index.ts");

type Compiled = (
  input: unknown,
  meta: unknown,
) => Promise<Record<string, unknown>>;

function load(
  source: string,
  runtime: ReturnType<typeof fakeRuntime>,
  aliases: Readonly<Record<string, string>>,
): Compiled {
  const steps = Object.fromEntries(
    Object.keys(aliases).map((alias) => [
      alias,
      (call: GraphStepCall) => runtime.step(call),
    ]),
  );
  // oxlint-disable-next-line eslint/no-new-func, typescript/no-implied-eval -- the test runs the compiled source the way the SDK's VM does.
  const factory = new Function(
    "steps",
    "sleep",
    "createHook",
    `${source}\nreturn workflow;`,
  );
  const sleep = (ms: number) => runtime.sleep(ms);
  const createHook = ({ token }: { token: string }) =>
    runtime.approval(token, token.split(":").at(-1) ?? "");
  const workflow: unknown = factory(steps, sleep, createHook);
  if (typeof workflow !== "function") throw new Error("no workflow");
  return async (input, meta) => {
    const result: unknown = await workflow(input, meta);
    return result as Record<string, unknown>;
  };
}

const CALL: BuilderStartCall = {
  definition: {
    id: "d1",
    tenant: "t1",
    slug: "s",
    name: "S",
    description: undefined,
    createdBy: undefined,
    createdAt: Temporal.Instant.from("2026-01-01T00:00:00Z"),
    updatedAt: Temporal.Instant.from("2026-01-01T00:00:00Z"),
  },
  version: {
    id: "v1",
    definition: "d1",
    version: 3,
    status: "published",
    createdBy: undefined,
    createdAt: Temporal.Instant.from("2026-01-01T00:00:00Z"),
    publishedAt: undefined,
    graph: GRAPH,
  },
  input: { email: "a@x.test" },
  tenant: "t1",
  actor: "u1",
  idempotencyKey: "run:k",
};

beforeEach(() => {
  start.mockClear();
  listRuns.mockClear();
  listRuns.mockResolvedValue({ data: [] });
  vi.unstubAllEnvs();
});

describe("compileGraph", () => {
  it("compiles to source that runs like executeGraph, one alias per step node", async () => {
    const compiled = compileGraph(GRAPH);
    expect(compiled).toMatchObject({
      engine: "workflow-sdk",
      format: 1,
      exportName: "workflow",
    });
    expect(compiled.source).toContain('"use workflow"');
    expect(Object.values(compiled.aliases)).toEqual([
      "crm.lookup",
      "email.send",
      "email.send",
      "slack.post",
    ]);
    for (const [plan, approval] of [
      ["pro", { approved: true }],
      ["pro", { approved: false }],
      ["free", undefined],
    ] as const) {
      const expected = fakeRuntime(plan, approval);
      const results = await executeGraph(
        GRAPH,
        { email: "a@x.test" },
        expected,
      );
      const actual = fakeRuntime(plan, approval);
      const run = load(compiled.source, actual, compiled.aliases);
      expect(await run({ email: "a@x.test" }, { runKey: "run-1" })).toEqual(
        results,
      );
      expect(actual.log).toEqual(expected.log);
    }
    const noMeta = fakeRuntime("pro", undefined);
    await load(compiled.source, noMeta, compiled.aliases)({}, null);
    expect(noMeta.log).toContain("approval :ok ok");
  });

  it("compiles every condition operator like evaluateCondition", async () => {
    const cases: [string, unknown, unknown][] = [
      ["notEquals", "input.plan", "pro"],
      ["exists", "input.plan", undefined],
      ["truthy", "input.missing", undefined],
      ["greaterThan", "input.seats", 3],
      ["lessThan", "input.seats", 3],
      ["contains", "input.plan", "fre"],
      ["contains", "input.tags", { a: 1 }],
      ["contains", "input.seats", 1],
      ["equals", "input.tags.0.a", 1],
      ["equals", "input.plan.x.y", null],
    ];
    for (const [op, path, value] of cases) {
      const graph = {
        nodes: [
          { id: "t", kind: "trigger" as const },
          { id: "c", kind: "condition" as const, config: { path, op, value } },
          { id: "s", kind: "step" as const, step: "x" },
        ],
        edges: [
          { id: "1", source: "t", target: "c" },
          { id: "2", source: "c", target: "s", branch: "true" as const },
        ],
      };
      const input = { plan: "free", seats: 5, tags: [{ a: 1 }] };
      const expected = await executeGraph(
        graph,
        input,
        fakeRuntime("", undefined),
      );
      const compiled = compileGraph(graph);
      const actual = await load(
        compiled.source,
        fakeRuntime("", undefined),
        compiled.aliases,
      )(input, { runKey: "k" });
      expect([op, path, actual]).toEqual([op, path, expected]);
    }
  });

  it("refuses invalid graphs and source over the dynamic limit", () => {
    expect(() => compileGraph({ nodes: [], edges: [] })).toThrow(
      "exactly one trigger",
    );
    const huge = {
      nodes: [
        { id: "t", kind: "trigger" as const },
        {
          id: "s",
          kind: "step" as const,
          step: "x",
          config: { blob: "x".repeat(DYNAMIC_SOURCE_MAX_BYTES) },
        },
      ],
      edges: [{ id: "1", source: "t", target: "s" }],
    };
    expect(() => compileGraph(huge)).toThrow("dynamic workflows take at most");
  });

  it("reads a stored compiled graph back", () => {
    const compiled = compileGraph(GRAPH);
    expect(compiledGraphOf(JSON.parse(JSON.stringify(compiled)))).toEqual(
      compiled,
    );
    expect(compiledGraphOf({ ...compiled, format: 2 })).toBeUndefined();
    expect(compiledGraphOf({ ...compiled, aliases: { a: 1 } })).toBeUndefined();
    expect(compiledGraphOf(null)).toBeUndefined();
  });
});

describe("graphStarter", () => {
  const steps = {
    "crm.lookup": { stepId: "crm" },
    "email.send": { stepId: "email" },
    "slack.post": { stepId: "slack" },
  };

  it("starts dynamic source with the steps bound by alias and the run attributes", async () => {
    const starter = graphStarter({ steps, dynamic: true });
    expect(await starter(CALL)).toBe("wrun_new");
    const [source, args, options] = start.mock.calls[0] ?? [];
    expect(source).toBe(compileGraph(GRAPH).source);
    expect(args).toEqual([
      { email: "a@x.test" },
      { runKey: "run:k", definition: "d1", version: 3 },
    ]);
    expect(options).toMatchObject({
      attributes: {
        "bs.tenant": "t1",
        "bs.actor": "u1",
        "bs.definition": "d1",
        "bs.version": "3",
        "bs.key": "run:k",
      },
      experimental_dynamic: { exportName: "workflow" },
    });
    const bound = (
      options as { experimental_dynamic: { steps: Record<string, unknown> } }
    ).experimental_dynamic.steps;
    expect(Object.values(bound)).toEqual([
      steps["crm.lookup"],
      steps["email.send"],
      steps["email.send"],
      steps["slack.post"],
    ]);
  });

  it("uses the stored compiled form and refuses steps it wasn't given", async () => {
    const compiled = {
      ...compileGraph(GRAPH),
      source: "async function workflow() {}",
    };
    await graphStarter({ steps, dynamic: true })({
      ...CALL,
      version: { ...CALL.version, compiled },
    });
    expect(start.mock.calls[0]?.[0]).toBe("async function workflow() {}");
    await expect(
      graphStarter({ steps: {}, dynamic: true })(CALL),
    ).rejects.toThrow('the graph uses step "crm.lookup"');
  });

  it("reads the env flag, and starts the static executor when it is off", async () => {
    const executor = Object.assign(async () => undefined, {
      workflowId: "executor",
    });
    vi.stubEnv(DYNAMIC_WORKFLOWS_ENV, "true");
    await graphStarter({ steps, executor })(CALL);
    expect(typeof start.mock.calls[0]?.[0]).toBe("string");
    vi.stubEnv(DYNAMIC_WORKFLOWS_ENV, "0");
    const world = {} as never;
    await graphStarter({ steps, executor, world })({
      ...CALL,
      actor: undefined,
      tenant: undefined,
    });
    const [fn, args, options] = start.mock.calls[1] ?? [];
    expect(fn).toBe(executor);
    expect(args).toEqual([
      GRAPH,
      { email: "a@x.test" },
      { runKey: "run:k", definition: "d1", version: 3 },
    ]);
    expect(options).toMatchObject({ world });
    expect(
      (options as { attributes: Record<string, string> }).attributes,
    ).not.toHaveProperty("bs.actor");
    await expect(graphStarter({ steps })(CALL)).rejects.toThrow(
      "pass an executor",
    );
  });

  it("returns the run a repeated key already started", async () => {
    listRuns.mockResolvedValue({ data: [{ runId: "wrun_old" }] });
    expect(await graphStarter({ steps, dynamic: true })(CALL)).toBe("wrun_old");
    expect(start).not.toHaveBeenCalled();
  });
});

describe("nodeRunReporter", () => {
  const call: GraphStepCall = {
    node: "n",
    step: "s",
    config: {},
    input: {},
    results: {},
    runKey: "k",
  };

  it("records running, then completed or failed, and never fails on a lost record", async () => {
    const record = vi.fn(async (_input: unknown) => true);
    const report = nodeRunReporter({ record });
    attempt = 2;
    expect(await report(call, async () => ({ ok: 1 }))).toEqual({ ok: 1 });
    await report(call, async () => undefined);
    await expect(
      report(call, async () => {
        throw new Error("boom");
      }),
    ).rejects.toThrow("boom");
    await expect(
      report(call, async () => {
        // oxlint-disable-next-line typescript/only-throw-error -- a step may throw a non-Error.
        throw "raw";
      }),
    ).rejects.toBe("raw");
    expect(record.mock.calls.map(([input]) => input)).toEqual([
      { run: "wrun_7", node: "n", status: "running", attempt: 2 },
      {
        run: "wrun_7",
        node: "n",
        status: "completed",
        attempt: 2,
        output: { ok: 1 },
      },
      { run: "wrun_7", node: "n", status: "running", attempt: 2 },
      {
        run: "wrun_7",
        node: "n",
        status: "completed",
        attempt: 2,
        output: undefined,
      },
      { run: "wrun_7", node: "n", status: "running", attempt: 2 },
      { run: "wrun_7", node: "n", status: "failed", attempt: 2, error: "boom" },
      { run: "wrun_7", node: "n", status: "running", attempt: 2 },
      { run: "wrun_7", node: "n", status: "failed", attempt: 2, error: "raw" },
    ]);
    const lossy = nodeRunReporter({
      record: async () => {
        throw new Error("db down");
      },
    });
    expect(await lossy(call, async () => 5)).toBe(5);
  });
});
