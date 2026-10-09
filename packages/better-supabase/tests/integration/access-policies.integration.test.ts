import { createClient } from "@supabase/supabase-js";
import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { defineTopic } from "../../src/realtime/index.ts";
import { defineBucket } from "../../src/storage/index.ts";
import { signLocalJwt } from "../../src/testing/local-key.ts";

const url = process.env["SUPABASE_URL"] ?? "http://127.0.0.1:55421";
const dbUrl =
  process.env["SUPABASE_DB_URL"] ??
  "postgresql://postgres:postgres@127.0.0.1:55422/postgres";
const publishableKey =
  process.env["SUPABASE_PUBLISHABLE_KEY"] ??
  "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH";
const secretKey =
  process.env["SUPABASE_SECRET_KEY"] ??
  "sb_secret_N7UND0UgjKTVK-Uodkm0Hg_xSvEMPvz";

const ACME = "00000000-0000-4000-8000-000000000001";
const OTHER = "00000000-0000-4000-8000-000000000002";
const USER = "00000000-0000-4000-8000-0000000000fe";
/** An id with hex letters, so its uppercase form differs. */
const HEX = "abcdef00-0000-4000-8000-0000000000ab";
const RUN = String(Date.now());
const SCHEMA = `bs_authz_${RUN}`;

async function reachable(): Promise<boolean> {
  try {
    const response = await fetch(`${url}/storage/v1/status`, {
      signal: AbortSignal.timeout(1000),
    });
    return response.ok;
  } catch {
    return false;
  }
}

const live = await reachable();

// Stand-ins for a provider's functions: the test token lists the
// organizations each key is permitted in under an `authz` claim.
const STUBS = `
create schema ${SCHEMA};
grant usage on schema ${SCHEMA} to authenticated;
create function ${SCHEMA}.organization_ids_with(key text)
returns table (id uuid) language sql stable set search_path = '' as $$
  select value::uuid
  from jsonb_array_elements_text(coalesce(auth.jwt() -> 'authz' -> key, '[]'::jsonb))
$$;
create function ${SCHEMA}.is_platform(key text)
returns boolean language sql stable set search_path = '' as $$
  select coalesce(auth.jwt() -> 'authz_platform' ? key, false)
$$;
`;

const SQL = {
  idsWith: `${SCHEMA}.{scope}_ids_with({permission})`,
  isPlatform: `${SCHEMA}.is_platform({permission})`,
};

const files = defineBucket({
  id: `bs-it-pd-${RUN}`,
  path: "{organizationId}/{file}",
  policy: {
    access: { read: "files.read", list: "files.list", write: "files.write" },
    scope: "organization",
    sql: SQL,
  },
});

const board = defineTopic("pd:{organizationId}:board", {
  name: `pd_board_${RUN}`,
  access: {
    receive: "board.read",
    send: "board.write",
    scope: "organization",
    sql: SQL,
  },
});

describe.skipIf(!live)("access policies on provider functions", async () => {
  const clientWith = (
    authz: Record<string, string[]>,
    platform: string[] = [],
  ) =>
    createClient(url, publishableKey, {
      accessToken: () =>
        signLocalJwt({
          sub: USER,
          role: "authenticated",
          authz,
          authz_platform: platform,
        }),
    });
  const service = createClient(url, secretKey, {
    auth: { persistSession: false },
  });
  const admin = files.connect(service);
  const reader = files.connect(clientWith({ "files.read": [ACME] }));
  const lister = files.connect(clientWith({ "files.list": [ACME] }));
  const writer = files.connect(clientWith({ "files.write": [ACME] }));
  const pool = new Pool({ connectionString: dbUrl, max: 1 });

  beforeAll(async () => {
    await pool.query(STUBS);
    await pool.query(files.sql());
    await pool.query(board.sql());
    await admin
      .upload({ organizationId: ACME, file: "a.txt" }, new Blob(["acme"]))
      .orThrow();
    await admin
      .upload({ organizationId: OTHER, file: "b.txt" }, new Blob(["other"]))
      .orThrow();
    for (const organizationId of [HEX, HEX.toUpperCase()]) {
      await admin
        .upload({ organizationId, file: "h.txt" }, new Blob([organizationId]))
        .orThrow();
    }
  });
  afterAll(async () => {
    await admin.remove([
      { organizationId: ACME, file: "a.txt" },
      { organizationId: ACME, file: "w.txt" },
      { organizationId: OTHER, file: "b.txt" },
      { organizationId: HEX, file: "h.txt" },
      { organizationId: HEX.toUpperCase(), file: "h.txt" },
    ]);
    await service.storage.deleteBucket(files.id);
    const objects = ["select", "list", "insert", "update", "delete"].map(
      (suffix) =>
        `drop policy if exists "bs_bs_it_pd_${RUN}_${suffix}" on storage.objects;`,
    );
    const topics = ["receive", "send"].map(
      (suffix) =>
        `drop policy if exists "bs_topic_pd_board_${RUN}_${suffix}" on realtime.messages;`,
    );
    await pool.query(
      [...objects, ...topics, `drop schema ${SCHEMA} cascade;`].join("\n"),
    );
    await pool.end();
  });

  it("downloads with read but lists only with list", async () => {
    const own = await reader
      .download({ organizationId: ACME, file: "a.txt" })
      .orThrow();
    expect(await own.text()).toBe("acme");
    expect(await reader.list({ organizationId: ACME }).orThrow()).toEqual([]);
    const other = await reader.download({
      organizationId: OTHER,
      file: "b.txt",
    });
    expect(other.ok).toBe(false);

    const listed = await lister.list({ organizationId: ACME }).orThrow();
    expect(listed.map((object) => object.path)).toEqual([`${ACME}/a.txt`]);
    expect(await lister.list({ organizationId: OTHER }).orThrow()).toEqual([]);
    const download = await lister.download({
      organizationId: ACME,
      file: "a.txt",
    });
    expect(download.ok).toBe(false);
  });

  it("writes only where write is permitted", async () => {
    const own = await writer.upload(
      { organizationId: ACME, file: "w.txt" },
      new Blob(["w"]),
    );
    expect(own.ok).toBe(true);
    const other = await writer.upload(
      { organizationId: OTHER, file: "w.txt" },
      new Blob(["w"]),
    );
    expect(other.error?.kind).toBe("forbidden");
    const readerWrite = await reader.upload(
      { organizationId: ACME, file: "r.txt" },
      new Blob(["r"]),
    );
    expect(readerWrite.error?.kind).toBe("forbidden");
  });

  it("compares ids as canonical lowercase text", async () => {
    const hexReader = files.connect(clientWith({ "files.read": [HEX] }));
    const lower = await hexReader.download({
      organizationId: HEX,
      file: "h.txt",
    });
    expect(lower.ok).toBe(true);
    const upper = await hexReader.download({
      organizationId: HEX.toUpperCase(),
      file: "h.txt",
    });
    expect(upper.ok).toBe(false);

    const client = clientWith({ "board.read": [HEX] });
    const joined = board.subscribe(client, { organizationId: HEX }, {});
    await joined.ready;
    await joined.unsubscribe();
    const shouting = board.subscribe(
      client,
      { organizationId: HEX.toUpperCase() },
      {},
    );
    await expect(shouting.ready).rejects.toThrow(/./);
    await shouting.unsubscribe();
    client.removeAllChannels();
  }, 20_000);

  it("joins and sends on topics by permission", async () => {
    const readOnly = clientWith({ "board.read": [ACME] });
    const joined = board.subscribe(readOnly, { organizationId: ACME }, {});
    await joined.ready;
    await joined.unsubscribe();

    const elsewhere = board.subscribe(readOnly, { organizationId: OTHER }, {});
    await expect(elsewhere.ready).rejects.toThrow(/./);
    await elsewhere.unsubscribe();

    const denied = await board.send(
      readOnly,
      { organizationId: ACME },
      "moved",
      {},
    );
    expect(denied.ok).toBe(false);
    const sender = clientWith({
      "board.read": [ACME],
      "board.write": [ACME],
    });
    const sent = await board.send(
      sender,
      { organizationId: ACME },
      "moved",
      {},
    );
    expect(sent.ok).toBe(true);
    readOnly.removeAllChannels();
    sender.removeAllChannels();
  }, 20_000);
});
