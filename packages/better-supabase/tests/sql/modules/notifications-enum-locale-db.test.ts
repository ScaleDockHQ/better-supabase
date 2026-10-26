import type { StandardSchemaV1 } from "@standard-schema/spec";

import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type {
  DeliveryTransport,
  EmailMessage,
} from "../../../src/blocks/notifications/index.ts";
import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";
import type { PgliteConnection } from "../../../src/lite/runtime.ts";
import type { SqlClient } from "../../../src/postgres/executor.ts";

import { createNotifications } from "../../../src/blocks/notifications/index.ts";
import { sqlTransport } from "../../../src/core/block-transport.ts";
import { loadLite, migrateLite } from "../../../src/lite/runtime.ts";
import { renderBlocks } from "../../../src/sql/render.ts";
import { ownTablesOf } from "../../fixtures/own-tables.ts";

const ADA = "11111111-1111-4111-8111-111111111111";
const BOB = "22222222-2222-4222-8222-222222222222";
const CY = "33333333-3333-4333-8333-333333333333";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;

-- PGlite loads no pgcrypto here; the modules need random bytes and sha256.
create schema if not exists extensions;
create or replace function extensions.gen_random_bytes(n integer) returns bytea
language sql volatile as $$ select decode(md5(random()::text), 'hex') $$;
create or replace function extensions.digest(data text, type text) returns bytea
language sql immutable as $$ select sha256(convert_to(data, 'UTF8')) $$;

-- The notification broadcast trigger calls Realtime, which PGlite lacks.
create schema if not exists realtime;
create or replace function realtime.send(payload jsonb, event text, topic text, private boolean default true)
returns void language sql as $$ select $$;
`;

const APP = `
create type public.app_locale as enum ('en', 'nl', 'de');

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text,
  username text,
  locale public.app_locale,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
`;

const BLOCKS: AnyBlocksConfig = {
  profiles: {
    tables: { profiles: "public.profiles" },
    columns: { profiles: { locale: "locale" } },
    options: { metadata: { locale: "locale" } },
  },
  notifications: {
    options: {
      channels: ["in_app", "email"],
      channelDefaults: { email: true },
    },
  },
};

const SEED = `
insert into auth.users (id, email, raw_user_meta_data) values
  ('${ADA}', 'ada@example.com', '{"locale": "nl"}'),
  ('${BOB}', 'bob@example.com', '{"locale": "de"}'),
  ('${CY}', 'cy@example.com', '{}');
select better_supabase.sync_profile(id) from auth.users;
`;

const SERVICE = `
select set_config('request.jwt.claims', '{"role":"service_role"}', false);
select set_config('request.jwt.claim.role', 'service_role', false);
`;

const titleOf = (data: unknown): string =>
  typeof data === "object" && data !== null && "title" in data
    ? String(data.title)
    : "";

const titled: StandardSchemaV1<{ title: string }> = {
  "~standard": {
    version: 1,
    vendor: "test",
    validate: (value) => {
      if (typeof value !== "object" || value === null || !("title" in value)) {
        return { issues: [{ message: "no title" }] };
      }

      // SAFETY: checked that `value` has `title`.
      return { value: value as { title: string } };
    },
  },
};

/** Lite migrates PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

describe("notifications to profiles with an enum locale", BOOT, () => {
  let connection: PgliteConnection | undefined;
  let sql: SqlClient;

  /** Runs one statement in the database. */
  const query = async <R>(text: string, params?: unknown[]): Promise<R[]> => {
    // SAFETY: PGlite's query takes parameters; the runtime type leaves them out.
    const driver = connection?.driver as unknown as {
      query(text: string, params?: unknown[]): Promise<{ rows: unknown[] }>;
    };

    // SAFETY: each caller names the row type its statement selects.
    return (await driver.query(text, params)).rows as R[];
  };

  beforeAll(async () => {
    const lite = await loadLite();

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

    const files = renderBlocks(["profiles", "notifications"], {
      modules: BLOCKS,
      ownTables: ownTablesOf(BLOCKS, ["profiles"]),
    });

    await migrateLite(connection, [
      ROLES,
      APP,
      ...files
        .filter((file) => file.kind !== "data")
        .map((file) => file.contents),
    ]);

    for (const file of files.filter((each) => each.kind === "data")) {
      await connection.driver.exec(file.contents);
    }

    await connection.driver.exec(SEED);
    await connection.driver.exec(SERVICE);

    sql = {
      queryRaw: query,
      transaction: <T>(fn: (client: SqlClient) => Promise<T>) => fn(sql),
    };
  }, 120_000);

  afterAll(async () => {
    await connection?.close();
  });

  const send = (title: string): Promise<unknown> =>
    query(
      `select better_supabase.send_notification(jsonb_build_object(
        'type', 'task.assigned',
        'data', jsonb_build_object('title', $1::text),
        'recipients', jsonb_build_array($2::uuid, $3::uuid, $4::uuid)
      ))`,
      [title, ADA, BOB, CY],
    );

  it("claims each delivery with the profile's locale label as text", async () => {
    await send("Claimed");

    const [claimed] = await query<{
      readonly claimed: readonly {
        readonly user_id: string;
        readonly locale: string | null;
      }[];
    }>(
      `select better_supabase.claim_notification_deliveries('email') as claimed`,
    );

    expect(
      Object.fromEntries(
        (claimed?.claimed ?? []).map((row) => [row.user_id, row.locale]),
      ),
    ).toEqual({ [ADA]: "nl", [BOB]: "de", [CY]: null });

    await query(`update better_supabase.notification_deliveries
      set status = 'sent'`);
  });

  it("renders and hydrates each locale group once in deliver()", async () => {
    await send("Ship it");

    const sent: EmailMessage[] = [];

    const mail: DeliveryTransport = {
      apiVersion: 1,
      channel: "email",
      provider: "fake",
      send(message) {
        sent.push(message);

        return { providerMessageId: `m-${sent.length}` };
      },
    };

    const hydrated: (string | undefined)[] = [];

    const notifications = createNotifications({
      transport: sqlTransport(sql),
      types: { "task.assigned": titled },
      hydrate: (items, { locale }) => {
        hydrated.push(locale);

        return items.length;
      },
      render: (item, { locale }) => ({
        title: `${locale ?? "default"}: ${titleOf(item.data)}`,
      }),
      email: { transport: mail, from: "hi@acme.test" },
    });

    expect(await notifications.deliver()).toEqual({
      sent: 3,
      skipped: 0,
      failed: 0,
    });
    expect(
      hydrated.toSorted((a, b) => (a ?? "").localeCompare(b ?? "")),
    ).toEqual(["de", "nl", undefined]);
    expect(
      Object.fromEntries(sent.map((message) => [message.to, message.subject])),
    ).toEqual({
      "ada@example.com": "nl: Ship it",
      "bob@example.com": "de: Ship it",
      "cy@example.com": "default: Ship it",
    });
  });
});
