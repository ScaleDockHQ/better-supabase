import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { BlockTransport } from "../../src/blocks/prompts/index.ts";

import { createAiEvals } from "../../src/blocks/ai-evals/index.ts";
import { createAiGuardrails } from "../../src/blocks/ai-guardrails/index.ts";
import { createPrompts, sqlTransport } from "../../src/blocks/prompts/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

describe.skipIf(!live)("AI list reads", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("pages prompts, datasets and policies of one organization", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install([
        "organizations",
        "prompts",
        "ai-evals",
        "ai-guardrails",
      ]);
      const owner = await s.user("owner");
      const other = await s.user("other");
      const tenant = await s.organization(owner);
      const otherTenant = await s.organization(other);

      const inner = sqlTransport(s.sql);

      const transport: BlockTransport = {
        async call(schema, fn, args) {
          await s.service();

          return inner.call(schema, fn, args);
        },
      };

      const prompts = createPrompts({ transport });
      const evals = createAiEvals({ transport });
      const guardrails = createAiGuardrails({ transport });

      // The SQL transport sends a JS array as a Postgres array, not jsonb.
      for (const name of ["a", "b", "c"]) {
        await s.value(
          "better_supabase.create_prompt_version($1, $2, $3, $4::jsonb, $5)",
          [name, `Hi ${name}`, tenant, "[]", "production"],
        );
      }

      await s.value(
        "better_supabase.create_prompt_version($1, $2, $3, $4::jsonb)",
        ["z", "x", otherTenant, "[]"],
      );

      const first = await prompts
        .list({ organizationId: tenant, limit: 2 })
        .orThrow();

      expect(first.items.map((item) => item.name)).toEqual(["a", "b"]);
      expect(first.hasMore).toBe(true);
      expect(first.items[0]?.labels).toEqual({ production: 1 });

      const second = await prompts
        .list({
          organizationId: tenant,
          limit: 2,
          ...(first.nextCursor === null ? {} : { after: first.nextCursor }),
        })
        .orThrow();

      expect(second.items.map((item) => item.name)).toEqual(["c"]);
      expect(second.hasMore).toBe(false);

      const dataset = await evals.datasets
        .create({ name: "set", organizationId: tenant })
        .orThrow();

      await s.value("better_supabase.add_eval_items($1, $2::jsonb)", [
        dataset.id,
        JSON.stringify([{ input: "q" }]),
      ]);

      const datasets = await evals.datasets
        .list({ organizationId: tenant })
        .orThrow();

      expect(datasets.items).toHaveLength(1);
      expect(datasets.items[0]).toMatchObject({
        name: "set",
        itemCount: 1,
        runCount: 0,
      });

      for (const agent of ["*", "sales"]) {
        for (const stage of ["input", "output"] as const) {
          await guardrails.policies
            .upsert({
              agent,
              stage,
              config: { injection: { action: "block" } },
              organizationId: tenant,
            })
            .orThrow();
        }
      }

      const policies = await guardrails.policies
        .list({ organizationId: tenant, limit: 3 })
        .orThrow();

      expect(
        policies.items.map((policy) => `${policy.agent}:${policy.stage}`),
      ).toEqual(["*:input", "*:output", "sales:input"]);
      expect(policies.nextCursor).toEqual(["sales", "input"]);

      const rest = await guardrails.policies
        .list({
          organizationId: tenant,
          limit: 3,
          ...(policies.nextCursor === null
            ? {}
            : { after: policies.nextCursor }),
        })
        .orThrow();

      expect(rest.items.map((policy) => policy.stage)).toEqual(["output"]);
    } finally {
      await s.close();
    }
  });
});
