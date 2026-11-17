import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../src/sql/render.ts";
import { liteStack } from "../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const CASH = "22222222-2222-4222-8222-222222222222";
const RENT = "44444444-4444-4444-8444-444444444444";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

const CHECK = `
insert into better_supabase.ledger_accounts (id, tenant_id, kind, code, name, unit, allow_negative)
values ('${CASH}', '${TENANT}', 'asset', 'cash', 'Cash', 'EUR', true),
  ('${RENT}', '${TENANT}', 'revenue', 'rent', 'Rent', 'EUR', true);
do $$
declare
  v_keyed uuid;
  v_plain uuid;
  v_entry text;
begin
  v_keyed := better_supabase.ledger_post('${TENANT}', 'lease.rent',
    jsonb_build_array(jsonb_build_object('account', '${CASH}', 'amount', 100), jsonb_build_object('account', '${RENT}', 'amount', -100)),
    memo => 'Rent from 2026-11-01', memo_key => 'lease.rent', memo_params => jsonb_build_object('periodStart', '2026-11-01'));
  v_plain := better_supabase.ledger_post('${TENANT}', 'test.post',
    jsonb_build_array(jsonb_build_object('account', '${CASH}', 'amount', 5), jsonb_build_object('account', '${RENT}', 'amount', -5)),
    memo => 'by hand');
  if (select row(memo, memo_key, memo_params ->> 'periodStart') from better_supabase.ledger_transactions where id = v_keyed)
    is distinct from row('Rent from 2026-11-01'::text, 'lease.rent'::text, '2026-11-01'::text) then
    raise exception 'ledger_post did not store the memo key and params';
  end if;
  if (select memo_key from better_supabase.ledger_transactions where id = v_plain) is not null then
    raise exception 'a memo without a key got one';
  end if;

  v_entry := better_supabase.audit_event('invoice.sent', summary => 'sent invoice INV-1');
  if (select row(summary, summary_key, summary_params) from better_supabase.audit_events where id = v_entry::bigint)
    is distinct from row('sent invoice INV-1'::text, 'invoice.sent'::text, null::jsonb) then
    raise exception 'audit_event did not default summary_key to the event type';
  end if;
  v_entry := better_supabase.audit_event('invoice.sent', summary => 'sent invoice INV-2',
    summary_key => 'invoice.sent_again', summary_params => jsonb_build_object('number', 'INV-2'));
  if (select row(summary_key, summary_params ->> 'number') from better_supabase.audit_events where id = v_entry::bigint)
    is distinct from row('invoice.sent_again'::text, 'INV-2'::text) then
    raise exception 'audit_event did not store the summary key and params';
  end if;
end;
$$;
`;

describe("translation keys next to block prose", { timeout: 60_000 }, () => {
  it("stores ledger memo keys and audit summary keys", async () => {
    const files = renderBlocks(["audit", "ledger"], {});

    const boot = async (): Promise<void> => {
      await using stack = await liteStack({
        driver: "pglite",
        migrations: [
          ROLES,
          ...files
            .filter((file) => file.kind === "schema")
            .map((file) => file.contents),
          CHECK,
        ],
      });

      expect(stack.url).not.toBe("");
    };

    await expect(boot()).resolves.toBeUndefined();
  });
});
