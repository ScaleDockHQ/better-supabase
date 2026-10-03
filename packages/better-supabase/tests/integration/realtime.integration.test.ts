import type { StandardSchemaV1 } from "@standard-schema/spec";

import { createClient } from "@supabase/supabase-js";
import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import {
  defineTopic,
  rowChange,
  type TopicMessage,
} from "../../src/realtime/index.ts";
import { signLocalJwt } from "../../src/testing/local-key.ts";
import { schema } from "../fixtures/generated-camel.ts";

const url = process.env["SUPABASE_URL"] ?? "http://127.0.0.1:55421";
const dbUrl =
  process.env["SUPABASE_DB_URL"] ??
  "postgresql://postgres:postgres@127.0.0.1:55422/postgres";
const publishableKey =
  process.env["SUPABASE_PUBLISHABLE_KEY"] ??
  "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH";

const ACME = "00000000-0000-4000-8000-000000000001";
const OTHER = "00000000-0000-4000-8000-000000000002";
const USER = "00000000-0000-4000-8000-0000000000ff";

async function reachable(): Promise<boolean> {
  try {
    const response = await fetch(`${url}/rest/v1/`, {
      headers: { apikey: publishableKey },
      signal: AbortSignal.timeout(1000),
    });
    return response.status < 500;
  } catch {
    return false;
  }
}

const live = await reachable();

const title: StandardSchemaV1<unknown, { title: string }> = {
  "~standard": {
    version: 1,
    vendor: "test",
    validate: (value) =>
      typeof value === "object" &&
      value !== null &&
      typeof (value as { title?: unknown }).title === "string"
        ? { value: { title: (value as { title: string }).title } }
        : { issues: [{ message: "title is required", path: ["title"] }] },
  },
};

const betterSupabase = defineSupabase(schema);
const customers = defineTopic("org:{orgId}:customers");
const notifications = defineTopic("org:{orgId}:notifications:{userId}", {
  events: { created: title },
  send: true,
});

function waitFor<T>(
  register: (resolve: (value: T) => void) => void,
  ms = 8000,
): Promise<T> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      reject(new Error("timed out waiting for a message"));
    }, ms);
    register((value) => {
      clearTimeout(timer);
      resolve(value);
    });
  });
}

describe.skipIf(!live)("Realtime kit", async () => {
  const clientFor = (orgId: string) =>
    createClient(url, publishableKey, {
      accessToken: () =>
        signLocalJwt({ sub: USER, role: "authenticated", tenant_id: orgId }),
    });
  const acme = clientFor(ACME);
  const other = clientFor(OTHER);
  const pool = new Pool({ connectionString: dbUrl, max: 1 });
  const kvk = `rt-${String(Date.now())}`;

  beforeAll(async () => {
    await pool.query(customers.sql());
    await pool.query(notifications.sql());
    await pool.query(
      customers.triggerSql(betterSupabase, "customers", {
        values: { orgId: "organizationId" },
      }),
    );
  });
  afterAll(async () => {
    await pool.query("delete from public.customers where kvk like $1", [
      `${kvk}%`,
    ]);
    acme.removeAllChannels();
    other.removeAllChannels();
    await pool.end();
  });

  it("broadcasts row changes to the tenant topic", async () => {
    let retry: ReturnType<typeof setInterval> | undefined;
    let attempt = 0;
    const insert = () =>
      betterSupabase
        .connect(acme, { claims: { tenant_id: ACME } })
        .customers.create({
          organizationId: ACME,
          name: "Realtime Co",
          kvk: `${kvk}-${String((attempt += 1))}`,
        })
        .orThrow();
    const got = waitFor<TopicMessage>((resolve) => {
      const sub = customers.subscribe(
        acme,
        { orgId: ACME },
        {
          INSERT: (_payload, message) => {
            resolve(message);
          },
        },
      );
      // A cold Realtime server acknowledges the join before it relays database
      // broadcasts, and a message sent in that gap is never delivered.
      void sub.ready.then(async () => {
        await insert();
        retry = setInterval(() => void insert(), 3000);
      });
    }, 15_000).finally(() => {
      clearInterval(retry);
    });
    const received = await got;
    const change = rowChange(betterSupabase, "customers", received);
    expect(change).toMatchObject({
      operation: "INSERT",
      table: "customers",
      record: {
        name: "Realtime Co",
        organizationId: ACME,
        kvk: expect.stringMatching(new RegExp(`^${kvk}-\\d+$`)),
      },
    });
    expect(rowChange(betterSupabase, "notes", received)).toBeNull();
  }, 20_000);

  it("refuses private topics of another tenant", async () => {
    const sub = customers.subscribe(other, { orgId: ACME }, {});
    await expect(sub.ready).rejects.toThrow(/./);
    await sub.unsubscribe();
  }, 20_000);

  it("sends validated events over HTTP", async () => {
    const values = { orgId: ACME, userId: USER };
    const invalid = await notifications.send(acme, values, "created", {
      nope: true,
    });
    expect(invalid.error).toMatchObject({
      kind: "validation",
      issues: [{ path: ["title"] }],
    });

    let retry: ReturnType<typeof setInterval> | undefined;
    const send = () =>
      notifications.send(acme, values, "created", { title: "Hello" }).orThrow();
    const message = await waitFor<{ title: string }>((resolve) => {
      const sub = notifications.subscribe(acme, values, {
        created: (payload) => {
          resolve(payload);
        },
      });
      // Same cold-server gap as the row broadcast above.
      void sub.ready.then(async () => {
        await send();
        retry = setInterval(() => void send(), 3000);
      });
    }, 15_000).finally(() => {
      clearInterval(retry);
    });
    expect(message).toEqual({ title: "Hello" });

    const denied = await notifications.send(other, values, "created", {
      title: "Hi",
    });
    expect(denied.ok).toBe(false);
  }, 20_000);
});
