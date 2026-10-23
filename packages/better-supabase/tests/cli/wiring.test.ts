import { describe, expect, it } from "vitest";

import type { TemplateContext } from "../../src/cli/templates.ts";

import {
  addProviderStubs,
  envExampleText,
  providersSource,
  wiringChecklist,
  wiringFiles,
  wiringFor,
} from "../../src/cli/wiring.ts";

const CONTEXT: TemplateContext = {
  srcDir: "src",
  generated: "src/lib/supabase/generated.ts",
  tsExtensions: true,
  frameworks: ["next"],
  version: "0.0.0",
  blocks: true,
};

describe("wiringFor", () => {
  it("merges env keys across blocks and keeps the stricter one", () => {
    const plan = wiringFor([
      { name: "queue", block: "queue" },
      { name: "billing", block: "billing" },
    ]);

    const database = plan.env.find((entry) => entry.key === "DATABASE_URL");
    const cron = plan.env.find((entry) => entry.key === "CRON_SECRET");

    expect(database?.required).not.toBe(false);
    expect(database?.blocks).toEqual(["queue", "billing"]);
    expect(cron?.blocks).toEqual(["queue", "billing"]);
    expect(plan.workers.map((worker) => worker.name)).toEqual([
      "queue-drain",
      "stripe-process",
    ]);
  });

  it("keys providers by instance, through a renamed instance", () => {
    const plan = wiringFor([{ name: "leads", block: "enrichment" }]);

    expect(
      plan.providers.map((entry) => [entry.instance, entry.provider.option]),
    ).toEqual([["leads", "provider"]]);
  });
});

describe("envExampleText", () => {
  const env = wiringFor([{ name: "billing", block: "billing" }]).env;

  it("appends only the missing keys, under their descriptions", () => {
    const text = envExampleText("STRIPE_SECRET_KEY=\n", env);

    expect(text).toContain("# better-supabase blocks\n");
    expect(text).toContain("\nSTRIPE_WEBHOOK_SECRET=\n");
    expect(text.match(/^STRIPE_SECRET_KEY=/gm)).toHaveLength(1);
    expect(envExampleText(text, env)).toBe(text);
  });
});

describe("providers.ts", () => {
  const plan = wiringFor([
    { name: "enrichment", block: "enrichment" },
    { name: "mail-sync", block: "mail-sync" },
  ]);

  it("writes a commented stub per provider", () => {
    const source = providersSource(CONTEXT, plan.providers.slice(0, 1));

    expect(source).toContain('import { blocks } from "./blocks.generated.ts";');
    expect(source).toContain(
      "  // enrichment: blocks.enrichment.with({ provider: peopleDataLabsEnrichment(",
    );
    expect(source).toContain("} satisfies Partial<typeof blocks>;");

    const edit = addProviderStubs(source, plan.providers);

    expect(edit.ok).toBe(true);
    expect(edit.ok && edit.text).toContain(
      '  // "mail-sync": blocks["mail-sync"].with({ providers: [gmailMail(), outlookMail()] }),',
    );
    expect(edit.ok && addProviderStubs(edit.text, plan.providers)).toEqual({
      ok: true,
      text: edit.ok && edit.text,
    });
  });

  it("refuses a file without the closing marker", () => {
    expect(
      addProviderStubs("export const providers = {};", plan.providers),
    ).toMatchObject({ ok: false });
  });

  it("plans .env.example and providers.ts, and numbers the checklist", async () => {
    const full = wiringFor([
      { name: "outbox", block: "outbox" },
      { name: "enrichment", block: "enrichment" },
    ]);

    const written = await wiringFiles(CONTEXT, full, () =>
      Promise.resolve(undefined),
    );

    expect(written.files.map((file) => file.path)).toEqual([
      ".env.example",
      "src/lib/supabase/providers.ts",
    ]);

    const steps = wiringChecklist(
      CONTEXT,
      full,
      "npx shadcn@latest add @better-supabase/outbox-relay-next",
    );

    expect(steps[0]).toMatch(/^ {2}1\. Set CRON_SECRET in \.env\.local/);
    expect(steps.some((step) => step.includes("/api/outbox"))).toBe(true);
    expect(steps.at(-1)).toContain(
      "enrichment in src/lib/supabase/providers.ts",
    );
  });

  it("edits the existing files, and notes a providers.ts it can't edit", async () => {
    const full = wiringFor([
      { name: "outbox", block: "outbox" },
      { name: "enrichment", block: "enrichment" },
    ]);

    const existing = await wiringFiles(CONTEXT, full, (path) =>
      Promise.resolve(
        path === ".env.example" ? "APP_URL=\n" : providersSource(CONTEXT, []),
      ),
    );

    expect(existing.files.map((file) => [file.path, file.policy])).toEqual([
      [".env.example", "edit"],
      ["src/lib/supabase/providers.ts", "edit"],
    ]);

    const broken = await wiringFiles(CONTEXT, full, (path) =>
      Promise.resolve(
        path === ".env.example"
          ? envExampleText(undefined, full.env)
          : "export const providers = {};",
      ),
    );

    expect(broken.files).toEqual([]);
    expect(broken.notes[0]).toContain(
      "Add the provider stubs to src/lib/supabase/providers.ts by hand",
    );
  });
});

describe("wiringFor edge cases", () => {
  it("finds a block through one of its SQL modules, and skips unknown ones", () => {
    const catalog = {
      manifests: [
        {
          name: "parent",
          sql: ["parent-sql"],
          env: [{ key: "OPTIONAL", description: "Optional.", required: false }],
          workers: [{ name: "sweeper", description: "Sweeps." }],
        },
        {
          name: "other",
          sql: [],
          env: [{ key: "OPTIONAL", description: "Now required." }],
          workers: [{ name: "sweeper", description: "Sweeps again." }],
        },
      ],
    };

    const plan = wiringFor(
      [
        { name: "a", block: "parent-sql" },
        { name: "b", block: "parent" },
        { name: "c", block: "other" },
        { name: "d", block: "missing" },
      ],
      // SAFETY: wiringFor reads only `manifests` and these fields.
      catalog as unknown as Parameters<typeof wiringFor>[1],
    );

    expect(plan.env).toEqual([
      {
        key: "OPTIONAL",
        description: "Now required.",
        blocks: ["parent", "other"],
      },
    ]);
    expect(plan.workers).toEqual([
      { name: "sweeper", description: "Sweeps.", block: "parent" },
    ]);
    expect(wiringChecklist(CONTEXT, plan, undefined)).toEqual([
      "  1. Set OPTIONAL in .env.local and in every deployed environment (.env.example lists them).",
      "  2. Run the sweeper worker (parent): Sweeps.",
    ]);
  });

  it("marks an optional key, and starts a file that has none", () => {
    const env = [
      {
        key: "AI_GATEWAY_API_KEY",
        description: "The gateway key.",
        required: false,
        blocks: ["ai-chat"],
      },
    ];

    expect(envExampleText(undefined, env)).toBe(
      "# better-supabase blocks\n# The gateway key. Optional. (ai-chat)\nAI_GATEWAY_API_KEY=\n",
    );
    expect(envExampleText("A=1", env)).toMatch(/^A=1\n\n# better-supabase/);
    expect(
      wiringChecklist(
        CONTEXT,
        { env, providers: [], workers: [], actions: [], schedules: [] },
        undefined,
      ),
    ).toEqual([]);
  });

  it("schedules a worker from a cron when it has no schedule", () => {
    const steps = wiringChecklist(
      CONTEXT,
      {
        env: [],
        providers: [],
        actions: [],
        schedules: [],
        workers: [
          {
            name: "drain",
            description: "Drains.",
            path: "/api/drain",
            block: "queue",
          },
        ],
      },
      undefined,
    );

    expect(steps).toEqual([
      "  1. Call /api/drain from a cron with `Authorization: Bearer $CRON_SECRET` (queue: Drains.)",
    ]);
  });

  it("names the block timers and the actions to register", () => {
    const plan = wiringFor([
      { name: "sla", block: "sla" },
      { name: "tasks", block: "tasks" },
      { name: "inbox", block: "inbox" },
    ]);

    const steps = wiringChecklist(CONTEXT, plan, undefined);

    expect(steps.join("\n")).toContain("sla check() at `* * * * *`");
    expect(steps.join("\n")).toContain("blockTickHandler");
    expect(steps.join("\n")).toContain(
      "createActionRegistry`: tasks.from_conversation (tasks)",
    );
  });
});
