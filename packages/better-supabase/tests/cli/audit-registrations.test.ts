import { describe, expect, it } from "vitest";

import { auditRegistrationsOf } from "../helpers/facts.ts";

const file = (text: string) => ({ text });

describe("auditRegistrations", () => {
  it("reads named and positional lists, quoted names and arrays", async () => {
    expect(
      await auditRegistrationsOf([
        file(`
select better_supabase.audit('public.customers', ignore => '{updated_at}', redact => '{kvk}');
select better_supabase.audit('notes', '{updated_at,"Body"}'::text[]);
select better_supabase.audit('crm."Deals"', redact := array['secret']::text[], category => 'sales');
`),
      ]),
    ).toEqual([
      { target: "crm.Deals", ignore: [], redact: ["secret"] },
      { target: "public.customers", ignore: ["updated_at"], redact: ["kvk"] },
      { target: "public.notes", ignore: ["updated_at", "Body"], redact: [] },
    ]);
  });

  it("reads a deferrable constraint trigger as a registration", async () => {
    expect(
      await auditRegistrationsOf([
        file(
          `create constraint trigger bsb_audit after insert or update or delete on better_supabase.tasks deferrable initially deferred for each row execute function better_supabase.audit_row_change('{"ignore":["updated_at"],"redact":[]}');`,
        ),
      ]),
    ).toEqual([
      { target: "better_supabase.tasks", ignore: ["updated_at"], redact: [] },
    ]);
  });

  it("lets a later call replace an earlier one and unaudit remove it", async () => {
    expect(
      await auditRegistrationsOf([
        file(
          "select better_supabase.audit('public.a');\nselect better_supabase.audit('public.b');",
        ),
        file(
          "select better_supabase.audit('public.a', ignore => '{x}');\nselect better_supabase.unaudit('public.b');",
        ),
      ]),
    ).toEqual([{ target: "public.a", ignore: ["x"], redact: [] }]);
  });

  it("treats a later drop table like unaudit and keeps a table audited again", async () => {
    expect(
      await auditRegistrationsOf([
        file(`
select better_supabase.audit('public.a');
select better_supabase.audit('public.b');
select better_supabase.audit('crm."Deals"');
select better_supabase.audit('public.c');
`),
        file(`
drop table public.a;
DROP TABLE IF EXISTS b, crm . "Deals" cascade;
drop table public.c;
create table public.c (id int primary key);
select better_supabase.audit('public.c', ignore => '{x}');
`),
      ]),
    ).toEqual([{ target: "public.c", ignore: ["x"], redact: [] }]);
  });

  it("moves a registration to the new name of a renamed table", async () => {
    expect(
      await auditRegistrationsOf([
        file(`
select better_supabase.audit('public.template_workflows', ignore => '{updated_at}');
select better_supabase.audit('crm."Old Deals"', redact => '{secret}');
select better_supabase.audit('public.kept');
`),
        file(`
alter table public.template_workflows rename to template_automations;
ALTER TABLE IF EXISTS ONLY crm."Old Deals" RENAME TO "Deals";
alter table public.kept rename column a to b;
alter table public.unaudited rename to other;
`),
      ]),
    ).toEqual([
      { target: "crm.Deals", ignore: [], redact: ["secret"] },
      { target: "public.kept", ignore: [], redact: [] },
      {
        target: "public.template_automations",
        ignore: ["updated_at"],
        redact: [],
      },
    ]);
  });

  it("skips comments, the module's own definitions and non-literal arguments", async () => {
    expect(
      await auditRegistrationsOf([
        file(`
-- select better_supabase.audit('public.commented');
/* select better_supabase.audit('public.block'); */
create or replace function better_supabase.audit(target regclass, ignore text[] default '{}')
returns void language sql as $$ select 1 $$;
revoke execute on function better_supabase.unaudit(regclass) from public;
select better_supabase.audit(format('%I.%I', 'public', 't'));
select better_supabase.audit('public.dynamic', ignore => columns_of('x'));
`),
      ]),
    ).toEqual([]);
  });
});

describe("auditRegistrations of static triggers", () => {
  it("reads a bsb_audit trigger with a when clause", async () => {
    expect(
      await auditRegistrationsOf([
        {
          text: `create trigger bsb_audit after insert or update or delete on public.invoices
  for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore": ["updated_at"], "redact": []}');`,
        },
      ]),
    ).toEqual([
      { target: "public.invoices", ignore: ["updated_at"], redact: [] },
    ]);
  });

  it("reads bsb_audit triggers that pass their settings to audit_row_change", async () => {
    expect(
      await auditRegistrationsOf([
        {
          text: `create trigger bsb_audit after insert or update or delete on public.invoices
  for each row execute function better_supabase.audit_row_change('{"ignore": ["updated_at"], "redact": ["iban"], "event_prefix": "invoice"}');
create trigger bsb_audit after insert or update or delete on "Billing"."Plans"
  for each row execute function better_supabase.audit_row_change();
create trigger other after insert on public.skipped
  for each row execute function better_supabase.audit_row_change();
create trigger bsb_audit after insert on public.broken
  for each row execute function better_supabase.audit_row_change('not json');`,
        },
        { text: "select better_supabase.unaudit('Billing.\"Plans\"');" },
        {
          text: "select better_supabase.audit('public.invoices', ignore => '{seen_at}');",
        },
      ]),
    ).toEqual([
      { target: "Billing.Plans", ignore: [], redact: [] },
      { target: "public.invoices", ignore: ["seen_at"], redact: [] },
    ]);
  });
});
