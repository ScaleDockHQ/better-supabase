import type { AiChat } from "../blocks/ai-chat/ai-chat.ts";
import type { AiRunStepStatus } from "../blocks/ai-chat/durable.ts";
import type { Usage } from "../blocks/usage/usage.ts";
import type { AsyncResult } from "../core/result.ts";
import type { FinalRunState } from "../core/run-state.ts";
import type { EveSessionStore, EveSessionStatus } from "./store.ts";

import { stableUuid } from "./ids.ts";

/**
 * One event of a session stream as a reader reads it back (eve's
 * `SessionStreamEvent`, typed structurally so this entry never imports eve).
 */
export interface EveSyncEvent {
  readonly type: string;
  readonly scope?: { readonly turnId?: string; readonly runId?: string };
  readonly data?: unknown;
  readonly meta?: {
    readonly position?: { readonly line: number; readonly index?: number };
    /** `false` while more records of the line follow. */
    readonly endOfLine?: boolean;
    /** Exclusive coverage after a line that emitted no events. */
    readonly next?: number;
  };
}

/**
 * Reads a session's stream from `startIndex` through its durable tail and
 * stops. With eve's client: `(id, startIndex) =>
 * client.sessions.attach(id).stream({ startIndex, follow: false })`.
 */
export type EveSessionRead = (
  sessionId: string,
  startIndex: number,
) => AsyncIterable<EveSyncEvent>;

/** Who sent a session's first message, as `delivery.admitted` names them. */
export interface EveSessionPrincipal {
  readonly id: string;
  readonly type: string;
  readonly issuer?: string;
}

export interface EveSessionResolveInput {
  readonly sessionId: string;
  /** `undefined` while no delivery named one. */
  readonly principal: EveSessionPrincipal | undefined;
  /** The tenant stored by an earlier pass. */
  readonly tenantId: string | undefined;
}

/** Whose chat an eve session becomes. */
export interface EveSessionTarget {
  readonly organizationId: string;
  readonly ownerId: string;
  readonly agentId?: string;
  /** The title of the chat. Defaults to `eve session`. */
  readonly title?: string;
}

/** The meters `syncSession` records one model call's usage on. */
export interface EveSessionMeters {
  readonly inputTokens: string;
  readonly outputTokens: string;
  readonly cacheReadTokens?: string;
  readonly cacheWriteTokens?: string;
  /** The cost in millionths of a US dollar. */
  readonly costMicroUsd?: string;
}

export interface SyncSessionsOptions {
  readonly store: EveSessionStore;
  /** `createAiChat` on a service transport. */
  readonly chats: AiChat;
  readonly read: EveSessionRead;
  /**
   * The tenant and owner of a session, or `undefined` to leave it out of the
   * blocks (the cursor still moves, so it is not read again). A tenant is not
   * part of eve's principal; take it from your own tables or the principal's
   * id.
   */
  readonly resolve: (
    input: EveSessionResolveInput,
  ) => EveSessionTarget | undefined | Promise<EveSessionTarget | undefined>;
  /** Records each model call's tokens and cost, once per call. */
  readonly usage?: {
    readonly client: Pick<Usage, "recordMany">;
    readonly meters: EveSessionMeters;
  };
  /** Seconds a pass holds the lease before another may take it. Default 60. */
  readonly leaseSeconds?: number;
  /**
   * Events one pass reads before it commits; the rest waits for the next pass.
   * Default 2000.
   */
  readonly maxEvents?: number;
}

export type SyncSessionStatus =
  /** The pass wrote its events and moved the cursor. */
  | "synced"
  /** Another job holds the lease. */
  | "busy"
  /** The session has no tenant or owner (`resolve` returned nothing). */
  | "skipped";

export interface SyncSessionResult {
  readonly sessionId: string;
  readonly status: SyncSessionStatus;
  /** Events the pass read. */
  readonly events: number;
  /** The next line to read. */
  readonly cursor: number;
  /** `true` when `maxEvents` cut the pass short and more lines remain. */
  readonly more: boolean;
}

const DEFAULT_MAX_EVENTS = 2000;

const RUN_STATES: Readonly<Record<string, FinalRunState>> = {
  completed: "completed",
  failed: "failed",
  cancelled: "cancelled",
};

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const pick = (value: unknown, key: string): unknown =>
  isRecord(value) ? value[key] : undefined;

const str = (value: unknown, key: string): string | undefined => {
  const found = pick(value, key);

  return typeof found === "string" ? found : undefined;
};

const num = (value: unknown, key: string): number | undefined => {
  const found = pick(value, key);

  return typeof found === "number" && Number.isFinite(found)
    ? found
    : undefined;
};

const streamOf = (sessionId: string, turnId: string): string =>
  `eve:${sessionId}:${turnId}`;

/**
 * The `ai_chats` id of an eve session: the same session always maps to the same
 * chat.
 */
export function sessionChatId(sessionId: string): Promise<string> {
  return stableUuid(`eve-session:${sessionId}`);
}

const approvalIdOf = (sessionId: string, interactionId: string) =>
  stableUuid(`eve-approval:${sessionId}:${interactionId}`);

const userText = (parts: unknown): string =>
  Array.isArray(parts)
    ? parts
        .flatMap((part: unknown) =>
          str(part, "kind") === "text" && typeof str(part, "text") === "string"
            ? [str(part, "text") ?? ""]
            : [],
        )
        .join("\n")
    : "";

const stepStatus = (outcome: string | undefined): AiRunStepStatus => {
  if (outcome === "completed") {
    return "done";
  }

  if (outcome === "interrupted" || outcome === "abandoned") {
    return "skipped";
  }

  return "error";
};

/** Throws unless the result is ok or fails with one of the hints. */
async function settle<T>(
  result: AsyncResult<T>,
  ...tolerated: readonly string[]
): Promise<void> {
  const done = await result;

  if (!done.ok && !tolerated.includes(done.error.hint ?? "")) {
    throw new Error(
      `eve session sync: ${done.error.message} (${done.error.hint ?? done.error.kind})`,
    );
  }
}

/**
 * The events of one pass, whole lines only: a line whose last record has not
 * arrived is left for the next pass.
 */
async function readLines(
  read: EveSessionRead,
  sessionId: string,
  from: number,
  max: number,
): Promise<{
  readonly events: readonly EveSyncEvent[];
  readonly cursor: number;
  readonly more: boolean;
}> {
  const events: EveSyncEvent[] = [];
  let pending: EveSyncEvent[] = [];
  let cursor = from;
  let more = false;

  for await (const event of read(sessionId, from)) {
    pending.push(event);

    if (event.meta?.endOfLine === false) {
      continue;
    }

    events.push(...pending);
    pending = [];

    const line = event.meta?.position?.line;

    cursor = Math.max(cursor, event.meta?.next ?? (line ?? cursor - 1) + 1);

    if (events.length >= max) {
      more = true;
      break;
    }
  }

  return { events, cursor, more };
}

/** The syncing functions of `createSessionSync`. */
export interface SessionSync {
  /**
   * Copies what the session did since the last pass into the blocks, then moves
   * the cursor. Every write is keyed by the event, so a pass that fails halfway
   * runs again from the same line and writes the same rows.
   */
  syncSession(sessionId: string): Promise<SyncSessionResult>;
  /**
   * Syncs the sessions a job has not caught up with: the safety net behind the
   * wake-ups. Resolves with how many it synced.
   */
  sweepSessions(options?: {
    readonly olderThan?: string;
    readonly limit?: number;
  }): Promise<number>;
  /** The queue the debounced wake-up jobs wait in. */
  readonly queue: "eve_session_sync";
  /** The handler for a job of `queue`: `(payload) => Promise<void>`. */
  readonly job: (payload: { readonly sessionId: string }) => Promise<void>;
}

/** The sync of eve sessions into the chat, approval and usage tables. */
export function createSessionSync(options: SyncSessionsOptions): SessionSync {
  const { store, chats } = options;
  const maxEvents = options.maxEvents ?? DEFAULT_MAX_EVENTS;

  async function pass(sessionId: string): Promise<SyncSessionResult> {
    const lease = await store.lease(sessionId, options.leaseSeconds);

    if (lease === undefined) {
      return { sessionId, status: "busy", events: 0, cursor: 0, more: false };
    }

    try {
      const { events, cursor, more } = await readLines(
        options.read,
        sessionId,
        lease.cursor,
        maxEvents,
      );

      let principal: EveSessionPrincipal | undefined =
        lease.principalId === undefined
          ? undefined
          : { id: lease.principalId, type: lease.principalKind ?? "user" };

      for (const event of events) {
        const admitted = pick(event.data, "principal");

        if (
          event.type === "delivery.admitted" &&
          principal === undefined &&
          str(admitted, "id") !== undefined
        ) {
          principal = {
            id: str(admitted, "id") ?? "",
            type: str(admitted, "type") ?? "user",
          };
        }
      }

      const target = await options.resolve({
        sessionId,
        principal,
        tenantId: lease.tenantId,
      });

      let status: EveSessionStatus | undefined;
      let chatId = lease.chatId;

      if (target !== undefined) {
        chatId = await sessionChatId(sessionId);
        await project({
          sessionId,
          chatId,
          target,
          events,
          activeRun: lease.runId,
        });
      }

      for (const event of events) {
        if (event.type === "session.ended") {
          status = str(event.data, "outcome") === "failed" ? "failed" : "ended";
        }
      }

      const committed = await store.commit({
        sessionId,
        leaseId: lease.leaseId,
        cursor,
        tenantId: target?.organizationId,
        principalKind: principal?.type,
        principalId: principal?.id,
        chatId: target === undefined ? undefined : chatId,
        recordType: target === undefined ? undefined : "ai-chat",
        recordId: target === undefined ? undefined : chatId,
        status,
      });

      if (!committed) {
        throw new Error(
          `eve session sync: the lease on ${sessionId} expired before the commit`,
        );
      }

      return {
        sessionId,
        status: target === undefined ? "skipped" : "synced",
        events: events.length,
        cursor,
        more,
      };
    } catch (error) {
      await store.release(sessionId, lease.leaseId);
      throw error;
    }
  }

  async function project(input: {
    readonly sessionId: string;
    readonly chatId: string;
    readonly target: EveSessionTarget;
    readonly events: readonly EveSyncEvent[];
    readonly activeRun: string | undefined;
  }): Promise<void> {
    const { sessionId, chatId, target, events } = input;

    await settle(
      chats.chats.create({
        organizationId: target.organizationId,
        input: {
          id: chatId,
          ownerId: target.ownerId,
          title: target.title ?? "eve session",
          ...(target.agentId === undefined ? {} : { agentId: target.agentId }),
        },
      }),
    );

    // The ai-chat run of each turn, by eve turn id.
    const runs = new Map<string, string | undefined>();
    // Turns whose run already ended in an earlier pass.
    const ended = new Set<string>();

    const runOf = async (
      turnId: string | undefined,
    ): Promise<string | undefined> => {
      if (turnId === undefined) {
        return undefined;
      }

      if (!runs.has(turnId)) {
        const chat = await chats.chats.get(chatId).orThrow();

        runs.set(turnId, chat.activeRunId);
      }

      return runs.get(turnId);
    };

    const step = async (
      turnId: string | undefined,
      key: string,
      label: string,
      status: AiRunStepStatus,
      detail: Readonly<Record<string, unknown>>,
    ): Promise<void> => {
      const runId = await runOf(turnId);

      if (runId === undefined) {
        return;
      }

      await settle(
        chats.runs.steps.record({
          runId,
          step: { key, label, status, detail },
        }),
      );
    };

    const stepDetail = async (
      turnId: string | undefined,
      key: string,
    ): Promise<Readonly<Record<string, unknown>> | undefined> => {
      const runId = await runOf(turnId);

      if (runId === undefined) {
        return undefined;
      }

      const steps = await chats.runs.steps
        .list(runId, { limit: 500 })
        .orThrow();

      return steps.find((candidate) => candidate.key === key)?.detail;
    };

    for (const event of events) {
      const { data } = event;
      const turnId = event.scope?.turnId ?? str(data, "turnId");

      switch (event.type) {
        case "turn.started": {
          // A pass that failed after the turn settled runs again from the
          // turn's first line; the ended run is the turn's run, so no second
          // run opens and the settled event has nothing left to release.
          const earlier = (
            await chats.runs.list({ chatId, limit: 200 }).orThrow()
          ).find(
            (run) =>
              run.streamId === streamOf(sessionId, turnId ?? "") &&
              run.status !== "running",
          );

          if (earlier !== undefined) {
            if (turnId !== undefined) {
              runs.set(turnId, earlier.id);
              ended.add(turnId);
            }

            break;
          }

          const claim = await chats.runs
            .claim({
              chatId,
              streamId: streamOf(sessionId, turnId ?? ""),
              engine: "eve",
              ...(input.activeRun === undefined
                ? {}
                : { externalRunId: input.activeRun }),
            })
            .orThrow();

          if (turnId !== undefined) {
            runs.set(
              turnId,
              claim.runId ??
                (await chats.chats.get(chatId).orThrow()).activeRunId,
            );
          }

          break;
        }

        case "delivery.consumed": {
          const text = userText(pick(data, "parts"));
          const deliveryId = str(data, "deliveryId");

          if (text.length > 0 && turnId !== undefined && deliveryId) {
            await chats.messages
              .appendUser({
                chatId,
                message: {
                  id: `${turnId}:${deliveryId}`,
                  role: "user",
                  parts: [{ type: "text", text }],
                },
              })
              .orThrow();
          }

          break;
        }

        case "content.completed": {
          const value = pick(data, "value");
          const partId = str(data, "partId");

          if (
            str(data, "kind") !== "text" ||
            typeof value !== "string" ||
            value.length === 0 ||
            turnId === undefined ||
            partId === undefined
          ) {
            break;
          }

          const chat = await chats.chats.get(chatId).orThrow();

          if (chat.leafId === undefined) {
            break;
          }

          await chats.messages
            .saveAssistant({
              chatId,
              message: {
                id: `${turnId}:${partId}`,
                role: "assistant",
                parts: [{ type: "text", text: value }],
                ...(str(data, "phase") === "reply"
                  ? {}
                  : { metadata: { interim: true } }),
              },
              options: {
                parentId: chat.leafId,
                status: "complete",
                format: "eve",
                native: data,
                runId: await runOf(turnId),
              },
            })
            .orThrow();

          break;
        }

        case "model.started": {
          const modelRun = str(data, "runId");

          if (modelRun !== undefined) {
            await step(
              turnId,
              `model:${modelRun}`,
              str(data, "modelId") ?? "model",
              "running",
              { attempt: num(data, "attempt") },
            );
          }

          break;
        }

        case "model.settled": {
          const modelRun = str(data, "runId");
          const outcome = str(data, "outcome");

          if (modelRun !== undefined) {
            await step(
              turnId,
              `model:${modelRun}`,
              "model",
              stepStatus(outcome),
              {
                outcome,
                finishReason: str(data, "finishReason"),
                generationId: str(data, "generationId"),
              },
            );
          }

          break;
        }

        case "call.requested": {
          const callId = str(data, "callId");

          if (callId !== undefined) {
            await step(
              turnId,
              `call:${callId}`,
              str(pick(data, "capability"), "name") ?? "call",
              "running",
              {
                kind: str(pick(data, "capability"), "kind"),
                policy: str(data, "policy"),
              },
            );
          }

          break;
        }

        case "call.settled": {
          const callId = str(data, "callId");
          const outcome = str(data, "outcome");

          if (callId !== undefined) {
            await step(turnId, `call:${callId}`, "call", stepStatus(outcome), {
              outcome,
              reason: str(data, "reason"),
            });
          }

          break;
        }

        case "interaction.opened": {
          const interactionId = str(data, "interactionId");
          const request = pick(data, "request");
          const kind = str(request, "kind");

          if (interactionId === undefined) {
            break;
          }

          const key = `interaction:${interactionId}`;
          const turn = str(pick(data, "subject"), "turnId") ?? turnId;
          const call = pick(pick(data, "origin"), "call");

          if (kind === "approval") {
            const approvalId = await approvalIdOf(sessionId, interactionId);
            const runId = await runOf(turn);

            await settle(
              chats.approvals.request({
                chatId,
                request: {
                  approvalId,
                  tool: str(call, "name") ?? "tool",
                  toolCallId:
                    str(call, "callId") ??
                    str(pick(data, "subject"), "callId") ??
                    interactionId,
                  input: pick(call, "input"),
                  ...(runId === undefined ? {} : { runId }),
                },
              }),
            );
            await step(turn, key, "approval", "running", { kind, approvalId });
          } else if (
            kind === "question" &&
            (await stepDetail(turn, key)) === undefined
          ) {
            const runId = await runOf(turn);

            const opened = await chats.inputs
              .open({
                chatId,
                request: {
                  question: str(request, "prompt") ?? "",
                  ...(runId === undefined ? {} : { runId }),
                },
              })
              .orThrow();

            await step(turn, key, "question", "running", {
              kind,
              inputId: opened.id,
            });
          }

          break;
        }

        case "interaction.settled": {
          const interactionId = str(data, "interactionId");

          if (interactionId === undefined) {
            break;
          }

          const key = `interaction:${interactionId}`;
          const outcome = str(data, "outcome");
          const detail = await stepDetail(turnId, key);

          if (detail === undefined) {
            break;
          }

          if (str(detail, "kind") === "approval") {
            await settle(
              chats.approvals.decide({
                approvalId: str(detail, "approvalId") ?? "",
                approved: outcome === "accepted",
                ...(outcome === "accepted" || outcome === "declined"
                  ? {}
                  : { reason: str(data, "reason") ?? outcome }),
              }),
              "AI_APPROVAL_DECIDED",
            );
          } else if (str(detail, "kind") === "question") {
            const response = pick(data, "response");

            if (outcome === "accepted" && response !== undefined) {
              await settle(
                chats.inputs.answer({
                  inputId: str(detail, "inputId") ?? "",
                  answer: response,
                }),
                "AI_INPUT_ANSWERED",
              );
            }
          }

          await step(
            turnId,
            key,
            "interaction",
            stepStatus(
              outcome === "accepted" || outcome === "declined"
                ? "completed"
                : outcome,
            ),
            { outcome },
          );

          break;
        }

        case "usage.recorded": {
          const meters = options.usage?.meters;
          const usage = pick(data, "usage");

          if (
            options.usage === undefined ||
            meters === undefined ||
            str(data, "kind") !== "model" ||
            !isRecord(usage)
          ) {
            break;
          }

          const entries = [
            [meters.inputTokens, num(usage, "inputTokens")],
            [meters.outputTokens, num(usage, "outputTokens")],
            [meters.cacheReadTokens, num(usage, "cacheReadTokens")],
            [meters.cacheWriteTokens, num(usage, "cacheWriteTokens")],
            [
              meters.costMicroUsd,
              (() => {
                const cost = num(usage, "costUsd");

                return cost === undefined ? undefined : Math.round(cost * 1e6);
              })(),
            ],
          ].flatMap(([meter, quantity]) =>
            typeof meter === "string" &&
            typeof quantity === "number" &&
            quantity > 0
              ? [{ meter, quantity }]
              : [],
          );

          if (entries.length === 0) {
            break;
          }

          const position = event.meta?.position;

          await options.usage.client
            .recordMany({
              organizationId: target.organizationId,
              entries,
              idempotencyKey: `eve:${sessionId}:${position?.line ?? "x"}:${position?.index ?? 0}`,
              source: "eve:model",
              actor: target.ownerId,
              metadata: { sessionId, owner: pick(data, "owner") },
            })
            .orThrow();

          break;
        }

        case "turn.settled": {
          const status = RUN_STATES[str(data, "outcome") ?? ""];

          if (
            status === undefined ||
            turnId === undefined ||
            ended.has(turnId)
          ) {
            break;
          }

          const error = pick(data, "error");

          await chats.runs
            .release({
              chatId,
              streamId: streamOf(sessionId, turnId),
              status,
              ...(error === undefined
                ? {}
                : {
                    error: `${str(error, "code") ?? "error"}: ${str(error, "message") ?? ""}`,
                  }),
            })
            .orThrow();

          break;
        }

        default: {
          break;
        }
      }
    }
  }

  return {
    syncSession: pass,
    async sweepSessions(sweep = {}) {
      const ids = await store.behind({
        ...(sweep.olderThan === undefined
          ? {}
          : { olderThan: sweep.olderThan }),
        ...(sweep.limit === undefined ? {} : { limit: sweep.limit }),
      });

      let synced = 0;

      for (const id of ids) {
        const result = await pass(id);

        if (result.status !== "busy") {
          synced += 1;
        }
      }

      return synced;
    },
    queue: "eve_session_sync",
    async job(payload) {
      let result = await pass(payload.sessionId);

      // A long session needs several passes; stop when one reads nothing more.
      while (result.more) {
        result = await pass(payload.sessionId);
      }
    },
  };
}

/** Syncs one session once; `createSessionSync` is the same for many calls. */
export function syncSession(
  options: SyncSessionsOptions,
  sessionId: string,
): Promise<SyncSessionResult> {
  return createSessionSync(options).syncSession(sessionId);
}

/** Syncs the sessions a job has not caught up with; resolves with the count. */
export function sweepSessions(
  options: SyncSessionsOptions & {
    readonly olderThan?: string;
    readonly limit?: number;
  },
): Promise<number> {
  return createSessionSync(options).sweepSessions(options);
}
