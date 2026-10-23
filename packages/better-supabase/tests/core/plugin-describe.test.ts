import { describe, expect, it } from "vitest";

import { membershipsExtension } from "../../src/blocks/memberships/index.ts";
import { trashExtension } from "../../src/blocks/trash/index.ts";
import { updatedAtExtension } from "../../src/blocks/updated-at/index.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { definePlugin } from "../../src/core/plugin.ts";
import { defineApi } from "../../src/spec/api.ts";
import { schema } from "../fixtures/generated-camel.ts";

const info = { title: "CRM", version: "1.0.0" };
const base = defineSupabase(schema);

const property = (
  schemas: Readonly<Record<string, unknown>>,
  name: string,
  column: string,
): Record<string, unknown> | undefined =>
  (schemas[name] as { properties?: Record<string, Record<string, unknown>> })
    .properties?.[column];

describe("Plugin.describe", () => {
  it("timestamps marks the managed columns read-only", () => {
    const { model } = defineApi(base.use(updatedAtExtension()), {
      info,
      resources: { notes: true },
    });

    expect(property(model.schemas, "NotesRow", "createdAt")).toMatchObject({
      readOnly: true,
      description: "Set by the server when the row is created.",
    });
    expect(property(model.schemas, "NotesUpdate", "updatedAt")).toMatchObject({
      readOnly: true,
    });
  });

  it("softDelete documents the hidden column", () => {
    const { model } = defineApi(base.use(trashExtension()), {
      info,
      resources: { customers: true, notes: true },
    });

    expect(property(model.schemas, "CustomersRow", "archivedAt")).toMatchObject(
      {
        readOnly: true,
        description: expect.stringContaining("Deleted rows are not returned"),
      },
    );
    expect(
      model.operations.some((operation) =>
        operation.parameters.some(
          (parameter) => parameter.name === "withDeleted",
        ),
      ),
    ).toBe(false);
  });

  it("tenant marks the tenant column and documents its header", () => {
    const { model } = defineApi(
      base.use(
        membershipsExtension({ header: "x-tenant", onMissing: "error" }),
      ),
      {
        info,
        resources: { notes: { operations: ["list", "get"] }, tags: true },
      },
    );

    expect(
      property(model.schemas, "NotesInsert", "organizationId"),
    ).toMatchObject({
      readOnly: true,
      description: "Set from the request's tenant.",
    });
    expect(
      (model.schemas["NotesInsert"] as { required?: string[] }).required ?? [],
    ).not.toContain("organizationId");

    const list = model.operations.find(
      (operation) => operation.id === "listNotes",
    );

    expect(list?.parameters).toContainEqual({
      name: "x-tenant",
      in: "header",
      required: true,
      description: "The tenant the request acts for.",
      schema: { type: "string" },
    });

    const optional = defineApi(
      base.use(membershipsExtension({ header: "x-tenant", onMissing: "skip" })),
      { info, resources: { notes: { operations: ["get"] } } },
    );

    expect(optional.model.operations[0]?.parameters).toContainEqual(
      expect.objectContaining({ name: "x-tenant", required: false }),
    );

    const noHeader = defineApi(base.use(membershipsExtension()), {
      info,
      resources: { notes: { operations: ["get"] } },
    });

    expect(noHeader.model.operations[0]?.parameters).toHaveLength(1);
  });

  it("lets plugins add parameters to named operations and describe columns", () => {
    const plugin = definePlugin({
      name: "docs",
      describe(api) {
        expect(api.extensionPrefix).toBe("x-better-supabase-");
        expect(api.schema).toBe(base.meta);
        expect(
          api.resources.map((resource) => [
            resource.table.key,
            resource.operations,
          ]),
        ).toEqual([["notes", ["list", "get"]]]);

        const parameter = {
          name: "trace",
          in: "header",
          schema: { type: "string" },
        } as const;

        api.addParameter("notes", parameter, ["get"]);
        api.addParameter("notes", parameter, ["get"]);
        api.addParameter("unknown", parameter);
        api.describeColumn("notes", "body", { maxLength: 10_000 });
        api.describeColumn("notes", "missing", { maxLength: 1 });
        api.markReadOnly("unknown", "id");
      },
    });

    const { model, diagnostics } = defineApi(base.use(plugin), {
      info,
      resources: { notes: { operations: ["list", "get"], verbs: false } },
    });

    expect(diagnostics).toEqual([]);
    const [list, get] = model.operations;
    expect(list?.parameters.map((parameter) => parameter.name)).not.toContain(
      "trace",
    );
    expect(
      get?.parameters.filter((parameter) => parameter.name === "trace"),
    ).toHaveLength(1);
    expect(property(model.schemas, "NotesRow", "body")).toMatchObject({
      maxLength: 10_000,
    });
  });

  it("reports a describe hook that throws", () => {
    const plugin = definePlugin({
      name: "broken",
      describe() {
        throw new Error("boom");
      },
    });

    const { diagnostics } = defineApi(base.use(plugin), { info });
    expect(diagnostics).toEqual([
      expect.objectContaining({
        code: "plugin-describe-failed",
        severity: "warning",
        message: expect.stringContaining("boom"),
      }),
    ]);
  });
});
