import type { SupabaseClient } from "@supabase/supabase-js";

import { describe, expect, it, vi } from "vitest";

import type { BlockEnv } from "../../src/blocks/block-env.ts";
import type { AuthPort } from "../../src/blocks/controller.ts";
import type { TopicPort } from "../../src/realtime/watch-topic.ts";

import {
  blockEnv,
  envBlockOptions,
  envBlockSettings,
} from "../../src/blocks/block-env.ts";

const auth: AuthPort = {
  current: () => ({ status: "loading", user: null, claims: null }),
  subscribe: () => () => undefined,
};

const topic: TopicPort = () => ({
  leave: () => undefined,
  send: () => undefined,
});

/** A supabase-js stand-in that records `schema(name).rpc(fn, args)`. */
function fakeSupabase() {
  const rpc = vi.fn(() => Promise.resolve({ data: [], error: null }));
  const schema = vi.fn(() => ({ rpc }));

  // SAFETY: the transport only calls `schema().rpc()`.
  const supabase = { schema } as unknown as SupabaseClient;

  return { supabase, schema, rpc };
}

function env(supabase: SupabaseClient, config: BlockEnv["config"]): BlockEnv {
  return { supabase, auth, ports: { topic }, config, tenant: () => undefined };
}

describe("envBlockOptions", () => {
  it("uses the module defaults without a config", () => {
    const { supabase } = fakeSupabase();
    const options = envBlockOptions(env(supabase, undefined), "comments");

    expect(options.schema).toBeUndefined();
  });

  it("calls the API schema and the renamed functions from the config", async () => {
    const { supabase, schema, rpc } = fakeSupabase();

    const options = envBlockOptions(
      env(supabase, {
        comments: {
          schema: "collab",
          api: "api",
          options: {},
          names: { functions: { list_comments: "list_notes" } },
        },
      }),
      "comments",
    );

    expect(options.schema).toBe("api");

    await options.transport.call("api", "list_comments", {});

    expect(schema).toHaveBeenCalledWith("api");
    expect(rpc).toHaveBeenCalledWith("list_notes", {});
  });
});

describe("envBlockSettings", () => {
  it("returns the generated options, or none", () => {
    const { supabase } = fakeSupabase();

    const withConfig = env(supabase, {
      reactions: { schema: "s", options: { topic: "reactions" } },
    });

    expect(envBlockSettings(withConfig, "reactions")).toEqual({
      topic: "reactions",
    });
    expect(envBlockSettings(env(supabase, undefined), "reactions")).toEqual({});
  });
});

describe("blockEnv tenant", () => {
  it("reads the client's tenant option first", () => {
    const { supabase } = fakeSupabase();
    let tenant = "org-1";

    const built = blockEnv({
      supabase,
      auth,
      ports: { topic },
      tenant: () => tenant,
    });

    expect(built.tenant()).toBe("org-1");

    tenant = "org-2";

    expect(built.tenant()).toBe("org-2");
  });

  it("has no tenant without an option or a session", () => {
    const { supabase } = fakeSupabase();

    const built = blockEnv({ supabase, auth, ports: { topic } });

    expect(built.tenant()).toBeUndefined();
  });
});
