import type { AiChat } from "../../blocks/ai-chat/ai-chat.ts";
import type { AiHarnessSessions } from "../../blocks/ai-chat/durable.ts";
import type { DbError } from "../../core/errors.ts";
import type { Result } from "../../core/result.ts";

import { errorText, sha256Hex } from "../../core/block-helpers.ts";
import { dbError } from "../../core/errors.ts";
import { isRecord } from "../../core/guards.ts";
import { problemResponse } from "../../core/problem.ts";
import { err, ok } from "../../core/result.ts";
import { badRequest, getJson } from "../http.ts";

/** The part of a `HarnessAgentSession` the routes use. */
export interface HarnessRouteSession {
  readonly sessionId: string;
  detach(): PromiseLike<unknown>;
  experimental_steerTurn(text: string): PromiseLike<void>;
}

/** The part of a `StreamTextResult` the route reads. */
export interface HarnessRouteResult {
  toUIMessageStreamResponse(): Response;
  /** Settles when the turn ended, or rejects when it failed. */
  readonly finishReason: PromiseLike<unknown>;
}

/**
 * The part of a `HarnessAgent` the route calls, so `@ai-sdk/harness` stays an
 * optional peer. A `HarnessAgent` satisfies it (`tests/ai-sdk/agents`).
 */
export interface HarnessRouteAgent<
  S extends HarnessRouteSession = HarnessRouteSession,
> {
  readonly harnessId: string;
  createSession(options: {
    sessionId?: string;
    // SAFETY at the call site: the SDK validates `resumeFrom` against the
    // harness's lifecycle schema, so the route passes what `detach()` returned.
    resumeFrom?: never;
    abortSignal?: AbortSignal;
  }): PromiseLike<S>;
  stream(options: {
    session: S;
    prompt: string;
    abortSignal?: AbortSignal;
  }): PromiseLike<HarnessRouteResult>;
}

/** A key that seals resume state. `key` is 32 random bytes, base64. */
export interface HarnessStateKey {
  readonly id: string;
  readonly key: string;
}

export interface HarnessStateCipher {
  /** Encrypts `state` for one chat and harness; the result is JSON-safe. */
  seal(
    state: unknown,
    binding: { chatId: string; harnessId: string },
  ): Promise<unknown>;
  /** Decrypts what `seal` returned; an error result when it was altered. */
  open(
    sealed: unknown,
    binding: { chatId: string; harnessId: string },
  ): Promise<Result<unknown>>;
}

const IV_BYTES = 12;

const toBase64 = (bytes: Uint8Array): string => {
  let text = "";

  for (const byte of bytes) {
    text += String.fromCodePoint(byte);
  }

  return btoa(text);
};

const fromBase64 = (text: string): Uint8Array<ArrayBuffer> => {
  const raw = atob(text);
  const bytes = new Uint8Array(raw.length);

  for (let index = 0; index < raw.length; index += 1) {
    bytes[index] = raw.codePointAt(index) ?? 0;
  }

  return bytes;
};

/**
 * AES-256-GCM over the harness's resume state, with a key ring: the first key
 * seals, every key opens, and the sealed value names the key that made it
 * (`kid`), so a rotation keeps old sessions readable. The chat and harness ids
 * are authenticated data, so a sealed value copied to another chat doesn't
 * open. Resume state can hold sandbox ids and harness credentials, so it is
 * never stored plain.
 */
export function harnessStateCipher(
  keys: readonly [HarnessStateKey, ...HarnessStateKey[]],
): HarnessStateCipher {
  const imported = new Map<string, Promise<CryptoKey>>();

  const keyOf = (id: string): Promise<CryptoKey> | undefined => {
    const found = keys.find((candidate) => candidate.id === id);

    if (!found) {
      return undefined;
    }

    let cached = imported.get(id);

    if (!cached) {
      cached = crypto.subtle.importKey(
        "raw",
        fromBase64(found.key),
        "AES-GCM",
        false,
        ["encrypt", "decrypt"],
      );
      imported.set(id, cached);
    }

    return cached;
  };

  const aad = (binding: { chatId: string; harnessId: string }) =>
    new TextEncoder().encode(`${binding.chatId}\n${binding.harnessId}`);

  return {
    async seal(state, binding) {
      const [current] = keys;
      const key = await keyOf(current.id);

      if (!key) {
        throw new Error("The harness state key could not be imported.");
      }

      const iv = crypto.getRandomValues(new Uint8Array(IV_BYTES));

      const data = await crypto.subtle.encrypt(
        { name: "AES-GCM", iv, additionalData: aad(binding) },
        key,
        new TextEncoder().encode(JSON.stringify(state ?? null)),
      );

      return {
        v: 1,
        kid: current.id,
        iv: toBase64(iv),
        ct: toBase64(new Uint8Array(data)),
      };
    },

    async open(sealed, binding) {
      if (
        !isRecord(sealed) ||
        sealed["v"] !== 1 ||
        typeof sealed["kid"] !== "string" ||
        typeof sealed["iv"] !== "string" ||
        typeof sealed["ct"] !== "string"
      ) {
        return err(dbError("unexpected", "The resume state is not sealed."));
      }

      const key = await keyOf(sealed["kid"]);

      if (!key) {
        return err(
          dbError("unexpected", "No key opens the resume state.", {
            hint: `The sealing key is ${sealed["kid"]}; add it back to the key ring.`,
          }),
        );
      }

      try {
        const plain = await crypto.subtle.decrypt(
          {
            name: "AES-GCM",
            iv: fromBase64(sealed["iv"]),
            additionalData: aad(binding),
          },
          key,
          fromBase64(sealed["ct"]),
        );

        const value: unknown = JSON.parse(new TextDecoder().decode(plain));

        return ok(value);
      } catch (error) {
        return err(
          dbError("unexpected", "The resume state could not be opened.", {
            hint: errorText(error),
          }),
        );
      }
    },
  };
}

/** One message a user sent while a turn ran. */
export interface SteeringMessage {
  readonly id: string;
  readonly text: string;
}

/**
 * Where a message sent during a turn waits for the turn to read it. The sender
 * and the running turn are separate requests, often on separate instances, so
 * it has to be shared storage.
 */
export interface SteeringMailbox {
  push(input: {
    chatId: string;
    messageId: string;
    text: string;
  }): Promise<Result<void>>;
  /** The messages pushed after `afterMessageId`, oldest first. */
  pending(input: {
    chatId: string;
    afterMessageId: string;
  }): Promise<Result<readonly SteeringMessage[]>>;
}

/**
 * A mailbox on the chat's own messages: a steering message is a user message on
 * the chat, so it is in the transcript, ordered, and readable only by the
 * people who can read the chat. The running turn reads the user messages after
 * the one that started it. Run it as the user (`createAiChat` with the user's
 * transport).
 */
export function chatSteering(chat: Pick<AiChat, "messages">): SteeringMailbox {
  return {
    async push({ chatId, messageId, text }) {
      const stored = await chat.messages.appendUser({
        chatId,
        message: {
          id: messageId,
          role: "user",
          parts: [{ type: "text", text }],
          metadata: { steering: true },
        },
      });

      return stored.ok ? ok(undefined) : err(stored.error);
    },
    async pending({ chatId, afterMessageId }) {
      const path = await chat.messages.path({ chatId });

      if (!path.ok) {
        return err(path.error);
      }

      const at = path.data.findIndex(
        (message) => message.id === afterMessageId,
      );

      if (at === -1) {
        return ok([]);
      }

      return ok(
        path.data
          .slice(at + 1)
          .flatMap((message) =>
            message.role === "user"
              ? [
                  {
                    id: message.id,
                    text: message.parts
                      .flatMap((part) =>
                        part.type === "text" ? [part.text] : [],
                      )
                      .join("\n"),
                  },
                ]
              : [],
          ),
      );
    },
  };
}

/** Who asks, for one harness request. */
export interface HarnessContext {
  readonly userId: string;
  readonly organizationId?: string;
  /** Keeps the function alive until the turn is saved: `after` in Next.js. */
  readonly waitUntil?: (promise: Promise<unknown>) => void;
}

export interface HarnessRouteOptions<S extends HarnessRouteSession> {
  readonly agent: HarnessRouteAgent<S>;
  readonly sessions: AiHarnessSessions;
  readonly cipher: HarnessStateCipher;
  /**
   * Whether the caller may drive this chat; the access check. Return an error
   * (`forbidden`, `not_found`) to refuse. Run it as the user so the chat's
   * policies decide.
   */
  readonly authorize: (
    context: HarnessContext,
    chatId: string,
  ) => Promise<DbError | undefined>;
  /** Reads the messages sent during the turn; omit to ignore steering. */
  readonly steering?: SteeringMailbox;
  /** The id of the message that started the turn; the steering baseline. */
  readonly messageId?: (body: Readonly<Record<string, unknown>>) => string;
  /** How often the turn reads the mailbox, in ms. Default 1000. */
  readonly steerPollMs?: number;
  /** Seconds the chat's session stays locked to this turn. Default 300. */
  readonly lockTtlSeconds?: number;
  /** Receives a failure to save state or steer; the turn goes on. */
  readonly onError?: (error: unknown) => void;
}

export interface HarnessRoute {
  respond(request: Request, context: HarnessContext): Promise<Response>;
}

const text = (value: unknown): string | undefined =>
  typeof value === "string" && value !== "" ? value : undefined;

const settle = async (value: PromiseLike<unknown>): Promise<void> => {
  try {
    await value;
  } catch {
    // The failure reaches the client through the stream.
  }
};

const sleep = (ms: number, signal: AbortSignal): Promise<void> =>
  new Promise((resolve) => {
    const timer = setTimeout(resolve, ms);

    signal.addEventListener(
      "abort",
      () => {
        clearTimeout(timer);
        resolve();
      },
      { once: true },
    );
  });

/**
 * A route for one turn of a `HarnessAgent` chat. It checks access, takes the
 * chat's session lock (a second turn gets 409), resumes the session from the
 * stored state, streams the turn as UI messages, feeds messages the user sent
 * meanwhile to the running turn, and when the turn ends detaches the session
 * and stores its resume state encrypted before it releases the lock. The body
 * is `{ chatId, prompt }`.
 */
export function harnessRoute<S extends HarnessRouteSession>(
  options: HarnessRouteOptions<S>,
): HarnessRoute {
  const { agent, sessions, cipher } = options;
  const { harnessId } = agent;
  const report = (error: unknown) => options.onError?.(error);

  return {
    async respond(request, context) {
      const body = await getJson(request);

      if (!isRecord(body)) {
        return badRequest("Expected a JSON object.");
      }

      const chatId = text(body["chatId"]);
      const prompt = text(body["prompt"]);

      if (chatId === undefined || prompt === undefined) {
        return badRequest("Expected a chatId and a prompt.");
      }

      const refused = await options.authorize(context, chatId);

      if (refused) {
        return problemResponse(refused);
      }

      const holder = crypto.randomUUID();

      const locked = await sessions.lock({
        chatId,
        harnessId,
        holder,
        ...(options.lockTtlSeconds === undefined
          ? {}
          : { ttlSeconds: options.lockTtlSeconds }),
      });

      if (!locked.ok) {
        return problemResponse(locked.error);
      }

      if (!locked.data) {
        return problemResponse(
          dbError("conflict", "This chat has a turn in progress.", {
            hint: "Send the message as a steering message, or wait for the turn.",
          }),
        );
      }

      const release = async () => {
        await sessions.unlock({ chatId, harnessId, holder });
      };

      const stored = await sessions.load({ chatId, harnessId });

      if (!stored.ok) {
        await release();

        return problemResponse(stored.error);
      }

      let resumeFrom: unknown;

      if (
        stored.data?.resumeState !== undefined &&
        stored.data.resumeState !== null
      ) {
        const opened = await cipher.open(stored.data.resumeState, {
          chatId,
          harnessId,
        });

        if (!opened.ok) {
          await release();

          return problemResponse(opened.error);
        }

        resumeFrom = opened.data;
      }

      const abort = new AbortController();
      request.signal.addEventListener("abort", () => {
        abort.abort();
      });

      let session: S;
      let result: HarnessRouteResult;

      try {
        session = await agent.createSession({
          sessionId: await sha256Hex(`${chatId}:${harnessId}`),
          abortSignal: abort.signal,
          // SAFETY: `resumeFrom` is what `detach()` returned for this chat and
          // harness, opened by the AEAD cipher; the SDK validates it again.
          ...(resumeFrom === undefined
            ? {}
            : { resumeFrom: resumeFrom as never }),
        });

        result = await agent.stream({
          session,
          prompt,
          abortSignal: abort.signal,
        });
      } catch (error) {
        await release();

        return problemResponse(dbError("network", errorText(error)));
      }

      const turnDone = new AbortController();
      const baseline = options.messageId?.(body) ?? text(body["messageId"]);

      const steer = async () => {
        if (!options.steering || baseline === undefined) {
          return;
        }

        const seen = new Set<string>();
        const interval = options.steerPollMs ?? 1000;

        const isDone = () => turnDone.signal.aborted;

        while (!isDone()) {
          await sleep(interval, turnDone.signal);

          if (isDone()) {
            return;
          }

          const pending = await options.steering.pending({
            chatId,
            afterMessageId: baseline,
          });

          if (!pending.ok) {
            report(pending.error);
            continue;
          }

          for (const message of pending.data) {
            if (seen.has(message.id) || message.text === "") {
              continue;
            }

            seen.add(message.id);

            try {
              await session.experimental_steerTurn(message.text);
            } catch (error) {
              report(error);
            }
          }
        }
      };

      const finish = async () => {
        await settle(result.finishReason);
        turnDone.abort();

        try {
          const state = await session.detach();
          const sealed = await cipher.seal(state, { chatId, harnessId });

          const saved = await sessions.upsert({
            chatId,
            harnessId,
            holder,
            patch: { resumeState: sealed, status: "idle" },
          });

          if (!saved.ok) {
            report(saved.error);
          }
        } catch (error) {
          report(error);
        } finally {
          await release();
        }
      };

      const work = Promise.all([steer(), finish()]);
      context.waitUntil?.(work);

      return result.toUIMessageStreamResponse();
    },
  };
}

export interface SteerRouteOptions {
  readonly steering: SteeringMailbox;
  readonly authorize: HarnessRouteOptions<HarnessRouteSession>["authorize"];
}

/**
 * The route a user's message goes to while a turn runs. The body is `{ chatId,
 * messageId, text }`; the answer is 202, and the running turn reads the message
 * on its next poll.
 */
export function steerRoute(options: SteerRouteOptions): HarnessRoute {
  return {
    async respond(request, context) {
      const body = await getJson(request);

      if (!isRecord(body)) {
        return badRequest("Expected a JSON object.");
      }

      const chatId = text(body["chatId"]);
      const messageId = text(body["messageId"]);
      const message = text(body["text"]);

      if (
        chatId === undefined ||
        messageId === undefined ||
        message === undefined
      ) {
        return badRequest("Expected a chatId, a messageId and a text.");
      }

      const refused = await options.authorize(context, chatId);

      if (refused) {
        return problemResponse(refused);
      }

      const pushed = await options.steering.push({
        chatId,
        messageId,
        text: message,
      });

      return pushed.ok
        ? new Response(null, { status: 202 })
        : problemResponse(pushed.error);
    },
  };
}
