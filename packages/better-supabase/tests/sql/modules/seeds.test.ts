import { describe, expect, it } from "vitest";

import { moduleBody, renderBlocks } from "../../../src/sql/render.ts";

describe("seeds module", () => {
  it("calls the defaults of every installed block that declares rows", () => {
    const sql = renderBlocks(["organizations", "leave"], {
      seedDefaults: {
        enabled: true,
        onCreate: true,
        locale: "en",
        variants: {},
      },
    })
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain("seed_tenant_defaults");
    expect(sql).toMatch(/perform .*seed_leave_defaults/u);
  });

  it("bakes the configured locale and variants into the defaults", () => {
    const sql = moduleBody("seeds", {
      modules: { pipelines: {} },
      seedDefaults: {
        enabled: true,
        onCreate: true,
        locale: "nl",
        variants: { pipelines: "b2b-sales" },
      },
    });

    expect(sql).toContain(`p_locale text default 'nl'`);
    expect(sql).toContain("b2b-sales");
  });

  it("is called from create_organization unless onCreate is off", () => {
    const on = moduleBody("organizations", {
      seedDefaults: {
        enabled: true,
        onCreate: true,
        locale: "en",
        variants: {},
      },
    });

    const off = moduleBody("organizations", {
      seedDefaults: {
        enabled: true,
        onCreate: false,
        locale: "en",
        variants: {},
      },
    });

    expect(on).toContain("seed_tenant_defaults");
    expect(off).not.toContain("seed_tenant_defaults");
  });
});
