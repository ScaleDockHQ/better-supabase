import { createClient } from "@supabase/supabase-js";
import { afterAll, describe, expect, it } from "vitest";

import { sessionStatus } from "../../src/auth/ended.ts";
import { createPostgres } from "../../src/postgres/pool.ts";
import { suspendAccount } from "../../src/server/suspend-account.ts";

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

async function reachable(): Promise<boolean> {
  try {
    const response = await fetch(`${url}/auth/v1/health`, {
      headers: { apikey: publishableKey },
      signal: AbortSignal.timeout(1000),
    });
    return response.ok;
  } catch {
    return false;
  }
}

describe.skipIf(!(await reachable()))("suspendAccount", () => {
  const service = createClient(url, secretKey, {
    auth: { persistSession: false },
  });
  const postgres = createPostgres({ connectionString: dbUrl, max: 1 });
  const userIds: string[] = [];

  afterAll(async () => {
    for (const id of userIds) await service.auth.admin.deleteUser(id);
    await postgres.end();
  });

  async function signedIn(): Promise<{ userId: string; token: string }> {
    const email = `suspend-${crypto.randomUUID()}@example.test`;
    const password = `pw-${crypto.randomUUID()}`;
    const { data, error } = await service.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
    });
    if (error) throw error;
    userIds.push(data.user.id);
    const client = createClient(url, publishableKey, {
      auth: { persistSession: false },
    });
    const signIn = await client.auth.signInWithPassword({ email, password });
    if (signIn.error) throw signIn.error;
    return { userId: data.user.id, token: signIn.data.session.access_token };
  }

  const status = (token: string) =>
    sessionStatus(token, { url, publishableKey });

  it("keeps the sessions, so Auth reports the user as banned", async () => {
    const { userId, token } = await signedIn();
    expect(await status(token)).toBe("active");

    expect(
      await suspendAccount(service, postgres.admin, userId, {
        suspended: true,
      }).orThrow(),
    ).toEqual({ userId, suspended: true, ended: 0 });
    expect(await status(token)).toBe("banned");

    expect(
      await suspendAccount(service, postgres.admin, userId, {
        suspended: false,
      }).orThrow(),
    ).toEqual({ userId, suspended: false, ended: 1 });
    expect(await status(token)).toBe("ended");
  });

  it("ends the sessions on suspension with endSessions", async () => {
    const { userId, token } = await signedIn();
    expect(
      await suspendAccount(service, postgres.admin, userId, {
        suspended: true,
        endSessions: true,
      }).orThrow(),
    ).toEqual({ userId, suspended: true, ended: 1 });
    expect(await status(token)).toBe("ended");
  });
});
