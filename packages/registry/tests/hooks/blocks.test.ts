import type { QueryClient } from "@tanstack/query-core";
import type { AuthSnapshot } from "better-supabase/client";
import type { ClientLike } from "better-supabase/react";
import type * as ReactModule from "react";

import { toStandardJsonSchema } from "@valibot/to-json-schema";
import { ok } from "better-supabase";
import { defineChecklist } from "better-supabase/blocks/onboarding";
import { defineSettings } from "better-supabase/blocks/settings";
import { undoToken } from "better-supabase/blocks/undo";
import { BetterSupabaseProvider, tenantOf } from "better-supabase/react";
import * as v from "valibot";
import { afterEach, describe, expect, it, vi } from "vitest";

import {
  useAiChats,
  useAiChatTree,
  useAiModels,
  useAiShare,
} from "../../items/hooks/use-ai-chat.ts";
import { useAnnouncements } from "../../items/hooks/use-announcements.ts";
import { useApiKeys } from "../../items/hooks/use-api-keys.ts";
import { useAuditLog } from "../../items/hooks/use-audit.ts";
import { usePlanPicker } from "../../items/hooks/use-billing.ts";
import { useComments } from "../../items/hooks/use-comments.ts";
import { useFeatureGate } from "../../items/hooks/use-entitlements.ts";
import { useNotifications } from "../../items/hooks/use-notifications.ts";
import { useOnboarding } from "../../items/hooks/use-onboarding.ts";
import {
  useInvitations,
  useMembers,
  useOrganizations,
} from "../../items/hooks/use-organizations.ts";
import { useReactions } from "../../items/hooks/use-reactions.ts";
import { useSavedViews } from "../../items/hooks/use-saved-views.ts";
import { useSettings } from "../../items/hooks/use-settings.ts";
import { useTagInput } from "../../items/hooks/use-tags.ts";
import { useUndoStack } from "../../items/hooks/use-undo.ts";
import { useUsageMeter } from "../../items/hooks/use-usage.ts";
import {
  useWorkflowCanvasRun,
  useWorkflowEditor,
} from "../../items/hooks/use-workflow-editor.ts";
import {
  useWorkflowRun,
  useWorkflowRuns,
} from "../../items/hooks/use-workflows.ts";

/**
 * A synchronous hook runtime standing in for React's dispatcher: no DOM
 * renderer is installed, and effects are what these hooks are about. Effects
 * run after each render; state updates re-render.
 */
const runtime = vi.hoisted(() => {
  interface Slot {
    value?: unknown;
    deps?: readonly unknown[] | undefined;
    cleanup?: (() => void) | undefined;
    setter?: (next: unknown) => void;
    subscribe?: unknown;
  }

  const state = {
    slots: [] as Slot[],
    index: 0,
    pending: [] as (() => void)[],
    provided: new Map<object, unknown>(),
    rendering: false,
    flushing: false,
    dirty: false,
    renders: 0,
    render: (() => undefined) as () => void,
  };

  const slot = (): Slot => {
    const index = state.index;
    state.index += 1;

    return (state.slots[index] ??= {});
  };

  const changed = (
    before: readonly unknown[] | undefined,
    after: readonly unknown[] | undefined,
  ): boolean =>
    before === undefined ||
    after === undefined ||
    before.length !== after.length ||
    before.some((value, index) => !Object.is(value, after[index]));

  const schedule = (): void => {
    if (state.rendering || state.flushing) {
      state.dirty = true;
    } else {
      state.render();
    }
  };

  return { state, slot, changed, schedule };
});

vi.mock(import("react"), async (importOriginal) => {
  const actual = await importOriginal();
  const { state, slot, changed, schedule } = runtime;

  const standIn = {
    createElement: (
      type: unknown,
      props: { value?: unknown } | null,
      ...children: unknown[]
    ) => {
      // A context object is its own provider in React 19.
      if (typeof type === "object" && type !== null && "Consumer" in type) {
        state.provided.set(type, props?.value);
      }

      return { type, props, children };
    },
    // The only context here is the browser context, whose default is null.
    useContext: (context: object) => state.provided.get(context) ?? null,
    useState: (initial: unknown) => {
      const cell = slot();

      if (!cell.setter) {
        cell.value = typeof initial === "function" ? initial() : initial;
        cell.setter = (next) => {
          const value = typeof next === "function" ? next(cell.value) : next;

          if (Object.is(value, cell.value)) {
            return;
          }

          cell.value = value;
          schedule();
        };
      }

      return [cell.value, cell.setter];
    },
    useRef: (initial: unknown) => {
      const cell = slot();

      if (!("value" in cell)) {
        cell.value = { current: initial };
      }

      return cell.value;
    },
    useMemo: (factory: () => unknown, deps: readonly unknown[]) => {
      const cell = slot();

      if (changed(cell.deps, deps)) {
        cell.value = factory();
        cell.deps = deps;
      }

      return cell.value;
    },
    useCallback: (fn: unknown, deps: readonly unknown[]) => {
      const cell = slot();

      if (changed(cell.deps, deps)) {
        cell.value = fn;
        cell.deps = deps;
      }

      return cell.value;
    },
    useEffect: (
      effect: () => (() => void) | undefined,
      deps?: readonly unknown[],
    ) => {
      const cell = slot();

      if (!changed(cell.deps, deps)) {
        return;
      }

      cell.deps = deps;
      state.pending.push(() => {
        cell.cleanup?.();
        const cleanup = effect();
        cell.cleanup = typeof cleanup === "function" ? cleanup : undefined;
      });
    },
    // Transitions run at once here; a rejected async one is the boundary's.
    useTransition: () => [
      false,
      (fn: () => unknown) => {
        const result = fn();

        if (result instanceof Promise) {
          result.catch(() => undefined);
        }
      },
    ],
    useSyncExternalStore: (
      subscribe: (listener: () => void) => () => void,
      getSnapshot: () => unknown,
    ) => {
      const cell = slot();

      if (cell.subscribe !== subscribe) {
        cell.cleanup?.();
        cell.subscribe = subscribe;
        cell.cleanup = subscribe(() => {
          if (!Object.is(getSnapshot(), cell.value)) {
            schedule();
          }
        });
      }

      cell.value = getSnapshot();

      return cell.value;
    },
  };

  return {
    ...actual,
    // SAFETY: the stand-in implements the part of React the hooks call.
    ...(standIn as unknown as Partial<typeof ReactModule>),
  };
});

/** Renders the provider and `hook` together; returns the latest result. */
function renderHook<P, R>(
  hook: (props: P) => R,
  initial: P,
  provider: { client: ClientLike; queryClient?: QueryClient } | null,
) {
  const { state } = runtime;
  state.slots = [];
  state.provided = new Map();
  state.renders = 0;
  let props = initial;
  const out: { result?: R; error?: Error } = {};
  // Effects set `dirty` through state updates, which control flow can't see.
  const dirty = (): boolean => state.dirty;
  state.render = () => {
    do {
      state.dirty = false;
      state.rendering = true;
      state.index = 0;
      state.renders += 1;

      try {
        if (provider) {
          void BetterSupabaseProvider(provider);
        }

        out.result = hook(props);
        delete out.error;
      } catch (cause) {
        out.error = cause instanceof Error ? cause : new Error(String(cause));
      } finally {
        state.rendering = false;
      }

      state.flushing = true;

      try {
        for (const effect of state.pending.splice(0)) {
          effect();
        }
      } finally {
        state.flushing = false;
      }
    } while (dirty());
  };

  state.render();

  return {
    get result(): R {
      if (out.error) {
        throw out.error;
      }

      return out.result!;
    },
    get error() {
      return out.error;
    },
    rerender(next: P) {
      props = next;
      state.render();
    },
    unmount() {
      for (const cell of state.slots) {
        cell.cleanup?.();
      }

      state.slots = [];
      state.render = () => undefined;
    },
  };
}

const USER = "00000000-0000-4000-8000-0000000000aa";
const OTHER = "00000000-0000-4000-8000-0000000000bb";
const LOADING: AuthSnapshot = { status: "loading", user: null, claims: null };

const SIGNED_OUT: AuthSnapshot = {
  status: "signed-out",
  user: null,
  claims: null,
};

const signedIn = (
  id: string,
  claims: Record<string, unknown> = {},
): AuthSnapshot => ({
  status: "signed-in",
  user: { id },
  claims: { sub: id, ...claims },
});

type Listener = (message: { event: string; payload: unknown }) => void;

function fakeRealtime() {
  const channels = new Map<
    string,
    { broadcast: Set<Listener>; status?: (status: string) => void }
  >();

  const client = {
    channel: vi.fn((topic: string, _options?: unknown) => {
      const entry = { broadcast: new Set<Listener>() } as {
        broadcast: Set<Listener>;
        status?: (status: string) => void;
      };

      channels.set(topic, entry);

      const channel = {
        topic,
        on: (_type: string, _filter: unknown, listener: Listener) => {
          entry.broadcast.add(listener);

          return channel;
        },
        subscribe: (callback: (status: string) => void) => {
          entry.status = callback;
          queueMicrotask(() => {
            callback("SUBSCRIBED");
          });

          return channel;
        },
      };

      return channel;
    }),
    removeChannel: vi.fn(async (channel: { topic: string }) => {
      channels.delete(channel.topic);

      return "ok" as const;
    }),
    realtime: { setAuth: vi.fn(async () => undefined) },
  };

  const emit = (topic: string, event: string, payload: unknown = {}) => {
    for (const listener of channels.get(topic)?.broadcast ?? []) {
      listener({ event, payload });
    }
  };

  return { client, channels, emit };
}

function fakeBrowser(initial: AuthSnapshot, run?: ClientLike["db"]) {
  let snapshot = initial;
  const listeners = new Set<() => void>();
  const realtime = fakeRealtime();

  const browser = {
    supabase: realtime.client,
    auth: {
      current: () => snapshot,
      subscribe: (listener: () => void) => {
        listeners.add(listener);

        return () => void listeners.delete(listener);
      },
    },
    tenant: () => tenantOf(snapshot),
    db: run ?? { name: "db" },
    queries: { name: "queries" },
  } as unknown as ClientLike;

  const setAuth = (next: AuthSnapshot) => {
    snapshot = next;

    for (const listener of [...listeners]) {
      listener();
    }
  };

  return { browser, setAuth, listeners, ...realtime };
}

const flush = () =>
  new Promise((resolve) => {
    setTimeout(resolve, 0);
  });

afterEach(() => {
  runtime.state.render = () => undefined;
});

describe("useNotifications", () => {
  const topic = `notifications:${USER}`;

  it("loads, merges sources, counts unread and reloads on broadcasts and rejoins", async () => {
    const { browser, emit, channels, client } = fakeBrowser(signedIn(USER));

    const load = vi.fn(async () => [
      { id: "a", readAt: null },
      { id: "b", readAt: "2026-01-01T00:00:00Z" },
    ]);

    const running = vi.fn(async () => [{ id: "job", readAt: null }]);
    const onMessage = vi.fn();

    const view = renderHook(
      () => useNotifications({ topic, load, sources: [running], onMessage }),
      undefined,
      { client: browser },
    );

    await flush();
    await flush();
    expect(view.result.items?.map((item) => item.id)).toEqual([
      "a",
      "b",
      "job",
    ]);
    expect(view.result.count).toBe(2);
    expect(view.result.status).toBe("subscribed");
    expect(client.channel.mock.calls[0]).toEqual([
      topic,
      { config: { private: true, broadcast: { self: false } } },
    ]);

    emit(topic, "notification_created", { id: "x" });
    await flush();
    expect(onMessage).toHaveBeenCalledWith("notification_created", { id: "x" });
    expect(load).toHaveBeenCalledTimes(2);

    channels.get(topic)!.status!("SUBSCRIBED");
    await flush();
    expect(load).toHaveBeenCalledTimes(3);
    channels.get(topic)!.status!("CHANNEL_ERROR");
    expect(view.result.status).toBe("error");

    view.unmount();
    await flush();
    expect(client.removeChannel).toHaveBeenCalledOnce();
  });

  it("loads once without a topic, sorts, counts its own way and keeps the error", async () => {
    const { browser, client } = fakeBrowser(signedIn(USER));
    let fail = false;

    const load = vi.fn(async () => {
      if (fail) {
        throw new Error("offline");
      }

      return [{ at: 1 }, { at: 3 }, { at: 2 }];
    });

    const view = renderHook(
      () =>
        useNotifications({
          topic: null,
          load,
          sort: (a, b) => b.at - a.at,
          count: (items) => items.length * 10,
        }),
      undefined,
      { client: browser },
    );

    await flush();
    expect(view.result.items).toEqual([{ at: 3 }, { at: 2 }, { at: 1 }]);
    expect(view.result.count).toBe(30);
    expect(client.channel).not.toHaveBeenCalled();

    fail = true;
    await view.result.refresh();
    expect((view.result.error as Error).message).toBe("offline");
    expect(view.result.items).toHaveLength(3);
    view.unmount();
  });

  it("waits for a signed-in user", async () => {
    const { browser } = fakeBrowser(SIGNED_OUT);
    const load = vi.fn(async () => []);

    const view = renderHook(
      () => useNotifications({ topic, load }),
      undefined,
      { client: browser },
    );

    await flush();
    expect(load).not.toHaveBeenCalled();
    expect(view.result).toMatchObject({ items: undefined, count: 0 });
    view.unmount();
  });
});

/** Answers `client.schema(name).rpc(fn, args)` from `answer`. */
function withRpc(
  client: object,
  answer: (fn: string, args: Record<string, unknown>) => unknown,
) {
  const rpc = vi.fn(async (fn: string, args: Record<string, unknown>) => {
    try {
      return { data: await answer(fn, args), error: null };
    } catch (cause) {
      return {
        data: null,
        error: { message: (cause as Error).message, code: "P0001" },
      };
    }
  });

  Object.assign(client, { schema: vi.fn(() => ({ rpc })) });

  return rpc;
}

describe("useOnboarding", () => {
  const profile = defineChecklist({
    id: "profile",
    scope: "user",
    steps: [{ id: "avatar" }, { id: "bio" }],
  });

  const team = defineChecklist({
    id: "team",
    scope: "organization",
    steps: [{ id: "invite" }],
  });

  it("loads the user's progress and reloads after completing a step", async () => {
    const { browser, client } = fakeBrowser(signedIn(USER));
    const done = new Set<string>();
    let fail = false;

    const rpc = withRpc(client, (fn, args) => {
      if (fail) {
        throw new Error("offline");
      }

      if (fn === "complete_onboarding_step") {
        done.add(String(args["step"]));
      }

      if (fn === "reset_onboarding_step") {
        done.delete(String(args["step"]));
      }

      return fn === "onboarding_progress"
        ? [...done].map((step) => ({
            step,
            completedAt: "2026-01-01T00:00:00Z",
          }))
        : true;
    });

    const view = renderHook(() => useOnboarding(profile), undefined, {
      client: browser,
    });

    await flush();
    expect(view.result.progress).toMatchObject({
      completed: 0,
      total: 2,
      done: false,
    });
    expect(rpc).toHaveBeenCalledWith("onboarding_progress", {
      checklist: "profile",
      tenant: null,
    });

    await view.result.complete("avatar");
    await flush();
    expect(view.result.progress?.next?.id).toBe("bio");
    await view.result.complete("bio");
    await flush();
    expect(view.result.progress?.done).toBe(true);
    await view.result.reset("bio");
    await flush();
    expect(view.result.progress?.completed).toBe(1);

    fail = true;
    await view.result.complete("bio");
    await flush();
    expect(view.result.error?.message).toBe("offline");
    await view.result.refresh();
    expect(view.result.progress?.completed).toBe(1);
    view.unmount();
  });

  it("waits for an organization on an organization checklist", async () => {
    const { browser, client } = fakeBrowser(signedIn(USER));
    const rpc = withRpc(client, () => []);

    const view = renderHook(
      (organizationId: string | null) =>
        useOnboarding(team, { organizationId, schema: "app" }),
      null as string | null,
      { client: browser },
    );

    await flush();
    expect(rpc).not.toHaveBeenCalled();
    view.rerender("org-1");
    await flush();
    expect(rpc).toHaveBeenCalledWith("onboarding_progress", {
      checklist: "team",
      tenant: "org-1",
    });
    expect(view.result.progress?.total).toBe(1);
    view.unmount();
  });
});

describe("useAnnouncements", () => {
  const row = (id: string) => ({
    id,
    title: `Title ${id}`,
    body: "",
    severity: "warning",
    starts_at: "2026-01-01T00:00:00Z",
    dismissible: true,
    created_at: "2026-01-01T00:00:00Z",
    updated_at: "2026-01-01T00:00:00Z",
  });

  it("loads, reloads on broadcasts and drops dismissed ones", async () => {
    const { browser, client, emit } = fakeBrowser(signedIn(USER));
    let rows = [row("a"), row("b")];
    let fail = false;

    const rpc = withRpc(client, (fn) => {
      if (fn === "dismiss_announcement" && fail) {
        throw new Error("not dismissible");
      }

      return fn === "active_announcements" ? rows : true;
    });

    const view = renderHook(
      () => useAnnouncements({ organizationId: "org-1" }),
      undefined,
      { client: browser },
    );

    await flush();
    await flush();
    expect(view.result.items?.map((item) => item.id)).toEqual(["a", "b"]);
    expect(view.result.items?.[0]?.severity).toBe("warning");
    expect(view.result.status).toBe("subscribed");
    expect(rpc).toHaveBeenCalledWith("active_announcements", {
      tenant: "org-1",
    });

    rows = [row("a"), row("b"), row("c")];
    emit("announcements", "announcement_changed", { id: "c" });
    await flush();
    expect(view.result.items).toHaveLength(3);

    await view.result.dismiss("a");
    expect(view.result.items?.map((item) => item.id)).toEqual(["b", "c"]);
    fail = true;
    await view.result.dismiss("b");
    expect(view.result.error?.message).toBe("not dismissible");
    await view.result.refresh();
    expect(view.result.error).toBeUndefined();
    view.unmount();
    await flush();
    expect(client.removeChannel).toHaveBeenCalledOnce();
  });

  it("loads once without a topic and waits for a signed-in user", async () => {
    const signedOut = fakeBrowser(SIGNED_OUT);
    const idle = withRpc(signedOut.client, () => []);

    const waiting = renderHook(() => useAnnouncements(), undefined, {
      client: signedOut.browser,
    });

    await flush();
    expect(idle).not.toHaveBeenCalled();
    waiting.unmount();

    const { browser, client } = fakeBrowser(signedIn(USER));
    withRpc(client, () => {
      throw new Error("offline");
    });

    const view = renderHook(
      () => useAnnouncements({ topic: null, schema: "app" }),
      undefined,
      { client: browser },
    );

    await flush();
    expect(client.channel).not.toHaveBeenCalled();
    expect(view.result.error?.message).toBe("offline");
    view.unmount();
  });
});

describe("useReactions", () => {
  it("loads, toggles and reloads when a watched subject changes", async () => {
    const { browser, client, emit } = fakeBrowser(
      signedIn(USER, { tenant_id: "org-1" }),
    );

    Object.assign(browser, {
      blocks: {
        reactions: { schema: "better_supabase", options: { topic: "emoji" } },
      },
    });
    let counts = [{ emoji: "👍", count: 1, reacted: false, actors: ["u2"] }];

    const rpc = withRpc(client, (fn, args) => {
      if (fn === "react") {
        return [
          {
            emoji: args["emoji"],
            count: args["present"] ? 2 : 0,
            reacted: args["present"],
            actors: [],
          },
        ];
      }

      return { c1: counts, c2: [] };
    });

    const view = renderHook(
      () =>
        useReactions({
          subjects: [
            { type: "comment", id: "c1" },
            { type: "comment", id: "c2" },
          ],
        }),
      undefined,
      { client: browser },
    );

    await flush();
    await flush();
    expect(view.result.reactions?.["comment:c1"]?.[0]?.count).toBe(1);
    expect(client.channel.mock.calls.map(([topic]) => topic)).toContain(
      "emoji:org-1",
    );
    expect(rpc).toHaveBeenCalledWith("reaction_summary", {
      tenant: "org-1",
      subject_type: "comment",
      subject_ids: ["c1", "c2"],
    });

    await view.result.toggle({
      subject: { type: "comment", id: "c1" },
      emoji: "👍",
    });
    expect(rpc).toHaveBeenLastCalledWith("react", {
      tenant: "org-1",
      subject_type: "comment",
      subject_id: "c1",
      emoji: "👍",
      present: true,
      actor: null,
    });
    expect(view.result.reactions?.["comment:c1"]?.[0]).toMatchObject({
      count: 2,
      reacted: true,
    });
    await view.result.toggle({
      subject: { type: "comment", id: "c1" },
      emoji: "👍",
    });
    expect(rpc).toHaveBeenLastCalledWith(
      "react",
      expect.objectContaining({ present: false }),
    );

    const calls = rpc.mock.calls.length;
    emit("emoji:org-1", "changed", {
      subjectType: "comment",
      subjectId: "other",
    });
    await flush();
    expect(rpc).toHaveBeenCalledTimes(calls);
    counts = [{ emoji: "🎉", count: 1, reacted: false, actors: ["u3"] }];
    emit("emoji:org-1", "changed", { subjectType: "comment", subjectId: "c2" });
    await flush();
    expect(view.result.reactions?.["comment:c1"]?.[0]?.emoji).toBe("🎉");
    view.unmount();
  });
});

describe("useComments", () => {
  const row = (id: string, body: string, deleted = false) => ({
    id,
    tenant_id: "org-1",
    conversation_id: "conv-1",
    subject_type: "customer",
    subject_id: "cu1",
    author_id: USER,
    body: deleted ? "" : body,
    mentions: [],
    sent_at: "2026-01-01T00:00:00Z",
    created_at: "2026-01-01T00:00:00Z",
    deleted_at: deleted ? "2026-01-02T00:00:00Z" : null,
  });

  it("loads the thread, adds and removes, and reloads for the conversation's topic", async () => {
    const { browser, client, emit } = fakeBrowser(
      signedIn(USER, { tenant_id: "org-1" }),
    );

    Object.assign(browser, {
      blocks: {
        comments: { schema: "better_supabase", api: "api", options: {} },
        messaging: {
          schema: "better_supabase",
          api: "api",
          options: { topic: "chat" },
        },
      },
    });
    let thread = [row("c1", "First")];

    const rpc = withRpc(client, (fn, args) => {
      if (fn === "create_comment") {
        return row("c2", String(args["body"]));
      }

      if (fn === "comment_conversation") {
        return "conv-1";
      }

      if (fn === "delete_message") {
        thread = [row("c1", "First", true)];

        return true;
      }

      if (fn === "get_comment") {
        return (
          thread.find((each) => each.id === args["message"]) ??
          row(String(args["message"]), "Pinged")
        );
      }

      return thread;
    });

    const view = renderHook(
      () => useComments({ subject: { type: "customer", id: "cu1" } }),
      undefined,
      { client: browser },
    );

    await flush();
    await flush();
    expect(view.result.comments?.map((comment) => comment.body)).toEqual([
      "First",
    ]);

    const { schema: toSchema } = client as unknown as {
      schema: ReturnType<typeof vi.fn>;
    };

    expect(toSchema).toHaveBeenCalledWith("api");
    expect(rpc).toHaveBeenCalledWith(
      "list_comments",
      expect.objectContaining({ tenant: "org-1", subject_id: "cu1" }),
    );

    expect((await view.result.add({ body: "Second" })).ok).toBe(true);
    expect(rpc).toHaveBeenLastCalledWith(
      "create_comment",
      expect.objectContaining({ body: "Second", subject_type: "customer" }),
    );
    expect(view.result.comments?.map((comment) => comment.id)).toEqual([
      "c1",
      "c2",
    ]);

    expect((await view.result.remove("c1")).ok).toBe(true);
    expect(view.result.comments?.[0]?.deletedAt).toBeDefined();

    const calls = rpc.mock.calls.length;
    emit("chat:conv-1", "message", {});
    emit("chat:conv-1", "message", { messageId: "c3" });
    await flush();
    expect(rpc).toHaveBeenCalledTimes(calls + 1);
    expect(rpc).toHaveBeenLastCalledWith("get_comment", { message: "c3" });
    expect(view.result.comments?.map((comment) => comment.id)).toEqual([
      "c1",
      "c2",
      "c3",
    ]);
    view.unmount();
  });

  it("waits without an organization", async () => {
    const { browser, client } = fakeBrowser(signedIn(USER));
    const rpc = withRpc(client, () => []);

    const view = renderHook(
      () => useComments({ subject: { type: "customer", id: "cu1" } }),
      undefined,
      { client: browser },
    );

    await flush();
    expect(view.result.comments).toBeUndefined();
    expect((await view.result.add({ body: "Hi" })).ok).toBe(false);
    expect(rpc).not.toHaveBeenCalled();
    view.unmount();
  });
});

describe("useOrganizations", () => {
  const rows = [
    { id: "org-1", name: "Acme", role: "admin", attributes: {} },
    { id: "org-2", name: "Globex", role: "member", attributes: {} },
  ];

  it("lists the organizations, switches and refreshes the session", async () => {
    const { browser, client, setAuth } = fakeBrowser(
      signedIn(USER, { tenant_id: "org-1" }),
    );

    const refreshSession = vi.fn(async () => {
      setAuth(signedIn(USER, { tenant_id: "org-2" }));

      return { data: {}, error: null };
    });

    Object.assign(client, { auth: { refreshSession } });

    const rpc = withRpc(client, (fn) =>
      fn === "switch_organization"
        ? { organization_id: "org-2", refresh: true }
        : rows,
    );

    const view = renderHook(() => useOrganizations(), undefined, {
      client: browser,
    });

    await flush();
    await flush();
    expect(view.result.organizations?.map((each) => each.name)).toEqual([
      "Acme",
      "Globex",
    ]);
    expect(view.result.active?.name).toBe("Acme");

    expect((await view.result.switchTo("org-2")).ok).toBe(true);
    expect(rpc).toHaveBeenCalledWith("switch_organization", {
      organization: "org-2",
    });
    expect(refreshSession).toHaveBeenCalledOnce();
    expect(view.result.activeId).toBe("org-2");
    expect(view.result.active?.name).toBe("Globex");
    expect(view.result.switching).toBeUndefined();
    view.unmount();
  });

  it("takes a loader, the server's rows and a switch callback", async () => {
    const { browser, client } = fakeBrowser(LOADING);

    const rpc = withRpc(client, () => ({
      organization_id: "org-2",
      refresh: true,
    }));

    const load = vi.fn(async () => [{ id: "org-2", plan: "pro" }]);
    const onSwitched = vi.fn();

    const view = renderHook(
      () =>
        useOrganizations({
          load,
          initial: [{ id: "org-1", plan: "free" }],
          activeId: "org-1",
          onSwitched,
        }),
      undefined,
      { client: browser },
    );

    await flush();
    expect(view.result.active?.plan).toBe("free");
    expect(load).not.toHaveBeenCalled();

    await view.result.switchTo("org-2");
    expect(onSwitched).toHaveBeenCalledWith({
      organizationId: "org-2",
      refresh: true,
    });
    expect(load).toHaveBeenCalledOnce();
    expect(view.result.organizations).toEqual([{ id: "org-2", plan: "pro" }]);
    expect(rpc).toHaveBeenCalledOnce();
    view.unmount();
  });
});

describe("usePlanPicker", () => {
  const catalog = {
    plans: [
      { key: "free", name: "Free" },
      { key: "pro", name: "Pro" },
    ],
    current: "free",
  };

  it("loads the plans and opens the URL the checkout action returns", async () => {
    const { browser } = fakeBrowser(signedIn(USER));
    const load = vi.fn(async () => catalog);

    const checkout = vi.fn(async (_plan: string) =>
      ok<{ url: string | undefined }>({
        url: "https://checkout.stripe.test/c/pay",
      }),
    );

    const open = vi.fn();

    const view = renderHook(
      () => usePlanPicker({ load, checkout, open }),
      undefined,
      { client: browser },
    );

    await flush();
    expect(view.result.active?.name).toBe("Free");
    expect((await view.result.choose("pro")).ok).toBe(true);
    expect(checkout).toHaveBeenCalledWith("pro");
    expect(open).toHaveBeenCalledWith("https://checkout.stripe.test/c/pay");
    view.unmount();
  });

  it("starts from the server's catalog", async () => {
    const { browser } = fakeBrowser(signedIn(USER));
    const load = vi.fn(async () => catalog);

    const view = renderHook(
      () =>
        usePlanPicker({
          load,
          initial: { ...catalog, current: "pro" },
          checkout: async () => ok({ url: undefined }),
          open: () => undefined,
        }),
      undefined,
      { client: browser },
    );

    await flush();
    expect(load).not.toHaveBeenCalled();
    expect(view.result.active?.key).toBe("pro");
    view.unmount();
  });
});

describe("useUsageMeter", () => {
  it("reads the organization's usage overview", async () => {
    const { browser, client } = fakeBrowser(signedIn(USER));

    const rpc = withRpc(client, () => [
      {
        meter: "api.calls",
        used: 10,
        limit: 40,
        remaining: 30,
        unlimited: false,
        period: "month",
        starts_at: "2026-10-01T00:00:00Z",
        resets_at: "2026-11-01T00:00:00Z",
      },
    ]);

    const view = renderHook(
      (organizationId: string | null) =>
        useUsageMeter({ organizationId, meters: ["api.calls"], schema: "api" }),
      null as string | null,
      { client: browser },
    );

    await flush();
    expect(rpc).not.toHaveBeenCalled();
    view.rerender("org-1");
    await flush();
    expect(rpc).toHaveBeenCalledWith("usage_overview", { tenant: "org-1" });
    expect(view.result.meters?.[0]).toMatchObject({
      meter: "api.calls",
      fraction: 0.25,
      exceeded: false,
    });
    view.unmount();
  });
});

describe("useFeatureGate", () => {
  it("opens when the session's plan gains the feature", async () => {
    const { browser, setAuth } = fakeBrowser(LOADING);

    const view = renderHook(() => useFeatureGate("exports"), undefined, {
      client: browser,
    });

    expect(view.result.allowed).toBeUndefined();
    setAuth(signedIn(USER, { tenant_id: "org-1", features: { "org-1": [] } }));
    await flush();
    expect(view.result.allowed).toBe(false);
    setAuth(
      signedIn(USER, {
        tenant_id: "org-1",
        features: { "org-1": ["exports"] },
      }),
    );
    await flush();
    expect(view.result.allowed).toBe(true);
    view.unmount();
  });

  it("checks another organization with a custom claim", async () => {
    const { browser } = fakeBrowser(
      signedIn(USER, { plan: { "org-2": ["e"] } }),
    );

    const view = renderHook(
      () =>
        useFeatureGate("exports", {
          organizationId: "org-2",
          claim: { claim: "plan", keys: { exports: "e" } },
          tenantClaim: "org",
        }),
      undefined,
      { client: browser },
    );

    await flush();
    expect(view.result.allowed).toBe(true);
    view.unmount();
  });
});

describe("useSettings", () => {
  const settings = defineSettings({
    user: {
      digest: { schema: toStandardJsonSchema(v.boolean()), default: true },
    },
    organization: {
      weekStart: {
        schema: toStandardJsonSchema(v.picklist(["monday", "sunday"])),
        default: "monday",
      },
    },
  });

  it("edits the caller's settings with fields from the definition", async () => {
    const { browser, client } = fakeBrowser(signedIn(USER));

    const rpc = withRpc(client, (fn) =>
      fn === "get_user_settings" ? { digest: false } : null,
    );

    const view = renderHook(
      () => useSettings(settings, { scope: "user" }),
      undefined,
      { client: browser },
    );

    await flush();
    expect(view.result.fields.map((field) => field.kind)).toEqual(["boolean"]);
    expect(view.result.values).toEqual({ digest: false });
    await view.result.set("digest", true);
    await flush();
    expect(rpc).toHaveBeenCalledWith("set_user_setting", {
      key: "digest",
      value: { value: true },
    });
    expect(view.result.values?.digest).toBe(true);
    view.unmount();
  });

  it("waits for an organization", async () => {
    const { browser, client } = fakeBrowser(signedIn(USER));
    const rpc = withRpc(client, () => ({ weekStart: "sunday" }));

    const view = renderHook(
      (organizationId: string | null) =>
        useSettings(settings, {
          scope: "organization",
          organizationId,
          schema: "api",
        }),
      null as string | null,
      { client: browser },
    );

    await flush();
    expect(rpc).not.toHaveBeenCalled();
    expect(view.result.fields[0]?.choices).toEqual(["monday", "sunday"]);
    view.rerender("org-1");
    await flush();
    expect(rpc).toHaveBeenCalledWith("get_organization_settings", {
      tenant: "org-1",
    });
    expect(view.result.values?.weekStart).toBe("sunday");
    view.unmount();
  });
});

describe("useMembers", () => {
  it("lists the members and changes a role through the browser client", async () => {
    const { browser, client } = fakeBrowser(signedIn(USER));

    const rpc = withRpc(client, (fn) =>
      fn === "list_members"
        ? [
            { user_id: USER, role: "owner" },
            { user_id: OTHER, role: "member" },
          ]
        : true,
    );

    const onChanged = vi.fn();

    const view = renderHook(
      () => useMembers({ organizationId: "org-1", schema: "api", onChanged }),
      undefined,
      { client: browser },
    );

    await flush();
    await flush();
    expect(view.result.members?.map((member) => member.role)).toEqual([
      "owner",
      "member",
    ]);
    expect(
      (await view.result.setRole({ userId: OTHER, role: "admin" })).ok,
    ).toBe(true);
    expect(rpc).toHaveBeenCalledWith("update_member_role", {
      organization: "org-1",
      member: OTHER,
      role: "admin",
    });
    expect(onChanged).toHaveBeenCalledWith(
      expect.objectContaining({ kind: "role", userId: OTHER }),
    );
    view.unmount();
  });

  it("takes a loader and the server's rows", async () => {
    const { browser, client } = fakeBrowser(signedIn(USER));
    const rpc = withRpc(client, () => true);

    const load = vi.fn(async () => [
      { userId: OTHER, role: "member", name: "Ada" },
    ]);

    const view = renderHook(
      () =>
        useMembers({
          organizationId: "org-1",
          load,
          initial: [{ userId: OTHER, role: "member", name: "Ada" }],
        }),
      undefined,
      { client: browser },
    );

    await flush();
    expect(load).not.toHaveBeenCalled();
    expect(view.result.members?.[0]?.name).toBe("Ada");
    await view.result.remove(OTHER);
    expect(rpc).toHaveBeenCalledWith("remove_member", {
      organization: "org-1",
      member: OTHER,
    });
    expect(load).toHaveBeenCalledWith("org-1");
    view.unmount();
  });
});

describe("useInvitations", () => {
  it("lists the open invitations and sends one", async () => {
    const { browser, client } = fakeBrowser(signedIn(USER));

    const rpc = withRpc(client, (fn, args) =>
      fn === "invite_member"
        ? {
            id: "inv-1",
            tenant: "org-1",
            email: args["invitee_email"],
            role: args["invitee_role"],
            expires_at: "2026-10-23T00:00:00Z",
            token: "token-1",
          }
        : [{ id: "inv-0", email: "a@b.c", role: "member" }],
    );

    const onChanged = vi.fn();

    const view = renderHook(
      () => useInvitations({ organizationId: "org-1", onChanged }),
      undefined,
      { client: browser },
    );

    await flush();
    await flush();
    expect(view.result.invitations?.map((each) => each.id)).toEqual(["inv-0"]);

    const result = await view.result.invite({
      email: "ada@example.com",
      role: "member",
    });

    expect(result.ok).toBe(true);
    expect(view.result.sent?.token).toBe("token-1");
    expect(rpc).toHaveBeenCalledWith(
      "invite_member",
      expect.objectContaining({
        tenant: "org-1",
        invitee_email: "ada@example.com",
      }),
    );
    expect(onChanged).toHaveBeenCalledWith(
      expect.objectContaining({ kind: "invited" }),
    );
    view.unmount();
  });

  it("takes a loader and the server's rows", async () => {
    const { browser, client } = fakeBrowser(signedIn(USER));
    withRpc(client, () => true);
    const load = vi.fn(async () => [{ id: "inv-2" }]);

    const view = renderHook(
      () =>
        useInvitations({
          organizationId: "org-1",
          load,
          initial: [{ id: "inv-1" }],
        }),
      undefined,
      { client: browser },
    );

    await flush();
    expect(load).not.toHaveBeenCalled();
    expect((await view.result.revoke("inv-1")).ok).toBe(true);
    expect(view.result.invitations).toEqual([{ id: "inv-2" }]);
    view.unmount();
  });
});

describe("useAuditLog", () => {
  it("loads a page, filters it and loads more", async () => {
    const { browser, client } = fakeBrowser(signedIn(USER));

    const entry = (id: string) => ({
      id,
      occurredAt: "2026-10-06T12:00:00Z",
      eventType: "invitation.created",
      actorId: USER,
    });

    const rpc = withRpc(client, (_fn, args) =>
      args["cursor_id"] === "e2" ? [entry("e3")] : [entry("e1"), entry("e2")],
    );

    const view = renderHook(
      () => useAuditLog({ organizationId: "org-1", limit: 2, schema: "api" }),
      undefined,
      { client: browser },
    );

    await flush();
    await flush();
    expect(view.result.entries?.map((each) => each.id)).toEqual(["e1", "e2"]);
    expect(view.result.hasMore).toBe(true);
    await view.result.loadMore();
    expect(view.result.entries?.map((each) => each.id)).toEqual([
      "e1",
      "e2",
      "e3",
    ]);
    expect(view.result.hasMore).toBe(false);
    await view.result.setFilters({ actorId: OTHER });
    expect(rpc).toHaveBeenLastCalledWith(
      "list_audit_events",
      expect.objectContaining({ for_tenants: ["org-1"], for_actors: [OTHER] }),
    );
    expect(view.result.filters).toEqual({ actorId: OTHER });
    view.unmount();
  });
});

describe("useApiKeys", () => {
  it("lists the keys, creates one and revokes one", async () => {
    const { browser, client } = fakeBrowser(signedIn(USER));

    const key = (id: string, created: string) => ({
      id,
      organization_id: "org-1",
      name: id,
      prefix: "bs",
      public_id: `p${id}`,
      scopes: [],
      created_at: created,
      state: "active",
    });

    const rpc = withRpc(client, (fn) => {
      if (fn === "create_api_key") {
        return key("k3", "2026-10-03T00:00:00Z");
      }

      if (fn === "revoke_api_key") {
        return true;
      }

      return [
        key("k1", "2026-10-01T00:00:00Z"),
        key("k2", "2026-10-02T00:00:00Z"),
      ];
    });

    const view = renderHook(
      () => useApiKeys({ organizationId: "org-1", schema: "api" }),
      undefined,
      { client: browser },
    );

    await flush();
    await flush();
    expect(view.result.keys?.map((each) => each.id)).toEqual(["k2", "k1"]);
    const created = await view.result.create({ name: "CI" });
    expect(created.ok).toBe(true);
    expect(view.result.created?.token).toMatch(/^bs_/);
    expect(rpc).toHaveBeenCalledWith(
      "create_api_key",
      expect.objectContaining({ name: "CI", tenant: "org-1" }),
    );
    view.result.dismiss();
    expect(view.result.created).toBeUndefined();
    expect((await view.result.revoke("k1")).ok).toBe(true);
    expect(rpc).toHaveBeenCalledWith("revoke_api_key", { key: "k1" });
    view.unmount();
  });
});

describe("useTagInput", () => {
  it("loads the subject's tags and adds, creates and removes one", async () => {
    const { browser, client } = fakeBrowser(
      signedIn(USER, { tenant_id: "org-1" }),
    );

    Object.assign(browser, {
      blocks: { tags: { schema: "better_supabase", api: "api", options: {} } },
    });

    const rpc = withRpc(client, (fn) => {
      if (fn === "subject_tags") {
        return [{ id: "t1", name: "VIP", slug: "vip" }];
      }

      if (fn === "list_tags") {
        return [
          { id: "t1", name: "VIP", slug: "vip" },
          { id: "t2", name: "Churn risk", slug: "churn-risk" },
        ];
      }

      if (fn === "create_tag") {
        return { id: "t3", slug: "new", rank: "V" };
      }

      return true;
    });

    const onChanged = vi.fn();

    const view = renderHook(
      () =>
        useTagInput({
          subject: { type: "customer", id: "cu1" },
          kind: "customer",
          onChanged,
        }),
      undefined,
      { client: browser },
    );

    await flush();
    await flush();
    expect(view.result.tags?.map((tag) => tag.name)).toEqual(["VIP"]);
    expect(view.result.available).toHaveLength(2);
    expect((await view.result.add("t2")).ok).toBe(true);
    expect(rpc).toHaveBeenCalledWith("tag", {
      tenant: "org-1",
      subject_type: "customer",
      subject_id: "cu1",
      tag_id: "t2",
    });
    expect((await view.result.create("New")).ok).toBe(true);
    expect(view.result.tags?.map((tag) => tag.id)).toEqual(["t1", "t2", "t3"]);
    expect(onChanged).toHaveBeenLastCalledWith(
      expect.objectContaining({ kind: "added", created: true }),
    );
    expect((await view.result.remove("t1")).ok).toBe(true);
    expect(view.result.tags?.map((tag) => tag.id)).toEqual(["t2", "t3"]);
    view.unmount();
  });
});

describe("workflow run hooks", () => {
  const run = (id: string, status = "running") => ({
    id,
    engine: "workflow-sdk",
    externalId: `wrun_${id}`,
    definition: "onboard",
    tenant: "t1",
    actor: USER,
    status,
    attributes: {},
    error: null,
    createdAt: "2026-01-01T00:00:00Z",
    updatedAt: "2026-01-01T00:00:00Z",
    startedAt: null,
    completedAt: null,
    cancelRequestedAt: null,
  });

  it("lists a tenant's runs and reloads on status broadcasts", async () => {
    const { browser, client, emit } = fakeBrowser(signedIn(USER));
    let rows = [run("a")];
    let fail = false;

    const rpc = withRpc(client, () => {
      if (fail) {
        throw new Error("offline");
      }

      return rows;
    });

    const view = renderHook(
      () =>
        useWorkflowRuns({
          tenant: "t1",
          definition: "onboard",
          status: "running",
          limit: 10,
          schema: "app",
        }),
      undefined,
      { client: browser },
    );

    await flush();
    await flush();
    expect(view.result.runs?.map((entry) => entry.id)).toEqual(["a"]);
    expect(view.result.status).toBe("subscribed");
    expect(rpc).toHaveBeenCalledWith("workflow_runs_list", {
      tenant: "t1",
      definition: "onboard",
      status: "running",
      max: 10,
      mode: "live",
    });

    rows = [run("a"), run("b")];
    emit("workflow-runs:t1", "workflow_run_changed", { id: "b" });
    await flush();
    expect(view.result.runs).toHaveLength(2);
    fail = true;
    await view.result.refresh();
    expect(view.result.error?.message).toBe("offline");
    expect(view.result.runs).toHaveLength(2);
    view.unmount();
    await flush();
    expect(client.removeChannel).toHaveBeenCalledOnce();
  });

  it("loads the user's own runs once without a tenant, after sign-in", async () => {
    const signedOut = fakeBrowser(SIGNED_OUT);
    const idle = withRpc(signedOut.client, () => []);

    const waiting = renderHook(() => useWorkflowRuns(), undefined, {
      client: signedOut.browser,
    });

    await flush();
    expect(idle).not.toHaveBeenCalled();
    waiting.unmount();

    const { browser, client } = fakeBrowser(signedIn(USER));
    withRpc(client, () => [run("a")]);

    const view = renderHook(() => useWorkflowRuns(), undefined, {
      client: browser,
    });

    await flush();
    expect(client.channel).not.toHaveBeenCalled();
    expect(view.result.runs).toHaveLength(1);
    view.unmount();
  });

  it("reads one run, watches its topic and cancels it", async () => {
    const { browser, client, emit } = fakeBrowser(signedIn(USER));
    let status = "running";
    let refuse = false;

    const rpc = withRpc(client, (fn) => {
      if (fn === "request_workflow_cancel") {
        if (refuse) {
          throw new Error("not allowed");
        }

        status = "cancelled";
      }

      return run("a", status);
    });

    const view = renderHook(
      () => useWorkflowRun("wrun_a", { schema: "app" }),
      undefined,
      { client: browser },
    );

    await flush();
    await flush();
    expect(view.result.run?.status).toBe("running");
    expect(view.result.status).toBe("subscribed");
    expect(client.channel.mock.calls[0]?.[0]).toBe("workflow-run:a");

    status = "waiting";
    emit("workflow-run:a", "workflow_run_changed");
    await flush();
    expect(view.result.run?.status).toBe("waiting");

    await view.result.cancel();
    expect(view.result.run?.status).toBe("cancelled");
    expect(rpc).toHaveBeenCalledWith("request_workflow_cancel", {
      run: "wrun_a",
    });
    refuse = true;
    await view.result.cancel();
    expect(view.result.error?.message).toBe("not allowed");
    view.unmount();
  });

  it("does nothing for a null run", async () => {
    const { browser, client } = fakeBrowser(signedIn(USER));
    const rpc = withRpc(client, () => null);

    const view = renderHook(() => useWorkflowRun(null), undefined, {
      client: browser,
    });

    await flush();
    await view.result.refresh();
    await view.result.cancel();
    expect(rpc).not.toHaveBeenCalled();
    expect(view.result.run).toBeUndefined();
    view.unmount();
  });

  it("keeps the error when a run can't be read", async () => {
    const { browser, client } = fakeBrowser(signedIn(USER));
    withRpc(client, () => {
      throw new Error("denied");
    });

    const view = renderHook(() => useWorkflowRun("a"), undefined, {
      client: browser,
    });

    await flush();
    expect(view.result.error?.message).toBe("denied");
    view.unmount();
  });
});

describe("workflow builder hooks", () => {
  const definition = {
    id: "d1",
    tenant: "t1",
    slug: "welcome",
    name: "Welcome",
    createdAt: "2026-01-01T00:00:00Z",
    updatedAt: "2026-01-01T00:00:00Z",
    published: 2,
    draft: true,
  };

  const step = {
    name: "email.send",
    title: "Send an email",
    inputSchema: { type: "object" },
  };

  const runRow = (status: string) => ({
    id: "r1",
    engine: "workflow-sdk",
    externalId: "wrun_r1",
    definition: "builder:d1",
    tenant: "t1",
    actor: USER,
    status,
    attributes: {},
    error: null,
    createdAt: "2026-01-01T00:00:00Z",
    updatedAt: "2026-01-01T00:00:00Z",
  });

  const nodeRow = (node: string, status: string) => ({
    run: "r1",
    node,
    status,
    attempts: 1,
  });

  it("lists a tenant's definitions and the step library after sign-in", async () => {
    const signedOut = fakeBrowser(SIGNED_OUT);
    const idle = withRpc(signedOut.client, () => []);

    const waiting = renderHook(() => useWorkflowEditor(), undefined, {
      client: signedOut.browser,
    });

    await flush();
    expect(idle).not.toHaveBeenCalled();
    expect(waiting.result.definitions).toBeUndefined();
    waiting.unmount();

    const { browser, client } = fakeBrowser(signedIn(USER));
    let failSteps = false;

    const rpc = withRpc(client, (fn) => {
      if (fn === "workflow_steps_list") {
        if (failSteps) {
          throw new Error("no steps");
        }

        return [step];
      }

      return [definition];
    });

    const view = renderHook(
      () => useWorkflowEditor({ tenant: "t1", schema: "app" }),
      undefined,
      { client: browser },
    );

    await flush();
    expect(view.result.definitions?.map((entry) => entry.slug)).toEqual([
      "welcome",
    ]);
    expect(view.result.definitions?.[0]?.published).toBe(2);
    expect(view.result.steps?.map((entry) => entry.name)).toEqual([
      "email.send",
    ]);
    expect(view.result.error).toBeUndefined();
    expect(rpc).toHaveBeenCalledWith("workflow_definitions_list", {
      tenant: "t1",
    });
    expect(typeof view.result.builder.definitions.upsert).toBe("function");

    failSteps = true;
    await view.result.refresh();
    expect(view.result.error?.message).toBe("no steps");
    expect(view.result.steps).toHaveLength(1);
    view.unmount();
  });

  it("keeps the definitions error first", async () => {
    const { browser, client } = fakeBrowser(signedIn(USER));
    withRpc(client, () => {
      throw new Error("denied");
    });

    const view = renderHook(() => useWorkflowEditor(), undefined, {
      client: browser,
    });

    await flush();
    expect(view.result.error?.message).toBe("denied");
    expect(view.result.definitions).toBeUndefined();
    view.unmount();
  });

  it("maps a run's node records by node and reloads on its topic", async () => {
    const { browser, client, emit } = fakeBrowser(signedIn(USER));
    let nodes = [nodeRow("lookup", "running")];
    let failNodes = false;

    const rpc = withRpc(client, (fn) => {
      if (fn === "workflow_node_runs_list") {
        if (failNodes) {
          throw new Error("no nodes");
        }

        return nodes;
      }

      return runRow("running");
    });

    const view = renderHook(
      () => useWorkflowCanvasRun("wrun_r1", { schema: "app" }),
      undefined,
      { client: browser },
    );

    await flush();
    await flush();
    expect(view.result.run?.id).toBe("r1");
    expect(view.result.nodes["lookup"]?.status).toBe("running");
    expect(view.result.status).toBe("subscribed");
    expect(client.channel.mock.calls[0]?.[0]).toBe("workflow-run:r1");
    expect(rpc).toHaveBeenCalledWith("workflow_node_runs_list", {
      run: "wrun_r1",
    });

    nodes = [nodeRow("lookup", "completed"), nodeRow("welcome", "failed")];
    emit("workflow-run:r1", "workflow_run_changed");
    await flush();
    expect(view.result.nodes["lookup"]?.status).toBe("completed");
    expect(view.result.nodes["welcome"]?.status).toBe("failed");

    failNodes = true;
    await view.result.refresh();
    expect(view.result.error?.message).toBe("no nodes");
    view.unmount();
    await flush();
    expect(client.removeChannel).toHaveBeenCalledOnce();
  });

  it("does nothing for a null run and keeps a read error", async () => {
    const idle = fakeBrowser(signedIn(USER));
    const unused = withRpc(idle.client, () => null);

    const empty = renderHook(() => useWorkflowCanvasRun(null), undefined, {
      client: idle.browser,
    });

    await flush();
    await empty.result.refresh();
    expect(unused).not.toHaveBeenCalled();
    expect(empty.result.nodes).toEqual({});
    expect(empty.result.status).toBe("closed");
    empty.unmount();

    const { browser, client } = fakeBrowser(signedIn(USER));
    withRpc(client, () => {
      throw new Error("denied");
    });

    const view = renderHook(() => useWorkflowCanvasRun("r1"), undefined, {
      client: browser,
    });

    await flush();
    expect(view.result.error?.message).toBe("denied");
    expect(view.result.run).toBeUndefined();
    view.unmount();
  });
});

describe("ai-chat hooks", () => {
  const AT = "2026-01-01T00:00:00Z";

  const chat = (id: string, extra: object = {}) => ({
    id,
    organization_id: "org-1",
    owner_id: USER,
    title: `Chat ${id}`,
    visibility: "private",
    is_temporary: false,
    last_message_at: AT,
    created_at: AT,
    updated_at: AT,
    ...extra,
  });

  const message = (id: string, parent: string | null) => ({
    id,
    parent_id: parent,
    role: parent === null ? "user" : "assistant",
    parts: [{ type: "text", text: id }],
    status: "complete",
    format: "canonical",
    created_at: AT,
    sibling_count: 1,
    sibling_index: 0,
  });

  it("lists, pages, creates, updates and removes chats", async () => {
    const { browser, client, emit } = fakeBrowser(signedIn(USER));
    let first = [chat("a"), chat("b")];
    let fail = false;

    const rpc = withRpc(client, (fn, args) => {
      if (fail) {
        throw new Error("denied");
      }

      switch (fn) {
        case "list_ai_chats": {
          return args["after"]
            ? { items: [chat("c")], next: null }
            : { items: first, next: "cursor" };
        }

        case "create_ai_chat": {
          return chat(
            "n",
            (args["fields"] as { is_temporary?: boolean }).is_temporary
              ? { is_temporary: true }
              : {},
          );
        }

        case "update_ai_chat": {
          return chat("a", { title: "Renamed" });
        }

        default: {
          return true;
        }
      }
    });

    const view = renderHook(
      () => useAiChats({ organizationId: "org-1", search: "x", limit: 2 }),
      undefined,
      { client: browser },
    );

    await flush();
    await flush();
    expect(view.result.items?.map((item) => item.id)).toEqual(["a", "b"]);
    expect(view.result.hasMore).toBe(true);
    expect(view.result.status).toBe("subscribed");
    expect(rpc).toHaveBeenCalledWith("list_ai_chats", {
      tenant: "org-1",
      search: "x",
      size: 2,
    });

    await view.result.loadMore();
    expect(view.result.items?.map((item) => item.id)).toEqual(["a", "b", "c"]);
    expect(view.result.hasMore).toBe(false);
    await view.result.loadMore();

    first = [chat("b")];
    emit(`ai-chats:${USER}`, "chat.updated", {});
    await flush();
    // The reload fetches both loaded pages again.
    expect(view.result.items?.map((item) => item.id)).toEqual(["b", "c"]);

    expect((await view.result.create({ title: "New" }))?.id).toBe("n");
    expect(view.result.items?.map((item) => item.id)).toEqual(["n", "b", "c"]);
    await view.result.create({ temporary: true });
    expect(view.result.items).toHaveLength(3);

    first = [chat("a"), chat("b")];
    await view.result.refresh();
    expect(
      (await view.result.update({ chatId: "a", patch: { title: "Renamed" } }))
        ?.title,
    ).toBe("Renamed");
    expect(view.result.items?.[0]?.title).toBe("Renamed");
    await view.result.remove("a");
    expect(view.result.items?.map((item) => item.id)).toEqual(["b", "c"]);

    fail = true;
    await view.result.remove("b");
    expect(view.result.error?.message).toBe("denied");
    expect(
      await view.result.update({ chatId: "b", patch: {} }),
    ).toBeUndefined();
    await view.result.refresh();
    expect(view.result.items?.map((item) => item.id)).toEqual(["b", "c"]);
    fail = false;
    await view.result.refresh();
    expect(view.result.error).toBeUndefined();
    view.unmount();
    await flush();
    expect(client.removeChannel).toHaveBeenCalledOnce();
  });

  it("waits for a user, loads once without a topic and needs a tenant to create", async () => {
    const signedOut = fakeBrowser(SIGNED_OUT);
    const idle = withRpc(signedOut.client, () => ({ items: [], next: null }));

    const waiting = renderHook(() => useAiChats(), undefined, {
      client: signedOut.browser,
    });

    await flush();
    expect(idle).not.toHaveBeenCalled();
    expect(await waiting.result.create()).toBeUndefined();
    waiting.unmount();

    const once = fakeBrowser(signedIn(USER));

    const rpc = withRpc(once.client, () => ({
      items: [chat("a")],
      next: null,
    }));

    const view = renderHook(
      () =>
        useAiChats({
          topic: null,
          schema: "api",
          archived: true,
          pinned: true,
          projectId: "p",
        }),
      undefined,
      { client: once.browser },
    );

    await flush();
    expect(view.result.items).toHaveLength(1);
    expect(rpc).toHaveBeenCalledWith("list_ai_chats", {
      tenant: null,
      project: "p",
      pinned: true,
      archived: true,
    });
    expect(once.client.channel).not.toHaveBeenCalled();
    view.unmount();
  });

  /** Holds the RPC answers `hold` picks until `release` lets them through. */
  function heldRpc(
    client: object,
    answer: (fn: string, args: Record<string, unknown>) => unknown,
  ) {
    const held: (() => void)[] = [];

    const control = {
      hold: (_fn: string, _args: Record<string, unknown>) => false,
      release: () => {
        for (const resume of held.splice(0)) {
          resume();
        }
      },
    };

    const rpc = withRpc(client, async (fn, args) => {
      const value = answer(fn, args);

      if (control.hold(fn, args)) {
        await new Promise<void>((resume) => {
          held.push(resume);
        });
      }

      return value;
    });

    return { rpc, control };
  }

  it("keeps loaded pages on a live reload and drops an older reload's answer", async () => {
    const { browser, client, emit } = fakeBrowser(signedIn(USER));
    let first = [chat("a"), chat("b")];
    let offline = false;

    const { control } = heldRpc(client, (_fn, args) => {
      if (!args["after"]) {
        return { items: first, next: "cursor" };
      }

      if (offline) {
        throw new Error("offline");
      }

      return { items: [chat("c")], next: null };
    });

    const view = renderHook(() => useAiChats(), undefined, { client: browser });

    await flush();
    offline = true;
    await view.result.loadMore();
    expect(view.result.error?.message).toBe("offline");
    expect(view.result.items?.map((item) => item.id)).toEqual(["a", "b"]);
    offline = false;
    await view.result.loadMore();
    expect(view.result.items?.map((item) => item.id)).toEqual(["a", "b", "c"]);

    first = [chat("old")];
    control.hold = (_fn, args) => args["after"] === undefined;
    emit(`ai-chats:${USER}`, "chat.updated", {});
    await flush();
    control.hold = () => false;
    first = [chat("new")];
    emit(`ai-chats:${USER}`, "chat.updated", {});
    await flush();
    expect(view.result.items?.map((item) => item.id)).toEqual(["new", "c"]);
    expect(view.result.hasMore).toBe(false);

    control.release();
    await flush();
    expect(view.result.items?.map((item) => item.id)).toEqual(["new", "c"]);
    view.unmount();
  });

  it("starts over when the query changes and drops the older query's page", async () => {
    const { browser, client } = fakeBrowser(signedIn(USER));

    const { rpc, control } = heldRpc(client, (_fn, args) => {
      const search = String(args["search"]);

      return args["after"]
        ? { items: [chat(`${search}-2`)], next: null }
        : { items: [chat(`${search}-1`)], next: "cursor" };
    });

    const view = renderHook<string, ReturnType<typeof useAiChats>>(
      (search) => useAiChats({ search, topic: null }),
      "x",
      { client: browser },
    );

    await flush();
    expect(view.result.items?.map((item) => item.id)).toEqual(["x-1"]);

    control.hold = (_fn, args) => args["after"] !== undefined;
    const stale = view.result.loadMore;
    const pending = view.result.loadMore();
    view.rerender("y");
    expect(view.result.items).toBeUndefined();
    expect(view.result.hasMore).toBe(false);
    control.hold = () => false;
    await flush();
    expect(view.result.items?.map((item) => item.id)).toEqual(["y-1"]);
    expect(view.result.hasMore).toBe(true);

    control.release();
    await pending;
    await flush();
    expect(view.result.items?.map((item) => item.id)).toEqual(["y-1"]);
    const calls = rpc.mock.calls.length;
    await stale();
    expect(rpc).toHaveBeenCalledTimes(calls);

    await view.result.loadMore();
    expect(view.result.items?.map((item) => item.id)).toEqual(["y-1", "y-2"]);
    expect(rpc).toHaveBeenLastCalledWith("list_ai_chats", {
      tenant: null,
      search: "y",
      after: "cursor",
    });
    view.unmount();
  });

  it("clears the chats on sign-out and drops answers for the old user", async () => {
    const { browser, client, emit, setAuth } = fakeBrowser(signedIn(USER));

    const { control } = heldRpc(client, () => ({
      items: [chat("a")],
      next: "cursor",
    }));

    const view = renderHook(() => useAiChats(), undefined, { client: browser });

    await flush();
    expect(view.result.items).toHaveLength(1);

    control.hold = () => true;
    emit(`ai-chats:${USER}`, "chat.updated", {});
    setAuth(SIGNED_OUT);
    expect(view.result).toMatchObject({
      items: undefined,
      hasMore: false,
      status: "closed",
      error: undefined,
    });
    control.release();
    await flush();
    expect(view.result.items).toBeUndefined();
    await view.result.refresh();
    await view.result.loadMore();
    expect(view.result.items).toBeUndefined();
    await flush();
    expect(client.removeChannel).toHaveBeenCalledOnce();
    view.unmount();
  });

  it("clears the old path while another chat loads and ignores its answers", async () => {
    const { browser, client } = fakeBrowser(signedIn(USER));

    const { control } = heldRpc(client, (fn, args) =>
      fn === "switch_ai_branch"
        ? { leaf_id: "a2" }
        : [message(`${String(args["chat"])}-u`, null)],
    );

    const view = renderHook<string | null, ReturnType<typeof useAiChatTree>>(
      (id) => useAiChatTree(id, { topic: null }),
      "c1",
      { client: browser },
    );

    await flush();
    expect(view.result.path?.map((item) => item.id)).toEqual(["c1-u"]);

    control.hold = (_fn, args) => args["chat"] === "c1";
    const { refresh, switchBranch } = view.result;
    const refreshing = refresh();
    const switching = switchBranch("a2");
    view.rerender("c2");
    expect(view.result.path).toBeUndefined();
    await flush();
    expect(view.result.path?.map((item) => item.id)).toEqual(["c2-u"]);

    control.release();
    await refreshing;
    await switching;
    await flush();
    expect(view.result.path?.map((item) => item.id)).toEqual(["c2-u"]);
    expect(view.result.error).toBeUndefined();

    view.rerender(null);
    expect(view.result.path).toBeUndefined();
    view.unmount();
  });

  it("follows a chat's branch and steps between siblings", async () => {
    const { browser, client, emit } = fakeBrowser(signedIn(USER));
    let path = [message("u1", null), message("a1", "u1")];

    let siblings = [
      { id: "a1", role: "assistant", created_at: AT },
      { id: "a2", role: "assistant", created_at: AT },
    ];

    let fail = false;

    const rpc = withRpc(client, (fn) => {
      if (fail) {
        throw new Error("gone");
      }

      switch (fn) {
        case "ai_message_path": {
          return path;
        }

        case "ai_message_siblings": {
          return siblings;
        }

        default: {
          return { leaf_id: "a2" };
        }
      }
    });

    const view = renderHook<string | null, ReturnType<typeof useAiChatTree>>(
      (id) => useAiChatTree(id),
      "c1",
      { client: browser },
    );

    await flush();
    await flush();
    expect(view.result.path?.map((item) => item.id)).toEqual(["u1", "a1"]);
    expect(view.result.status).toBe("subscribed");

    path = [message("u1", null), message("a2", "u1")];
    emit("ai-chat:c1", "stream.started", {});
    await flush();
    expect(view.result.path?.[1]?.id).toBe("a1");
    emit("ai-chat:c1", "message.saved", {});
    await flush();
    expect(view.result.path?.[1]?.id).toBe("a2");

    await view.result.step({ messageId: "a1", offset: 1 });
    expect(rpc).toHaveBeenCalledWith("switch_ai_branch", {
      chat: "c1",
      message_id: "a2",
    });
    expect(rpc).toHaveBeenLastCalledWith("ai_message_path", {
      chat: "c1",
      leaf: "a2",
    });
    const calls = rpc.mock.calls.length;
    await view.result.step({ messageId: "a1", offset: -1 });
    await view.result.step({ messageId: "zz", offset: 1 });
    expect(rpc).toHaveBeenCalledTimes(calls + 2);
    await view.result.refresh();

    siblings = [];
    fail = true;
    await view.result.step({ messageId: "a1", offset: 1 });
    await view.result.switchBranch("a1");
    expect(view.result.error?.message).toBe("gone");

    view.rerender(null);
    await view.result.refresh();
    await view.result.switchBranch("a1");
    await view.result.step({ messageId: "a1", offset: 1 });
    view.unmount();
  });

  it("loads a chat once without a topic", async () => {
    const { browser, client } = fakeBrowser(signedIn(USER));
    withRpc(client, () => [message("u1", null)]);

    const view = renderHook(
      () => useAiChatTree("c1", { topic: null, schema: "api" }),
      undefined,
      { client: browser },
    );

    await flush();
    expect(view.result.path).toHaveLength(1);
    expect(client.channel).not.toHaveBeenCalled();
    view.unmount();
  });

  it("reads the allowed models", async () => {
    const { browser, client } = fakeBrowser(signedIn(USER));

    const rpc = withRpc(client, () => [
      { model_id: "openai/gpt-5", provider: "openai", name: "GPT-5" },
    ]);

    const view = renderHook(() => useAiModels("org-1"), undefined, {
      client: browser,
    });

    await flush();
    expect(view.result.models?.map((model) => model.id)).toEqual([
      "openai/gpt-5",
    ]);
    await view.result.refresh();
    expect(rpc).toHaveBeenLastCalledWith("allowed_ai_models", {
      tenant: "org-1",
    });
    view.unmount();

    const none = renderHook(
      () => useAiModels(undefined, { schema: "api" }),
      undefined,
      { client: browser },
    );

    await flush();
    expect(rpc).toHaveBeenLastCalledWith("allowed_ai_models", { tenant: null });
    none.unmount();
  });

  it("creates and revokes share links", async () => {
    const { browser, client } = fakeBrowser(signedIn(USER));
    let shares: object[] = [];
    let fail = false;
    withRpc(client, (fn) => {
      if (fail) {
        throw new Error("not yours");
      }

      switch (fn) {
        case "share_ai_chat": {
          shares = [{ id: "s1", leaf_id: "a1", created_at: AT }];

          return { id: "s1", token: "tok", leaf_id: "a1", created_at: AT };
        }

        case "revoke_ai_chat_share": {
          shares = [];

          return true;
        }

        default: {
          return shares;
        }
      }
    });

    const view = renderHook<string | null, ReturnType<typeof useAiShare>>(
      (id) => useAiShare(id),
      "c1",
      { client: browser },
    );

    await flush();
    expect(view.result.shares).toEqual([]);
    expect((await view.result.create())?.token).toBe("tok");
    expect(view.result.shares).toHaveLength(1);
    await view.result.revoke("s1");
    expect(view.result.shares).toEqual([]);
    fail = true;
    expect(await view.result.create("a1")).toBeUndefined();
    await view.result.revoke("s1");
    expect(view.result.error?.message).toBe("not yours");
    view.rerender(null);
    expect(await view.result.create()).toBeUndefined();
    view.unmount();
  });
});

describe("useSavedViews", () => {
  const views = [
    {
      id: "all",
      name: "All",
      scope: "tenant" as const,
      isDefault: false,
      state: {},
    },
    {
      id: "open",
      name: "Open",
      scope: "user" as const,
      isDefault: true,
      state: { query: { facets: { status: ["open"] }, sort: "name" } },
    },
  ];

  it("opens the default view, tracks the active one and saves the URL", async () => {
    let urlState: Record<string, unknown> = {
      q: null,
      sort: null,
      page: null,
      status: null,
    };

    const setUrlState = vi.fn((next: Record<string, unknown>) => {
      urlState = { ...urlState, ...next };
    });

    const save = vi.fn(async () => undefined);
    const remove = vi.fn(async () => undefined);
    const load = vi.fn(async () => views);

    const view = renderHook(
      () => useSavedViews({ load, save, remove, urlState, setUrlState }),
      undefined,
      null,
    );

    expect(view.result.views).toBeUndefined();
    await flush();
    expect(setUrlState).toHaveBeenCalledWith({
      q: null,
      sort: "name",
      page: null,
      status: ["open"],
    });
    view.rerender(undefined);
    expect(view.result.active?.id).toBe("open");
    expect(view.result.isDirty).toBe(false);

    urlState = { ...urlState, q: "bug" };
    view.rerender(undefined);
    expect(view.result.active).toBeUndefined();
    expect(view.result.isDirty).toBe(true);
    await view.result.saveCurrent({ name: "Bugs" });
    const bugs = { q: "bug", sort: "name", facets: { status: ["open"] } };
    expect(save).toHaveBeenCalledWith({
      name: "Bugs",
      query: bugs,
      state: { query: bugs },
    });
    expect(load).toHaveBeenCalledTimes(2);

    view.result.apply(views[0]!);
    view.rerender(undefined);
    expect(urlState).toMatchObject({ q: null, sort: null, status: null });
    expect(view.result.active?.id).toBe("all");
    await view.result.remove("all");
    expect(remove).toHaveBeenCalledWith("all");
    expect(view.result.isDirty).toBe(false);
  });

  it("leaves a URL with a query alone and reports load errors", async () => {
    const setUrlState = vi.fn();

    const load = vi
      .fn<() => Promise<typeof views>>()
      .mockResolvedValueOnce(views)
      .mockRejectedValueOnce(new Error("down"));

    const view = renderHook(
      () =>
        useSavedViews({
          load,
          urlState: { q: "x", status: null },
          setUrlState,
        }),
      undefined,
      null,
    );

    await flush();
    expect(setUrlState).not.toHaveBeenCalled();
    await view.result.refresh();
    expect(view.result.error).toEqual(new Error("down"));
    await expect(view.result.saveCurrent({ name: "x" })).rejects.toThrow(
      "pass `save`",
    );
    await expect(view.result.remove("x")).rejects.toThrow("pass `remove`");
    await expect(view.result.duplicate({ id: "x", name: "y" })).rejects.toThrow(
      "pass `duplicate`",
    );
    await expect(
      view.result.setPreference({ id: "x", preference: {} }),
    ).rejects.toThrow("pass `setPreference`");
  });

  it("saves and applies the state outside the URL", async () => {
    const board = {
      id: "board",
      name: "Board",
      scope: "tenant" as const,
      isDefault: true,
      state: {
        query: { sort: "name" },
        columns: { visible: ["title"] },
        density: "compact" as const,
      },
    };

    let urlState: Record<string, unknown> = { q: null, sort: null };
    let shown: Record<string, unknown> = {};

    const setUrlState = vi.fn((next: Record<string, unknown>) => {
      urlState = { ...urlState, ...next };
    });

    const onApplyState = vi.fn((state: Record<string, unknown>) => {
      shown = state;
    });

    const save = vi.fn(async () => undefined);

    const view = renderHook(
      () =>
        useSavedViews({
          load: async () => [board],
          save,
          urlState,
          setUrlState,
          getState: () => shown,
          onApplyState,
        }),
      undefined,
      null,
    );

    await flush();
    expect(onApplyState).toHaveBeenCalledWith(
      { columns: { visible: ["title"] }, density: "compact" },
      board,
    );
    view.rerender(undefined);
    expect(view.result.active?.id).toBe("board");
    expect(view.result.isDirty).toBe(false);

    shown = { ...shown, density: "comfortable" };
    view.rerender(undefined);
    expect(view.result.active).toBeUndefined();
    expect(view.result.isDirty).toBe(true);
    expect(view.result.state).toEqual({
      query: { sort: "name" },
      columns: { visible: ["title"] },
      density: "comfortable",
    });
    await view.result.saveCurrent({ name: "Roomy", id: "board" });
    expect(save).toHaveBeenCalledWith({
      name: "Roomy",
      id: "board",
      query: { sort: "name" },
      state: {
        query: { sort: "name" },
        columns: { visible: ["title"] },
        density: "comfortable",
      },
    });
  });

  it("opens the caller's preferred view, then duplicates and pins", async () => {
    const preferred = {
      id: "shared",
      name: "Shared",
      scope: "tenant" as const,
      isDefault: false,
      state: { query: { q: "mine" } },
      preference: { isDefault: true },
    };

    const slot = { ...views[1]!, preference: { isDefault: false } };
    const setUrlState = vi.fn();
    const duplicate = vi.fn(async () => undefined);
    const setPreference = vi.fn(async () => undefined);
    const load = vi.fn(async () => [slot, preferred]);

    const view = renderHook(
      () =>
        useSavedViews({
          load,
          urlState: { q: null },
          setUrlState,
          duplicate,
          setPreference,
        }),
      undefined,
      null,
    );

    await flush();
    expect(setUrlState).toHaveBeenCalledWith({ q: "mine" });
    await view.result.duplicate({ id: "shared", name: "Copy", scope: "user" });
    expect(duplicate).toHaveBeenCalledWith({
      id: "shared",
      name: "Copy",
      scope: "user",
    });
    await view.result.setPreference({
      id: "shared",
      preference: { pinned: true },
    });
    expect(setPreference).toHaveBeenCalledWith("shared", { pinned: true });
    expect(load).toHaveBeenCalledTimes(3);
  });
});

describe("useUndoStack", () => {
  const token = (entry: string) =>
    undoToken([{ fn: "revert_audit_entries", args: { entries: [entry] } }]);

  it("keeps the newest tokens and applies them last in, first out", async () => {
    const apply = vi.fn(async () => undefined);

    const view = renderHook(
      () => useUndoStack({ apply, limit: 2 }),
      undefined,
      null,
    );

    const { push } = view.result;
    push({ token: token("1"), label: "first" });
    push({ token: null, label: "no inverse" });
    push({ token: token("2"), label: "second" });
    push({ token: token("3"), label: "third" });
    view.rerender(undefined);
    expect(view.result.entries.map((entry) => entry.label)).toEqual([
      "second",
      "third",
    ]);
    expect(view.result.canUndo).toBe(true);

    expect(await view.result.undo()).toBe(true);
    expect(apply).toHaveBeenCalledWith(token("3"));
    view.rerender(undefined);
    expect(view.result.entries.map((entry) => entry.label)).toEqual(["second"]);
    view.result.clear();
    view.rerender(undefined);
    expect(view.result.canUndo).toBe(false);
    expect(await view.result.undo()).toBe(false);
  });

  it("drops a token whose undo failed and reports the error", async () => {
    const apply = vi.fn(async () => {
      throw new Error("ROW_CHANGED_SINCE");
    });

    const view = renderHook(() => useUndoStack({ apply }), undefined, null);
    view.result.push({ token: token("1"), label: "moved" });
    expect(await view.result.undo()).toBe(false);
    view.rerender(undefined);
    expect(view.result.entries).toEqual([]);
    expect(view.result.error).toEqual(new Error("ROW_CHANGED_SINCE"));
  });
});
