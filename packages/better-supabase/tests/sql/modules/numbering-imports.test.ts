import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);
  perform set_config('request.jwt.claim.sub', '', true);`;

const BOOT = { timeout: 90_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(
    ["invoices", "numbering", "legal-entities", "imports"],
    {
      modules: {
        numbering: {
          options: {
            entities: {
              invoice: { period: "year", format: "{yy}{n:6}" },
              credit_note: { period: "year", format: "CN{yy}{n:4}" },
            },
          },
        },
        queue: { options: { backend: "table" } },
        "legal-entities": { options: { on: ["invoices", "numbering"] } },
      },
    },
  );

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
      ...files
        .filter((file) => file.kind !== "data")
        .map((file) => file.contents),
    ],
    seed: [
      ...files
        .filter((file) => file.kind === "data")
        .map((file) => file.contents),
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

const draft = (title: string, entity = "null"): string =>
  `(select x.id from (select (better_supabase.create_invoice('${TENANT}', '{"title": "${title}", "currency": "EUR"}'::jsonb,
    '[{"description": "Work", "quantity": 1, "unitAmount": "10000"}]'::jsonb) ->> 'id')::uuid as id) x
    where (select better_supabase.__set_entity(x.id, ${entity})) is not null)`;

describe("numbering for imports", BOOT, () => {
  it("keeps fixed numbers per series and continues above them", async () => {
    await expect(
      run(`create function better_supabase.__set_entity(p_id uuid, p_entity uuid) returns boolean
language sql as $$
  update better_supabase.invoices set legal_entity_id = p_entity where id = p_id returning true;
$$;
do $$
declare
  v_be uuid;
  v_run uuid;
  v_id uuid;
  v_note uuid;
  v_text text;
begin
  ${SERVICE}
  perform better_supabase.create_legal_entity('${TENANT}', 'DE01', 'Acme GmbH');
  v_be := (better_supabase.create_legal_entity('${TENANT}', 'BE01', 'Acme NV') ->> 'id')::uuid;

  v_id := ${draft("Old 1")};
  begin
    perform better_supabase.issue_invoice(v_id, date '2023-05-01', null, null, '23000365');
    raise exception 'a fixed number outside an import was accepted';
  exception when others then
    if sqlerrm not like '%only accepted during an import%' then
      raise;
    end if;
  end;

  v_run := (better_supabase.start_import_run('${TENANT}', 'numbering', '{}'::jsonb) ->> 'id')::uuid;
  perform better_supabase.mark_import_running(v_run);
  perform better_supabase.begin_import_session(v_run);

  v_text := better_supabase.issue_invoice(v_id, date '2023-05-01', null, null, '23000365') ->> 'identifier';
  if v_text <> '23000365' then
    raise exception 'fixed identifier %', v_text;
  end if;

  v_id := ${draft("Old BE", "v_be")};
  perform better_supabase.issue_invoice(v_id, date '2023-05-02', null, null, '23000100');

  v_note := (better_supabase.credit_invoice(v_id, null, 'Imported', 'CN230077', date '2023-06-01') ->> 'id')::uuid;
  if (select identifier from better_supabase.invoices where id = v_note) <> 'CN230077' then
    raise exception 'fixed credit note %', (select identifier from better_supabase.invoices where id = v_note);
  end if;

  perform set_config('better_supabase.import_run', '', true);

  v_id := ${draft("New default")};
  v_text := better_supabase.issue_invoice(v_id, date '2023-07-01') ->> 'identifier';
  if v_text <> '23000366' then
    raise exception 'default entity continued with %', v_text;
  end if;

  v_id := ${draft("New BE", "v_be")};
  v_text := better_supabase.issue_invoice(v_id, date '2023-07-02') ->> 'identifier';
  if v_text <> '23000101' then
    raise exception 'second entity continued with %', v_text;
  end if;

  v_id := ${draft("New year")};
  v_text := better_supabase.issue_invoice(v_id, date '2024-01-02') ->> 'identifier';
  if v_text <> '24000001' then
    raise exception 'a new period started with %', v_text;
  end if;

  v_note := (better_supabase.credit_invoice((select id from better_supabase.invoices where identifier = '23000366'), null, 'Credit') ->> 'id')::uuid;
  v_text := better_supabase.issue_invoice(v_note, date '2023-08-01') ->> 'identifier';
  if v_text <> 'CN230001' then
    raise exception 'the credit note series (default entity) started with %', v_text;
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("syncs the counters back and reports numbers outside the format", async () => {
    await expect(
      run(`create function better_supabase.__set_entity(p_id uuid, p_entity uuid) returns boolean
language sql as $$
  update better_supabase.invoices set legal_entity_id = p_entity where id = p_id returning true;
$$;
do $$
declare
  v_be uuid;
  v_run uuid;
  v_id uuid;
  v_report jsonb;
begin
  ${SERVICE}
  perform better_supabase.create_legal_entity('${TENANT}', 'DE01', 'Acme GmbH');
  v_be := (better_supabase.create_legal_entity('${TENANT}', 'BE01', 'Acme NV') ->> 'id')::uuid;
  v_run := (better_supabase.start_import_run('${TENANT}', 'numbering', '{}'::jsonb) ->> 'id')::uuid;
  perform better_supabase.mark_import_running(v_run);
  perform better_supabase.begin_import_session(v_run);

  v_id := ${draft("A")};
  perform better_supabase.issue_invoice(v_id, date '2023-05-01', null, null, '23000365');
  v_id := ${draft("B", "v_be")};
  perform better_supabase.issue_invoice(v_id, date '2023-05-02', null, null, '23000100');
  v_id := ${draft("C")};
  perform better_supabase.issue_invoice(v_id, date '2023-05-03', null, null, 'LEGACY-7');

  delete from better_supabase.number_sequences;
  v_report := better_supabase.sync_number_sequences('${TENANT}', 'invoice');
  if (v_report ->> 'synced')::int <> 2 then
    raise exception 'synced %', v_report;
  end if;
  if (select last_number from better_supabase.number_sequences where entity = 'invoice' and scope = '' and period = '2023') <> 365 then
    raise exception 'the default entity counter %', (select jsonb_agg(s) from better_supabase.number_sequences s);
  end if;
  if (select last_number from better_supabase.number_sequences where entity = 'invoice' and scope = v_be::text and period = '2023') <> 100 then
    raise exception 'the second entity counter %', (select jsonb_agg(s) from better_supabase.number_sequences s);
  end if;
  if jsonb_array_length(v_report -> 'mismatched') <> 1 or v_report -> 'mismatched' -> 0 ->> 'number' <> 'LEGACY-7' then
    raise exception 'mismatched %', v_report;
  end if;
  if not exists (select 1 from better_supabase.import_runs r where r.id = v_run and r.errors::text like '%LEGACY-7%') then
    raise exception 'the run holds no warning: %', (select errors from better_supabase.import_runs where id = v_run);
  end if;
  if (select identifier from better_supabase.invoices where title = 'C') <> 'LEGACY-7' then
    raise exception 'the number was changed';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});
