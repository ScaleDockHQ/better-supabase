import type { BlockTransport } from "../../core/block-transport.ts";
import type { DbError, ErrorMapper } from "../../core/errors.ts";
import type {
  CredentialProvider,
  CredentialRef,
} from "../../credentials/provider.ts";

import { dbError } from "../../core/errors.ts";
import { AsyncResult, ok } from "../../core/result.ts";
import {
  applyTemporal,
  blockCall,
  type BlockTemporalOptions,
  instantArg,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  stringsOf,
  textOf,
  toInstant,
} from "../shared.ts";

export type ConnectorTransport = "http" | "sse";
/** `none`, OAuth per user (a grant each), or a header from the server's credential_ref. */
export type ConnectorAuth = "none" | "oauth" | "header";
export type FingerprintStatus = "approved" | "pending" | "rejected";

export interface ConnectorGrant {
  readonly id: string;
  readonly userId: string;
  readonly serverId: string;
  readonly organizationId: string;
  readonly credentialRef: CredentialRef;
  readonly scopes: readonly string[];
  readonly expiresAt: Temporal.Instant | undefined;
  readonly grantedAt: Temporal.Instant;
  readonly revokedAt: Temporal.Instant | undefined;
}

export interface ConnectorServer {
  readonly id: string;
  readonly organizationId: string;
  readonly name: string;
  readonly url: string;
  readonly transport: ConnectorTransport;
  readonly authType: ConnectorAuth;
  /** For `header` auth: the app credential sent with every request. */
  readonly credentialRef: CredentialRef | undefined;
  /** The OAuth scopes to ask for. */
  readonly scopes: readonly string[];
  /** OAuth client metadata for dynamic client registration. */
  readonly clientMetadata: Readonly<Record<string, unknown>>;
  readonly enabled: boolean;
  /** The caller's (or `ownerId`'s) active grant, from `list` and `get`. */
  readonly grant: ConnectorGrant | undefined;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface ConnectorServerFields {
  readonly name?: string;
  readonly url?: string;
  readonly transport?: ConnectorTransport;
  readonly authType?: ConnectorAuth;
  readonly credentialRef?: CredentialRef | null;
  readonly scopes?: readonly string[];
  readonly clientMetadata?: Readonly<Record<string, unknown>>;
  readonly enabled?: boolean;
}

export interface ConnectorSession {
  readonly sessionId: string | undefined;
  readonly initializeResult: Readonly<Record<string, unknown>> | undefined;
  readonly expiresAt: Temporal.Instant;
}

export interface ConnectorsOptions extends BlockTemporalOptions {
  /** Calls as the user: `rpcTransport(supabase)`. */
  readonly transport: BlockTransport;
  /** Calls as the service role, for grants and renewals. */
  readonly service?: BlockTransport;
  /** The module schema (`sql.modules.connectors.schema`), default `better_supabase`. */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
  /** Revokes a grant's credential when the grant or its server goes away. */
  readonly credentials?: CredentialProvider;
}

export interface Connectors {
  readonly servers: {
    list(organizationId: string): AsyncResult<readonly ConnectorServer[]>;
    /** With `ownerId` (service role), the grant is that user's. */
    get(
      serverId: string,
      options?: { readonly ownerId?: string },
    ): AsyncResult<ConnectorServer>;
    create(
      organizationId: string,
      server: ConnectorServerFields & {
        readonly name: string;
        readonly url: string;
      },
    ): AsyncResult<ConnectorServer>;
    update(
      organizationId: string,
      serverId: string,
      fields: ConnectorServerFields,
    ): AsyncResult<ConnectorServer>;
    /** Deletes a server and revokes its grants' credentials. Returns how many. */
    remove(serverId: string): AsyncResult<number>;
  };
  readonly grants: {
    /**
     * Records a user's grant after the provider stored the credential
     * (service role), revoking the grant it replaces.
     */
    record(
      serverId: string,
      userId: string,
      credentialRef: CredentialRef,
      options?: {
        readonly scopes?: readonly string[];
        readonly expiresAt?: Temporal.Instant;
      },
    ): AsyncResult<ConnectorGrant>;
    /** Revokes a grant (its owner or the service role) and its credential. */
    revoke(grantId: string): AsyncResult<boolean>;
    /** Active grants expiring before `before` (service role). */
    expiring(
      before: Temporal.Instant,
      options?: { readonly limit?: number },
    ): AsyncResult<readonly ConnectorGrant[]>;
    renew(grantId: string, expiresAt: Temporal.Instant): AsyncResult<boolean>;
  };
  readonly sessions: {
    get(
      serverId: string,
      chatKey?: string,
    ): AsyncResult<ConnectorSession | undefined>;
    save(
      serverId: string,
      session: {
        readonly chatKey?: string;
        readonly sessionId?: string;
        readonly initializeResult?: Readonly<Record<string, unknown>>;
      },
    ): AsyncResult<boolean>;
    forget(serverId: string, chatKey?: string): AsyncResult<boolean>;
    /** Deletes expired sessions (service role). */
    purge(): AsyncResult<number>;
  };
  readonly fingerprints: {
    /** Records a tool list's fingerprint and returns whether it may be called. */
    check(
      serverId: string,
      fingerprint: string,
      tools?: Readonly<Record<string, unknown>>,
    ): AsyncResult<FingerprintStatus>;
    approve(serverId: string, fingerprint: string): AsyncResult<boolean>;
    reject(serverId: string, fingerprint: string): AsyncResult<boolean>;
  };
}

const TRANSPORTS: ReadonlySet<string> = new Set(["http", "sse"]);
const AUTHS: ReadonlySet<string> = new Set(["none", "oauth", "header"]);
const STATUSES: ReadonlySet<string> = new Set([
  "approved",
  "pending",
  "rejected",
]);

const instant = (value: unknown): Temporal.Instant =>
  value instanceof Date ? toInstant(value) : toInstant(textOf(value));

function refOf(value: unknown): CredentialRef | undefined {
  if (!isRecord(value) || typeof value["provider"] !== "string") {
    return undefined;
  }
  return { ...value, provider: value["provider"] };
}

function grantOf(value: unknown): ConnectorGrant {
  const row = recordOf(value, "connector_grants");
  const credentialRef = refOf(row["credential_ref"]);
  if (credentialRef === undefined) {
    throw new TypeError("connector_grants returned a grant without a ref");
  }
  return {
    id: textOf(row["id"]),
    userId: textOf(row["user_id"]),
    serverId: textOf(row["server_id"]),
    organizationId: textOf(row["organization_id"]),
    credentialRef,
    scopes: stringsOf(row["scopes"]),
    expiresAt: optionalInstant(row["expires_at"]),
    grantedAt: instant(row["granted_at"]),
    revokedAt: optionalInstant(row["revoked_at"]),
  };
}

function serverOf(value: unknown): ConnectorServer {
  const row = recordOf(value, "connector_servers");
  const transport = textOf(row["transport"]);
  const authType = textOf(row["auth_type"]);
  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organization_id"]),
    name: textOf(row["name"]),
    url: textOf(row["url"]),
    // SAFETY: TRANSPORTS holds exactly the ConnectorTransport members.
    transport: TRANSPORTS.has(transport)
      ? (transport as ConnectorTransport)
      : "http",
    // SAFETY: AUTHS holds exactly the ConnectorAuth members.
    authType: AUTHS.has(authType) ? (authType as ConnectorAuth) : "none",
    credentialRef: refOf(row["credential_ref"]),
    scopes: stringsOf(row["scopes"]),
    clientMetadata: isRecord(row["client_metadata"])
      ? row["client_metadata"]
      : {},
    enabled: row["enabled"] !== false,
    grant: isRecord(row["grant"]) ? grantOf(row["grant"]) : undefined,
    createdAt: instant(row["created_at"]),
    updatedAt: instant(row["updated_at"]),
  };
}

function fieldsArg(fields: ConnectorServerFields): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  if (fields.name !== undefined) out["name"] = fields.name;
  if (fields.url !== undefined) out["url"] = fields.url;
  if (fields.transport !== undefined) out["transport"] = fields.transport;
  if (fields.authType !== undefined) out["auth_type"] = fields.authType;
  if (fields.credentialRef !== undefined) {
    out["credential_ref"] = fields.credentialRef;
  }
  if (fields.scopes !== undefined) out["scopes"] = fields.scopes;
  if (fields.clientMetadata !== undefined) {
    out["client_metadata"] = fields.clientMetadata;
  }
  if (fields.enabled !== undefined) out["enabled"] = fields.enabled;
  return out;
}

const notFound = (): DbError =>
  dbError("not_found", "No connector you can see has this id", {
    hint: "CONNECTOR_NOT_FOUND",
  });

/** MCP servers, per-user grants, sessions and tool list fingerprints. */
export function createConnectors(options: ConnectorsOptions): Connectors {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const service = blockCall(
    options.service ?? options.transport,
    options.schema,
    options.mappers,
  );
  const credentials = options.credentials;

  const revokeCredential = (grant: ConnectorGrant): AsyncResult<boolean> =>
    credentials === undefined
      ? AsyncResult.ok(true)
      : credentials
          .revoke(grant.credentialRef, {
            subject: { type: "user", id: grant.userId },
          })
          .map(() => true);

  const revokeAll = (grants: readonly ConnectorGrant[]): AsyncResult<number> =>
    AsyncResult.from(async () => {
      for (const grant of grants) {
        const revoked = await revokeCredential(grant);
        if (!revoked.ok) return revoked;
      }
      return ok(grants.length);
    });

  const save = (
    organizationId: string,
    serverId: string | undefined,
    fields: ConnectorServerFields,
  ): AsyncResult<ConnectorServer> =>
    call(
      "save_connector_server",
      { tenant: organizationId, id: serverId, fields: fieldsArg(fields) },
      serverOf,
    );

  const decide = (
    serverId: string,
    fingerprint: string,
    approved: boolean,
  ): AsyncResult<boolean> =>
    call(
      "decide_connector_fingerprint",
      { server_id: serverId, fingerprint, approved },
      (value) => value === true,
    );

  return {
    servers: {
      list: (organizationId) =>
        call("list_connector_servers", { tenant: organizationId }, (value) =>
          recordsOf(value, "list_connector_servers").map(serverOf),
        ),
      get: (serverId, getOptions = {}) =>
        (getOptions.ownerId === undefined ? call : service)(
          "get_connector",
          { id: serverId, owner: getOptions.ownerId },
          (value) => value,
        ).andThen((value) =>
          isRecord(value)
            ? AsyncResult.ok(serverOf(value))
            : AsyncResult.err(notFound()),
        ),
      create: (organizationId, server) =>
        save(organizationId, undefined, server),
      update: (organizationId, serverId, fields) =>
        save(organizationId, serverId, fields),
      remove: (serverId) =>
        call("delete_connector_server", { id: serverId }, (value) =>
          recordsOf(value, "delete_connector_server").map(grantOf),
        ).andThen(revokeAll),
    },
    grants: {
      record: (serverId, userId, credentialRef, recordOptions = {}) =>
        service(
          "record_connector_grant",
          {
            server_id: serverId,
            owner: userId,
            credential_ref: credentialRef,
            scopes: recordOptions.scopes,
            expires_at: instantArg(recordOptions.expiresAt),
          },
          (value) => recordOf(value, "record_connector_grant"),
        ).andThen((row) => {
          const grant = grantOf(row["grant"]);
          const replaced = isRecord(row["replaced"])
            ? grantOf(row["replaced"])
            : undefined;
          // A reconnect writes the same ref again; revoking it would drop the new token.
          const stale =
            replaced !== undefined &&
            JSON.stringify(replaced.credentialRef) !==
              JSON.stringify(grant.credentialRef);
          return stale
            ? revokeCredential(replaced).map(() => grant)
            : AsyncResult.ok(grant);
        }),
      revoke: (grantId) =>
        call(
          "revoke_connector_grant",
          { id: grantId },
          (value) => value,
        ).andThen((value) =>
          isRecord(value)
            ? revokeCredential(grantOf(value))
            : AsyncResult.ok(false),
        ),
      expiring: (before, expiringOptions = {}) =>
        service(
          "expiring_connector_grants",
          { before: before.toString(), max_rows: expiringOptions.limit },
          (value) => recordsOf(value, "expiring_connector_grants").map(grantOf),
        ),
      renew: (grantId, expiresAt) =>
        service(
          "renew_connector_grant",
          { id: grantId, expires_at: expiresAt.toString() },
          (value) => value === true,
        ),
    },
    sessions: {
      get: (serverId, chatKey) =>
        call(
          "get_connector_session",
          { server_id: serverId, chat_key: chatKey ?? "" },
          (value): ConnectorSession | undefined =>
            isRecord(value)
              ? {
                  sessionId: optionalText(value["session_id"]),
                  initializeResult: isRecord(value["initialize_result"])
                    ? value["initialize_result"]
                    : undefined,
                  expiresAt: instant(value["expires_at"]),
                }
              : undefined,
        ),
      save: (serverId, session) =>
        call(
          "save_connector_session",
          {
            server_id: serverId,
            chat_key: session.chatKey ?? "",
            session_id: session.sessionId,
            initialize_result: session.initializeResult,
          },
          (value) => value === true,
        ),
      forget: (serverId, chatKey) =>
        call(
          "save_connector_session",
          { server_id: serverId, chat_key: chatKey ?? "" },
          (value) => value === true,
        ),
      purge: () => service("purge_connector_sessions", {}, Number),
    },
    fingerprints: {
      check: (serverId, fingerprint, tools) =>
        call(
          "check_connector_fingerprint",
          { server_id: serverId, fingerprint, tools },
          (value): FingerprintStatus => {
            const status = textOf(value);
            // SAFETY: STATUSES holds exactly the FingerprintStatus members.
            return STATUSES.has(status)
              ? (status as FingerprintStatus)
              : "pending";
          },
        ),
      approve: (serverId, fingerprint) => decide(serverId, fingerprint, true),
      reject: (serverId, fingerprint) => decide(serverId, fingerprint, false),
    },
  };
}
