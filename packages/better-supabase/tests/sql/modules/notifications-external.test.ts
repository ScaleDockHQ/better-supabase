import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";
import type { PgliteConnection } from "../../../src/lite/runtime.ts";

import { getLite, migrateLite } from "../../../src/lite/runtime.ts";
import { moduleBody, renderBlocks } from "../../../src/sql/render.ts";
import { ownTablesOf } from "../../fixtures/own-tables.ts";
import { unnamedChecks } from "../unnamed-checks.ts";

const CONTACT = "44444444-4444-4444-8444-444444444444";

const ON: AnyBlocksConfig = {
  notifications: {
    options: {
      channels: ["in_app", "email"],
      channelDefaults: { email: true },
      externalRecipients: true,
      resolveAddress: "public.contact_address",
    },
  },
};

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
create schema if not exists extensions;
create or replace function extensions.gen_random_bytes(n integer) returns bytea
language sql volatile as $$ select decode(md5(random()::text), 'hex') $$;
create or replace function extensions.digest(data text, type text) returns bytea
language sql immutable as $$ select sha256(convert_to(data, 'UTF8')) $$;
create schema if not exists realtime;
create or replace function realtime.send(payload jsonb, event text, topic text, private boolean default true)
returns void language sql as $$ select $$;
create or replace function public.contact_address(contact uuid, channel text) returns text
language sql as $$ select case when contact = '${CONTACT}' then 'Contact@Example.com' end $$;
`;

const SERVICE = `
select set_config('request.jwt.claims', '{"role":"service_role"}', false);
select set_config('request.jwt.claim.role', 'service_role', false);
`;

describe("external notification recipients (render)", () => {
  it("stays off by default", () => {
    const sql = unnamedChecks(moduleBody("notifications", { modules: {} })!);
    expect(sql).not.toContain("v_external");
    expect(sql).toContain(`"user_id" uuid not null references auth.users`);
  });

  it("makes the user optional and requires exactly one target", () => {
    const sql = unnamedChecks(moduleBody("notifications", { modules: ON })!);
    expect(sql).toContain(`"user_id" uuid references auth.users`);
    expect(sql).toContain(`"contact_id" uuid`);
    expect(sql).toContain("num_nonnulls");
    expect(sql).toContain("NOTIFICATION_EXTERNAL_INVALID");
  });
});

describe(
  "external notification recipients (database)",
  { timeout: 60_000 },
  () => {
    let connection: PgliteConnection | undefined;

    const query = async <R>(text: string, params?: unknown[]): Promise<R[]> => {
      // SAFETY: PGlite's query takes parameters; the runtime type leaves them out.
      const driver = connection?.driver as unknown as {
        query(text: string, params?: unknown[]): Promise<{ rows: unknown[] }>;
      };

      // SAFETY: each caller names the row type its statement selects.
      return (await driver.query(text, params)).rows as R[];
    };

    const send = (external: unknown) =>
      query(
        `select better_supabase.send_notification(jsonb_build_object(
        'type', 'invoice.sent',
        'data', jsonb_build_object('title', 'Invoice'),
        'recipients', '[]'::jsonb,
        'external', $1::jsonb
      ))`,
        [JSON.stringify(external)],
      );

    beforeAll(async () => {
      const lite = await getLite();

      if (!lite) {
        throw new Error("@supabase/lite is a devDependency of these tests");
      }

      connection = await lite.createPgliteConnection();
      await new lite.App({
        connection,
        auth: {
          enabled: true,
          jwt_secret: "x".repeat(32),
          publishable_key: "sb_publishable_test",
          secret_key: "sb_secret_test",
        },
      }).init();

      const files = renderBlocks(["notifications"], {
        modules: ON,
        ownTables: ownTablesOf(ON, []),
      });

      await migrateLite(connection, [
        ROLES,
        ...files
          .filter((file) => file.kind === "schema")
          .map((file) => file.contents),
      ]);
      await connection.driver.exec(SERVICE);
    }, 120_000);

    afterAll(async () => {
      await connection?.close();
    });

    it("claims an email for an address and for a resolved contact", async () => {
      await send([{ address: " Bob@Example.com " }, { contact: CONTACT }]);

      const [row] = await query<{
        readonly claimed: readonly {
          readonly user_id: string | null;
          readonly email: string | null;
        }[];
      }>(
        `select better_supabase.claim_notification_deliveries('email') as claimed`,
      );

      const claimed = row?.claimed ?? [];
      expect(claimed.map((each) => each.user_id)).toEqual([null, null]);
      expect(
        claimed
          .map((each) => each.email)
          .toSorted((a, b) => String(a).localeCompare(String(b))),
      ).toEqual(["bob@example.com", "Contact@Example.com"]);
    });

    it("rejects an entry that is not exactly one address or contact", async () => {
      await expect(send([{ address: "nope" }])).rejects.toThrow(
        /external recipients/,
      );
      await expect(
        send([{ address: "a@b.co", contact: CONTACT }]),
      ).rejects.toThrow(/external recipients/);
    });
  },
);
