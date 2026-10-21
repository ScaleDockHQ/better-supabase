import { describe, expect, expectTypeOf, it } from "vitest";

import type { GeneratorInput } from "../../src/config/index.ts";
import type { InsertOf } from "../fixtures/generated-camel.ts";

import { checkBounds, factories } from "../../src/generators/factories.ts";
import { defineFactory, factoryPath } from "../../src/testing/factory.ts";
import { factories as fixture } from "../fixtures/generated-camel.factories.ts";

const ORG = "11111111-1111-4111-8111-111111111111";

describe("factories generator", () => {
  it("fills required columns with defaults that pass the checks", () => {
    const first = fixture.organizations();
    const second = fixture.organizations({ name: "Acme" });
    expect(first).toEqual({ name: "name-1", slug: "slug-1" });
    expect(second).toEqual({ name: "Acme", slug: "slug-2" });
    expect(fixture.contacts({ organizationId: ORG }).email).toMatch(
      /^user\d+@example\.com$/,
    );
  });

  it("takes a parent row or its id for a foreign key", () => {
    const customer = { id: "c1", organizationId: ORG, name: "Acme" };
    const note = fixture.notes({ organizationId: ORG, customerId: customer });
    expect(note).toMatchObject({ organizationId: ORG, customerId: "c1" });
    expect(note.body).toMatch(/^body-\d+$/);
    expect(
      fixture.planFeatures({ planKey: { key: "pro", name: "Pro" } }).planKey,
    ).toBe("pro");
  });

  it("requires foreign keys without a default and types the rows", () => {
    // @ts-expect-error organizationId has no default
    fixture.tags();
    expectTypeOf(fixture.tags({ organizationId: ORG })).toEqualTypeOf<
      InsertOf<"tags">
    >();
    expect(fixture.plans.many(2).map((plan) => plan.key)).toHaveLength(2);
  });

  it("creates the row through a repository", () => {
    const created: unknown[] = [];

    const result = fixture.organizations.create(
      {
        create(data: InsertOf<"organizations">) {
          created.push(data);

          return "ok" as const;
        },
      },
      { slug: "acme" },
    );

    expect(result).toBe("ok");
    expect(created).toEqual([{ name: expect.any(String), slug: "acme" }]);
  });

  it("reads numeric and length bounds from check constraints", () => {
    expect(
      checkBounds("priority", [
        "CHECK (((priority >= 1) AND (priority <= 5)))",
      ]),
    ).toEqual({ min: 1, max: 5 });
    expect(checkBounds("amount", ["CHECK ((0 < amount))"])).toEqual({ min: 1 });
    expect(
      checkBounds("title", [
        "CHECK (((char_length(title) >= 3) AND (char_length(title) <= 200)))",
      ]),
    ).toEqual({ minLength: 3, maxLength: 200 });
    expect(checkBounds("score", ["CHECK (score BETWEEN 0 AND 10)"])).toEqual({
      min: 0,
      max: 10,
    });
    expect(checkBounds("total", ["CHECK ((subtotal >= 0))"])).toEqual({});
  });

  it("names block entities, bounds numbers and refuses unknown tables", () => {
    const column = (
      app: string,
      tsType: string,
      extra: { optional?: boolean } = {},
    ) => ({
      app,
      db: app,
      tsType,
      nullable: false,
      optional: extra.optional ?? false,
      readonly: false,
      values: undefined,
      json: false,
    });

    const input = {
      config: { output: "/app/src/db.ts" },
      importPath: () => "./db.ts",
      introspection: {
        tables: [{ schema: "app", name: "work_items" }],
        columns: [],
        relationships: [],
      },
      extras: {
        tables: [
          {
            schema: "app",
            name: "work_items",
            checks: [
              {
                name: "p",
                definition: "CHECK ((priority >= 1 AND priority <= 3))",
              },
            ],
          },
        ],
      },
      model: {
        tables: [
          {
            key: "tasks",
            schema: "app",
            name: "work_items",
            casing: "camel",
            columns: [
              column("priority", "number"),
              column("logo", 'StoragePath<"logos">'),
              column("meta", "{ a: 1 }"),
              column("notes", "string", { optional: true }),
            ],
          },
        ],
        enums: [],
        functions: [],
        blocks: [
          {
            name: "work-items",
            schema: "app",
            client: undefined,
            entities: [
              {
                key: "work_item",
                from: { singular: "work_item", plural: "work_items" },
                to: { singular: "task", plural: "tasks" },
                primary: true,
                table: "work_items",
                url: undefined,
                schemas: {},
              },
            ],
          },
        ],
      },
    } as unknown as GeneratorInput;

    const [file] = factories().generate(input) as Awaited<
      ReturnType<ReturnType<typeof factories>["generate"]>
    >;

    expect(file?.path).toBe("/app/src/db.factories.ts");
    expect(file?.contents).toContain('"priority": 1 + ((n - 1) % 3)');
    expect(file?.contents).toContain(
      `factoryPath("logos", \`logo/\${String(n)}\`)`,
    );
    expect(file?.contents).toContain('InsertOf<"tasks">, never, "meta">');
    expect(file?.contents).not.toContain('"notes":');
    expect(file?.contents).toContain("  task: tasksFactory,");
    expect(file?.contents).toContain(
      'import { defineFactory, factoryPath } from "better-supabase/testing";',
    );
    expect(() => factories({ tables: ["nope"] }).generate(input)).toThrow(
      'factories(): no table named "nope"',
    );
  });

  it("defines a factory by hand with typed references", () => {
    const tasks = defineFactory<
      { title: string; projectId: string; logo?: string },
      "projectId",
      "projectId"
    >(
      (n) => ({ title: `t${String(n)}`, logo: factoryPath("logos", "a.png") }),
      { projectId: "id" },
    );

    expect(tasks({ projectId: { id: "p1" } })).toEqual({
      title: "t1",
      logo: "a.png",
      projectId: "p1",
    });
  });
});
