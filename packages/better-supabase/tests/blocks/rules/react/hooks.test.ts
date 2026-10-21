import type * as ReactModule from "react";

import { afterEach, describe, expect, it, vi } from "vitest";

import type { AuthSnapshot } from "../../../../src/client/index.ts";

import { useRuleBuilder } from "../../../../src/blocks/rules/react/index.ts";
import {
  BetterSupabaseProvider,
  type ClientLike,
} from "../../../../src/react/hooks.ts";
import { renderHook } from "../../../fixtures/hook-runtime.ts";

const rpc = vi.hoisted(() => {
  const calls: { schema: string; fn: string; args: unknown }[] = [];

  const client = {
    schema: (schema: string) => ({
      rpc: async (fn: string, args: unknown) => {
        calls.push({ schema, fn, args });

        return { data: [], error: null };
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

// SAFETY: the hook reads only `supabase` and `auth` from the client.
const client = {
  supabase: rpc.client,
  auth: { current: () => signedIn, subscribe: () => () => undefined },
} as unknown as ClientLike;

const provide = (): void => {
  void BetterSupabaseProvider({ client });
};

afterEach(() => {
  rpc.calls.length = 0;
});

describe("useRuleBuilder", () => {
  it("loads the subject type's fields from the schema and edits a new rule", async () => {
    const view = renderHook(
      useRuleBuilder,
      {
        organizationId: "org-1",
        rule: null,
        subjectType: "expense",
        trigger: "expense.submitted",
        locked: ["first"],
        initial: {
          id: "root",
          type: "group",
          combinator: "and",
          rules: [
            { id: "first", type: "rule", path: ["status"], operator: "" },
          ],
        },
        limits: {
          maxDepth: 3,
          maxRules: 10,
          maxValueLength: 100,
          maxValues: 10,
        },
        schema: "api",
      },
      provide,
    );

    await vi.waitFor(() => {
      expect(view.result.loading).toBe(false);
    });

    expect(view.result.fields).toEqual([]);
    expect(view.result.locked).toEqual(["first"]);
    expect(view.result.conditions.rules).toHaveLength(1);
    expect(typeof view.result.rules.list).toBe("function");
    expect(rpc.calls[0]).toMatchObject({
      schema: "api",
      fn: "rule_fields_list",
      args: { subject_type: "expense" },
    });
    view.unmount();
  });
});
