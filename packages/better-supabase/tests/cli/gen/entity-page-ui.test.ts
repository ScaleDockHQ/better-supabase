import { describe, expect, it } from "vitest";

import {
  entityPageColumns,
  entityFormFields,
  humanize,
} from "../../../src/cli/gen/entity-page-ui.ts";
import {
  emitEntityPages,
  resolveEntityPage,
} from "../../../src/cli/gen/entity-pages.ts";
import { resolveConfig } from "../../../src/config/resolve.ts";
import { defineEntityPage } from "../../../src/list/entity-page.ts";

const risks = defineEntityPage({
  entity: "risks.risk",
  route: "/risks/",
  columns: ["number", "title", "status", "residualScore", "nextReviewOn"],
  sections: ["overview", "audit-log"],
});

const config = (pages = [risks]) =>
  resolveConfig(
    {
      blocks: { memberships: {}, permissions: {}, risks: {} },
      gen: { entityPages: { pages } },
    },
    "/project",
  );

const emit = (pages = [risks]) =>
  new Map(
    emitEntityPages(config(pages), "better-supabase").map((file) => [
      file.path,
      file.contents,
    ]),
  );

describe("humanize", () => {
  it("spaces camelCase and kebab-case names", () => {
    expect(humanize("nextReviewOn")).toBe("Next review on");
    expect(humanize("audit-log")).toBe("Audit log");
    expect(humanize("review_interval")).toBe("Review interval");
  });
});

describe("entityPageColumns", () => {
  const columns = entityPageColumns(resolveEntityPage(config(), risks));

  it("keeps the order and names the database column", () => {
    expect(columns.map((column) => column.key)).toStrictEqual([
      "number",
      "title",
      "status",
      "residualScore",
      "nextReviewOn",
    ]);

    expect(columns[4]).toMatchObject({
      column: "next_review_on",
      label: "Next review on",
      kind: "date",
      sort: "nextReviewOn",
    });
  });

  it("links a column to the sort and facet that are declared", () => {
    expect(columns[2]).toMatchObject({ filter: "status" });
    expect(columns[2]?.sort).toBeUndefined();
    expect(columns[3]).toMatchObject({ sort: "residualScore" });
    expect(columns[1]?.filter).toBeUndefined();
  });

  it("reads the kind from the input schema when it lists the column", () => {
    expect(columns[1]?.kind).toBe("text");
  });

  it("names the columns of the table when one is unknown", () => {
    expect(() =>
      entityPageColumns(
        resolveEntityPage(
          config(),
          defineEntityPage({
            entity: "risks.risk",
            route: "/risks",
            columns: ["nope"],
          }),
        ),
      ),
    ).toThrow(/column "nope" is not a column of risks/);
  });
});

describe("entityFormFields", () => {
  it("keeps what the action validates and drops json and read-only fields", () => {
    const fields = entityFormFields({
      title: "Input",
      fields: {
        title: { kind: "string", minLength: 1, maxLength: 30 },
        level: { kind: "integer", minimum: 1, maximum: 5, optional: true },
        state: { kind: "enum", values: ["open", "closed"] },
        extra: { kind: "json", optional: true },
        stamp: { kind: "datetime", readOnly: true },
        note: { kind: "string", nullable: true, description: "Why." },
      },
    });

    expect(fields.map((field) => field.name)).toStrictEqual([
      "title",
      "level",
      "state",
      "note",
    ]);

    expect(fields[0]).toMatchObject({ minLength: 1, maxLength: 30 });
    expect(fields[1]).toMatchObject({ kind: "number", optional: true });
    expect(fields[2]).toMatchObject({ values: ["open", "closed"] });
    expect(fields[3]).toMatchObject({ nullable: true, description: "Why." });
  });
});

describe("field kinds", () => {
  const kinds = entityFormFields({
    title: "Input",
    fields: {
      a: { kind: "bigint" },
      b: { kind: "boolean" },
      c: { kind: "plainDate" },
      d: { kind: "instant" },
      e: { kind: "custom" },
      f: { kind: "unknown" },
      g: { kind: "uuid" },
      h: { kind: "number" },
    },
  }).map((field) => [field.name, field.kind]);

  it("maps each schema kind to a form kind", () => {
    expect(kinds).toStrictEqual([
      ["a", "number"],
      ["b", "boolean"],
      ["c", "date"],
      ["d", "datetime"],
      ["f", "text"],
      ["g", "uuid"],
      ["h", "number"],
    ]);
  });

  it("guesses the kind of a column the schema does not list", () => {
    const columns = entityPageColumns(
      resolveEntityPage(
        config(),
        defineEntityPage({
          entity: "risks.risk",
          route: "/risks",
          columns: ["id", "createdAt", "reviewedAt", "currentAssessment"],
        }),
      ),
    ).map((column) => column.kind);

    expect(columns).toStrictEqual(["uuid", "datetime", "datetime", "text"]);
  });
});

describe("the columns, detail and forms outputs", () => {
  const files = emit();

  it("writes the three modules beside the list", () => {
    expect([...files.keys()].toSorted()).toStrictEqual([
      "app/api/risks/list/route.ts",
      "src/lib/supabase/pages/risks.columns.ts",
      "src/lib/supabase/pages/risks.detail.ts",
      "src/lib/supabase/pages/risks.form.ts",
      "src/lib/supabase/pages/risks.list.ts",
      "supabase/schemas/entity_page_indexes.sql",
      "supabase/tests/scale/scale_list_risks.test.sql",
    ]);
  });

  it("writes the columns as typed data", () => {
    const text = files.get("src/lib/supabase/pages/risks.columns.ts");

    expect(text).toContain(
      'import type { EntityColumn } from "better-supabase/list";',
    );
    expect(text).toContain("export const risksColumns = [");
    expect(text).toContain(
      '{ key: "nextReviewOn", column: "next_review_on", label: "Next review on", kind: "date", sort: "nextReviewOn" },',
    );
    expect(text).toContain("] as const satisfies readonly EntityColumn[];");
  });

  it("writes the detail frame with its sections and href", () => {
    const text = files.get("src/lib/supabase/pages/risks.detail.ts");

    expect(text).toContain('route: "/risks/:id",');
    expect(text).toContain('{ id: "audit-log", label: "Audit log" },');
    expect(text).toContain(["href: (id) => `/risks/$", "{id}`,"].join(""));
  });

  it("writes the forms of the schemas the block exports", () => {
    const text = files.get("src/lib/supabase/pages/risks.form.ts");

    expect(text).toContain(
      'import { defineEntityForm } from "better-supabase/list";',
    );
    expect(text).toContain("export const risksCreateForm = defineEntityForm({");
    // The risks block exports an input schema and no change schema.
    expect(text).not.toContain("risksEditForm");
    expect(text).toContain('name: "title"');
    expect(text).not.toContain('name: "fields"');
  });

  it("skips columns and detail without the descriptor fields", () => {
    const plain = emit([
      defineEntityPage({ entity: "risks.risk", route: "/r" }),
    ]);

    expect(plain.has("src/lib/supabase/pages/r.columns.ts")).toBe(false);
    expect(plain.has("src/lib/supabase/pages/r.detail.ts")).toBe(false);
    expect(plain.has("src/lib/supabase/pages/r.form.ts")).toBe(true);
  });

  it("refuses a section name that is not kebab-case or is repeated", () => {
    expect(() =>
      emit([
        defineEntityPage({
          entity: "risks.risk",
          route: "/r",
          sections: ["Audit Log"],
        }),
      ]),
    ).toThrow(/section "Audit Log"/);

    expect(() =>
      emit([
        defineEntityPage({
          entity: "risks.risk",
          route: "/r",
          sections: ["a", "a"],
        }),
      ]),
    ).toThrow(/listed twice/);
  });
});
