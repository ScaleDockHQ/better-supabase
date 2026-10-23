import type { ClientLike } from "better-supabase/react";
import type * as ReactModule from "react";

import { BetterSupabaseProvider } from "better-supabase/react";
import { describe, expect, it, vi } from "vitest";

import {
  useConversations,
  useMessages,
} from "../../items/hooks/use-messaging.ts";
import { renderHook } from "../fixtures/hook-runtime.ts";
import { fakeTopic, flush, signedIn } from "../fixtures/ports.ts";

const rpc = vi.hoisted(() => {
  const calls: { schema: string; fn: string; args: unknown }[] = [];

  const supabase = {
    schema: (schema: string) => ({
      rpc: async (fn: string, args: unknown) => {
        calls.push({ schema, fn, args });

        return { data: [], error: null };
      },
    }),
  };

  return { calls, supabase };
});

vi.mock(import("react"), async (importOriginal) => {
  const { reactHooks } = await import("../fixtures/hook-runtime.ts");

  return {
    ...(await importOriginal()),
    // SAFETY: the stand-in implements the part of React the hooks call.
    ...(reactHooks as unknown as Partial<typeof ReactModule>),
  };
});

function clientFor(
  tenant: string | undefined,
  topic: ReturnType<typeof fakeTopic>,
  blocks: Record<string, unknown> = {},
): ClientLike {
  // SAFETY: the hooks read only `supabase`, `auth`, `tenant`, `ports` and `blocks`.
  return {
    supabase: rpc.supabase,
    auth: { current: () => signedIn(), subscribe: () => () => undefined },
    ports: { topic: topic.port },
    blocks,
    ...(tenant === undefined ? {} : { tenant }),
  } as unknown as ClientLike;
}

const provider = (client: ClientLike) => (): void => {
  void BetterSupabaseProvider({ client });
};

describe("messaging hooks", () => {
  it("follows a conversation or a thread on the configured topic", async () => {
    rpc.calls.length = 0;

    const topic = fakeTopic();

    const client = clientFor("org-1", topic, {
      messaging: { options: { topic: "chat" } },
    });

    const view = renderHook(
      () =>
        useMessages({
          conversationId: "c1",
          threadId: "m1",
          limit: 10,
          markRead: false,
        }),
      undefined,
      provider(client),
    );

    await flush();
    expect(view.result.messages).toEqual([]);
    expect(topic.open()).toEqual(["chat:c1"]);
    expect(rpc.calls.map((call) => call.fn)).not.toContain(
      "mark_conversation_read",
    );
    view.unmount();
  });

  it("waits without a tenant or a conversation", async () => {
    rpc.calls.length = 0;

    const topic = fakeTopic();

    const outside = renderHook(
      () => useMessages({ conversationId: "c1" }),
      undefined,
      provider(clientFor(undefined, topic)),
    );

    await flush();
    expect(outside.result.messages).toBeUndefined();
    outside.unmount();

    const unset = renderHook(
      () => useMessages({ conversationId: undefined }),
      undefined,
      provider(clientFor("org-1", topic)),
    );

    await flush();
    expect(unset.result.messages).toBeUndefined();
    unset.unmount();
    expect(rpc.calls).toEqual([]);
  });

  it("lists conversations by kind, and waits without a tenant", async () => {
    rpc.calls.length = 0;

    const topic = fakeTopic();

    const channels = renderHook(
      () => useConversations({ kinds: ["channel"], limit: 5 }),
      undefined,
      provider(clientFor("org-1", topic)),
    );

    await flush();
    expect(channels.result.conversations).toEqual([]);
    expect(rpc.calls).toHaveLength(1);
    channels.unmount();

    const outside = renderHook(
      () => useConversations(),
      undefined,
      provider(clientFor(undefined, topic)),
    );

    await flush();
    expect(outside.result.conversations).toBeUndefined();
    expect(rpc.calls).toHaveLength(1);
    outside.unmount();
  });
});
