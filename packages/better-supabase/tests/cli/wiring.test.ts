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
});
