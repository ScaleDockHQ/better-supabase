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
