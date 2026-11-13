import { describe, expect, it } from "vitest";

import type { BlockSqlLayout } from "../../../src/sql/module-types.ts";

import { renderBlocks } from "../../../src/sql/render.ts";

const BLOCKS = [
  "memberships",
  "permissions",
  "field-encryption",
  "custom-fields",
];

function schemaOf(layout: BlockSqlLayout = {}): string {
  return renderBlocks(BLOCKS, layout)
    .filter((file) => file.module === "field-encryption")
    .map((file) => file.contents)
    .join("\n");
}

const rotation = (sql: string): string =>
  sql.slice(sql.indexOf("rotate_field_key"));

describe("field-encryption module", () => {
  it("re-encrypts the custom field values custom-fields contributes", () => {
    const sql = rotation(schemaOf());

    expect(sql).toContain(
      `lock table "better_supabase"."field_values" in exclusive mode;`,
    );
    expect(sql).toContain(
      `where 'tenant:' || (x."tenant_id")::text = rotate_field_key.owner`,
    );
    expect(sql).toContain("perform vault.update_secret(v_secret, v_new);");
  });

  it("re-encrypts app table columns and the sealed columns the options list", () => {
    const sql = schemaOf({
      appTables: {
        charts: { columns: { diagnosis: { type: "text", encrypted: true } } },
        diaries: {
          scope: "user",
          columns: { entry: { type: "text", encrypted: true } },
        },
      },
      modules: {
        "field-encryption": {
          options: {
            sealed: [
              {
                table: "public.legacy_notes",
                columns: ["body"],
                owner: "tenant",
                column: "org_id",
              },
            ],
          },
        },
      },
    });

    expect(rotation(sql)).toContain(
      `lock table "public"."charts", "public"."diaries", "public"."legacy_notes", "better_supabase"."field_values" in exclusive mode;`,
    );
    expect(sql).toContain(
      `where 'user:' || (x."user_id")::text = rotate_field_key.owner and (left(x."entry", 5) = 'bsf1:')`,
    );
    expect(sql).toContain(
      `where 'tenant:' || (x."org_id")::text = rotate_field_key.owner and (left(x."body", 5) = 'bsf1:')`,
    );
    expect(sql).toContain(
      `'[{"table":"charts","column":"diagnosis"},{"table":"legacy_notes","column":"body"}]'::jsonb`,
    );
    expect(sql).toContain(`'[{"table":"diaries","column":"entry"}]'::jsonb`);
  });

  it("lets a member rotate only with field_encryption.manage, and reads no key material", () => {
    const sql = schemaOf();

    expect(sql).toContain("'field_encryption.manage'");
    expect(sql).toContain(
      `grant execute on function "better_supabase"."rotate_field_key"(text) to authenticated, service_role;`,
    );
    expect(
      sql.slice(sql.indexOf("field_key_status"), sql.indexOf("drop_field_key")),
    ).not.toContain("decrypted_secret");
  });

  it("refuses a sealed entry that names no schema, columns or owner", () => {
    const render = (sealed: unknown) => () =>
      schemaOf({ modules: { "field-encryption": { options: { sealed } } } });

    expect(
      render([{ table: "notes", columns: ["a"], owner: "tenant" }]),
    ).toThrow(/sealed\[0\]\.table must be schema\.table/u);
    expect(
      render([{ table: "public.notes", columns: [], owner: "tenant" }]),
    ).toThrow(/columns must list at least one column/u);
    expect(
      render([{ table: "public.notes", columns: ["a"], owner: "team" }]),
    ).toThrow(/owner must be tenant, user or app/u);
    expect(
      render([{ table: "public.notes", columns: ["A b"], owner: "app" }]),
    ).toThrow(/columns\[0\] must be a lowercase SQL name/u);
  });
});
