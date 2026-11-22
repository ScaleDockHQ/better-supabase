import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

const sqlOf = (modules: Record<string, unknown>): string =>
  renderBlocks(["data-lifecycle"], { modules: modules as never })
    .map((file) => file.contents)
    .join("\n");

describe("data-lifecycle tenant row", () => {
  it("deletes the configured tenant row last", () => {
    expect(
      sqlOf({ "data-lifecycle": { options: { tenantRow: "app.tenants.id" } } }),
    ).toContain(
      'delete from "app"."tenants" where "id" = purge_organization.tenant;',
    );
  });

  it("deletes no tenant row when tenantRow is false", () => {
    expect(
      sqlOf({ "data-lifecycle": { options: { tenantRow: false } } }),
    ).not.toMatch(/delete from \S+ where "id" = purge_organization\.tenant;/u);
  });

  it("rejects a tenantRow that is not a column reference", () => {
    expect(() =>
      sqlOf({ "data-lifecycle": { options: { tenantRow: 3 } } }),
    ).toThrow(
      'blocks.data-lifecycle.options.tenantRow must be "schema.table.column" or false',
    );
  });

  it("disables tenants through a permissions.disabled.tenant column", () => {
    expect(
      sqlOf({
        "data-lifecycle": {},
        permissions: { disabled: { tenant: "app.tenants.disabled_at" } },
      }),
    ).toContain(
      'update "app"."tenants" set "disabled_at" = coalesce("disabled_at", now()) where "id" = request_organization_deletion.tenant;',
    );
  });

  it("disables tenants through a permissions.disabled.tenant table", () => {
    expect(
      sqlOf({
        "data-lifecycle": {},
        permissions: {
          disabled: {
            tenant: { table: "app.tenants", id: "tid", disabledAt: "off_at" },
          },
        },
      }),
    ).toContain(
      'update "app"."tenants" set "off_at" = coalesce("off_at", now()) where "tid" = request_organization_deletion.tenant;',
    );
  });

  it("needs disabledAt or a status on a disabled tenant table", () => {
    expect(() =>
      sqlOf({
        "data-lifecycle": {},
        permissions: {
          disabled: { tenant: { table: "app.tenants", id: "tid" } },
        },
      }),
    ).toThrow(
      "blocks.permissions.disabled.tenant needs disabledAt, status or both",
    );
  });
});
