import type { Experimental_SandboxSession } from "ai";

import type { AiSandbox, AiSandboxes } from "../blocks/ai-chat/sandboxes.ts";
import type { DbError } from "../core/errors.ts";
import type {
  CredentialProvider,
  CredentialRef,
  CredentialSubject,
} from "../credentials/provider.ts";

import { trackedSandbox } from "../ai-sdk/providers.ts";
import { isRecord } from "../core/block-helpers.ts";
import { dbError, isDbError } from "../core/errors.ts";
import { importOptionalPeer } from "../core/optional-peer.ts";
import { AsyncResult, err, ok } from "../core/result.ts";

/** The `provider` an adapter's rows carry in `ai_sandboxes`. */
export const VERCEL_SANDBOX_PROVIDER = "vercel";

/** The AI Gateway host a sandbox reaches with `gatewayOnly`. */
export const AI_GATEWAY_HOST = "ai-gateway.vercel.sh";

/** One rule of a domain in a network policy. */
export interface VercelNetworkRule {
  readonly match?: Readonly<Record<string, unknown>>;
  readonly transform?: readonly {
    readonly headers?: Readonly<Record<string, string>>;
  }[];
}

/** The egress firewall of a sandbox, as `@vercel/sandbox` takes it. */
export type VercelNetworkPolicy =
  | "allow-all"
  | "deny-all"
  | {
      readonly allow?:
        | readonly string[]
        | Readonly<Record<string, readonly VercelNetworkRule[]>>;
      readonly subnets?: {
        readonly allow?: readonly string[];
        readonly deny?: readonly string[];
      };
    };

/**
 * The `Sandbox.create` options the adapter sets or merges. Other keys pass
 * through to `@vercel/sandbox` unchanged.
 */
export interface VercelSandboxCreateOptions {
  readonly runtime?: string;
  readonly image?: string;
  readonly resources?: { readonly vcpus?: number };
  /** Session timeout in milliseconds; merged options keep the shortest. */
  readonly timeout?: number;
  readonly ports?: readonly number[];
  /** `false` discards the filesystem on stop instead of keeping a snapshot. */
  readonly persistent?: boolean;
  readonly networkPolicy?: VercelNetworkPolicy;
  readonly env?: Readonly<Record<string, string>>;
  readonly tags?: Readonly<Record<string, string>>;
  readonly region?: string;
  readonly [option: string]: unknown;
}

/** The part of a `@vercel/sandbox` `Sandbox` the adapter calls. */
export interface VercelSandboxInstance {
  readonly name: string;
  stop(options?: { signal?: AbortSignal }): Promise<unknown>;
  update(params: { networkPolicy?: VercelNetworkPolicy }): Promise<unknown>;
}

/** The part of `@vercel/sandbox` the adapter calls, typed structurally. */
export interface VercelSandboxModule {
  readonly Sandbox: {
    getOrCreate(
      params: Record<string, unknown>,
    ): Promise<VercelSandboxInstance>;
    get(
      params: {
        name: string;
        signal?: AbortSignal;
      } & Partial<VercelSandboxCredentials>,
    ): Promise<VercelSandboxInstance>;
  };
}

/** The part of `@ai-sdk/sandbox-vercel` the adapter calls. */
export interface VercelSandboxSessionModule {
  createVercelNetworkSandboxSessionFromNativeSandbox(
    sandbox: never,
  ): Experimental_SandboxSession;
}

/** A Vercel access token and its scope, for apps that don't run on Vercel. */
export interface VercelSandboxCredentials {
  readonly token: string;
  readonly teamId: string;
  readonly projectId: string;
}

export interface VercelSandboxesOptions {
  /** The ai-chat block's sandboxes, with a service transport. */
  readonly sandboxes: Pick<AiSandboxes, "register" | "touch">;
  /** Defaults to the deployment's OIDC token (`VERCEL_OIDC_TOKEN`). */
  readonly credentials?: VercelSandboxCredentials;
  /** Options for every sandbox, such as `untrusted`. */
  readonly defaults?: VercelSandboxCreateOptions;
  /** Prefix of the sandbox name; the chat id follows. Default `chat-`. */
  readonly namePrefix?: string;
  /** Milliseconds between two registry touches. Default 30000. */
  readonly touchEvery?: number;
  /** Returns `@vercel/sandbox`; defaults to importing it on first use. */
  readonly load?: () => Promise<unknown>;
  /** Returns `@ai-sdk/sandbox-vercel`; defaults to importing it on first use. */
  readonly loadSession?: () => Promise<unknown>;
}

export interface ForChatOptions {
  readonly userId?: string;
  /** Options for this chat's sandbox, merged over `defaults`. */
  readonly create?: VercelSandboxCreateOptions;
  /** Seconds without use before the idle-stop job stops it. */
  readonly idleSeconds?: number;
  readonly expiresAt?: Temporal.Instant;
  readonly signal?: AbortSignal;
}

/** A chat's sandbox: the AI SDK session, the native sandbox, its registry row. */
export interface VercelChatSandbox {
  /** Pass as `experimental_sandbox`; each use touches the registry row. */
  readonly session: Experimental_SandboxSession;
  readonly sandbox: VercelSandboxInstance;
  readonly row: AiSandbox;
}

export interface VercelSandboxes {
  /**
   * The chat's sandbox, created on first use and resumed after that. The
   * sandbox is named after the chat, so a stopped persistent sandbox comes back
   * with its files. A `networkPolicy` in `create` also applies to an existing
   * sandbox, so brokered tokens stay fresh.
   */
  forChat(
    organizationId: string,
    chatId: string,
    options?: ForChatOptions,
  ): AsyncResult<VercelChatSandbox>;
  /**
   * Wraps a sandbox the app created itself, such as a harness template's, as a
   * tracked session for its registry row.
   */
  session(
    sandbox: VercelSandboxInstance,
    row: Pick<AiSandbox, "id">,
  ): AsyncResult<Experimental_SandboxSession>;
  /**
   * Stops a claimed sandbox for `idleStopJob`. A sandbox Vercel no longer knows
   * counts as stopped, so the job doesn't retry it.
   */
  stop(sandbox: Pick<AiSandbox, "sandboxId">): Promise<void>;
}

/**
 * Options for code nobody reviewed: no network, one vCPU, five minutes, and no
 * snapshot kept on stop.
 */
export const untrusted: VercelSandboxCreateOptions = {
  networkPolicy: "deny-all",
  persistent: false,
  resources: { vcpus: 1 },
  timeout: 300_000,
};

/**
 * A network policy that reaches only the AI Gateway, with `token` added at the
 * firewall: code in the sandbox calls the gateway without holding the token.
 */
export function gatewayOnly(token: string): VercelNetworkPolicy {
  return {
    allow: {
      [AI_GATEWAY_HOST]: [
        { transform: [{ headers: { authorization: `Bearer ${token}` } }] },
      ],
    },
  };
}

export interface BrokeredOptions {
  /** The one host the sandbox may reach, with the token's headers added. */
  readonly domain: string;
  readonly subject: CredentialSubject;
  readonly scopes?: readonly string[];
  /** Milliseconds kept free before the token expires. Default 60000. */
  readonly margin?: number;
  /** The clock in epoch milliseconds, for tests. */
  readonly now?: () => number;
}

/**
 * Create options that reach only `domain`, with the credential's headers added
 * at the firewall, so the sandbox never holds the token. The session timeout
 * ends before the token expires.
 */
export function brokered(
  credentials: Pick<CredentialProvider, "getToken">,
  ref: CredentialRef,
  options: BrokeredOptions,
): AsyncResult<VercelSandboxCreateOptions> {
  return credentials
    .getToken(ref, {
      subject: options.subject,
      ...(options.scopes === undefined ? {} : { scopes: options.scopes }),
    })
    .map((token): VercelSandboxCreateOptions => {
      const networkPolicy: VercelNetworkPolicy = {
        allow: {
          [options.domain]: [
            { transform: [{ headers: { ...token.headers } }] },
          ],
        },
      };

      if (token.expiresAt === undefined) {
        return { networkPolicy };
      }

      const now = (options.now ?? Date.now)();

      const timeout =
        token.expiresAt.epochMilliseconds - now - (options.margin ?? 60_000);

      return { networkPolicy, timeout: Math.max(1000, timeout) };
    });
}

/** `layers` merged left to right; `timeout` keeps the shortest one set. */
export function mergeSandboxOptions(
  ...layers: readonly (VercelSandboxCreateOptions | undefined)[]
): VercelSandboxCreateOptions {
  const merged: Record<string, unknown> = {};
  let timeout: number | undefined;

  for (const layer of layers) {
    if (layer === undefined) {
      continue;
    }

    Object.assign(merged, layer);

    if (typeof layer.timeout === "number") {
      timeout =
        timeout === undefined
          ? layer.timeout
          : Math.min(timeout, layer.timeout);
    }
  }

  if (timeout !== undefined) {
    merged["timeout"] = timeout;
  }

  // SAFETY: merged holds only keys copied from VercelSandboxCreateOptions layers.
  return merged;
}

const isSandboxModule = (value: unknown): value is VercelSandboxModule =>
  isRecord(value) &&
  isRecord(value["Sandbox"]) &&
  typeof value["Sandbox"]["getOrCreate"] === "function" &&
  typeof value["Sandbox"]["get"] === "function";

const isSessionModule = (value: unknown): value is VercelSandboxSessionModule =>
  isRecord(value) &&
  typeof value["createVercelNetworkSandboxSessionFromNativeSandbox"] ===
    "function";

/** Loads a peer once; a failed load or a module of the wrong shape is retried. */
function peerLoader<M>(
  load: () => Promise<unknown>,
  is: (value: unknown) => value is M,
): () => Promise<M | null> {
  let pending: Promise<M | null> | undefined;

  return () =>
    (pending ??= load().then(
      (value) => {
        if (is(value)) {
          return value;
        }

        pending = undefined;

        return null;
      },
      (cause: unknown) => {
        pending = undefined;
        throw cause;
      },
    ));
}

const INSTALL = "pnpm add @vercel/sandbox @ai-sdk/sandbox-vercel";

const missing = (name: string): DbError =>
  dbError(
    "unsupported",
    `vercelSandboxes needs the ${name} package: ${INSTALL}`,
    { hint: "AI_SANDBOX_UNAVAILABLE" },
  );

/** The HTTP status of a `@vercel/sandbox` `APIError`, matched by shape. */
function statusOf(cause: unknown): number | undefined {
  if (!isRecord(cause) || !isRecord(cause["response"])) {
    return undefined;
  }

  const status = cause["response"]["status"];

  return typeof status === "number" ? status : undefined;
}

/**
 * A `@vercel/sandbox` failure as a `DbError`. The message is fixed per kind,
 * since the SDK's own message can quote the sandbox's output.
 */
export function sandboxErrorToDbError(cause: unknown): DbError {
  if (cause instanceof Error && cause.name === "AbortError") {
    return dbError("aborted", "The sandbox request was stopped.", {
      hint: "AI_SANDBOX_ABORTED",
    });
  }

  const status = statusOf(cause);

  if (status === 401 || status === 403) {
    return dbError("forbidden", "The sandbox is not available to this app.", {
      hint: "AI_SANDBOX_FORBIDDEN",
    });
  }

  if (status === 404) {
    return dbError("not_found", "The sandbox does not exist.", {
      hint: "AI_SANDBOX_NOT_FOUND",
    });
  }

  if (status === 429) {
    return dbError("rate_limited", "Too many sandboxes are running.", {
      hint: "AI_SANDBOX_LIMIT",
    });
  }

  return dbError("network", "The sandbox could not be reached.", {
    hint: "AI_SANDBOX_UNAVAILABLE",
  });
}

/**
 * Vercel Sandbox for the ai-chat block: one sandbox per chat, recorded in
 * `ai_sandboxes`, wrapped as an AI SDK sandbox session, and stopped by the
 * block's idle-stop job. Needs `@vercel/sandbox` and `@ai-sdk/sandbox-vercel`.
 */
export function vercelSandboxes(
  options: VercelSandboxesOptions,
): VercelSandboxes {
  const loadSdk = peerLoader(
    options.load ?? (() => importOptionalPeer("@vercel/sandbox")),
    isSandboxModule,
  );

  const loadSessions = peerLoader(
    options.loadSession ?? (() => importOptionalPeer("@ai-sdk/sandbox-vercel")),
    isSessionModule,
  );

  const wrap = async (
    sandbox: VercelSandboxInstance,
    id: string,
  ): Promise<Experimental_SandboxSession | DbError> => {
    const module = await loadSessions();

    if (module === null) {
      return missing("@ai-sdk/sandbox-vercel");
    }

    // SAFETY: the sandbox came from @vercel/sandbox, the type the function takes.
    const native = sandbox as never;

    return trackedSandbox(
      module.createVercelNetworkSandboxSessionFromNativeSandbox(native),
      {
        sandboxes: options.sandboxes,
        id,
        ...(options.touchEvery === undefined
          ? {}
          : { every: options.touchEvery }),
      },
    );
  };

  return {
    forChat(organizationId, chatId, chatOptions = {}) {
      const name = `${options.namePrefix ?? "chat-"}${chatId}`;
      const create = mergeSandboxOptions(options.defaults, chatOptions.create);

      return options.sandboxes
        .register({
          organizationId,
          sandbox: {
            provider: VERCEL_SANDBOX_PROVIDER,
            sandboxId: name,
            chatId,
            ...(chatOptions.userId === undefined
              ? {}
              : { userId: chatOptions.userId }),
            ...(chatOptions.idleSeconds === undefined
              ? {}
              : { idleSeconds: chatOptions.idleSeconds }),
            ...(chatOptions.expiresAt === undefined
              ? {}
              : { expiresAt: chatOptions.expiresAt }),
          },
        })
        .andThen(async (row) => {
          const module = await loadSdk();

          if (module === null) {
            return err(missing("@vercel/sandbox"));
          }

          const fresh = { created: false };
          let sandbox: VercelSandboxInstance;

          try {
            sandbox = await module.Sandbox.getOrCreate({
              ...create,
              ...options.credentials,
              name,
              ...(chatOptions.signal === undefined
                ? {}
                : { signal: chatOptions.signal }),
              onCreate: () => {
                fresh.created = true;

                return Promise.resolve();
              },
            });

            if (!fresh.created && create.networkPolicy !== undefined) {
              await sandbox.update({ networkPolicy: create.networkPolicy });
            }
          } catch (cause) {
            return err(sandboxErrorToDbError(cause));
          }

          const session = await wrap(sandbox, row.id);

          return isDbError(session)
            ? err(session)
            : ok({ session, sandbox, row });
        });
    },
    session(sandbox, row) {
      return AsyncResult.from(async () => {
        const session = await wrap(sandbox, row.id);

        return isDbError(session) ? err(session) : ok(session);
      });
    },
    async stop(sandbox) {
      const module = await loadSdk();

      if (module === null) {
        throw new TypeError(missing("@vercel/sandbox").message);
      }

      try {
        const native = await module.Sandbox.get({
          ...options.credentials,
          name: sandbox.sandboxId,
        });

        await native.stop();
      } catch (cause) {
        if (statusOf(cause) !== 404) {
          throw cause;
        }
      }
    },
  };
}
