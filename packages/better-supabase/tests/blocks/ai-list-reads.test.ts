/* oxlint-disable typescript/no-deprecated -- these tests cover the deprecated methods until 0.70 (ADR 1077). 5 findings. */
import { describe, expect, it } from "vitest";

import type { BlockTransport } from "../../src/core/block-transport.ts";

import { createAiEvals } from "../../src/blocks/ai-evals/index.ts";
import { createAiGuardrails } from "../../src/blocks/ai-guardrails/index.ts";
import { createPrompts } from "../../src/blocks/prompts/index.ts";

const ORG = "00000000-0000-4000-8000-000000000001";
const AT = "2026-01-01T00:00:00Z";

function fake(handlers: Record<string, () => unknown>) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];

  const transport: BlockTransport = {
    call: (_schema, fn, args) => {
      calls.push({ fn, args });
      const handler = handlers[fn];

      return handler
        ? Promise.resolve(handler())
        : Promise.reject(new Error(`unexpected ${fn}`));
    },
  };

  return { transport, calls };
}

const page = (items: unknown[], nextCursor: string[] | null = null) => ({
  items,
  hasMore: nextCursor !== null,
  nextCursor,
});

describe("prompts.list", () => {
  const summary = {
    name: "alpha",
    tenant_id: ORG,
    latest_version: "2",
    version_count: 2,
    labels: { production: 2, staging: 1 },
    updated_at: AT,
  };

  it("maps a page and passes the cursor", async () => {
    const { transport, calls } = fake({
      list_prompts: () => page([summary], ["alpha"]),
    });

    const result = await createPrompts({ transport })
      .list({ organizationId: ORG, limit: 5, after: ["aaa"] })
      .orThrow();

    expect(calls[0]?.args).toEqual({ tenant: ORG, after: "aaa", max_rows: 5 });
    expect(result.nextCursor).toEqual(["alpha"]);
    expect(result.items[0]).toMatchObject({
      organizationId: ORG,
      name: "alpha",
      latestVersion: 2,
      versionCount: 2,
      labels: { production: 2, staging: 1 },
    });
    expect(result.items[0]?.updatedAt?.toString()).toBe("2026-01-01T00:00:00Z");
  });

  it("leaves updatedAt empty without the column", async () => {
    const { transport } = fake({
      list_prompts: () => page([{ ...summary, updated_at: null }]),
    });

    const result = await createPrompts({ transport }).list().orThrow();

    expect(result.items[0]?.updatedAt).toBeUndefined();
  });

  it("refuses another organization and a missing one under access", async () => {
    const { transport, calls } = fake({ list_prompts: () => page([]) });

    const prompts = createPrompts({
      transport,
      access: { organizationId: ORG, allowed: true },
    });

    expect((await prompts.list({ organizationId: "other" })).ok).toBe(false);
    expect((await prompts.list()).ok).toBe(false);
    expect((await prompts.list({ organizationId: ORG })).ok).toBe(true);
    expect(calls).toHaveLength(1);
  });
});

describe("datasets.list", () => {
  it("maps counts and the last run", async () => {
    const { transport, calls } = fake({
      list_eval_datasets: () =>
        page([
          {
            id: "d1",
            tenant_id: ORG,
            name: "set",
            description: null,
            created_at: AT,
            item_count: 3,
            run_count: "2",
            last_run_at: AT,
          },
          {
            id: "d2",
            tenant_id: ORG,
            name: "empty",
            description: null,
            created_at: AT,
            item_count: 0,
            run_count: 0,
            last_run_at: null,
          },
        ]),
    });

    const result = await createAiEvals({ transport })
      .datasets.list({ organizationId: ORG })
      .orThrow();

    expect(calls[0]?.args).toMatchObject({ tenant: ORG });
    expect(result.items[0]).toMatchObject({ itemCount: 3, runCount: 2 });
    expect(result.items[0]?.lastRunAt?.toString()).toBe("2026-01-01T00:00:00Z");
    expect(result.items[1]?.lastRunAt).toBeUndefined();
  });

  it("refuses another organization under access", async () => {
    const { transport } = fake({ list_eval_datasets: () => page([]) });

    const evals = createAiEvals({
      transport,
      access: { organizationId: ORG, allowed: true },
    });

    expect((await evals.datasets.list({ organizationId: "other" })).ok).toBe(
      false,
    );
    expect((await evals.datasets.list({ organizationId: ORG })).ok).toBe(true);
  });
});

describe("policies.list", () => {
  const policy = {
    id: "p1",
    tenant_id: ORG,
    agent: "sales",
    stage: "input",
    config: { pii: { action: "redact" } },
    enabled: true,
    updated_at: AT,
  };

  it("splits the cursor into agent and stage", async () => {
    const { transport, calls } = fake({
      list_guardrail_policies: () => page([policy], ["sales", "input"]),
    });

    const result = await createAiGuardrails({ transport })
      .policies.list({
        organizationId: ORG,
        agent: "sales",
        after: ["a", "output"],
      })
      .orThrow();

    expect(calls[0]?.args).toEqual({
      tenant: ORG,
      agent: "sales",
      after_agent: "a",
      after_stage: "output",
      max_rows: undefined,
    });
    expect(result.items[0]).toMatchObject({ agent: "sales", stage: "input" });
    expect(result.nextCursor).toEqual(["sales", "input"]);
  });

  it("refuses a missing organization under access", async () => {
    const { transport, calls } = fake({
      list_guardrail_policies: () => page([]),
    });

    const guardrails = createAiGuardrails({
      transport,
      access: { organizationId: ORG, allowed: true },
    });

    expect((await guardrails.policies.list()).ok).toBe(false);
    expect(calls).toHaveLength(0);
  });
});
