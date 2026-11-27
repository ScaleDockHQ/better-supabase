import { describe, expect, it } from "vitest";

import {
  auditStatementEdits,
  auditTableName,
} from "../../src/cli/codemod-audit-statement.ts";

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

  it("leaves a trigger whose settings are not an object or not JSON", async () => {
    const edited = await auditStatementEdits(
      [
        {
          path: "supabase/schemas/widgets.sql",
          text: `create table public.widgets (id uuid primary key);\ncreate trigger bsb_audit after insert on public.widgets for each row execute function better_supabase.audit_row_change('[]');\ncreate table public.gadgets (id uuid primary key);\ncreate trigger bsb_audit after insert on public.gadgets for each row execute function better_supabase.audit_row_change('{');\n`,
        },
      ],
      ["public.widgets", "public.gadgets"],
    );

    expect(edited.files).toEqual([]);
    expect(edited.review.map((line) => line.message)).toEqual([
      "public.widgets was left on row triggers: its settings are not an object.",
      "public.gadgets was left on row triggers: its settings are not JSON.",
    ]);
  });

  it("leaves tenant_path, a non-literal ignore list and a quoted name", async () => {
    const edited = await auditStatementEdits(
      [
        {
          path: "supabase/schemas/accounts.sql",
          text: `create table public.accounts (id uuid primary key);\nselect better_supabase.audit('public.accounts', tenant_path => 'org_id');\ncreate table public.tokens (id uuid primary key);\nselect better_supabase.audit('public.tokens', ignore => array['seen']);\ncreate table "Public"."Customers" (id uuid primary key);\nselect better_supabase.audit('"Public"."Customers"', category => 'billing', event_prefix => 'cust');\n`,
        },
      ],
      ["public.accounts", "public.tokens", '"Public"."Customers"'],
    );

    expect(auditTableName('"Public"."Customers"')).toBe("Public.Customers");
    expect(auditTableName("Customers")).toBe("public.customers");
    expect(edited.review.map((line) => line.message)).toEqual([
      "public.accounts audits with tenant_path or tenant_function, and statement mode does not combine with either.",
      "public.tokens was left on row triggers: its ignore argument is not a '{...}' literal.",
      "Public.Customers has no primary key in the schema files, and statement mode needs one.",
    ]);
    expect(edited.files).toEqual([]);
  });

  it("keeps key columns already stored on the trigger and drops a duplicate audit() call", async () => {
    const edited = await auditStatementEdits(
      [
        {
          path: "supabase/migrations/old.sql",
          text: "select better_supabase.audit('public.kept');\n",
        },
        {
          path: "supabase/schemas/kept.sql",
          text: `create table public.kept (id uuid primary key);\ncreate trigger bsb_audit after insert or update or delete on public.kept for each row execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"key_columns":["id"]}');\nselect better_supabase.audit('public.kept');\ncreate trigger bsb_audit_update after update on public.kept for each row execute function better_supabase.audit_row_change('{"ignore":["seen"],"redact":[]}');\n`,
        },
      ],
      ["public.kept"],
    );

    expect(edited.review).toEqual([]);
    expect(edited.files).toHaveLength(1);
    expect(edited.files[0]?.path).toBe("supabase/schemas/kept.sql");
    expect(edited.files[0]?.contents).toContain('"key_columns":["id"]');
    expect(edited.files[0]?.contents).not.toContain("better_supabase.audit(");
    expect(edited.files[0]?.contents).not.toContain("bsb_audit_update");
  });
});
