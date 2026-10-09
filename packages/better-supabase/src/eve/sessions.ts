import type { AiChat } from "../blocks/ai-chat/ai-chat.ts";
import type { FinalRunState } from "../core/run-state.ts";
import type { EveSessionAuth, EveSessionContext } from "./types.ts";

import { stableUuid } from "./ids.ts";

interface EveEvent<T> {
  readonly type?: string;
  readonly data: T;
  readonly meta?: { readonly id?: string; readonly at?: string };
}

interface TurnData {
  readonly turnId: string;
  readonly sequence: number;
}

/** Hook handlers for eve's `defineHook({ events })`. */
export interface EveSessionHooks {
  "session.started"(
    event: EveEvent<unknown>,
    ctx: EveSessionContext,
  ): Promise<void>;
  "turn.started"(
    event: EveEvent<TurnData>,
    ctx: EveSessionContext,
  ): Promise<void>;
  "message.received"(
    event: EveEvent<TurnData & { readonly message: string }>,
    ctx: EveSessionContext,
  ): Promise<void>;
  "message.completed"(
    event: EveEvent<
      TurnData & {
        readonly message: string;
        readonly stepIndex: number;
        readonly finishReason: string;
      }
    >,
    ctx: EveSessionContext,
  ): Promise<void>;
  "turn.completed"(
    event: EveEvent<TurnData>,
    ctx: EveSessionContext,
  ): Promise<void>;
  "turn.failed"(
    event: EveEvent<
      TurnData & { readonly code: string; readonly message: string }
    >,
    ctx: EveSessionContext,
  ): Promise<void>;
  "turn.cancelled"(
    event: EveEvent<TurnData>,
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

/** The `ai_chats` id of an eve session: the same session always maps to the same chat. */
export function chatIdOf(sessionId: string): Promise<string> {
  return stableUuid(`eve-session:${sessionId}`);
}

const streamOf = (sessionId: string, turnId: string): string =>
  `eve:${sessionId}:${turnId}`;

/**
 * Hook handlers that copy an eve session into the canonical chat tables, so
 * the chat UI, search, memory recall and analytics read eve sessions like any
 * other chat. Every write is keyed by the event, so eve's at-least-once
 * delivery stores each message once. Sessions without a signed-in user and
 * tenant are skipped.
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
    if (auth?.principalType !== "user") return undefined;
    const organizationId = organizationOf(auth);
    if (organizationId === undefined) return undefined;
    const id = await chatIdOf(ctx.session.id);
    await chats.chats
      .create(organizationId, {
        id,
        ownerId: auth.principalId,
        title: options.title ?? "eve session",
        ...(options.agentId === undefined ? {} : { agentId: options.agentId }),
      })
      .orThrow();
    return id;
  };

  const knownChat = async (
    ctx: EveSessionContext,
  ): Promise<string | undefined> => {
    const auth = ctx.session.auth.initiator ?? ctx.session.auth.current;
    if (auth?.principalType !== "user" || organizationOf(auth) === undefined)
      return undefined;
    return chatIdOf(ctx.session.id);
  };

  const release = async (
    ctx: EveSessionContext,
    turnId: string,
    status: FinalRunState,
    error?: string,
  ): Promise<void> => {
    const chatId = await knownChat(ctx);
    if (chatId === undefined) return;
    await chats.runs
      .release(chatId, streamOf(ctx.session.id, turnId), {
        status,
        ...(error === undefined ? {} : { error }),
      })
      .orThrow();
  };

  return {
    "session.started": async (_event, ctx) => {
      await chatFor(ctx);
    },
    "turn.started": async (event, ctx) => {
      const chatId = await chatFor(ctx);
      if (chatId === undefined) return;
      await chats.runs
        .claim(chatId, streamOf(ctx.session.id, event.data.turnId), {
          engine: "eve",
        })
        .orThrow();
    },
    "message.received": async (event, ctx) => {
      const chatId = await chatFor(ctx);
      if (chatId === undefined || event.data.message.length === 0) return;
      const id = `${event.data.turnId}:${String(event.data.sequence)}`;
      await chats.messages
        .appendUser(chatId, {
          id,
          role: "user",
          parts: [{ type: "text", text: event.data.message }],
        })
        .orThrow();
    },
    "message.completed": async (event, ctx) => {
      const chatId = await knownChat(ctx);
      if (chatId === undefined || event.data.message.length === 0) return;
      const chat = await chats.chats.get(chatId).orThrow();
      if (chat.leafId === undefined) return;
      const id = `${event.data.turnId}:${String(event.data.stepIndex)}:${String(event.data.sequence)}`;
      await chats.messages
        .saveAssistant(
          chatId,
          {
            id,
            role: "assistant",
            parts: [{ type: "text", text: event.data.message }],
            ...(event.data.finishReason === "tool-calls"
              ? { metadata: { interim: true } }
              : {}),
          },
          {
            parentId: chat.leafId,
            status: "complete",
            format: "eve",
            native: event.data,
            runId: chat.activeRunId,
          },
        )
        .orThrow();
    },
    "turn.completed": (event, ctx) =>
      release(ctx, event.data.turnId, "completed"),
    "turn.failed": (event, ctx) =>
      release(
        ctx,
        event.data.turnId,
        "failed",
        `${event.data.code}: ${event.data.message}`,
      ),
    "turn.cancelled": (event, ctx) =>
      release(ctx, event.data.turnId, "cancelled"),
  };
}
