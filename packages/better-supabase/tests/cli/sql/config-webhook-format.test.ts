import { describe, expect, it } from "vitest";

import { pinWebhookFormat } from "../../../src/cli/sql/config-webhook-format.ts";

const ts = (block: string): string =>
  `export default defineConfig({\n  blocks: { "webhooks-out": ${block} },\n});\n`;

describe("pinWebhookFormat", () => {
  it("pins an adopted JSON block and skips the rest", () => {
    const adopted = JSON.stringify({
      blocks: { "webhooks-out": { mode: "adopt" } },
    });

    const pinned = pinWebhookFormat(adopted, true, "standard");

    expect(pinned?.ok).toBe(true);
    expect(pinned?.ok && JSON.parse(pinned.text)).toMatchObject({
      blocks: { "webhooks-out": { options: { defaultFormat: "standard" } } },
    });

    for (const block of [
      { mode: "install" },
      { mode: "adopt", options: { defaultFormat: "cloudevents" } },
      { mode: "adopt", columns: { endpoints: { format: "format" } } },
      "webhooks-out",
    ]) {
      const source = JSON.stringify({ blocks: { "webhooks-out": block } });

      expect(pinWebhookFormat(source, true, "standard")).toBeUndefined();
    }

    expect(pinWebhookFormat("[]", true, "standard")).toBeUndefined();
    expect(pinWebhookFormat("{", true, "standard")).toEqual({
      ok: false,
      reason: "it isn't valid JSON",
    });
  });

  it("pins an adopted block in a TypeScript config", () => {
    const pinned = pinWebhookFormat(
      ts(`{ mode: 'adopt', columns: { endpoints: { url: "target" } } }`),
      false,
      "cloudevents",
    );

    expect(pinned?.ok && pinned.text).toContain('defaultFormat: "cloudevents"');
  });

  it("skips TypeScript configs that already choose a format or don't adopt", () => {
    for (const source of [
      "export const config = {};\n",
      "export default defineConfig({ blocks: {} });\n",
      ts(`{ mode: "install" }`),
      ts(`{ options: {} }`),
      ts(`{ mode: "adopt", options: { defaultFormat: "standard" } }`),
      ts(`{ mode: "adopt", columns: { endpoints: { format: "kind" } } }`),
    ]) {
      expect(pinWebhookFormat(source, false, "standard")).toBeUndefined();
    }
  });

  it("refuses TypeScript blocks it can't read as literals", () => {
    const reason = (block: string): string | undefined => {
      const result = pinWebhookFormat(ts(block), false, "standard");

      return result && !result.ok ? result.reason : undefined;
    };

    expect(reason("webhooksOut")).toContain("isn't a literal object");
    expect(reason(`{ mode: "adopt", options: shared }`)).toContain(
      "options or columns aren't literal objects",
    );
    expect(reason(`{ mode: "adopt", columns: shared }`)).toContain(
      "options or columns aren't literal objects",
    );
    expect(
      reason(`{ mode: "adopt", columns: { endpoints: shared } }`),
    ).toContain("columns.endpoints isn't a literal object");
  });
});
