import { describe, expect, it } from "vitest";

import { probeRestated } from "../../src/cli/restated-probe.ts";
import { resolveConfig } from "../../src/config/index.ts";

const config = (claimFormat: string) =>
  resolveConfig(
    { blocks: { memberships: { options: { claimFormat } }, tags: {} } },
    "/project",
  );

describe("probeRestated", () => {
  it("reports an option equal to its default", async () => {
    const entries = await probeRestated(config("array"));

    expect(entries.map((entry) => entry.path)).toContain(
      "blocks.memberships.options.claimFormat",
    );
  });

  it("keeps an option that changes the render", async () => {
    const entries = await probeRestated(config("map"));

    expect(entries.map((entry) => entry.path)).not.toContain(
      "blocks.memberships.options.claimFormat",
    );
  });
});
