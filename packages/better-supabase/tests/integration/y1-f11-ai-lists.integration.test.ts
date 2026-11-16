import { Pool } from "pg";
import { afterAll, describe, it } from "vitest";

import type { BlockTransport } from "../../src/core/block-transport.ts";

import { createAiEvals } from "../../src/blocks/ai-evals/index.ts";
import { createAiGuardrails } from "../../src/blocks/ai-guardrails/index.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { testBlockList } from "../../src/testing/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

/** One transaction gives every row the same now(); a sort needs distinct values. */
async function spreadTimes(
  s: BlockSession,
  table: string,
  columns: readonly string[],
): Promise<void> {
  await s.client.query("reset role");
  await s.client.query(
    `update better_supabase.${table} a set ${columns.map((column) => `${column} = now() + (r.n || ' minutes')::interval`).join(", ")} from (select id, row_number() over (order by random()) as n from better_supabase.${table}) r where r.id = a.id`,
  );
}

describe.skipIf(!live)("the ai-guardrails and ai-evals lists", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("pages guardrail policies and decisions, and ai-evals datasets and runs", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["organizations", "ai-evals", "ai-guardrails"]);
      const owner = await s.user("ai-lists-owner");
      const org = await s.organization(owner);
      const inner = sqlTransport(s.sql);

      const transport: BlockTransport = {
        async call(schema, fn, args) {
          await s.service();

          return inner.call(schema, fn, args);
        },
      };

      const guardrails = createAiGuardrails({ transport });
      const evals = createAiEvals({ transport });

      const agents = ["alpha", "alpine", "beta", "gamma"];

      for (const [index, agent] of agents.entries()) {
        await guardrails.policies
          .upsert({
            agent,
            stage: index % 2 === 0 ? "input" : "output",
            config: { injection: { action: "block" } },
            organizationId: org,
            enabled: index !== 3,
          })
          .orThrow();
      }

      await guardrails.policies
        .upsert({
          agent: "delta",
          stage: "input",
          config: { injection: { action: "flag" } },
          organizationId: org,
        })
        .orThrow();
      await spreadTimes(s, "guardrail_policies", ["updated_at"]);

      await testBlockList({
        name: "ai-guardrails.policies",
        target: {
          page: (options) =>
            guardrails.policies.page({ ...options, organizationId: org }),
          count: (options) =>
            guardrails.policies.count({ ...options, organizationId: org }),
          facets: (options) =>
            guardrails.policies.facets({ ...options, organizationId: org }),
          get: (id) => guardrails.policies.getPolicy(id),
        },
        rows: 5,
        sorts: ["agent", "updatedAt"],
        facets: {
          stage: { input: 3, output: 2 },
          enabled: { true: 4, false: 1 },
        },
        arrayFilter: { column: "agent", values: ["alpha", "beta"] },
        search: "alp",
      });

      // The SQL transport sends a JS array as a Postgres array, not jsonb, so
      // the log is seeded through the function with a jsonb cast.
      await s.service();

      for (const [agent, decision] of [
        ["alpha", "block"],
        ["alpine", "allow"],
        ["beta", "block"],
        ["gamma", "allow"],
        ["alpha2", "allow"],
      ] as const) {
        await s.value(
          "better_supabase.record_guardrail_decision($1, 'input', $2, '[]'::jsonb, $3)",
          [agent, decision, org],
        );
      }

      await spreadTimes(s, "guardrail_decisions", ["created_at"]);

      await testBlockList({
        name: "ai-guardrails.decisions",
        target: {
          page: (options) =>
            guardrails.decisions.page({ ...options, organizationId: org }),
          count: (options) =>
            guardrails.decisions.count({ ...options, organizationId: org }),
          facets: (options) =>
            guardrails.decisions.facets({ ...options, organizationId: org }),
        },
        rows: 5,
        sorts: ["createdAt", "agent"],
        facets: { decision: { block: 2, allow: 3 }, stage: { input: 5 } },
        arrayFilter: { column: "agent", values: ["alpha", "beta"] },
        search: "alp",
        idOf: (entry) => entry.id,
      });

      const names = [
        "alpha-set",
        "alpine-set",
        "beta-set",
        "beta-two",
        "gamma",
      ];

      const datasetIds: string[] = [];

      for (const name of names) {
        const dataset = await evals.datasets
          .create({ name, organizationId: org })
          .orThrow();

        datasetIds.push(dataset.id);
      }

      await spreadTimes(s, "eval_datasets", ["created_at"]);

      await testBlockList({
        name: "ai-evals.datasets",
        target: {
          page: (options) =>
            evals.datasets.page({ ...options, organizationId: org }),
          count: (options) =>
            evals.datasets.count({ ...options, organizationId: org }),
          facets: (options) =>
            evals.datasets.facets({ ...options, organizationId: org }),
          get: (id) => evals.datasets.getDataset(id),
        },
        rows: 5,
        sorts: ["name", "createdAt"],
        arrayFilter: {
          column: "id",
          values: [datasetIds[0] ?? "", datasetIds[1] ?? ""],
        },
        search: "alp",
      });

      const models = ["m-one", "m-one", "m-two", "m-two", "m-two"];

      for (const [index, model] of models.entries()) {
        await s.value(
          "better_supabase.create_eval_run($1, $2, 1, $3, '[]'::jsonb)",
          [
            datasetIds[index % 2] ?? "",
            index < 2 ? "greet" : "farewell",
            model,
          ],
        );
      }

      await spreadTimes(s, "eval_runs", ["created_at"]);

      await testBlockList({
        name: "ai-evals.runs",
        target: {
          page: (options) =>
            evals.runs.page({ ...options, organizationId: org }),
          count: (options) =>
            evals.runs.count({ ...options, organizationId: org }),
          facets: (options) =>
            evals.runs.facets({ ...options, organizationId: org }),
          get: (id) => evals.runs.getRun(id),
        },
        rows: 5,
        sorts: ["createdAt"],
        facets: {
          model: { "m-one": 2, "m-two": 3 },
          promptName: { greet: 2, farewell: 3 },
          status: { running: 5 },
        },
        arrayFilter: { column: "model", values: ["m-one", "m-two"] },
        search: "greet",
      });
    } finally {
      await s.close();
    }
  });
});
