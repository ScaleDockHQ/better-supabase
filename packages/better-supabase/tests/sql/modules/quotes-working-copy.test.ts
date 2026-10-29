import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const STAFF = "22222222-2222-4222-8222-222222222222";
const CUSTOMER = "33333333-3333-4333-8333-333333333333";

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
  perform set_config('request.jwt.claim.role', 'service_role', true);
  perform set_config('request.jwt.claim.sub', '', true);`;

const ANON = `perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('request.jwt.claim.role', 'anon', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.headers', '{"x-forwarded-for": "203.0.113.9", "user-agent": "Browser/1"}', true);`;

const STATUSES = [
  "draft",
  "sent",
  "viewed",
  "accepted",
  "rejected",
  "changes_requested",
  "expired",
  "withdrawn",
];

const MACHINE: AnyBlocksConfig = {
  "state-machine": {
    options: {
      machines: {
        quote: {
          table: "better_supabase.quotes",
          column: "status",
          tenant: "tenant_id",
          initial: "draft",
          transitions: Object.fromEntries(
            STATUSES.map((from) => [
              from,
              STATUSES.filter((to) => to !== from),
            ]),
          ),
        },
      },
    },
  },
};

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(
  check: string,
  modules: AnyBlocksConfig = {},
  installed: readonly string[] = ["quotes"],
): Promise<void> {
  const files = renderBlocks(installed, { modules });

  const quotesFirst = [
    ...files.filter((file) => file.module !== "state-machine"),
    ...files.filter((file) => file.module === "state-machine"),
  ];

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
      PGCRYPTO,
      ...quotesFirst
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

const WORKING_COPY: AnyBlocksConfig = {
  quotes: { options: { workingCopy: true, versionLines: true } },
};

describe("quote deposits, periods, withdrawals and app actors", BOOT, () => {
  it("counts periods, keeps a fixed deposit, withdraws and takes an app portal answer", async () => {
    await expect(
      run(`do $$
declare
  v_quote jsonb;
  v_id uuid;
  v_sent jsonb;
  v_view jsonb;
begin
  ${SERVICE}
  v_quote := better_supabase.create_quote('${TENANT}', '{"title": "Hosting", "currency": "EUR", "depositAmount": "5000"}'::jsonb,
    '[{"description": "Plan", "quantity": 2, "periods": 12, "unitAmount": "1000"}, {"description": "Setup", "unitAmount": "500"}]'::jsonb);
  v_id := (v_quote ->> 'id')::uuid;
  if (v_quote ->> 'total')::bigint <> 24500 or (v_quote ->> 'deposit_due')::bigint <> 5000
    or (v_quote -> 'lines' -> 0 ->> 'periods')::integer <> 12 then
    raise exception 'created %', v_quote;
  end if;
  perform better_supabase.update_quote(v_id, '{"depositAmount": "999999"}'::jsonb);
  if (select deposit_due from better_supabase.quotes where id = v_id) <> 24500 then
    raise exception 'a fixed deposit is at most the total';
  end if;
  v_sent := better_supabase.send_quote(v_id);
  v_view := better_supabase.portal_quote(v_id);
  if v_view ->> 'depositAmount' <> '999999' or (v_view ->> 'depositRequired')::boolean then
    raise exception 'the service role reads the customer view %', v_view;
  end if;
  v_quote := better_supabase.withdraw_quote(v_id);
  if v_quote ->> 'status' <> 'withdrawn' then
    raise exception 'withdrawn %', v_quote;
  end if;
  perform better_supabase.revise_quote(v_id);
  if (select token_hash from better_supabase.quotes where id = v_id) is not null then
    raise exception 'without a working copy, revise still ends the link';
  end if;
  perform better_supabase.send_quote(v_id);
  v_quote := better_supabase.decide_quote(v_id, 'accepted', null, null, null,
    '{"id": "${CUSTOMER}", "name": "Cleo", "email": "cleo@example.com", "ip": "198.51.100.4", "userAgent": "App/2"}'::jsonb);
  if v_quote ->> 'status' <> 'accepted' or v_quote ->> 'decided_by' <> 'Cleo' or v_quote ->> 'decided_ip' <> '198.51.100.4'
    or v_quote ->> 'decided_user_agent' <> 'App/2' or v_quote ->> 'decided_user_id' <> '${CUSTOMER}' then
    raise exception 'decided %', v_quote;
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("refuses a share and an amount as the deposit", async () => {
    await expect(
      run(`do $$
begin
  ${SERVICE}
  perform better_supabase.create_quote('${TENANT}', '{"title": "Hosting", "currency": "EUR", "depositAmount": "5000", "depositBps": 1000}'::jsonb, null);
end;
$$;`),
    ).rejects.toThrow(/a share \(depositBps\) or an amount/);
  });

  it("refuses the customer's own acceptance until the deposit is paid", async () => {
    await expect(
      run(`do $$
declare
  v_token text;
begin
  ${SERVICE}
  v_token := better_supabase.send_quote((better_supabase.create_quote('${TENANT}',
    '{"title": "Hosting", "currency": "EUR", "depositBps": 2000, "depositRequired": true}'::jsonb,
    '[{"description": "Plan", "unitAmount": "1000"}]'::jsonb) ->> 'id')::uuid) ->> 'token';
  ${ANON}
  perform better_supabase.respond_to_quote(v_token, 'accepted', 'Cleo', null);
end;
$$;`),
    ).rejects.toThrow(/pay the deposit before accepting/);
  });

  it("refuses a withdrawal of a draft and an actor that is not an IP", async () => {
    await expect(
      run(`do $$
begin
  ${SERVICE}
  perform better_supabase.withdraw_quote((better_supabase.create_quote('${TENANT}', '{"title": "Hosting", "currency": "EUR"}'::jsonb,
    '[{"description": "Plan", "unitAmount": "1000"}]'::jsonb) ->> 'id')::uuid);
end;
$$;`),
    ).rejects.toThrow(/only a sent quote that wasn't answered is withdrawn/);
    await expect(
      run(`do $$
begin
  ${SERVICE}
  perform better_supabase.send_quote((better_supabase.create_quote('${TENANT}', '{"title": "Hosting", "currency": "EUR"}'::jsonb,
    '[{"description": "Plan", "unitAmount": "1000"}]'::jsonb) ->> 'id')::uuid, '{"ip": "not an address"}'::jsonb);
end;
$$;`),
    ).rejects.toThrow(/actor.ip must be an IP address/);
  });

  it("refuses a withdrawal by a user who can't write quotes", async () => {
    await expect(
      run(`do $$
declare
  v_id uuid;
begin
  ${SERVICE}
  v_id := (better_supabase.create_quote('${TENANT}', '{"title": "Hosting", "currency": "EUR"}'::jsonb,
    '[{"description": "Plan", "unitAmount": "1000"}]'::jsonb) ->> 'id')::uuid;
  perform better_supabase.send_quote(v_id);
  perform set_config('request.jwt.claims', '{"role":"authenticated","sub":"${CUSTOMER}"}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', '${CUSTOMER}', true);
  perform better_supabase.withdraw_quote(v_id);
end;
$$;`),
    ).rejects.toThrow(/no such quote you can edit/);
  });
});

describe("quote working copies and version lines", BOOT, () => {
  it("edits a sent quote while the customer sees the published version", async () => {
    await expect(
      run(
        `do $$
declare
  v_quote jsonb;
  v_id uuid;
  v_token text;
  v_view jsonb;
  v_optional text;
  v_hash text;
begin
  ${SERVICE}
  v_quote := better_supabase.create_quote('${TENANT}', '{"title": "Website", "currency": "EUR"}'::jsonb,
    '[{"description": "Design", "unitAmount": "5000"}, {"description": "Support", "unitAmount": "1000", "optional": true}]'::jsonb);
  v_id := (v_quote ->> 'id')::uuid;
  v_token := better_supabase.send_quote(v_id) ->> 'token';
  v_hash := (select token_hash from better_supabase.quotes where id = v_id);
  if (select count(*) from better_supabase.quote_version_lines) <> 2 then
    raise exception 'version lines %', (select jsonb_agg(l) from better_supabase.quote_version_lines l);
  end if;
  perform better_supabase.update_quote(v_id, '{"title": "Website v2"}'::jsonb);
  perform better_supabase.set_quote_lines(v_id, '[{"description": "Design and build", "unitAmount": "9000"}]'::jsonb);
  if (select (status, unpublished_changes) from better_supabase.quotes where id = v_id) is distinct from ('sent'::text, true) then
    raise exception 'the working copy %', (select to_jsonb(q) from better_supabase.quotes q where id = v_id);
  end if;
  perform better_supabase.revise_quote(v_id);
  if (select token_hash from better_supabase.quotes where id = v_id) is distinct from v_hash then
    raise exception 'revise ended the link';
  end if;
  ${ANON}
  v_view := better_supabase.public_quote(v_token);
  if v_view ->> 'title' <> 'Website' or jsonb_array_length(v_view -> 'lines') <> 2 or v_view ->> 'total' <> '5000'
    or v_view ->> 'status' <> 'viewed' then
    raise exception 'the customer saw %', v_view;
  end if;
  v_optional := v_view -> 'lines' -> 1 ->> 'versionLineId';
  perform better_supabase.respond_to_quote(v_token, 'accepted', 'Cleo', null, jsonb_build_array(v_optional));
  ${SERVICE}
  v_quote := better_supabase.quote_versions(v_id);
  if (select (title, total, unpublished_changes, status) from better_supabase.quotes where id = v_id)
    is distinct from ('Website'::text, 6000::bigint, false, 'accepted'::text)
    or (select string_agg(description || ':' || selected, ',' order by position) from better_supabase.quote_lines where parent_id = v_id) <> 'Design:true,Support:true' then
    raise exception 'accepted %', (select to_jsonb(q) from better_supabase.quotes q where id = v_id);
  end if;
end;
$$;`,
        WORKING_COPY,
      ),
    ).resolves.toBeUndefined();
  });

  it("publishes the working copy on the same link", async () => {
    await expect(
      run(
        `do $$
declare
  v_id uuid;
  v_token text;
  v_again jsonb;
  v_view jsonb;
begin
  ${SERVICE}
  v_id := (better_supabase.create_quote('${TENANT}', '{"title": "Website", "currency": "EUR"}'::jsonb,
    '[{"description": "Design", "unitAmount": "5000"}]'::jsonb) ->> 'id')::uuid;
  v_token := better_supabase.send_quote(v_id) ->> 'token';
  perform better_supabase.update_quote(v_id, '{"title": "Website v2"}'::jsonb);
  v_again := better_supabase.send_quote(v_id);
  if v_again ->> 'token' is not null or (v_again ->> 'revision')::integer <> 2 or (v_again ->> 'unpublished_changes')::boolean then
    raise exception 'published %', v_again;
  end if;
  v_view := better_supabase.public_quote(v_token);
  if v_view ->> 'title' <> 'Website v2' or (v_view ->> 'revision')::integer <> 2 then
    raise exception 'the link shows %', v_view;
  end if;
  if (select count(distinct version_id) from better_supabase.quote_version_lines) <> 2 then
    raise exception 'each version keeps its lines';
  end if;
end;
$$;`,
        WORKING_COPY,
      ),
    ).resolves.toBeUndefined();
  });

  it("never changes a version line", async () => {
    await expect(
      run(
        `do $$
declare
  v_id uuid;
begin
  ${SERVICE}
  v_id := (better_supabase.create_quote('${TENANT}', '{"title": "Website", "currency": "EUR"}'::jsonb,
    '[{"description": "Design", "unitAmount": "5000"}]'::jsonb) ->> 'id')::uuid;
  perform better_supabase.send_quote(v_id);
  update better_supabase.quote_version_lines set unit_amount = 1;
end;
$$;`,
        WORKING_COPY,
      ),
    ).rejects.toThrow(/a published quote version never changes/);
  });

  it("keeps a sent quote locked without the option", async () => {
    await expect(
      run(`do $$
declare
  v_id uuid;
begin
  ${SERVICE}
  v_id := (better_supabase.create_quote('${TENANT}', '{"title": "Website", "currency": "EUR"}'::jsonb,
    '[{"description": "Design", "unitAmount": "5000"}]'::jsonb) ->> 'id')::uuid;
  perform better_supabase.send_quote(v_id);
  perform better_supabase.update_quote(v_id, '{"title": "Website v2"}'::jsonb);
end;
$$;`),
    ).rejects.toThrow(
      /only a draft quote, or one with changes requested, can change/,
    );
  });

  it("refuses a working copy without its column", () => {
    expect(() =>
      renderBlocks(["quotes"], {
        modules: {
          quotes: {
            columns: { quotes: { unpublishedChanges: null } },
            options: { workingCopy: true },
          },
        },
      }),
    ).toThrow(/unpublishedChanges column/);
  });
});

describe("quote status history from the block's own writes", BOOT, () => {
  it("keeps the staff actor and the customer's answer", async () => {
    await expect(
      run(
        `do $$
declare
  v_id uuid;
  v_token text;
begin
  ${SERVICE}
  v_id := (better_supabase.create_quote('${TENANT}', '{"title": "Website", "currency": "EUR"}'::jsonb,
    '[{"description": "Design", "unitAmount": "5000"}]'::jsonb) ->> 'id')::uuid;
  v_token := better_supabase.send_quote(v_id, '{"id": "${STAFF}", "name": "Sam", "email": "sam@example.com"}'::jsonb) ->> 'token';
  if (select (actor_user_id, actor_name, actor_email) from better_supabase.status_history where to_status = 'sent')
    is distinct from ('${STAFF}'::uuid, 'Sam'::text, 'sam@example.com'::text) then
    raise exception 'sent by %', (select jsonb_agg(h) from better_supabase.status_history h);
  end if;
  ${ANON}
  perform better_supabase.respond_to_quote(v_token, 'rejected', 'Cleo', 'too much');
  ${SERVICE}
  if (select (actor_user_id, actor_name, host(ip_address), user_agent) from better_supabase.status_history where to_status = 'rejected')
    is distinct from (null::uuid, 'Cleo'::text, '203.0.113.9'::text, 'Browser/1'::text) then
    raise exception 'answered by %', (select jsonb_agg(h) from better_supabase.status_history h);
  end if;
end;
$$;`,
        MACHINE,
        ["quotes", "state-machine"],
      ),
    ).resolves.toBeUndefined();
  });
});
