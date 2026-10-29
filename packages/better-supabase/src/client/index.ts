import type {
  SupabaseClient,
  SupabaseClientOptions,
} from "@supabase/supabase-js";

import { createBrowserClient } from "@supabase/ssr";
import { createClient as createSupabaseClient } from "@supabase/supabase-js";

import type { SessionEncoding } from "../auth/session.ts";
import type { BetterSupabase } from "../core/define.ts";
import type { PublicEnv } from "../env/index.ts";
import type { AnyFunctions, AnyModels } from "../schema/types.ts";
import type { BetterClient, BindClientOptions } from "./bind.ts";
import type { ClientPorts } from "./ports.ts";

import { EnvValidationError, parseEnv } from "../env/index.ts";
import { bindClient } from "./bind.ts";
import { storageUpload } from "./ports.ts";
import { webPorts } from "./web-ports.ts";

export { bindClient } from "./bind.ts";

export { AUTHZ_EVENT, authzUserTopic } from "../core/authz-topic.ts";

export type { AuthzVersionSource } from "../core/authz-topic.ts";

export { functions } from "./functions.ts";

export type {
  FunctionContract,
  FunctionContracts,
  FunctionsHost,
  InvokeOptions,
  TypedFunctions,
} from "./functions.ts";

export type {
  AuthSnapshot,
  AuthUser,
  BetterClient,
  BindClientOptions,
  ClientAuth,
} from "./bind.ts";

export { memoryStorage, storageUpload } from "./ports.ts";

export type {
  ClientPorts,
  DeepLinkPort,
  FilePickerPort,
  KeyboardPort,
  PickedFile,
  PickFilesOptions,
  PushTokenPort,
  Shortcut,
  StoragePort,
  TopicHandle,
  TopicPort,
  TopicWatch,
  UploadDestination,
  UploadPort,
} from "./ports.ts";

export { liveEngine, memoryEngine } from "../bindings/data-engine.ts";

export type {
  DataChanges,
  DataEngine,
  DataEngineOptions,
  DataEntry,
  DataSync,
  DataSyncState,
  LiveEngineOptions,
  LocalTablesOption,
} from "../bindings/data-engine.ts";

export { defineController, whileSignedIn } from "../blocks/controller.ts";

export type {
  AuthPort,
  Controller,
  ControllerParts,
  ControllerState,
} from "../blocks/controller.ts";

export {
  webDeepLinks,
  webFilePicker,
  webKeyboard,
  webPorts,
  webPushToken,
  webStorage,
} from "./web-ports.ts";

export type { PushRegistrationLike, WebPushTokenOptions } from "./web-ports.ts";

export interface ClientOptions {
  /** URL and publishable key. Not needed when `client` is given. */
  readonly env?: PublicEnv;
  /**
   * Bring your own supabase-js client (custom storage). React Native apps use
   * `better-supabase/client/native`, which doesn't load `@supabase/ssr`.
   */
  readonly client?: SupabaseClient;
  /**
   * `cookies` (default) shares the session with the server through
   * `@supabase/ssr`; `local` keeps it in localStorage for SPAs without a
   * server.
   */
  readonly storage?: "cookies" | "local";
  readonly cookies?: {
    /**
     * `tokens-only` keeps the user object out of the cookie (it lives in
     * `auth.userStorage`, localStorage by default), so cookies stay small. Use
     * the same value as the server's `encode`. Defaults to `user-and-tokens`.
     */
    readonly encode?: SessionEncoding;
  };
  readonly auth?: {
    /** Where auth-js keeps the user object with `cookies.encode: 'tokens-only'`. */
    readonly userStorage?: UserStorage;
  };
  /**
   * `staleTime` for every query option in `bsb.queries`. Above zero, a remount
   * or a window focus reuses cached rows instead of refetching.
   */
  readonly staleTime?: number;
  /**
   * Platform services for the block hooks, over the web defaults (`webPorts()`
   * and an upload port over Supabase Storage).
   */
  readonly ports?: ClientPorts;
  /**
   * `blockConfig` from `blocks.generated.ts`: the block hooks call the schema,
   * function names and topics `gen` wrote.
   */
  readonly blocks?: BindClientOptions["blocks"];
  /**
   * The organization `db` and the hooks act in; default the session's
   * organization claim. Pass a function for one picked in the UI.
   */
  readonly organization?: BindClientOptions["organization"];
  /**
   * Where the data hooks keep their reads: `queryEngine(queryClient)` from
   * `better-supabase/query`, an engine over a local database, or one in memory
   * by default.
   */
  readonly engine?: BindClientOptions["engine"];
}

type UserStorage = NonNullable<
  NonNullable<SupabaseClientOptions<"public">["auth"]>["userStorage"]
>;

function clientFor(options: ClientOptions): SupabaseClient {
  if (options.client) {
    return options.client;
  }

  if (!options.env) {
    throw new TypeError(
      "createClient needs `env` ({ url, publishableKey }) or `client`",
    );
  }

  const checked = parseEnv({
    SUPABASE_URL: options.env.url,
    SUPABASE_PUBLISHABLE_KEY: options.env.publishableKey,
  });

  if (!checked.ok) {
    throw new EnvValidationError(checked.issues);
  }

  const userStorage = options.auth?.userStorage;
  const auth = userStorage ? { auth: { userStorage } } : {};

  if (options.storage === "local") {
    // oxlint-disable-next-line typescript/no-unsafe-return -- supabase-js infers `any` for the schema name without a Database type.
    return createSupabaseClient(
      checked.env.url,
      checked.env.publishableKey,
      auth,
    );
  }

  const encode = options.cookies?.encode;

  // oxlint-disable-next-line typescript/no-unsafe-return -- supabase-js infers `any` for the schema name without a Database type.
  return createBrowserClient(checked.env.url, checked.env.publishableKey, {
    ...auth,
    ...(encode ? { cookies: { encode } } : {}),
  });
}

/**
 * The browser side: a supabase-js client, repositories that follow the session,
 * TanStack Query options and an auth store for UI state.
 *
 * ```ts
 * export const bsb = createClient(betterSupabase, {
 *   env: { url, publishableKey },
 * });
 * ```
 */
export function createClient<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
  B = unknown,
>(
  betterSupabase: BetterSupabase<M, D, F, E, C, P, B>,
  options: ClientOptions = {},
): BetterClient<M, F, E, C, P, B> {
  const supabase = clientFor(options);

  return bindClient(betterSupabase, supabase, {
    ...(options.staleTime === undefined
      ? {}
      : { staleTime: options.staleTime }),
    ports: { ...webPorts(), upload: storageUpload(supabase), ...options.ports },
    ...(options.blocks === undefined ? {} : { blocks: options.blocks }),
    ...(options.organization === undefined
      ? {}
      : { organization: options.organization }),
    ...(options.engine === undefined ? {} : { engine: options.engine }),
  });
}
