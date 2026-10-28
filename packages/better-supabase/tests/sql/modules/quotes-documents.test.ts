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

// PGlite has no pgcrypto; the quote link needs random bytes and a sha256.
const PGCRYPTO = `
create schema if not exists extensions;
create or replace function extensions.gen_random_bytes(n integer) returns bytea
language sql volatile as $$
  select decode(substr(repeat(md5(random()::text), 8), 1, n * 2), 'hex')
$$;
create or replace function extensions.digest(data text, kind text) returns bytea
language sql immutable as $$
  select sha256(convert_to(data, 'UTF8'))
$$;
`;

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(check: string, modules = ["quotes"]): Promise<void> {
  const files = renderBlocks(modules);

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
      PGCRYPTO,
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

// Two rates with prices that include tax, a fixed document discount and an
// optional line the customer takes on acceptance.
const MIXED = `
  v_quote := better_supabase.create_quote('${TENANT}',
    '{"title": "Fit-out", "currency": "EUR", "pricesIncludeTax": true, "discountAmount": "1000", "depositBps": 3000}'::jsonb,
    '[{"section": "Work", "description": "Install", "unitAmount": "12100", "taxRateBps": 2100},
      {"section": "Work", "description": "Books", "quantity": 2, "unitAmount": "5450", "taxRateBps": 900},
      {"section": "Extras", "description": "Support", "unitAmount": "10000", "taxRateBps": 2100, "optional": true}]'::jsonb);
  v_id := (v_quote ->> 'id')::uuid;`;

describe("quote documents", BOOT, () => {
  it("spreads a document discount over the rates of prices that include tax", async () => {
    await expect(
      run(`do $$
declare
  v_quote jsonb;
  v_id uuid;
begin
  ${SERVICE}
  ${MIXED}
  if (v_quote ->> 'list_total', v_quote ->> 'discount_total', v_quote ->> 'subtotal', v_quote ->> 'tax_total', v_quote ->> 'total', v_quote ->> 'deposit_due')
    is distinct from ('23000', '1000', '19130', '2870', '22000', '6600') then
    raise exception 'totals %', v_quote;
  end if;
  if (select jsonb_agg(jsonb_build_array(x ->> 'taxRateBps', x ->> 'net', x ->> 'tax', x ->> 'gross', x ->> 'discount')) from jsonb_array_elements(v_quote -> 'taxLines') x)
    <> '[["900", "9565", "861", "10426", "474"], ["2100", "9565", "2009", "11574", "526"]]'::jsonb then
    raise exception 'tax lines %', v_quote -> 'taxLines';
  end if;
  if (v_quote -> 'lines' -> 2 ->> 'section') <> 'Extras' or (v_quote -> 'lines' -> 2 ->> 'selected')::boolean then
    raise exception 'optional line %', v_quote -> 'lines' -> 2;
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("takes a share of an untaxed total off before tax", async () => {
    await expect(
      run(`do $$
declare
  v_quote jsonb;
begin
  ${SERVICE}
  v_quote := better_supabase.create_quote('${TENANT}', '{"title": "Plan", "currency": "EUR", "discountBps": 1000}'::jsonb,
    '[{"description": "Plan", "unitAmount": "10000", "taxRateBps": 2100}]'::jsonb);
  if (v_quote ->> 'subtotal', v_quote ->> 'tax_total', v_quote ->> 'total') is distinct from ('9000', '1890', '10890') then
    raise exception 'totals %', v_quote;
  end if;
  v_quote := better_supabase.update_quote((v_quote ->> 'id')::uuid, '{"discountBps": 0}'::jsonb);
  if v_quote ->> 'total' <> '12100' then
    raise exception 'update did not recount %', v_quote;
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("publishes a version per send and keeps an accepted quote as accepted", async () => {
    await expect(
      run(`do $$
declare
  v_quote jsonb;
  v_sent jsonb;
  v_answer jsonb;
  v_id uuid;
begin
  ${SERVICE}
  ${MIXED}
  v_sent := better_supabase.send_quote(v_id);
  begin
    perform better_supabase.update_quote(v_id, '{"title": "Changed"}'::jsonb);
    raise exception 'changed a sent quote';
  exception when others then
    if sqlerrm not like '%can change%' then
      raise;
    end if;
  end;
  if (better_supabase.quote_version(v_id, 1) ->> 'total') <> '22000' then
    raise exception 'version %', better_supabase.quote_version(v_id, 1);
  end if;
  perform set_config('request.headers', '{"x-forwarded-for": "203.0.113.9, 10.0.0.1", "user-agent": "Browser/1"}', true);
  v_answer := better_supabase.respond_to_quote(v_sent ->> 'token', 'accepted', 'Els Jansen', null, '[3]'::jsonb);
  if v_answer ->> 'status' <> 'accepted' or (v_answer ->> 'revision')::int <> 1 then
    raise exception 'answer %', v_answer;
  end if;
  if (select (total, tax_total, decided_by, decided_ip, decided_user_agent) from better_supabase.quotes where id = v_id)
    is distinct from (32000::bigint, 4593::bigint, 'Els Jansen'::text, '10.0.0.1'::text, 'Browser/1'::text) then
    raise exception 'accepted %', (select to_jsonb(x) from better_supabase.quotes x where id = v_id);
  end if;
  if (select snapshot ->> 'total' from better_supabase.quote_versions where quote_id = v_id) <> '22000' then
    raise exception 'the published version changed';
  end if;
  begin
    perform better_supabase.revise_quote(v_id);
    raise exception 'revised an accepted quote';
  exception when others then
    if sqlerrm not like '%stays as accepted%' then
      raise;
    end if;
  end;
  begin
    update better_supabase.quote_versions set total = 0 where quote_id = v_id;
    raise exception 'changed a version';
  exception when others then
    if sqlerrm not like '%never changes%' then
      raise;
    end if;
  end;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("refuses a selection that names a line that isn't optional", async () => {
    await expect(
      run(`do $$
declare
  v_quote jsonb;
  v_id uuid;
begin
  ${SERVICE}
  ${MIXED}
  perform better_supabase.send_quote(v_id);
  perform better_supabase.decide_quote(v_id, 'accepted', null, 'Ann', '[1]'::jsonb);
end;
$$;`),
    ).rejects.toThrow(/pick optional lines/u);
  });

  it("revises the same quote and sends the next revision after changes", async () => {
    await expect(
      run(`do $$
declare
  v_quote jsonb;
  v_id uuid;
begin
  ${SERVICE}
  ${MIXED}
  perform better_supabase.send_quote(v_id);
  perform better_supabase.decide_quote(v_id, 'changes_requested', 'cheaper', 'Ann');
  perform better_supabase.update_quote(v_id, '{"discountAmount": "2000"}'::jsonb);
  v_quote := better_supabase.send_quote(v_id);
  if (v_quote ->> 'revision')::int <> 2 or v_quote ->> 'decided_by' is not null then
    raise exception 'resent %', v_quote;
  end if;
  v_quote := better_supabase.revise_quote(v_id);
  if (v_quote ->> 'id')::uuid <> v_id or (v_quote ->> 'revision')::int <> 3 or v_quote ->> 'status' <> 'draft' then
    raise exception 'revised %', v_quote;
  end if;
  if jsonb_array_length(better_supabase.quote_versions(v_id)) <> 2 then
    raise exception 'versions %', better_supabase.quote_versions(v_id);
  end if;
  if better_supabase.portal_quote(v_id) is not null then
    raise exception 'a quote reached the portal without guests';
  end if;
exception when others then
  if sqlerrm not like '%shared with you%' then
    raise;
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("invoices exactly the totals the customer accepted", async () => {
    await expect(
      run(
        `do $$
declare
  v_quote jsonb;
  v_invoice jsonb;
  v_id uuid;
begin
  ${SERVICE}
  ${MIXED}
  perform better_supabase.send_quote(v_id);
  perform better_supabase.decide_quote(v_id, 'accepted', null, 'Ann', '[3]'::jsonb);
  v_invoice := better_supabase.invoice_from_quote(v_id, null);
  if (v_invoice ->> 'total', v_invoice ->> 'tax_total', (v_invoice ->> 'prices_include_tax')::boolean)
    is distinct from ('32000', '4593', true) then
    raise exception 'invoice %', v_invoice;
  end if;
  v_invoice := better_supabase.invoice_from_quote(v_id, 3000);
  if v_invoice ->> 'total' <> '9600' then
    raise exception 'deposit %', v_invoice;
  end if;
end;
$$;`,
        ["quotes", "invoices"],
      ),
    ).resolves.toBeUndefined();
  });
});
