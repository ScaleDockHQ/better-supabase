import type { SupabaseClient } from "@supabase/supabase-js";

import { describe, expect, it, vi } from "vitest";

import type { SqlClient } from "../../src/postgres/executor.ts";

import {
  endSessions,
  suspendAccount,
} from "../../src/server/suspend-account.ts";

const USER = "6f1f5b8e-2c1d-4a3b-9e7f-0a1b2c3d4e5f";

type UpdateUser = (
  id: string,
  attributes: { ban_duration: string },
) => Promise<{ error: unknown }>;

function setup(
  options: {
    ended?: number;
    sqlError?: Error;
    updateUser?: UpdateUser;
  } = {},
) {
  const order: string[] = [];
  const queryRaw = vi.fn(async (text: string, params?: unknown[]) => {
    order.push("sessions");
    if (options.sqlError) throw options.sqlError;
    expect(params).toEqual([USER]);
    expect(text).toContain(
      "delete from auth.sessions where user_id = $1::uuid",
    );
    expect(text).toContain(
      "delete from auth.refresh_tokens where user_id = $1::text",
    );
    return [{ ended: options.ended ?? 2 }];
  });
  const sql = { queryRaw } as unknown as SqlClient;
  const updateUserById = vi.fn<UpdateUser>(async (_id, attributes) => {
    order.push(`ban:${attributes.ban_duration}`);
    return options.updateUser
      ? options.updateUser(_id, attributes)
      : { error: null };
  });
  const client = {
    auth: { admin: { updateUserById } },
  } as unknown as SupabaseClient;
  return { sql, queryRaw, updateUserById, client, order };
}

describe("endSessions", () => {
  it("deletes the user's sessions and refresh tokens", async () => {
    const { sql } = setup({ ended: 3 });
    expect(await endSessions(sql, USER).orThrow()).toEqual({
      userId: USER,
      ended: 3,
    });
  });

  it("refuses an id that is not a uuid without a query", async () => {
    const { sql, queryRaw } = setup();
    expect(await endSessions(sql, "nope")).toMatchObject({
      ok: false,
      error: { kind: "invalid_request" },
    });
    expect(queryRaw).not.toHaveBeenCalled();
  });

  it("maps a Postgres error", async () => {
    const { sql } = setup({
      sqlError: Object.assign(new Error("permission denied"), {
        code: "42501",
      }),
    });
    expect(await endSessions(sql, USER)).toMatchObject({
      ok: false,
      error: { kind: "forbidden", table: "auth.sessions" },
    });
  });

  it("is exported from the server entry", async () => {
    const server = await import("../../src/server/index.ts");
    expect(server.endSessions).toBe(endSessions);
    expect(server.suspendAccount).toBe(suspendAccount);
  });
});

describe("suspendAccount", () => {
  it("bans the user, then ends every session", async () => {
    const { sql, client, order } = setup({ ended: 1 });
    expect(
      await suspendAccount(client, sql, USER, { suspended: true }).orThrow(),
    ).toEqual({ userId: USER, suspended: true, ended: 1 });
    expect(order).toEqual(["ban:876000h", "sessions"]);
  });

  it("takes a ban duration and a client factory", async () => {
    const { sql, client, order } = setup();
    await suspendAccount(() => client, sql, USER, {
      suspended: true,
      duration: "24h",
    }).orThrow();
    expect(order).toEqual(["ban:24h", "sessions"]);
  });

  it("ends sessions left from before the ban, then lifts it", async () => {
    const { sql, client, order } = setup({ ended: 0 });
    expect(
      await suspendAccount(client, sql, USER, { suspended: false }).orThrow(),
    ).toEqual({ userId: USER, suspended: false, ended: 0 });
    expect(order).toEqual(["sessions", "ban:none"]);
  });

  it("keeps the sessions when Auth refuses the ban", async () => {
    const { sql, client, queryRaw } = setup({
      updateUser: async () => ({
        error: { message: "User not found", status: 404 },
      }),
    });
    expect(
      await suspendAccount(client, sql, USER, { suspended: true }),
    ).toMatchObject({ ok: false, error: { kind: "not_found" } });
    expect(queryRaw).not.toHaveBeenCalled();
  });

  it("keeps the ban when ending sessions fails while resuming", async () => {
    const { sql, client, updateUserById } = setup({
      sqlError: new Error("connection reset"),
    });
    expect(
      await suspendAccount(client, sql, USER, { suspended: false }),
    ).toMatchObject({ ok: false, error: { kind: "unexpected" } });
    expect(updateUserById).not.toHaveBeenCalled();
  });

  it("maps a thrown Auth failure", async () => {
    const { sql, client } = setup({
      updateUser: async () => {
        throw Object.assign(new Error("fetch failed"), {
          name: "AuthRetryableFetchError",
        });
      },
    });
    expect(
      await suspendAccount(client, sql, USER, { suspended: true }),
    ).toMatchObject({ ok: false, error: { kind: "network" } });
  });

  it("refuses an id that is not a uuid", async () => {
    const { sql, client, updateUserById } = setup();
    expect(
      await suspendAccount(client, sql, "nope", { suspended: true }),
    ).toMatchObject({ ok: false, error: { kind: "invalid_request" } });
    expect(updateUserById).not.toHaveBeenCalled();
  });
});
