import type { SupabaseClient } from "@supabase/supabase-js";

import { describe, expect, it } from "vitest";

import { refreshRealtimeAuth } from "../../src/realtime/auth.ts";

const clientWith = (realtime: object) => {
  const calls: unknown[] = [];
  const client = {
    realtime: Object.assign(realtime, {
      setAuth: (token?: string) => {
        calls.push(token);
        return Promise.resolve();
      },
    }),
  } as unknown as Pick<SupabaseClient, "realtime">;
  return { client, calls };
};

describe("refreshRealtimeAuth", () => {
  it("keeps a token the app set, and refreshes a session token", async () => {
    let manual = true;
    const { client, calls } = clientWith({
      _isManualToken() {
        return manual;
      },
    });
    await refreshRealtimeAuth(client);
    expect(calls).toEqual([]);
    manual = false;
    await refreshRealtimeAuth(client);
    expect(calls).toEqual([undefined]);
  });

  it("refreshes on a realtime-js without the check", async () => {
    const { client, calls } = clientWith({});
    await refreshRealtimeAuth(client);
    const odd = clientWith({ _isManualToken: "yes" });
    await refreshRealtimeAuth(odd.client);
    expect([...calls, ...odd.calls]).toEqual([undefined, undefined]);
  });
});
