import { describe, expect, it } from "vitest";

import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";

import { WIRING_RULES } from "../../../src/cli/doctor/wiring.ts";

const rule = (code: string) =>
  WIRING_RULES.find((candidate) => candidate.code === code)!;

const context = (
  instances: Record<string, string>,
  parts: Partial<DoctorContext> = {},
): DoctorContext =>
  // SAFETY: BS504 and BS505 read only config.instances, envFiles, sources and shellEnv.
  ({
    config: {
      instances: Object.fromEntries(
        Object.entries(instances).map(([name, block]) => [name, { block }]),
      ),
      blocks: {},
    },
    envFiles: [],
    sources: [],
    ...parts,
  }) as unknown as DoctorContext;

describe("BS504", () => {
  it("names each required key no env file lists", async () => {
    const findings = await rule("BS504").check(
      context(
        { billing: "billing" },
        {
          envFiles: [
            {
              path: ".env.example",
              text: "STRIPE_SECRET_KEY=\n# CRON_SECRET=",
            },
          ],
        },
      ),
    );

    expect(findings.map((finding) => finding.target)).toEqual([
      "STRIPE_WEBHOOK_SECRET",
      "CRON_SECRET",
      "DATABASE_URL",
    ]);
  });

  it("names every block that reads a missing key", async () => {
    const findings = await rule("BS504").check(
      context({ outbox: "outbox", queue: "queue" }),
    );

    expect(findings[0]?.message).toMatch(/^outbox, queue read CRON_SECRET /);
  });

  it("accepts a key the shell sets and skips optional keys", async () => {
    const findings = await rule("BS504").check(
      context(
        { outbox: "outbox", "ai-chat": "ai-chat" },
        { shellEnv: { CRON_SECRET: "set" } },
      ),
    );

    expect(findings).toEqual([]);
  });
});

describe("BS505", () => {
  it("fails while a required provider is only a comment", async () => {
    const findings = await rule("BS505").check(
      context(
        { enrichment: "enrichment", shipments: "shipments" },
        {
          sources: [
            {
              path: "src/lib/supabase/providers.ts",
              text: "export const providers = {\n  // enrichment: blocks.enrichment.with({ provider: x }),\n};",
            },
          ],
        },
      ),
    );

    expect(findings.map((finding) => finding.target)).toEqual([
      "enrichment.provider",
    ]);
  });

  it("passes once a source passes the instance its provider", async () => {
    const findings = await rule("BS505").check(
      context(
        { "mail-sync": "mail-sync", leads: "enrichment" },
        {
          sources: [
            {
              path: "src/lib/supabase/providers.ts",
              text: [
                '  "mail-sync": blocks["mail-sync"].with({',
                "  leads: blocks.leads.using((options) => createEnrichment(options)),",
              ].join("\n"),
            },
          ],
        },
      ),
    );

    expect(findings).toEqual([]);
  });
});

describe("BS507", () => {
  it("reports shipped actions until a source builds a registry", async () => {
    const missing = await rule("BS507").check(
      context({ tasks: "tasks" }, { sources: [] }),
    );

    expect(missing.map((finding) => finding.target)).toEqual(["actions"]);

    const registered = await rule("BS507").check(
      context(
        { tasks: "tasks" },
        {
          sources: [
            {
              path: "route.ts",
              text: "createActionRegistry([...blockActions(blocks, { clients })]);",
            },
          ],
        },
      ),
    );

    expect(registered).toEqual([]);
  });
});

describe("BS508", () => {
  it("reports timers until a source drains the tick queue", async () => {
    const missing = await rule("BS508").check(
      context({ cases: "cases" }, { sources: [] }),
    );

    expect(missing.length).toBeGreaterThan(0);

    const handled = await rule("BS508").check(
      context(
        { cases: "cases" },
        { sources: [{ path: "route.ts", text: "blockTickHandler(blocks);" }] },
      ),
    );

    expect(handled).toEqual([]);
  });
});

describe("BS510", () => {
  const definition = `create or replace view better_supabase.maintenance_jobs as select 1;
create or replace function better_supabase.maintenance_schedule(cron_schedule text default '*/5 * * * *') returns text as $$
begin execute pg_catalog.format('select cron.schedule(%L, %L, %L)', 'a', cron_schedule, 'select better_supabase.maintenance()'); end; $$;
revoke all on function better_supabase.maintenance_schedule(text) from public;`;

  const sql = (...texts: string[]) =>
    texts.map((text, index) => ({ path: `f${String(index)}.sql`, text }));

  it("stays quiet without the housekeeping module or without sql files", async () => {
    expect(await rule("BS510").check(context({}))).toEqual([]);
    expect(
      await rule("BS510").check(
        context({}, { sqlFiles: sql("create table t (id int);") }),
      ),
    ).toEqual([]);
  });

  it("reports the module when nothing schedules maintenance()", async () => {
    const findings = await rule("BS510").check(
      context({}, { sqlFiles: sql(definition) }),
    );

    expect(findings).toHaveLength(1);
  });

  it("accepts a schedule call, a cron line or a tick handler", async () => {
    for (const parts of [
      {
        sqlFiles: sql(
          definition,
          "select better_supabase.maintenance_schedule();",
        ),
      },
      {
        sqlFiles: sql(
          definition,
          "select cron.schedule('m', '* * * * *', 'select better_supabase.maintenance()');",
        ),
      },
      {
        sqlFiles: sql(definition),
        sources: [
          { path: "route.ts", text: "maintenanceTick(rpcTransport(a))" },
        ],
      },
    ]) {
      expect(await rule("BS510").check(context({}, parts))).toEqual([]);
    }
  });
});

describe("BS511", () => {
  const run = (text: string) =>
    rule("BS511").check(
      context({}, { sources: [{ path: "src/a.tsx", text }] }),
    );

  it("flags a client component that imports the server wiring", async () => {
    expect(
      await run(
        '"use client";\nimport { blocks } from "@/lib/supabase/blocks.generated";',
      ),
    ).toHaveLength(1);
    expect(
      await run(
        '"use client";\nimport { defineBlocks } from "x";\ndefineBlocks(a, b);',
      ),
    ).toHaveLength(1);
  });

  it("accepts blocks.config and server files", async () => {
    expect(
      await run(
        '"use client";\nimport { blockConfig } from "@/lib/supabase/blocks.config";',
      ),
    ).toHaveLength(0);
    expect(
      await run('import { blocks } from "@/lib/supabase/blocks.generated";'),
    ).toHaveLength(0);
  });
});

describe("BS512", () => {
  const vercel = (json: unknown): Partial<DoctorContext> => ({
    vercelConfig: { path: "vercel.json", text: JSON.stringify(json) },
  });

  const targets = async (parts: Partial<DoctorContext>): Promise<string[]> =>
    (await rule("BS512").check(context({}, parts))).map(
      (finding) => finding.target ?? "",
    );

  it("flags crons, a path in both, and a function without its trigger", async () => {
    expect(
      await targets(
        vercel({
          crons: [
            { path: "/api/drain", schedule: "* * * * *" },
            { path: "/api/old", schedule: "0 * * * *" },
          ],
          schedules: {
            drain: { schedule: "* * * * *", path: "/api/drain" },
            tick: { schedule: "* * * * *", function: "app/api/tick/route.ts" },
          },
          functions: { "app/api/tick/route.ts": { maxDuration: 60 } },
        }),
      ),
    ).toEqual(["crons:/api/drain", "crons:/api/old", "schedules:tick"]);
  });

  it("accepts schedules with their triggers, and a file that is not JSON", async () => {
    expect(
      await targets(
        vercel({
          schedules: {
            drain: { schedule: "* * * * *", path: "/api/drain" },
            tick: { schedule: "* * * * *", function: "app/api/tick/route.ts" },
          },
          functions: {
            "app/api/tick/route.ts": {
              experimentalTriggers: [{ type: "schedule/v1beta" }],
            },
          },
        }),
      ),
    ).toEqual([]);
    expect(
      await targets({ vercelConfig: { path: "vercel.json", text: "{" } }),
    ).toEqual([]);
  });

  it("checks pg_net and the Vault secrets while httpTick is on", async () => {
    const config = (httpTick: boolean): Partial<DoctorContext> =>
      // SAFETY: BS512 reads only config.blocks.queue.options.
      ({
        config: { instances: {}, blocks: { queue: { options: { httpTick } } } },
      }) as unknown as Partial<DoctorContext>;

    expect(await targets(config(false))).toEqual([]);
    expect(await targets(config(true))).toEqual([
      "blocks.queue.options.httpTick:pg_net",
      "blocks.queue.options.httpTick:vault",
    ]);
    expect(
      await targets({
        ...config(true),
        sqlFiles: [
          {
            path: "a.sql",
            text: "create extension if not exists pg_net with schema extensions;",
          },
        ],
        seedFiles: [
          {
            path: "seed.sql",
            text: "select vault.create_secret('http://x/api/drain', 'jobs_tick_url');",
          },
        ],
      }),
    ).toEqual(["blocks.queue.options.httpTick:vault"]);
    expect(
      await targets({
        ...config(true),
        sqlFiles: [
          {
            path: "a.sql",
            text: "create extension if not exists pg_net with schema extensions;",
          },
        ],
        seedFiles: [
          {
            path: "seed.sql",
            text: "select vault.create_secret('http://x/api/drain', 'jobs_tick_url');\nselect vault.create_secret('token', 'jobs_tick_token');",
          },
        ],
      }),
    ).toEqual([]);
  });
});
