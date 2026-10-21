import { describe, expect, it } from "vitest";

import type { GeneratorInput } from "../../src/config/index.ts";

import { nuqs } from "../../src/generators/nuqs.ts";
import {
  customersSearchParams,
  loadCustomersSearchParams,
  serializeCustomersSearchParams,
} from "../fixtures/generated-camel.nuqs.ts";

describe("nuqs generator", () => {
  it("parses filters, order and paging from a URL", () => {
    expect(
      loadCustomersSearchParams(
        "https://app.test/customers?status=active&orderBy=name&direction=desc&cursor=c1",
      ),
    ).toEqual({
      status: "active",
      orderBy: "name",
      direction: "desc",
      cursor: "c1",
      limit: 25,
    });
  });

  it("drops values outside a column's closed set", () => {
    const params = loadCustomersSearchParams(
      "https://app.test/customers?status=deleted&orderBy=nope",
    );

    expect(params.status).toBeNull();
    expect(params.orderBy).toBeNull();
  });

  it("serializes links and leaves defaults out", () => {
    expect(
      serializeCustomersSearchParams("/customers", {
        status: "lead",
        limit: 25,
      }),
    ).toBe("/customers?status=lead");
    expect(Object.keys(customersSearchParams)).toEqual([
      "status",
      "orderBy",
      "direction",
      "cursor",
      "limit",
    ]);
  });

  it("writes only the tables it names and refuses unknown ones", () => {
    const input = {
      config: { output: "/app/src/db.ts" },
      model: {
        tables: [
          {
            key: "tasks",
            schema: "app",
            name: "tasks",
            casing: "camel",
            columns: [
              {
                app: "status",
                db: "status",
                tsType: '"open" | "done"',
                nullable: false,
                optional: false,
                readonly: false,
                values: ["open", "done"],
                json: false,
              },
              {
                app: "meta",
                db: "meta",
                tsType: "Json",
                nullable: true,
                optional: true,
                readonly: false,
                values: undefined,
                json: true,
              },
            ],
          },
          {
            key: "notes",
            schema: "app",
            name: "notes",
            casing: "camel",
            columns: [],
          },
        ],
        enums: [],
        functions: [],
        blocks: [],
      },
    };

    // SAFETY: nuqs() reads only `config.output` and `model.tables`.
    const fake = input as unknown as GeneratorInput;

    const [file] = nuqs({ tables: ["tasks"], limit: 50 }).generate(fake) as [
      { path: string; contents: string },
    ];

    expect(file.path).toBe("/app/src/db.nuqs.ts");
    expect(file.contents).toContain(
      'orderBy: parseAsStringLiteral(["status"] as const)',
    );
    expect(file.contents).toContain("limit: parseAsInteger.withDefault(50)");
    expect(file.contents).not.toContain("notes");
    expect(() => nuqs({ tables: ["missing"] }).generate(fake)).toThrow(
      /no table named "missing"/,
    );
  });
});
