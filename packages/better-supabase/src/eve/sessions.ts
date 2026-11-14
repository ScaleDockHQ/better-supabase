import type { AiChat } from "../blocks/ai-chat/ai-chat.ts";
import type { FinalRunState } from "../core/run-state.ts";
import type { EveSessionAuth, EveSessionContext } from "./types.ts";

import { stableUuid } from "./ids.ts";

/** A v27 session event: its type, the turn or run it belongs to, and its data. */
interface EveEvent<T> {
  readonly type: string;
  readonly scope?: { readonly turnId?: string; readonly runId?: string };
  readonly data: T;
}

/** A part of what a person sent, as `delivery.consumed` carries it. */
type EveUserPart =
  | { readonly kind: "text"; readonly text: string }
  | { readonly kind: string };

/** Hook handlers for eve's `defineHook({ events })`, on stream version 27. */
export interface EveSessionHooks {
  "session.started"(
    event: EveEvent<unknown>,
    ctx: EveSessionContext,
  ): Promise<void>;
  "turn.started"(
    event: EveEvent<{ readonly turnId: string }>,
    ctx: EveSessionContext,
  ): Promise<void>;
  "delivery.consumed"(
    event: EveEvent<{
      readonly deliveryId: string;
      readonly turnId: string;
      readonly parts: readonly EveUserPart[];
    }>,
    ctx: EveSessionContext,
  ): Promise<void>;
  "content.completed"(
    event: EveEvent<{
      readonly partId: string;
      readonly runId: string;
      readonly kind: string;
      readonly value?: unknown;
      readonly phase: string;
    }>,
    ctx: EveSessionContext,
  ): Promise<void>;
  "turn.settled"(
    event: EveEvent<{
      readonly turnId: string;
      readonly outcome: string;
      readonly error?: { readonly code: string; readonly message: string };
    }>,
    ctx: EveSessionContext,
  ): Promise<void>;
}

export interface PersistSessionsOptions {
  /** `createAiChat` on a service transport. */
  readonly chats: AiChat;
  /** The tenant of a principal. Defaults to `attributes.tenantId`. */
  readonly organizationOf?: (auth: EveSessionAuth) => string | undefined;
  readonly agentId?: string;
  /** The title of a new chat. Defaults to `eve session`. */
  readonly title?: string;
}

/**
 * The `ai_chats` id of an eve session: the same session always maps to the same
 * chat.
 */
export function chatIdOf(sessionId: string): Promise<string> {
  return stableUuid(`eve-session:${sessionId}`);
}

const streamOf = (sessionId: string, turnId: string): string =>
  `eve:${sessionId}:${turnId}`;

const textOf = (parts: readonly EveUserPart[]): string =>
  parts
    .flatMap((part) =>
      part.kind === "text" && "text" in part ? [part.text] : [],
    )
    .join("\n");

const FINAL_STATES: Readonly<Record<string, FinalRunState>> = {
  completed: "completed",
  failed: "failed",
  cancelled: "cancelled",
};

/**
 * Hook handlers that copy an eve session into the canonical chat tables, so the
 * chat UI, search, memory recall and analytics read eve sessions like any other
 * chat. Every write is keyed by the event, so eve's at-least-once delivery
 * stores each message once. Sessions without a signed-in user and tenant are
 * skipped.
 */
export function persistSessions(
  options: PersistSessionsOptions,
): EveSessionHooks {
  const { chats } = options;

  const organizationOf =
    options.organizationOf ??
    ((auth: EveSessionAuth) => {
      const tenant = auth.attributes["tenantId"];

      return typeof tenant === "string" ? tenant : undefined;
    });

  const chatFor = async (
    ctx: EveSessionContext,
  ): Promise<string | undefined> => {
    const auth = ctx.session.auth.initiator ?? ctx.session.auth.current;

    if (auth?.principalType !== "user") {
      return undefined;
    }

    const organizationId = organizationOf(auth);

    if (organizationId === undefined) {
      return undefined;
    }

    const id = await chatIdOf(ctx.session.id);
    await chats.chats
      .create({
        organizationId,
        input: {
          id,
          ownerId: auth.principalId,
          title: options.title ?? "eve session",
          ...(options.agentId === undefined
            ? {}
            : { agentId: options.agentId }),
        },
      })
      .orThrow();

    return id;
  };

  const knownChat = async (
    ctx: EveSessionContext,
  ): Promise<string | undefined> => {
    const auth = ctx.session.auth.initiator ?? ctx.session.auth.current;

    if (auth?.principalType !== "user" || organizationOf(auth) === undefined) {
      return undefined;
    }

    return chatIdOf(ctx.session.id);
  };

  return {
    "session.started": async (_event, ctx) => {
      await chatFor(ctx);
    },
    "turn.started": async (event, ctx) => {
      const chatId = await chatFor(ctx);

      if (chatId === undefined) {
        return;
      }

      await chats.runs
        .claim({
          chatId,
          streamId: streamOf(ctx.session.id, event.data.turnId),
          engine: "eve",
        })
        .orThrow();
    },
    "delivery.consumed": async (event, ctx) => {
      const chatId = await chatFor(ctx);
      const text = textOf(event.data.parts);

      if (chatId === undefined || text.length === 0) {
        return;
      }

      await chats.messages
        .appendUser({
          chatId,
          message: {
            id: `${event.data.turnId}:${event.data.deliveryId}`,
            role: "user",
            parts: [{ type: "text", text }],
          },
        })
        .orThrow();
    },
    "content.completed": async (event, ctx) => {
      const { kind, value, phase, partId } = event.data;
      const turnId = event.scope?.turnId;

      if (
        kind !== "text" ||
        typeof value !== "string" ||
        value.length === 0 ||
        turnId === undefined
      ) {
        return;
      }

      const chatId = await knownChat(ctx);

      if (chatId === undefined) {
        return;
      }

      const chat = await chats.chats.get(chatId).orThrow();

      if (chat.leafId === undefined) {
        return;
      }

      await chats.messages
        .saveAssistant({
          chatId,
          message: {
            id: `${turnId}:${partId}`,
            role: "assistant",
            parts: [{ type: "text", text: value }],
            ...(phase === "reply" ? {} : { metadata: { interim: true } }),
          },
          options: {
            parentId: chat.leafId,
            status: "complete",
            format: "eve",
            native: event.data,
            runId: chat.activeRunId,
          },
        })
        .orThrow();
    },
    "turn.settled": async (event, ctx) => {
      const status = FINAL_STATES[event.data.outcome];
      const chatId = status === undefined ? undefined : await knownChat(ctx);

      if (status === undefined || chatId === undefined) {
        return;
      }

      const { error } = event.data;

      await chats.runs
        .release({
          chatId,
          streamId: streamOf(ctx.session.id, event.data.turnId),
          status,
          ...(error === undefined
            ? {}
            : { error: `${error.code}: ${error.message}` }),
        })
        .orThrow();
    },
  };
}
