import { describe, expect, it } from "vitest";

import { auditStatementEdits } from "../../src/cli/codemod-audit-statement.ts";

const customers = `
create table public.customers (
  id uuid primary key,
  name text,
  updated_at timestamptz,
  api_key text
);

create trigger bsb_audit
  after insert or update or delete on public.customers
  for each row
  when (better_supabase.import_run() is null)
  execute function better_supabase.audit_row_change('{"ignore": ["updated_at"], "redact": ["api_key"], "key_columns": ["id"]}');
`;

describe("codemod audit-statement", () => {
  it("rewrites a row trigger into the three statement triggers", async () => {
    const edited = await auditStatementEdits(
      [{ path: "supabase/schemas/customers.sql", text: customers }],
      ["public.customers"],
    );

    expect(edited.review).toEqual([]);
    expect(edited.files).toHaveLength(1);
    expect(edited.files[0]?.contents).toContain(
      "create trigger bsb_audit_stmt_insert after insert on public.customers referencing new table as new_rows",
    );
    expect(edited.files[0]?.contents).toContain(
      "create trigger bsb_audit_stmt_update after update on public.customers referencing old table as old_rows new table as new_rows",
    );
    expect(edited.files[0]?.contents).toContain(
      "create trigger bsb_audit_stmt_delete after delete on public.customers referencing old table as old_rows",
    );
    expect(edited.files[0]?.contents).toContain('"ignore":["updated_at"]');
    expect(edited.files[0]?.contents).toContain('"redact":["api_key"]');
    expect(edited.files[0]?.contents).not.toContain("audit_row_change");
  });

  it("rewrites an audit() call and keeps its settings", async () => {
    const edited = await auditStatementEdits(
      [
        {
          path: "supabase/schemas/orders.sql",
          text: `create table public.orders (id uuid primary key);\nselect better_supabase.audit('public.orders', ignore => '{seen_at}', redact => '{token}');\n`,
        },
      ],
      ["public.orders"],
    );

    expect(edited.review).toEqual([]);
    expect(edited.files[0]?.contents).toContain("bsb_audit_stmt_insert");
    expect(edited.files[0]?.contents).toContain('"ignore":["seen_at"]');
    expect(edited.files[0]?.contents).toContain('"key_columns":["id"]');
    expect(edited.files[0]?.contents).not.toContain("better_supabase.audit(");
  });

  it("refuses a deferred trigger, a missing key and an unknown table", async () => {
    const edited = await auditStatementEdits(
      [
        {
          path: "supabase/schemas/notes.sql",
          text: `create table public.notes (id uuid primary key);\ncreate constraint trigger bsb_audit after insert or update or delete on public.notes deferrable initially deferred for each row execute function better_supabase.audit_row_change('{"ignore":[],"redact":[]}');\ncreate table public.loose (id uuid);\ncreate trigger bsb_audit after insert on public.loose for each row execute function better_supabase.audit_row_change('{"ignore":[],"redact":[]}');\n`,
        },
      ],
      ["public.notes", "public.loose", "public.missing"],
    );

    expect(edited.files).toEqual([]);
    expect(edited.review.map((line) => line.message)).toEqual([
      "public.notes audits with a deferred trigger, and statement mode does not combine with deferred.",
      "public.loose has no primary key in the schema files, and statement mode needs one.",
      "public.missing has no bsb_audit trigger and no better_supabase.audit() call in the schema files.",
    ]);
  });
});
