import type { AiRun } from "../ai-chat/durable.ts";
import type { AiChat } from "../ai-chat/index.ts";
import type { Agent } from "./agents.ts";

import { isRecord } from "../shared.ts";

/** The A2A protocol version the card and the handler speak. */
export const A2A_PROTOCOL_VERSION = "1.0";

/** Where an Agent Card is served (A2A section 8.2). */
export const A2A_CARD_PATH = "/.well-known/agent-card.json";

export interface A2AAgentSkill {
  readonly id: string;
  readonly name: string;
  readonly description: string;
  readonly tags: readonly string[];
  readonly examples?: readonly string[];
}

export interface A2AAgentInterface {
  readonly url: string;
  readonly protocolBinding: "JSONRPC";
  readonly protocolVersion: string;
}

/** An Agent Card as `a2a.proto` v1.0.1 defines it, in its JSON form. */
export interface A2AAgentCard {
  readonly name: string;
  readonly description: string;
  readonly supportedInterfaces: readonly A2AAgentInterface[];
  readonly provider?: { readonly organization: string; readonly url: string };
  readonly version: string;
  readonly documentationUrl?: string;
  readonly capabilities: {
    readonly streaming: boolean;
    readonly pushNotifications: boolean;
    readonly extendedAgentCard: boolean;
  };
  readonly securitySchemes?: Readonly<Record<string, unknown>>;
  readonly securityRequirements?: readonly unknown[];
  readonly defaultInputModes: readonly string[];
  readonly defaultOutputModes: readonly string[];
  readonly skills: readonly A2AAgentSkill[];
}

export interface AgentCardOptions {
  readonly name: string;
  readonly description: string;
  /** The agent's own version, not the protocol's. */
  readonly version: string;
  /** The URL of the JSON-RPC endpoint {@link createA2AHandler} serves. */
  readonly url: string;
  readonly provider?: { readonly organization: string; readonly url: string };
  readonly documentationUrl?: string;
  /** The A2A `securitySchemes` map; copied as given. */
  readonly securitySchemes?: Readonly<Record<string, unknown>>;
  readonly securityRequirements?: readonly unknown[];
  /** Whether the endpoint serves `SendStreamingMessage`. Default `true`. */
  readonly streaming?: boolean;
}

type CardAgent = Pick<
  Agent,
  "slug" | "name" | "description" | "tools" | "starters" | "visibility"
>;

/**
 * The card of the agents an app publishes: one skill per saved agent. Only
 * `public` agents appear unless `includeOrganization` is set, so a public card
 * never lists private agents.
 */
export function agentCard(
  agents: readonly CardAgent[],
  options: AgentCardOptions & { readonly includeOrganization?: boolean },
): A2AAgentCard {
  const visible = agents.filter(
    (agent) =>
      agent.visibility === "public" ||
      (options.includeOrganization === true &&
        agent.visibility === "organization"),
  );

  return {
    name: options.name,
    description: options.description,
    supportedInterfaces: [
      {
        url: options.url,
        protocolBinding: "JSONRPC",
        protocolVersion: A2A_PROTOCOL_VERSION,
      },
    ],
    version: options.version,
    capabilities: {
      streaming: options.streaming ?? true,
      pushNotifications: false,
      extendedAgentCard: false,
    },
    defaultInputModes: ["text/plain"],
    defaultOutputModes: ["text/plain"],
    skills: visible.map((agent) => ({
      id: agent.slug,
      name: agent.name,
      description: agent.description === "" ? agent.name : agent.description,
      tags: agent.tools.length === 0 ? ["agent"] : ["agent", ...agent.tools],
      ...(agent.starters.length === 0 ? {} : { examples: agent.starters }),
    })),
    ...(options.provider === undefined ? {} : { provider: options.provider }),
    ...(options.documentationUrl === undefined
      ? {}
      : { documentationUrl: options.documentationUrl }),
    ...(options.securitySchemes === undefined
      ? {}
      : { securitySchemes: options.securitySchemes }),
    ...(options.securityRequirements === undefined
      ? {}
      : { securityRequirements: options.securityRequirements }),
  };
}

/** The card as a cacheable response, with an `ETag` and `If-None-Match`. */
export async function agentCardResponse(
  request: Request,
  card: A2AAgentCard,
  options: { readonly maxAge?: number } = {},
): Promise<Response> {
  const body = JSON.stringify(card);

  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(body),
  );

  const etag = `"${[...new Uint8Array(digest).slice(0, 12)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("")}"`;

  const headers = {
    "cache-control": `public, max-age=${String(options.maxAge ?? 300)}`,
    etag,
  };

  if (request.headers.get("if-none-match") === etag) {
    return new Response(null, { status: 304, headers });
  }

  return new Response(body, {
    headers: { ...headers, "content-type": "application/json" },
  });
}

/** The A2A task states a chat run maps to. */
export type A2ATaskState =
  | "TASK_STATE_SUBMITTED"
  | "TASK_STATE_WORKING"
  | "TASK_STATE_COMPLETED"
  | "TASK_STATE_FAILED"
  | "TASK_STATE_CANCELED";

export interface A2APart {
  readonly text: string;
}

export interface A2AMessage {
  readonly messageId: string;
  readonly role: "ROLE_USER" | "ROLE_AGENT";
  readonly parts: readonly A2APart[];
  readonly contextId?: string;
  readonly taskId?: string;
}

export interface A2ATask {
  readonly id: string;
  readonly contextId: string;
  readonly status: {
    readonly state: A2ATaskState;
    readonly message?: A2AMessage;
    readonly timestamp?: string;
  };
  readonly artifacts?: readonly {
    readonly artifactId: string;
    readonly name?: string;
    readonly parts: readonly A2APart[];
  }[];
}

const TERMINAL: ReadonlySet<A2ATaskState> = new Set([
  "TASK_STATE_COMPLETED",
  "TASK_STATE_FAILED",
  "TASK_STATE_CANCELED",
]);

/** Whether a task has ended; a terminal task takes no more messages. */
export const isTerminalTask = (state: A2ATaskState): boolean =>
  TERMINAL.has(state);

/** The A2A state of a run: a queued run is submitted, an active one working. */
export function taskStateOf(status: AiRun["status"]): A2ATaskState {
  switch (status) {
    case "queued": {
      return "TASK_STATE_SUBMITTED";
    }

    case "running":
    case "cancel_requested": {
      return "TASK_STATE_WORKING";
    }

    case "completed": {
      return "TASK_STATE_COMPLETED";
    }

    case "failed": {
      return "TASK_STATE_FAILED";
    }

    case "cancelled": {
      return "TASK_STATE_CANCELED";
    }

    default: {
      const unreachable: never = status;

      return unreachable;
    }
  }
}

/** The text of the answer a finished run produced, when the app has it. */
export type A2AAnswer = string | undefined;

/**
 * The A2A task of a run: the run id is the task id and the chat id the context
 * id. The answer, once the run completed, is the one artifact.
 */
export function taskOf(run: AiRun, answer?: A2AAnswer): A2ATask {
  const state = taskStateOf(run.status);

  return {
    id: run.id,
    contextId: run.chatId,
    status: {
      state,
      timestamp: (run.endedAt ?? run.startedAt).toString(),
      ...(state === "TASK_STATE_FAILED" && run.error !== undefined
        ? {
            message: {
              messageId: `${run.id}:error`,
              role: "ROLE_AGENT",
              parts: [{ text: run.error }],
            },
          }
        : {}),
    },
    ...(state === "TASK_STATE_COMPLETED" && answer !== undefined
      ? {
          artifacts: [
            {
              artifactId: `${run.id}:answer`,
              name: "answer",
              parts: [{ text: answer }],
            },
          ],
        }
      : {}),
  };
}

/** The A2A errors the handler returns, with the JSON-RPC codes of section 5.4. */
export const A2A_ERRORS = {
  parse: { code: -32_700, reason: "PARSE_ERROR" },
  invalidRequest: { code: -32_600, reason: "INVALID_REQUEST" },
  methodNotFound: { code: -32_601, reason: "METHOD_NOT_FOUND" },
  invalidParams: { code: -32_602, reason: "INVALID_PARAMS" },
  internal: { code: -32_603, reason: "INTERNAL" },
  taskNotFound: { code: -32_001, reason: "TASK_NOT_FOUND" },
  taskNotCancelable: { code: -32_002, reason: "TASK_NOT_CANCELABLE" },
  unsupportedOperation: { code: -32_004, reason: "UNSUPPORTED_OPERATION" },
  contentTypeNotSupported: {
    code: -32_005,
    reason: "CONTENT_TYPE_NOT_SUPPORTED",
  },
  versionNotSupported: { code: -32_009, reason: "VERSION_NOT_SUPPORTED" },
} as const;

type A2AErrorKind = keyof typeof A2A_ERRORS;

/** The chat client's methods the handler calls. */
export interface A2AChatClient {
  readonly chats: Pick<AiChat["chats"], "create" | "get">;
  readonly messages: Pick<AiChat["messages"], "appendUser" | "path">;
  readonly runs: Pick<AiChat["runs"], "get" | "stop">;
}

/** What `resolve` returns for an authenticated request. */
export interface A2ASession {
  /** A chat client that acts as the caller. */
  readonly chat: A2AChatClient;
  /** The organization new chats belong to; `null` for a chat outside one. */
  readonly organizationId: string | null;
  /**
   * Starts the run that answers the chat's last message with the agent whose
   * slug is `agent` (when given), and resolves to the run's id. The app owns
   * the model call: this is where it claims the stream and runs the model.
   */
  start(input: {
    readonly chatId: string;
    readonly agent: string | undefined;
  }): Promise<{ readonly runId: string }>;
}

export interface A2AHandlerOptions {
  /**
   * The caller's session, or `undefined` for a request without valid
   * credentials (answered with 401 and `WWW-Authenticate`).
   */
  resolve(request: Request): Promise<A2ASession | undefined>;
  /** The `WWW-Authenticate` challenge of a 401. Default `Bearer`. */
  readonly challenge?: string;
  /** Milliseconds between run lookups on a stream. Default 1000. */
  readonly pollMs?: number;
  /** A stream ends after this many milliseconds. Default 300000. */
  readonly streamTimeoutMs?: number;
}

const json = (body: unknown, status = 200): Response =>
  Response.json(body, {
    status,
    headers: { "content-type": "application/json" },
  });

const rpcError = (
  id: unknown,
  kind: A2AErrorKind,
  message: string,
): Response => {
  const { code, reason } = A2A_ERRORS[kind];

  return json({
    jsonrpc: "2.0",
    id: id ?? null,
    error: {
      code,
      message,
      data: [
        {
          "@type": "type.googleapis.com/google.rpc.ErrorInfo",
          reason,
          domain: "a2a-protocol.org",
        },
      ],
    },
  });
};

const rpcResult = (id: unknown, result: unknown): Response =>
  json({ jsonrpc: "2.0", id, result });

function textOfParts(value: unknown): string | undefined {
  if (!Array.isArray(value) || value.length === 0) {
    return undefined;
  }

  const texts: string[] = [];

  for (const part of value) {
    if (!isRecord(part) || typeof part["text"] !== "string") {
      return undefined;
    }

    texts.push(part["text"]);
  }

  return texts.join("\n");
}

/** The text of the last assistant message of a chat path. */
function lastAnswer(
  path: readonly {
    readonly role: string;
    readonly parts: readonly { readonly type: string }[];
  }[],
): A2AAnswer {
  const message = path.findLast((item) => item.role === "assistant");

  if (message === undefined) {
    return undefined;
  }

  const texts = message.parts.flatMap((part) =>
    "text" in part && typeof part.text === "string" ? [part.text] : [],
  );

  return texts.length === 0 ? undefined : texts.join("");
}

async function taskFor(
  session: A2ASession,
  runId: string,
): Promise<A2ATask | undefined> {
  const run = await session.chat.runs.get(runId);

  if (!run.ok) {
    return undefined;
  }

  if (run.data.status !== "completed") {
    return taskOf(run.data);
  }

  const path = await session.chat.messages.path(run.data.chatId);

  return taskOf(run.data, path.ok ? lastAnswer(path.data) : undefined);
}

const sse = (id: unknown, result: unknown): string =>
  `data: ${JSON.stringify({ jsonrpc: "2.0", id, result })}\n\n`;

function stream(
  session: A2ASession,
  id: unknown,
  runId: string,
  options: A2AHandlerOptions,
  signal: AbortSignal,
): Response {
  const pollMs = options.pollMs ?? 1000;
  const deadline = Date.now() + (options.streamTimeoutMs ?? 300_000);
  const encoder = new TextEncoder();

  const body = new ReadableStream<Uint8Array>({
    async start(controller) {
      let last: A2ATaskState | undefined;

      try {
        while (!signal.aborted && Date.now() < deadline) {
          const task = await taskFor(session, runId);

          if (task === undefined) {
            break;
          }

          if (last === undefined) {
            controller.enqueue(encoder.encode(sse(id, { task })));
          } else if (task.status.state !== last) {
            controller.enqueue(
              encoder.encode(
                sse(id, {
                  ...(task.artifacts === undefined
                    ? {}
                    : {
                        artifactUpdate: {
                          taskId: task.id,
                          contextId: task.contextId,
                          artifact: task.artifacts[0],
                          lastChunk: true,
                        },
                      }),
                }),
              ),
            );

            controller.enqueue(
              encoder.encode(
                sse(id, {
                  statusUpdate: {
                    taskId: task.id,
                    contextId: task.contextId,
                    status: task.status,
                  },
                }),
              ),
            );
          }

          last = task.status.state;

          if (isTerminalTask(task.status.state)) {
            break;
          }

          await new Promise((resolve) => {
            setTimeout(resolve, pollMs);
          });
        }
      } finally {
        controller.close();
      }
    },
  });

  return new Response(body, {
    headers: {
      "content-type": "text/event-stream",
      "cache-control": "no-cache",
    },
  });
}

/**
 * A JSON-RPC 2.0 endpoint for A2A 1.0: `SendMessage`, `SendStreamingMessage`,
 * `GetTask` and `CancelTask` over the app's ai-chat. A task is a chat run, its
 * context the chat. Each call needs `A2A-Version: 1.0`; a request without it
 * reads as 0.3 and fails with `VersionNotSupportedError`.
 */
export function createA2AHandler(
  options: A2AHandlerOptions,
): (request: Request) => Promise<Response> {
  return async (request) => {
    if (request.method !== "POST") {
      return new Response(null, { status: 405, headers: { allow: "POST" } });
    }

    const session = await options.resolve(request);

    if (session === undefined) {
      return new Response(null, {
        status: 401,
        headers: { "www-authenticate": options.challenge ?? "Bearer" },
      });
    }

    let envelope: unknown;

    try {
      envelope = await request.json();
    } catch {
      return rpcError(null, "parse", "The body is not JSON");
    }

    if (
      !isRecord(envelope) ||
      envelope["jsonrpc"] !== "2.0" ||
      typeof envelope["method"] !== "string"
    ) {
      return rpcError(null, "invalidRequest", "Not a JSON-RPC 2.0 request");
    }

    const { id, method } = envelope;
    const params = isRecord(envelope["params"]) ? envelope["params"] : {};

    const version =
      request.headers.get("a2a-version") ??
      new URL(request.url).searchParams.get("A2A-Version");

    if (version !== A2A_PROTOCOL_VERSION) {
      return rpcError(
        id,
        "versionNotSupported",
        `This endpoint speaks A2A ${A2A_PROTOCOL_VERSION}: send the A2A-Version header`,
      );
    }

    switch (method) {
      case "SendMessage":
      case "SendStreamingMessage": {
        const message = isRecord(params["message"])
          ? params["message"]
          : undefined;

        const text =
          message === undefined ? undefined : textOfParts(message["parts"]);

        if (message === undefined || typeof message["messageId"] !== "string") {
          return rpcError(id, "invalidParams", "message.messageId is required");
        }

        if (text === undefined) {
          return rpcError(
            id,
            "contentTypeNotSupported",
            "Only text parts are supported",
          );
        }

        const metadata = isRecord(params["metadata"])
          ? params["metadata"]
          : undefined;

        const agent =
          typeof metadata?.["agent"] === "string"
            ? metadata["agent"]
            : undefined;

        let chatId: string;

        if (typeof message["taskId"] === "string") {
          const known = await session.chat.runs.get(message["taskId"]);

          if (!known.ok) {
            return rpcError(
              id,
              "taskNotFound",
              "No task you can see has this id",
            );
          }

          if (isTerminalTask(taskStateOf(known.data.status))) {
            return rpcError(
              id,
              "unsupportedOperation",
              "The task ended; start a new one in the same context",
            );
          }

          chatId = known.data.chatId;
        } else if (typeof message["contextId"] === "string") {
          const chat = await session.chat.chats.get(message["contextId"]);

          if (!chat.ok) {
            return rpcError(
              id,
              "invalidParams",
              "No chat you can see has this contextId",
            );
          }

          chatId = chat.data.id;
        } else {
          const created = await session.chat.chats.create(
            session.organizationId,
          );

          if (!created.ok) {
            return rpcError(id, "internal", "The chat could not be created");
          }

          chatId = created.data.id;
        }

        const appended = await session.chat.messages.appendUser(chatId, {
          id: message["messageId"],
          role: "user",
          parts: [{ type: "text", text }],
        });

        if (!appended.ok) {
          return rpcError(id, "internal", "The message could not be stored");
        }

        const started = await session
          .start({ chatId, agent })
          .catch(() => undefined);

        if (started === undefined) {
          return rpcError(id, "internal", "The run could not start");
        }

        if (method === "SendStreamingMessage") {
          return stream(session, id, started.runId, options, request.signal);
        }

        const configuration = isRecord(params["configuration"])
          ? params["configuration"]
          : {};

        if (configuration["returnImmediately"] === true) {
          const task = await taskFor(session, started.runId);

          return task === undefined
            ? rpcError(id, "internal", "The run is not readable")
            : rpcResult(id, { task });
        }

        const deadline = Date.now() + (options.streamTimeoutMs ?? 300_000);

        let task = await taskFor(session, started.runId);

        while (
          task !== undefined &&
          !isTerminalTask(task.status.state) &&
          Date.now() < deadline
        ) {
          await new Promise((resolve) => {
            setTimeout(resolve, options.pollMs ?? 1000);
          });
          task = await taskFor(session, started.runId);
        }

        return task === undefined
          ? rpcError(id, "internal", "The run is not readable")
          : rpcResult(id, { task });
      }

      case "GetTask": {
        const taskId = typeof params["id"] === "string" ? params["id"] : "";
        const task = taskId === "" ? undefined : await taskFor(session, taskId);

        return task === undefined
          ? rpcError(id, "taskNotFound", "No task you can see has this id")
          : rpcResult(id, task);
      }

      case "CancelTask": {
        const taskId = typeof params["id"] === "string" ? params["id"] : "";

        const run =
          taskId === "" ? undefined : await session.chat.runs.get(taskId);

        if (run === undefined || !run.ok) {
          return rpcError(
            id,
            "taskNotFound",
            "No task you can see has this id",
          );
        }

        if (isTerminalTask(taskStateOf(run.data.status))) {
          return rpcError(id, "taskNotCancelable", "The task already ended");
        }

        await session.chat.runs.stop(run.data.chatId);
        const task = await taskFor(session, taskId);

        return task === undefined
          ? rpcError(id, "taskNotFound", "No task you can see has this id")
          : rpcResult(id, task);
      }

      default: {
        return rpcError(id, "methodNotFound", `Unknown method ${method}`);
      }
    }
  };
}
