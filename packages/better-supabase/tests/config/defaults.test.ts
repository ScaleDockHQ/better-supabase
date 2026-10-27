import { describe, expect, it } from "vitest";

import { CONFIG_DEFAULTS } from "../../src/config/defaults.ts";
import { GEN_TASKS, INTEGRATION_NAMES } from "../../src/config/names.ts";
import { resolveConfig } from "../../src/config/resolve.ts";
import { tenantNames } from "../../src/core/entity-naming.ts";
import { registeredSubjects } from "../../src/sql/subject-registry.ts";

describe("CONFIG_DEFAULTS", () => {
  const resolved = resolveConfig({}, "/app");

  it("is what an empty config resolves to", () => {
    expect(resolved.output).toBe(CONFIG_DEFAULTS.output);
    expect(resolved.schemas).toEqual(CONFIG_DEFAULTS.schemas);
    expect(resolved.casing).toBe(CONFIG_DEFAULTS.casing);
    expect(resolved.postgrestVersion).toBe(CONFIG_DEFAULTS.postgrestVersion);
    expect(resolved.codecs).toEqual(CONFIG_DEFAULTS.codecs);
    expect(resolved.sql).toMatchObject(CONFIG_DEFAULTS.sql);
    expect(resolved.seed).toEqual(CONFIG_DEFAULTS.seed);
    expect(resolved.openapi).toEqual(CONFIG_DEFAULTS.openapi);
    expect(resolved.specs.failOn).toBe(CONFIG_DEFAULTS.specs.failOn);
    expect(resolved.doctor).toMatchObject(CONFIG_DEFAULTS.doctor);
    expect(resolved.env.output).toBe(CONFIG_DEFAULTS.env.output);
  });

  it("resolves the watch interval", () => {
    expect(resolved.gen.watchInterval).toBe(CONFIG_DEFAULTS.gen.watchInterval);
    expect(
      resolveConfig({ gen: { watchInterval: 500 } }, "/app").gen.watchInterval,
    ).toBe(500);
  });

  it("names the organization column after the tenant's name", () => {
    expect(
      resolveConfig({ blocks: ["memberships"] }, "/app").extensions.tenant,
    ).toEqual({ column: "organization_id" });
    expect(
      resolveConfig(
        { blocks: { memberships: { names: { organization: "workspace" } } } },
        "/app",
      ).extensions.tenant,
    ).toEqual({ column: "workspace_id" });
    expect(resolveConfig({}, "/app").extensions.tenant).toBeUndefined();
    expect(
      resolveConfig(
        { auth: { tenant: { column: "org_id", onMissing: "error" } } },
        "/app",
      ).extensions.tenant,
    ).toEqual({ column: "org_id", onMissing: "error" });
  });

  it("turns each block's extension on with the block, with its columns", () => {
    expect(resolveConfig({}, "/app").extensions).toEqual({
      timestamps: undefined,
      softDelete: undefined,
      tenant: undefined,
      actor: undefined,
    });
    expect(
      resolveConfig(
        {
          blocks: {
            "updated-at": { options: { updatedAt: "changed_at" } },
            "created-by": {},
            trash: { options: { deletedAt: "archived_at" } },
          },
        },
        "/app",
      ).extensions,
    ).toEqual({
      timestamps: { createdAt: "created_at", updatedAt: "changed_at" },
      softDelete: { column: "archived_at" },
      tenant: undefined,
      actor: {
        createdBy: "created_by",
        updatedBy: "updated_by",
        impersonatedBy: "impersonated_by",
      },
    });
  });

  it("names the subjects' tenant column after the tenant's name", () => {
    expect(
      registeredSubjects(
        { deal: { table: "public.deals" } },
        tenantNames("workspace"),
      )[0]?.tenant,
    ).toBe('"workspace_id"');
    expect(
      registeredSubjects({ deal: { table: "public.deals" } })[0]?.tenant,
    ).toBe('"organization_id"');
  });

  it("keeps the name tuples unique", () => {
    expect(new Set(GEN_TASKS).size).toBe(GEN_TASKS.length);
    expect(new Set(INTEGRATION_NAMES).size).toBe(INTEGRATION_NAMES.length);
  });
});
