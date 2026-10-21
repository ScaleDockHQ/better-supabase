import type * as ReactModule from "react";

import { describe, expect, it, vi } from "vitest";

import type { AuthSnapshot } from "../../../../src/client/index.ts";
import type { ClientLike } from "../../../../src/react/hooks.ts";

import {
  useSubject,
  useSubjects,
} from "../../../../src/blocks/subjects/react/index.ts";
import { BetterSupabaseProvider } from "../../../../src/react/hooks.ts";
import { renderHook } from "../../../fixtures/hook-runtime.ts";

const rpc = vi.hoisted(() => {
  const calls: { schema: string; fn: string; args: unknown }[] = [];

  const client = {
    schema: (schema: string) => ({
      rpc: async (
        fn: string,
        args: { refs: { type: string; id: string }[] },
      ) => {
        calls.push({ schema, fn, args });

        return {
          data: args.refs
            .filter((ref) => ref.id !== "hidden")
            .map((ref) => ({
              ...ref,
              title: `Title ${ref.id}`,
              url: `/${ref.type}s/${ref.id}`,
            })),
          error: null,
        };
      },
    }),
  };

  return { calls, client };
});

// vi.mock factories run before the imports above, so they load modules themselves.
vi.mock("react", async (importOriginal) => ({
  ...(await importOriginal<typeof ReactModule>()),
  ...(await import("../../../fixtures/hook-runtime.ts")).reactHooks,
}));

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

describe("subjects hooks", () => {
  it("resolves useSubject and useSubjects from one batched call", async () => {
    const view = renderHook(
      () => ({
        one: useSubject({ type: "customer", id: "c1" }),
        hidden: useSubject({ type: "customer", id: "hidden" }),
        none: useSubject(null),
        many: useSubjects([
          { type: "project", id: "p1" },
          { type: "project", id: "p1" },
          { type: "customer", id: "c1" },
        ]),
      }),
      undefined,
      provide,
    );

    expect(view.result.one.subject).toBeUndefined();
    expect(view.result.none.subject).toBeNull();

    await vi.waitFor(() => {
      expect(view.result.one.subject).toMatchObject({ title: "Title c1" });
    });

    expect(view.result.hidden.subject).toBeNull();
    expect(view.result.many.get({ type: "project", id: "p1" })).toEqual({
      type: "project",
      id: "p1",
      title: "Title p1",
      url: "/projects/p1",
    });
    expect(rpc.calls).toHaveLength(1);
    expect(rpc.calls[0]).toMatchObject({ fn: "subject_titles" });

    await view.result.one.refresh();

    expect(rpc.calls.length).toBeGreaterThan(1);
  });
});
