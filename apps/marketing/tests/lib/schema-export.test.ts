import { describe, expect, test } from "vitest";

import type { SchemaData } from "../../lib/schema";

import { addTable } from "../../lib/design";
import { toDbml, toJson, toMermaid } from "../../lib/schema-export";

const data: Pick<SchemaData, "tables"> = {
  tables: [
    {
      id: "app.orders",
      schema: "app",
      name: "orders",
      module: "shop",
      primaryKey: ["id"],
      foreignKeys: [
        {
          columns: ["user_id"],
          target: { schema: "auth", table: "users", columns: ["id"] },
        },
      ],
      tenantColumn: null,
      columns: [
        {
          name: "id",
          type: "uuid",
          nullable: false,
          default: "gen_random_uuid()",
          unique: false,
        },
        {
          name: "user_id",
          type: "uuid",
          nullable: true,
          default: null,
          unique: false,
        },
        {
          name: "total",
          type: "numeric(12, 2)",
          nullable: false,
          default: "0",
          unique: false,
        },
      ],
    },
  ],
};

describe("exports", () => {
  test("Mermaid", () => {
    expect(toMermaid(data)).toBe(`erDiagram
  app_orders {
    uuid id PK
    uuid user_id FK
    numeric_12_2 total
  }
  auth_users ||--o{ app_orders : "user_id"
`);
  });

  test("DBML", () => {
    expect(toDbml(data)).toBe(`Table app.orders {
  id uuid [pk, not null, default: \`gen_random_uuid()\`]
  user_id uuid
  total "numeric(12, 2)" [not null, default: \`0\`]
}

Ref: app.orders.(user_id) > auth.users.(id)
`);
  });

  test("JSON keeps the preset code and the design", () => {
    const design = addTable({}, "projects");

    expect(JSON.parse(toJson("abc", design, data))).toEqual({
      preset: "abc",
      design,
      tables: data.tables,
    });
  });
});
