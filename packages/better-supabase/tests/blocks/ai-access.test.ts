import { describe, expect, it } from "vitest";

import type { BlockTransport } from "../../src/core/block-transport.ts";

import { accessDenied } from "../../src/blocks/ai-access.ts";
import { createAiEvals } from "../../src/blocks/ai-evals/index.ts";
import { createAiGuardrails } from "../../src/blocks/ai-guardrails/index.ts";
import { createPrompts } from "../../src/blocks/prompts/index.ts";

const AT = "2026-01-01T00:00:00Z";
const MINE = "00000000-0000-4000-8000-000000000001";
const OTHER = "00000000-0000-4000-8000-000000000002";

function fake(
  handlers: Record<string, (args: Record<string, unknown>) => unknown>,
) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];

  const transport: BlockTransport = {
    call: (_schema, fn, args) => {
      calls.push({ fn, args });
      const handler = handlers[fn];

      return handler
        ? Promise.resolve(handler(args))
        : Promise.reject(new Error(`unexpected ${fn}`));
    },
  };

  return { transport, calls };
}

const allowed = {
  organizationId: MINE,
  allowed: true,
  permission: "ai_chat.manage",
} as const;

const dataset = (tenant: string | null) => ({
  id: "d1",
  tenant_id: tenant,
  name: "set",
  description: null,
  created_at: AT,
});

const run = (tenant: string | null) => ({
  id: "r1",
  dataset_id: "d1",
  tenant_id: tenant,
  prompt_name: "p",
  prompt_version: 1,
  model: "m",
  scorers: [],
  status: "running",
  summary: null,
  created_at: AT,
  finished_at: null,
});

describe("accessDenied", () => {
  it("lets an unscoped block through", () => {
    expect(accessDenied(undefined, [OTHER])).toBeUndefined();
  });

  it("refuses a caller without a permission or an organization", () => {
    expect(accessDenied({ organizationId: MINE, allowed: false })?.kind).toBe(
      "forbidden",
    );

    expect(
      accessDenied({ organizationId: undefined, allowed: true })?.kind,
    ).toBe("forbidden");
  });

  it("refuses another organization and system records", () => {
    expect(accessDenied(allowed, [MINE])).toBeUndefined();
    expect(accessDenied(allowed, [OTHER])?.kind).toBe("forbidden");
    expect(accessDenied(allowed, [undefined])?.kind).toBe("forbidden");
  });
});

describe("prompts with access", () => {
  it("refuses before the database for a missing permission", async () => {
    const { transport, calls } = fake({});

    const got = await createPrompts({
      transport,
      access: { organizationId: MINE, allowed: false },
    }).get({ name: "greet", organizationId: MINE });

    expect(got.ok).toBe(false);
    expect(got.error?.kind).toBe("forbidden");
    expect(calls).toHaveLength(0);
  });

  it("refuses another organization and system writes", async () => {
    const { transport, calls } = fake({});
    const prompts = createPrompts({ transport, access: allowed });

    const foreign = await prompts.versions({
      name: "greet",
      organizationId: OTHER,
    });

    const system = await prompts.create({ name: "greet", template: "Hi" });

    expect(foreign.error?.kind).toBe("forbidden");
    expect(system.error?.kind).toBe("forbidden");
    expect(calls).toHaveLength(0);
  });

  it("serves the caller's own organization", async () => {
    const { transport, calls } = fake({ get_prompt: () => null });

    const got = await createPrompts({ transport, access: allowed }).get({
      name: "greet",
      organizationId: MINE,
    });

    expect(got.ok).toBe(true);
    expect(calls[0]?.args).toMatchObject({ tenant: MINE });
  });
});

describe("ai-guardrails with access", () => {
  it("refuses another organization's log and the global purge", async () => {
    const { transport, calls } = fake({});
    const guardrails = createAiGuardrails({ transport, access: allowed });

    const list = await guardrails.decisions.list({ organizationId: OTHER });
    const unscoped = await guardrails.decisions.list();
    const purge = await guardrails.decisions.purge();

    expect(list.error?.kind).toBe("forbidden");
    expect(unscoped.error?.kind).toBe("forbidden");
    expect(purge.error?.kind).toBe("forbidden");
    expect(calls).toHaveLength(0);
  });

  it("refuses a policy write for another organization", async () => {
    const { transport, calls } = fake({});

    const saved = await createAiGuardrails({
      transport,
      access: allowed,
    }).policies.upsert({
      agent: "*",
      stage: "input",
      config: {},
      organizationId: OTHER,
    });

    expect(saved.error?.kind).toBe("forbidden");
    expect(calls).toHaveLength(0);
  });
});

describe("ai-evals with access", () => {
  it("reads another organization's run as not found", async () => {
    const { transport, calls } = fake({ get_eval_run: () => run(OTHER) });

    const results = await createAiEvals({
      transport,
      access: allowed,
    }).runs.results({ runId: "r1" });

    expect(results.error?.kind).toBe("not_found");
    expect(calls.map((call) => call.fn)).toEqual(["get_eval_run"]);
  });

  it("reads another organization's dataset as not found", async () => {
    const { transport, calls } = fake({
      get_eval_dataset: () => dataset(OTHER),
    });

    const added = await createAiEvals({ transport, access: allowed }).items.add(
      { datasetId: "d1", items: [{ input: "x" }] },
    );

    expect(added.error?.kind).toBe("not_found");
    expect(calls.map((call) => call.fn)).toEqual(["get_eval_dataset"]);
  });

  it("refuses a system dataset and an unknown id", async () => {
    const { transport } = fake({ get_eval_dataset: () => dataset(null) });
    const evals = createAiEvals({ transport, access: allowed });

    expect((await evals.items.list({ datasetId: "d1" })).error?.kind).toBe(
      "not_found",
    );

    const missing = createAiEvals({
      transport: fake({ get_eval_dataset: () => null }).transport,
      access: allowed,
    });

    expect((await missing.runs.list({ datasetId: "d9" })).error?.kind).toBe(
      "not_found",
    );
  });

  it("checks both runs of a compare", async () => {
    const { transport } = fake({
      get_eval_run: (args) => run(args["run"] === "r2" ? OTHER : MINE),
    });

    const compared = await createAiEvals({
      transport,
      access: allowed,
    }).runs.compare({ baseRunId: "r1", candidateRunId: "r2" });

    expect(compared.error?.kind).toBe("not_found");
  });

  it("goes on for the caller's own dataset", async () => {
    const { transport, calls } = fake({
      get_eval_dataset: () => dataset(MINE),
      add_eval_items: () => 1,
    });

    const added = await createAiEvals({ transport, access: allowed }).items.add(
      { datasetId: "d1", items: [{ input: "x" }] },
    );

    expect(added.ok).toBe(true);
    expect(calls.map((call) => call.fn)).toEqual([
      "get_eval_dataset",
      "add_eval_items",
    ]);
  });

  it("refuses without the permission before any lookup", async () => {
    const { transport, calls } = fake({});

    const got = await createAiEvals({
      transport,
      access: { organizationId: MINE, allowed: false },
    }).runs.get("r1");

    expect(got.error?.kind).toBe("forbidden");
    expect(calls).toHaveLength(0);
  });
});
