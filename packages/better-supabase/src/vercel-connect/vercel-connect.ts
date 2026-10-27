import type { Result } from "../core/result.ts";
import type {
  CredentialProvider,
  CredentialRef,
  CredentialSubject,
  CredentialToken,
  GetTokenOptions,
  StartAuthorizationResult,
} from "../credentials/provider.ts";

import { isRecord } from "../core/block-helpers.ts";
import { DbException, dbError } from "../core/errors.ts";
import { importOptionalPeer } from "../core/optional-peer.ts";
import { AsyncResult, err, ok } from "../core/result.ts";
import { optionalTemporal } from "../core/temporal.ts";

/** An RFC 9396 authorization detail; `type` names its kind. */
export interface VercelConnectAuthorizationDetail {
  type: string;
  [key: string]: unknown;
}

const isDetail = (value: unknown): value is VercelConnectAuthorizationDetail =>
  isRecord(value) && typeof value["type"] === "string";

interface ConnectTokenParams {
  subject: CredentialSubject;
  installationId?: string;
  audience?: string[];
  scopes?: string[];
  resources?: string[];
  authorizationDetails?: VercelConnectAuthorizationDetail[];
  validityBufferMs?: number;
}

interface ConnectOptions {
  vercelToken?: string;
  forceRefresh?: boolean;
  region?: string;
}

interface ConnectAuthorizationOptions {
  vercelToken?: string;
  callbackUrl?: string;
  deviceCode?: boolean;
  prompt?: string;
  region?: string;
}

interface ConnectAuthorization {
  url: string;
  request?: string;
  verifier?: string;
  deviceCode?: string;
  expiresAt?: number;
}

/** The token response from `@vercel/connect`, typed structurally. */
export interface VercelConnectTokenResponse {
  token: string;
  tokenId?: string;
  expiresAt: number;
  connector?: { id: string; uid: string; type: string };
  name?: string;
  installationId?: string;
  tenantId?: string;
  externalSubject?: string;
  metadata?: Record<string, unknown>;
  claims?: Record<string, unknown>;
}

/** What `getConnectorMetadata` returns, typed structurally. */
export interface VercelConnectorMetadata {
  id: string;
  uid: string;
  name: string;
  type: string;
  service: string;
  clientUrl?: string;
}

/** The part of `@vercel/connect` this provider calls, typed structurally. */
export interface VercelConnectModule {
  getTokenResponse(
    connector: string,
    params: ConnectTokenParams,
    options?: ConnectOptions,
  ): Promise<VercelConnectTokenResponse>;
  revokeToken(
    connector: string,
    params: { subject: CredentialSubject; installationId?: string },
    options?: ConnectOptions,
  ): Promise<void>;
  startAuthorization(
    connector: string,
    params: ConnectTokenParams,
    options?: ConnectAuthorizationOptions,
  ): Promise<ConnectAuthorization>;
  deleteTokenCacheEntry?(connector: string, params: ConnectTokenParams): void;
  getConnectorMetadata?(
    connector: string,
    options?: ConnectOptions,
  ): Promise<VercelConnectorMetadata>;
  experimental_startInstallation?(
    connector: string,
    params?: Omit<ConnectTokenParams, "subject">,
    options?: ConnectInstallationOptions,
  ): Promise<VercelConnectInstallation>;
}

interface ConnectInstallationOptions {
  vercelToken?: string;
  returnUrl?: string;
  webhook?: string;
  tenantId?: string;
  deviceCode?: boolean;
  expiresInMs?: number;
  region?: string;
}

/** What `experimental_startInstallation` returns, typed structurally. */
export interface VercelConnectInstallation {
  url: string;
  request: string;
  verifier: string;
  deviceCode?: string;
  expiresAt: number;
  connector: { id: string; uid: string; type: string; name: string };
}

/** The Chat SDK platforms `@vercel/connect/chat` has an adapter config for. */
export type VercelConnectChannel =
  | "discord"
  | "github"
  | "linear"
  | "linq"
  | "notion"
  | "sendblue"
  | "slack"
  | "teams"
  | "telegram";

type ChannelHelper = (
  connector: string,
  params: Omit<ConnectTokenParams, "subject">,
  options: ConnectOptions,
) => unknown;

const isChannelHelper = (value: unknown): value is ChannelHelper =>
  typeof value === "function";

const CHANNEL_HELPERS: Readonly<Record<VercelConnectChannel, string>> = {
  discord: "connectDiscordAdapter",
  github: "connectGitHubAdapter",
  linear: "connectLinearAdapter",
  linq: "connectLinqAdapter",
  notion: "connectNotionAdapter",
  sendblue: "connectSendblueAdapter",
  slack: "connectSlackAdapter",
  teams: "connectTeamsAdapter",
  telegram: "connectTelegramAdapter",
};

/** The part of `@vercel/connect/chat` `verifyInbound` calls. */
export interface VercelConnectChatModule {
  createConnectWebhookVerifier(
    options?: Record<string, unknown>,
  ): (request: Request, body: string) => unknown;
  [helper: string]: unknown;
}

/** The options `startInstallation` takes. */
export interface VercelConnectInstallationOptions {
  /** The tenant the installation belongs to; Connect returns it on tokens. */
  readonly tenantId?: string;
  readonly returnUrl?: string;
  readonly webhook?: string;
  readonly deviceCode?: boolean;
  readonly expiresInMs?: number;
}

/** A Vercel Connect `CredentialProvider` with the calls only Connect has. */
export interface VercelConnectCredentials extends CredentialProvider {
  /**
   * The whole token response: `tokenId`, `installationId`, `tenantId`,
   * `externalSubject`, `metadata` and `claims` besides the token.
   */
  tokenDetails(
    ref: CredentialRef,
    options: GetTokenOptions,
  ): AsyncResult<VercelConnectTokenResponse>;
  /**
   * Drops the cached token, for a token the provider rejected with a 401 before
   * it expired. Resolves `false` when `@vercel/connect` has no cache to clear.
   */
  invalidateToken(
    ref: CredentialRef,
    options: {
      readonly subject: CredentialSubject;
      readonly installationId?: string;
    },
  ): AsyncResult<boolean>;
  /** The connector's name, type and service, for a settings page. */
  connectorMetadata(ref: CredentialRef): AsyncResult<VercelConnectorMetadata>;
  /**
   * Starts installing the connector for a tenant (a Slack workspace, a GitHub
   * organization). Send an admin to `url`; read the tenant's tokens with an
   * `installationRef` afterwards.
   */
  startInstallation(
    ref: CredentialRef,
    options?: VercelConnectInstallationOptions,
  ): AsyncResult<VercelConnectInstallation>;
  /**
   * The Chat SDK adapter config for a connector, from `@vercel/connect/chat`: a
   * token resolver and a webhook verifier, so the adapter reads a fresh token
   * for every webhook. Pass it to the platform's adapter factory.
   */
  channelConfig(
    ref: CredentialRef,
    channel: VercelConnectChannel,
  ): AsyncResult<Record<string, unknown>>;
}

/**
 * A Vercel Connect connector; `connector` is its UID. `audience`, `resources`,
 * `authorizationDetails` and `validityBufferMs` pass through to the token
 * request; `inbound: true` lets `verifyInbound` check webhooks Connect forwards
 * for it. A type alias, so a ref passes where a `CredentialRef` is expected.
 */
export type VercelConnectRef = {
  readonly provider: "vercel-connect";
  readonly connector: string;
  readonly installationId?: string;
  readonly scopes?: readonly string[];
  readonly audience?: readonly string[];
  readonly resources?: readonly string[];
  readonly authorizationDetails?: readonly Readonly<VercelConnectAuthorizationDetail>[];
  readonly validityBufferMs?: number;
  readonly inbound?: boolean;
};

export interface VercelConnectCredentialsOptions {
  /** Defaults to the OIDC token `@vercel/connect` reads on Vercel. */
  readonly vercelToken?: string;
  /** The Connect region, for a project outside the default one. */
  readonly region?: string;
  /**
   * Passed to `createConnectWebhookVerifier`: the project and environment a
   * forwarded webhook's OIDC token must name. Defaults to the deployment's.
   */
  readonly inbound?: Readonly<Record<string, unknown>>;
  /** Returns `@vercel/connect`; defaults to importing it on first use. */
  readonly load?: () => Promise<unknown>;
  /** Returns `@vercel/connect/chat`; defaults to importing it on first use. */
  readonly loadChat?: () => Promise<unknown>;
}

const isModule = (value: unknown): value is VercelConnectModule =>
  isRecord(value) &&
  typeof value["getTokenResponse"] === "function" &&
  typeof value["revokeToken"] === "function" &&
  typeof value["startAuthorization"] === "function";

const isChatModule = (value: unknown): value is VercelConnectChatModule =>
  isRecord(value) &&
  typeof value["createConnectWebhookVerifier"] === "function";

/**
 * Loads `@vercel/connect` on first use. The specifier is a variable so bundlers
 * leave the optional peer out of apps that don't use it.
 */
const loadConnect = (): Promise<unknown> =>
  importOptionalPeer("@vercel/connect");

/** Loads the Chat SDK helpers only when a ref takes forwarded webhooks. */
const loadConnectChat = (): Promise<unknown> =>
  importOptionalPeer("@vercel/connect/chat");

const strings = (value: unknown): string[] | undefined =>
  Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string")
    : undefined;

function connectRef(ref: CredentialRef): Result<VercelConnectRef> {
  const { connector, installationId, validityBufferMs, inbound } = ref;

  if (ref.provider !== "vercel-connect" || typeof connector !== "string") {
    return err(
      dbError(
        "invalid_input",
        `vercel-connect resolves refs with a connector, not "${ref.provider}"`,
        { hint: "CREDENTIAL_REF_INVALID" },
      ),
    );
  }

  const scopes = strings(ref["scopes"]);
  const audience = strings(ref["audience"]);
  const resources = strings(ref["resources"]);
  const details = ref["authorizationDetails"];

  return ok({
    provider: "vercel-connect",
    connector,
    ...(typeof installationId === "string" ? { installationId } : {}),
    ...(scopes === undefined ? {} : { scopes }),
    ...(audience === undefined ? {} : { audience }),
    ...(resources === undefined ? {} : { resources }),
    ...(Array.isArray(details)
      ? { authorizationDetails: details.filter(isDetail) }
      : {}),
    ...(typeof validityBufferMs === "number" ? { validityBufferMs } : {}),
    ...(inbound === true ? { inbound } : {}),
  });
}

/** The fields a `ConnectError` carries. */
function connectCause(cause: unknown): Record<string, unknown> {
  if (!isRecord(cause)) {
    return {};
  }

  const kept: Record<string, unknown> = {};

  for (const key of ["code", "status", "vendor"]) {
    if (cause[key] !== undefined) {
      kept[key] = cause[key];
    }
  }

  return kept;
}

const HINTS: Readonly<
  Record<string, readonly ["forbidden" | "not_found", string]>
> = {
  user_authorization_required: [
    "forbidden",
    "CREDENTIAL_AUTHORIZATION_REQUIRED",
  ],
  connector_installation_required: [
    "forbidden",
    "CREDENTIAL_INSTALLATION_REQUIRED",
  ],
  client_installation_required: [
    "forbidden",
    "CREDENTIAL_INSTALLATION_REQUIRED",
  ],
  no_token: ["not_found", "CREDENTIAL_NOT_FOUND"],
  connector_not_found: ["not_found", "CREDENTIAL_CONNECTOR_NOT_FOUND"],
  client_not_linked_to_project: [
    "forbidden",
    "CREDENTIAL_CONNECTOR_NOT_LINKED",
  ],
  client_not_enabled_for_environment: [
    "forbidden",
    "CREDENTIAL_CONNECTOR_NOT_ENABLED",
  ],
};

const NAMES: Readonly<Record<string, string>> = {
  UserAuthorizationRequiredError: "user_authorization_required",
  ConnectorInstallationRequiredError: "connector_installation_required",
  NoValidTokenError: "no_token",
};

/**
 * Maps a `@vercel/connect` error by its `code` (or, for an error without one,
 * its class name), without importing the classes.
 */
function connectError(cause: unknown): Result<never> {
  if (cause instanceof DbException) {
    return err(cause.error);
  }

  const message = cause instanceof Error ? cause.message : String(cause);
  const fields = connectCause(cause);
  const name = cause instanceof Error ? cause.name : "";

  const code =
    typeof fields["code"] === "string" ? fields["code"] : NAMES[name];

  const mapped = code === undefined ? undefined : HINTS[code];
  const { status, vendor } = fields;

  const detail = {
    ...(code === undefined ? {} : { code }),
    ...(status === undefined && vendor === undefined
      ? {}
      : { details: JSON.stringify({ status, vendor }) }),
  };

  if (mapped !== undefined) {
    const [kind, hint] = mapped;

    return err(
      kind === "forbidden"
        ? dbError("forbidden", message, { hint, ...detail })
        : dbError("not_found", message, { hint, ...detail }),
    );
  }

  if (fields["status"] === 429) {
    return err(
      dbError("rate_limited", message, {
        hint: "CREDENTIAL_RATE_LIMITED",
        ...detail,
      }),
    );
  }

  return err(dbError("network", message, detail));
}

/**
 * A `CredentialProvider` over Vercel Connect: OAuth tokens for a connector, for
 * the app, a user or an exchanged token, refreshed by Vercel. Needs
 * `@vercel/connect`.
 */
export function vercelConnectCredentials(
  options: VercelConnectCredentialsOptions = {},
): VercelConnectCredentials {
  let loaded: Promise<VercelConnectModule> | undefined;

  let verifier:
    | Promise<(request: Request, body: string) => unknown>
    | undefined;

  const connect = (): Promise<VercelConnectModule> =>
    (loaded ??= (options.load ?? loadConnect)().then((value) => {
      if (!isModule(value)) {
        loaded = undefined;
        throw new TypeError(
          "vercelConnectCredentials needs the @vercel/connect package: pnpm add @vercel/connect",
        );
      }

      return value;
    }));

  let chatLoaded: Promise<VercelConnectChatModule> | undefined;

  const chat = (): Promise<VercelConnectChatModule> =>
    (chatLoaded ??= (options.loadChat ?? loadConnectChat)().then((value) => {
      if (!isChatModule(value)) {
        chatLoaded = undefined;
        throw new TypeError(
          "@vercel/connect/chat needs @vercel/connect 2.2 or later: pnpm add @vercel/connect",
        );
      }

      return value;
    }));

  const webhookVerifier = (): Promise<
    (request: Request, body: string) => unknown
  > =>
    (verifier ??= chat().then(
      (module) =>
        module.createConnectWebhookVerifier(
          options.inbound === undefined ? undefined : { ...options.inbound },
        ),
      (cause: unknown) => {
        verifier = undefined;
        throw cause;
      },
    ));

  // An optional call the installed @vercel/connect may lack fails with this.
  const missing = (name: string): DbException =>
    new DbException(
      dbError(
        "invalid_request",
        `${name} needs a newer @vercel/connect: pnpm add @vercel/connect@latest`,
      ),
    );

  const connectOptions: ConnectOptions = {
    ...(options.vercelToken === undefined
      ? {}
      : { vercelToken: options.vercelToken }),
    ...(options.region === undefined ? {} : { region: options.region }),
  };

  const foreign = (): DbException =>
    new DbException(
      dbError(
        "forbidden",
        "vercel-connect has no per-tenant credentials; use a user subject, the tenant's installationRef or a provider with tenant namespaces",
        { hint: "CREDENTIAL_REF_FOREIGN" },
      ),
    );

  /**
   * `installation` lets a tenant ref with an `installationId` through for the
   * app subject; the caller then checks the token's `tenantId`.
   */
  const run = <T>(
    ref: CredentialRef,
    subject: CredentialSubject | undefined,
    fn: (module: VercelConnectModule, parsed: VercelConnectRef) => Promise<T>,
    installation = false,
  ): AsyncResult<T> => {
    // Connect has no tenant namespace: the app subject would resolve the
    // app's own installation for every tenant.
    if (
      subject?.type === "app" &&
      ref.tenant !== undefined &&
      !(installation && typeof ref["installationId"] === "string")
    ) {
      return AsyncResult.err(foreign().error);
    }

    const parsed = connectRef(ref);

    if (!parsed.ok) {
      return AsyncResult.err(parsed.error);
    }

    return AsyncResult.from(async () => {
      const module = await connect();

      try {
        return ok(await fn(module, parsed.data));
      } catch (cause) {
        return connectError(cause);
      }
    });
  };

  const refParams = (
    parsed: VercelConnectRef,
    scopes: readonly string[] | undefined,
    installationId: string | undefined,
  ): Omit<ConnectTokenParams, "subject"> => {
    const chosen = scopes ?? parsed.scopes;
    const installation = installationId ?? parsed.installationId;

    return {
      ...(installation === undefined ? {} : { installationId: installation }),
      ...(chosen === undefined ? {} : { scopes: [...chosen] }),
      ...(parsed.audience === undefined
        ? {}
        : { audience: [...parsed.audience] }),
      ...(parsed.resources === undefined
        ? {}
        : { resources: [...parsed.resources] }),
      ...(parsed.authorizationDetails === undefined
        ? {}
        : {
            authorizationDetails: parsed.authorizationDetails.map((detail) => ({
              ...detail,
            })),
          }),
      ...(parsed.validityBufferMs === undefined
        ? {}
        : { validityBufferMs: parsed.validityBufferMs }),
    };
  };

  const params = (
    parsed: VercelConnectRef,
    subject: CredentialSubject,
    scopes: readonly string[] | undefined,
    installationId: string | undefined,
  ): ConnectTokenParams => ({
    subject,
    ...refParams(parsed, scopes, installationId),
  });

  const instant = (
    epochMilliseconds: number | undefined,
  ): Temporal.Instant | undefined => {
    const temporal = optionalTemporal();

    return temporal === undefined || epochMilliseconds === undefined
      ? undefined
      : temporal.Instant.fromEpochMilliseconds(epochMilliseconds);
  };

  const tokenResponse = async (
    module: VercelConnectModule,
    ref: CredentialRef,
    parsed: VercelConnectRef,
    getOptions: GetTokenOptions,
  ): Promise<VercelConnectTokenResponse> => {
    const response = await module.getTokenResponse(
      parsed.connector,
      params(
        parsed,
        getOptions.subject,
        getOptions.scopes,
        getOptions.installationId,
      ),
      getOptions.fresh === true
        ? { ...connectOptions, forceRefresh: true }
        : connectOptions,
    );

    // A tenant admin can store any installationId in a ref; only an
    // installation started with this tenant's id resolves for it.
    if (
      getOptions.subject.type === "app" &&
      ref.tenant !== undefined &&
      response.tenantId !== ref.tenant
    ) {
      throw foreign();
    }

    return response;
  };

  return {
    apiVersion: 1,
    name: "vercel-connect",
    tokenDetails(ref, getOptions) {
      return run(
        ref,
        getOptions.subject,
        (module, parsed) => tokenResponse(module, ref, parsed, getOptions),
        true,
      );
    },
    invalidateToken(ref, invalidateOptions) {
      return run(ref, invalidateOptions.subject, (module, parsed) => {
        if (module.deleteTokenCacheEntry === undefined) {
          return Promise.resolve(false);
        }

        module.deleteTokenCacheEntry(
          parsed.connector,
          params(
            parsed,
            invalidateOptions.subject,
            undefined,
            invalidateOptions.installationId,
          ),
        );

        return Promise.resolve(true);
      });
    },
    connectorMetadata(ref) {
      return run(ref, undefined, async (module, parsed) => {
        if (module.getConnectorMetadata === undefined) {
          throw missing("connectorMetadata");
        }

        return module.getConnectorMetadata(parsed.connector, connectOptions);
      });
    },
    startInstallation(ref, installOptions = {}) {
      return run(ref, undefined, async (module, parsed) => {
        if (module.experimental_startInstallation === undefined) {
          throw missing("startInstallation");
        }

        return module.experimental_startInstallation(
          parsed.connector,
          refParams(parsed, undefined, undefined),
          {
            ...connectOptions,
            ...(installOptions.tenantId === undefined
              ? {}
              : { tenantId: installOptions.tenantId }),
            ...(installOptions.returnUrl === undefined
              ? {}
              : { returnUrl: installOptions.returnUrl }),
            ...(installOptions.webhook === undefined
              ? {}
              : { webhook: installOptions.webhook }),
            ...(installOptions.deviceCode === true ? { deviceCode: true } : {}),
            ...(installOptions.expiresInMs === undefined
              ? {}
              : { expiresInMs: installOptions.expiresInMs }),
          },
        );
      });
    },
    channelConfig(ref, channel) {
      return run(ref, undefined, async (_module, parsed) => {
        const helper = (await chat())[CHANNEL_HELPERS[channel]];

        if (!isChannelHelper(helper)) {
          throw missing(`channelConfig("${channel}")`);
        }

        const config: unknown = helper(
          parsed.connector,
          refParams(parsed, undefined, undefined),
          connectOptions,
        );

        if (!isRecord(config)) {
          throw missing(`channelConfig("${channel}")`);
        }

        return config;
      });
    },
    getToken(ref, getOptions) {
      return run(
        ref,
        getOptions.subject,
        async (module, parsed): Promise<CredentialToken> => {
          const response = await tokenResponse(module, ref, parsed, getOptions);

          const expiresAt = instant(response.expiresAt);

          return {
            token: response.token,
            ...(expiresAt === undefined ? {} : { expiresAt }),
            headers: { authorization: `Bearer ${response.token}` },
          };
        },
        true,
      );
    },
    capabilities(ref) {
      return {
        userSubjects: true,
        exchangeSubjects: true,
        authorization: true,
        revoke: true,
        inbound: ref["inbound"] === true,
      };
    },
    startAuthorization(ref, startOptions) {
      return run(
        ref,
        startOptions.subject,
        async (module, parsed): Promise<StartAuthorizationResult> => {
          const started = await module.startAuthorization(
            parsed.connector,
            params(
              parsed,
              startOptions.subject,
              startOptions.scopes,
              undefined,
            ),
            {
              ...connectOptions,
              callbackUrl: startOptions.redirectUri,
              ...(startOptions.deviceCode === true ? { deviceCode: true } : {}),
              ...(startOptions.prompt === undefined
                ? {}
                : { prompt: startOptions.prompt }),
            },
          );

          const expiresAt = instant(started.expiresAt);

          return {
            url: started.url,
            ...(started.request === undefined
              ? {}
              : { request: started.request }),
            ...(started.verifier === undefined
              ? {}
              : { verifier: started.verifier }),
            ...(started.deviceCode === undefined
              ? {}
              : { deviceCode: started.deviceCode }),
            ...(expiresAt === undefined ? {} : { expiresAt }),
          };
        },
      );
    },
    revoke(ref, revokeOptions) {
      return run(ref, revokeOptions.subject, async (module, parsed) => {
        await module.revokeToken(
          parsed.connector,
          {
            subject: revokeOptions.subject,
            ...(parsed.installationId === undefined
              ? {}
              : { installationId: parsed.installationId }),
          },
          connectOptions,
        );

        return true;
      });
    },
    verifyInbound(request, ref) {
      const parsed = connectRef(ref);

      if (!parsed.ok) {
        return AsyncResult.err(parsed.error);
      }

      if (parsed.data.inbound !== true) {
        return AsyncResult.err(
          dbError(
            "invalid_input",
            `"${parsed.data.connector}" doesn't take forwarded webhooks; set inbound: true on its ref`,
            { hint: "CREDENTIAL_INBOUND_DISABLED" },
          ),
        );
      }

      return AsyncResult.from(async () => {
        const verify = await webhookVerifier();

        try {
          const body = await request.clone().text();

          return ok(Boolean(await verify(request, body)));
        } catch {
          return ok(false);
        }
      });
    },
  };
}

/**
 * A ref for one tenant's installation of a connector, so the app subject reads
 * that tenant's token. The installation must have been started with
 * `startInstallation(ref, { tenantId: ref.tenant })`: a token whose `tenantId`
 * differs fails with `CREDENTIAL_REF_FOREIGN`. Without `installationId`, a
 * tenant ref resolves only for a user subject.
 */
export function installationRef<R extends CredentialRef>(
  ref: R,
  installationId: string,
): R & { readonly installationId: string } {
  return { ...ref, installationId };
}

/**
 * The Connect subject for a Supabase Auth user. The issuer is the project's
 * Auth URL, so local, preview and production deployments that share one
 * Supabase project resolve the same Connect grant.
 */
export function connectSubject(
  user: { readonly id: string },
  options: { readonly supabaseUrl: string },
): CredentialSubject {
  return {
    type: "user",
    id: user.id,
    issuer: `${options.supabaseUrl.replace(/\/+$/u, "")}/auth/v1`,
  };
}

/** What `withConnectorToken` resolves with. */
export type ConnectorTokenOutcome<T> =
  | { readonly status: "ok"; readonly value: T }
  | {
      readonly status: "authorization_required";
      readonly url: string;
      readonly deviceCode?: string;
    };

/**
 * Runs `fn` with the subject's token. When the subject hasn't authorized the
 * connector, starts the authorization and resolves with its `url` instead, so a
 * tool or route can hand the consent link to the user.
 */
export async function withConnectorToken<T>(
  credentials: CredentialProvider,
  ref: CredentialRef,
  options: {
    readonly subject: CredentialSubject;
    readonly redirectUri: string;
    readonly scopes?: readonly string[];
    readonly deviceCode?: boolean;
  },
  fn: (token: CredentialToken) => Promise<T>,
): Promise<Result<ConnectorTokenOutcome<T>>> {
  const token = await credentials.getToken(ref, {
    subject: options.subject,
    ...(options.scopes === undefined ? {} : { scopes: options.scopes }),
  });

  if (token.ok) {
    return ok({ status: "ok", value: await fn(token.data) });
  }

  if (
    token.error.hint !== "CREDENTIAL_AUTHORIZATION_REQUIRED" ||
    credentials.startAuthorization === undefined
  ) {
    return token;
  }

  const started = await credentials.startAuthorization(ref, {
    subject: options.subject,
    redirectUri: options.redirectUri,
    ...(options.scopes === undefined ? {} : { scopes: options.scopes }),
    ...(options.deviceCode === true ? { deviceCode: true } : {}),
  });

  if (!started.ok) {
    return started;
  }

  return ok({
    status: "authorization_required",
    url: started.data.url,
    ...(started.data.deviceCode === undefined
      ? {}
      : { deviceCode: started.data.deviceCode }),
  });
}
