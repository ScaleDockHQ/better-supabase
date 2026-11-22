import type { EveSessionStore } from "./store.ts";
import type { EveSessionContext } from "./types.ts";

import { sessionChatId } from "./sync.ts";

/** A v27 session event: its type, the turn or run it belongs to, and its data. */
interface EveEvent<T> {
  readonly type: string;
  readonly scope?: { readonly turnId?: string; readonly runId?: string };
  readonly data: T;
}

/** The events `persistSessions` wakes the session sync on. */
export const PERSIST_SESSION_EVENTS = [
  "session.started",
  "session.ended",
  "turn.started",
  "turn.settled",
  "delivery.consumed",
  "content.completed",
  "interaction.opened",
  "interaction.settled",
  "usage.recorded",
] as const;

export type EvePersistedEvent = (typeof PERSIST_SESSION_EVENTS)[number];

/**
 * Hook handlers for eve's `defineHook({ events })`, on stream version 27. They
 * only wake the session's sync job; `syncSession` reads the stream.
 */
export type EveSessionHooks = {
  readonly [Type in EvePersistedEvent]: (
    event: EveEvent<unknown>,
    ctx: EveSessionContext,
  ) => Promise<void>;
};

export interface PersistSessionsOptions {
  /** `world.eveSessions` from `createSupabaseWorld()`. */
  readonly store: Pick<EveSessionStore, "wake">;
  /**
   * Seconds the job waits before it runs, so the events of one burst share one
   * job. Default 2.
   */
  readonly delaySeconds?: number;
}

/**
 * The `ai_chats` id of an eve session: the same session always maps to the same
 * chat.
 */
export function chatIdOf(sessionId: string): Promise<string> {
  return sessionChatId(sessionId);
}

/**
 * Hook handlers that wake the session's sync job (`createSessionSync`), which
 * copies the session into the canonical chat tables. They write nothing
 * themselves: eve does not retry a hook, so a missed hook costs one wake-up,
 * not a lost event, and the sync reads the stream from its own cursor. The
 * `workflow-sdk` module's triggers wake the same job on every run change, so
 * the hooks only matter on a World without them.
 */
export function persistSessions(
  options: PersistSessionsOptions,
): EveSessionHooks {
  const wake = async (
    _event: EveEvent<unknown>,
    ctx: EveSessionContext,
  ): Promise<void> => {
    await options.store.wake(ctx.session.id, options.delaySeconds);
  };

  return {
    "session.started": wake,
    "session.ended": wake,
    "turn.started": wake,
    "turn.settled": wake,
    "delivery.consumed": wake,
    "content.completed": wake,
    "interaction.opened": wake,
    "interaction.settled": wake,
    "usage.recorded": wake,
  };
}
