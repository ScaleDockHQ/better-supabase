import type { AuthSnapshot } from "better-supabase/client";
import type { ClientLike } from "better-supabase/react";
import type * as ReactModule from "react";

import { BetterSupabaseProvider } from "better-supabase/react";
import { describe, expect, it, vi } from "vitest";

import {
  Can,
  usePermission,
  usePermissions,
} from "../../items/hooks/use-permissions.ts";
import { renderHook } from "../fixtures/hook-runtime.ts";

const rpc = vi.hoisted(() => {
  const calls: { schema: string; fn: string; args: unknown }[] = [];

  const client = {
    schema: (schema: string) => ({
      rpc: async (fn: string, args: { keys: string[] }) => {
        calls.push({ schema, fn, args });

        return {
          data: args.keys.filter((key) => key !== "invoices.void"),
          error: null,
        };
      },
    }),
  };

  return { calls, client };
});

// vi.mock factories run before the imports above, so they load modules themselves.
vi.mock(import("react"), async (importOriginal) => {
  const { reactHooks } = await import("../fixtures/hook-runtime.ts");

  return {
    ...(await importOriginal()),
    // SAFETY: the stand-in implements the part of React the hooks call.
    ...(reactHooks as unknown as Partial<typeof ReactModule>),
  };
});

const signedIn: AuthSnapshot = {
  status: "signed-in",
  user: { id: "user-1" },
  claims: { sub: "user-1" },
};

// SAFETY: the hooks read only `supabase`, `auth` and `tenant` from the client.
const client = {
  supabase: rpc.client,
  auth: { current: () => signedIn, subscribe: () => () => undefined },
  tenant: "org-1",
} as unknown as ClientLike;

const provide = (): void => {
  void BetterSupabaseProvider({ client });
};

describe("access hooks", () => {
  it("answers usePermission, usePermissions and Can from one batched call", async () => {
    const view = renderHook(
      () => ({
        write: usePermission("invoices.write"),
        all: usePermissions(["invoices.read", "invoices.void"]),
        gate: Can({
          permission: "invoices.void",
          fallback: "no",
          children: "yes",
        }),
      }),
      undefined,
      provide,
    );

    expect(view.result.write).toBeUndefined();

    await vi.waitFor(() => {
      expect(view.result.write).toBe(true);
    });

    expect(view.result.all.can("invoices.read")).toBe(true);
    expect(view.result.all.can("invoices.void")).toBe(false);
    expect(view.result.gate).toBe("no");
    expect(rpc.calls).toHaveLength(1);
    expect(rpc.calls[0]).toMatchObject({
      fn: "my_permissions",
      args: { tenant: "org-1" },
    });
  });
});
