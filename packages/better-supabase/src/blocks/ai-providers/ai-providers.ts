import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type {
  CredentialProvider,
  CredentialRef,
} from "../../credentials/provider.ts";
import type { AiSandboxes } from "../ai-chat/sandboxes.ts";

import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import { revokeIfConfigured } from "../../credentials/compose.ts";
import {
  credentialRefInTenant,
  foreignCredentialRef,
} from "../../credentials/provider.ts";
import { aiSandboxes } from "../ai-chat/sandboxes.ts";
import {
  applyTemporal,
  blockCall,
  type BlockTemporalOptions,
  credentialRefOf,
  instantArg,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordOrEmpty,
  recordsOf,
  textOf,
  toInstant,
  type CursorPageOptions,
  pageOf,
} from "../shared.ts";

/** A tenant's own key for a provider. The key itself stays in the credential provider. */
export interface AiProviderKey {
  readonly id: string;
  readonly organizationId: string;
  /** The AI Gateway's provider slug, such as `anthropic` or `openai`. */
  readonly provider: string;
  /** Tells several keys of one provider apart; `default` unless named. */
  readonly name: string;
  readonly credentialRef: CredentialRef;
  /** The provider's other options, such as a region; never a secret. */
  readonly settings: Readonly<Record<string, unknown>>;
  readonly enabled: boolean;
  readonly createdBy: string | undefined;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface AiProviderKeyInput {
  readonly provider: string;
  /** Store the key first, for example with `vaultCredentials().set(ref, apiKey)`. */
  readonly credentialRef: CredentialRef;
  readonly name?: string;
  readonly settings?: Readonly<Record<string, unknown>>;
  readonly enabled?: boolean;
}

/** A key resolved for one request. */
export interface ResolvedProviderKey {
  readonly provider: string;
  readonly name: string;
  readonly token: string;
  readonly headers: Readonly<Record<string, string>>;
  readonly settings: Readonly<Record<string, unknown>>;
}

export type AiBatchStatus = "pending" | "completed" | "failed" | "cancelled";

export interface AiBatchCounts {
  readonly total?: number;
  readonly pending?: number;
  readonly completed?: number;
  readonly failed?: number;
}

export interface AiBatch {
  readonly id: string;
  readonly organizationId: string;
  readonly userId: string | undefined;
  readonly provider: string;
  /** The SDK's batch reference, such as `{ version, id, provider }`. */
  readonly reference: Readonly<Record<string, unknown>>;
  readonly status: AiBatchStatus;
  /** The provider's own status word. */
  readonly rawStatus: string | undefined;
  readonly itemCount: number;
  readonly counts: AiBatchCounts;
  readonly error: string | undefined;
  readonly metadata: Readonly<Record<string, unknown>>;
  /** The results are in `items`. */
  readonly resultsSaved: boolean;
  readonly polls: number;
  readonly nextPollAt: Temporal.Instant | undefined;
  readonly expiresAt: Temporal.Instant | undefined;
  readonly completedAt: Temporal.Instant | undefined;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface NewAiBatch {
  readonly provider: string;
  readonly reference: Readonly<Record<string, unknown>>;
  readonly itemCount?: number;
  readonly metadata?: Readonly<Record<string, unknown>>;
  /** Service role only: the user the batch is for. */
  readonly userId?: string;
  readonly status?: AiBatchStatus;
  readonly rawStatus?: string;
  readonly counts?: AiBatchCounts;
  readonly expiresAt?: Temporal.Instant;
}

export interface AiBatchPatch {
  readonly status?: AiBatchStatus;
  readonly rawStatus?: string;
  readonly counts?: AiBatchCounts;
  readonly error?: string | null;
  readonly expiresAt?: Temporal.Instant;
  readonly resultsSaved?: boolean;
  /** `null` stops polling. */
  readonly nextPollAt?: Temporal.Instant | null;
}

export type AiBatchItemStatus =
  | "succeeded"
  | "failed"
  | "cancelled"
  | "expired";

export interface AiBatchItem {
  readonly batchId: string;
  readonly requestId: string;
  readonly organizationId: string;
  readonly status: AiBatchItemStatus;
  readonly output: unknown;
  readonly usage: unknown;
  readonly error: string | undefined;
  readonly createdAt: Temporal.Instant;
}

export interface AiBatchItemInput {
  readonly requestId: string;
  readonly status: AiBatchItemStatus;
  readonly output?: unknown;
  readonly usage?: unknown;
  readonly error?: string;
}

export interface AiProvidersOptions extends BlockTemporalOptions {
  /** Calls as the user: `rpcTransport(supabase)`. */
  readonly transport: BlockTransport;
  /** Calls as the service role, for resolving keys, polling and the idle stop. */
  readonly service?: BlockTransport;
  /** Resolves and revokes the keys' credential refs. */
  readonly credentials?: CredentialProvider;
  /** The module schema (`sql.modules.ai-providers.schema`), default `better_supabase`. */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
}

export interface AiProviders {
  readonly keys: {
    list(organizationId: string): AsyncResult<readonly AiProviderKey[]>;
    /** Adds or replaces a key (`ai_chat.admin`), and revokes the credential it replaced. */
    save(
      organizationId: string,
      key: AiProviderKeyInput,
    ): AsyncResult<AiProviderKey>;
    /** Deletes a key and revokes its credential. `false` when there was none. */
    remove(keyId: string): AsyncResult<boolean>;
    /**
     * Deletes every key of a tenant and revokes each credential (service
     * role): the step to run when a tenant is deleted. Returns how many.
     */
    removeAll(organizationId: string): AsyncResult<number>;
    /** The tenant's enabled keys with their tokens, for one request (service role). */
    resolve(
      organizationId: string,
      options?: {
        readonly providers?: readonly string[];
        readonly signal?: AbortSignal;
      },
    ): AsyncResult<readonly ResolvedProviderKey[]>;
  };
  readonly batches: {
    record(organizationId: string, batch: NewAiBatch): AsyncResult<AiBatch>;
    get(batchId: string): AsyncResult<AiBatch | undefined>;
    list(
      organizationId: string,
      options?: { readonly status?: AiBatchStatus; readonly limit?: number },
    ): AsyncResult<readonly AiBatch[]>;
    items(
      batchId: string,
      options?: CursorPageOptions<string> & {
        /** @deprecated Use `cursor`. Removed in 0.8. */
        readonly after?: string;
      },
    ): AsyncResult<readonly AiBatchItem[]>;
    /** Claims batches to poll for `leaseSeconds` (service role). */
    due(options?: {
      readonly batch?: number;
      readonly leaseSeconds?: number;
    }): AsyncResult<readonly AiBatch[]>;
    update(batchId: string, patch: AiBatchPatch): AsyncResult<AiBatch>;
    saveItems(
      batchId: string,
      items: readonly AiBatchItemInput[],
    ): AsyncResult<number>;
  };
  /**
   * The sandbox registry, which lives in the ai-chat module since 0.7. It
   * calls `options.schema`, so that schema needs ai-chat installed. Use
   * `createAiChat(...).sandboxes`; this alias goes in 0.8.
   */
  readonly sandboxes: AiSandboxes;
}

const BATCH_STATUSES: ReadonlySet<string> = new Set([
  "pending",
  "completed",
  "failed",
  "cancelled",
]);
const ITEM_STATUSES: ReadonlySet<string> = new Set([
  "succeeded",
  "failed",
  "cancelled",
  "expired",
]);
const instant = (value: unknown): Temporal.Instant =>
  value instanceof Date ? toInstant(value) : toInstant(textOf(value));

const numberOf = (value: unknown): number =>
  typeof value === "number" && Number.isFinite(value) ? value : 0;

function refOf(value: unknown): CredentialRef {
  const ref = credentialRefOf(value);
  if (ref === undefined) {
    throw new TypeError("ai_provider_keys returned a key without a ref");
  }
  return ref;
}

function keyOf(value: unknown): AiProviderKey {
  const row = recordOf(value, "ai_provider_keys");
  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organization_id"]),
    provider: textOf(row["provider"]),
    name: textOf(row["name"]),
    credentialRef: refOf(row["credential_ref"]),
    settings: recordOrEmpty(row["settings"]),
    enabled: row["enabled"] !== false,
    createdBy: optionalText(row["created_by"]),
    createdAt: instant(row["created_at"]),
    updatedAt: instant(row["updated_at"]),
  };
}

function countsOf(value: unknown): AiBatchCounts {
  const row = recordOrEmpty(value);
  const out: Record<string, number> = {};
  for (const key of ["total", "pending", "completed", "failed"] as const)
    if (typeof row[key] === "number") out[key] = row[key];
  return out;
}

function batchOf(value: unknown): AiBatch {
  const row = recordOf(value, "ai_batches");
  const status = textOf(row["status"]);
  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organization_id"]),
    userId: optionalText(row["user_id"]),
    provider: textOf(row["provider"]),
    reference: recordOrEmpty(row["reference"]),
    // SAFETY: BATCH_STATUSES holds exactly the AiBatchStatus members.
    status: BATCH_STATUSES.has(status) ? (status as AiBatchStatus) : "failed",
    rawStatus: optionalText(row["raw_status"]),
    itemCount: numberOf(row["item_count"]),
    counts: countsOf(row["counts"]),
    error: optionalText(row["error"]),
    metadata: recordOrEmpty(row["metadata"]),
    resultsSaved: row["results_saved"] === true,
    polls: numberOf(row["polls"]),
    nextPollAt: optionalInstant(row["next_poll_at"]),
    expiresAt: optionalInstant(row["expires_at"]),
    completedAt: optionalInstant(row["completed_at"]),
    createdAt: instant(row["created_at"]),
    updatedAt: instant(row["updated_at"]),
  };
}

function itemOf(value: unknown): AiBatchItem {
  const row = recordOf(value, "ai_batch_items");
  const status = textOf(row["status"]);
  return {
    batchId: textOf(row["batch_id"]),
    requestId: textOf(row["request_id"]),
    organizationId: textOf(row["organization_id"]),
    // SAFETY: ITEM_STATUSES holds exactly the AiBatchItemStatus members.
    status: ITEM_STATUSES.has(status)
      ? (status as AiBatchItemStatus)
      : "failed",
    output: row["output"] ?? undefined,
    usage: row["usage"] ?? undefined,
    error: optionalText(row["error"]),
    createdAt: instant(row["created_at"]),
  };
}

const sameRef = (a: CredentialRef, b: CredentialRef): boolean =>
  JSON.stringify(a) === JSON.stringify(b);

/** Per-tenant provider keys and provider batch jobs. */
export function createAiProviders(options: AiProvidersOptions): AiProviders {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const service = blockCall(
    options.service ?? options.transport,
    options.schema,
    options.mappers,
  );
  const credentials = options.credentials;

  const revoke = (
    ref: CredentialRef,
    organizationId: string,
  ): AsyncResult<boolean> =>
    revokeIfConfigured(credentials, ref, {
      subject: { type: "app" },
      tenant: organizationId,
    });

  const revokeAll = (keys: readonly AiProviderKey[]): AsyncResult<number> =>
    AsyncResult.from(async () => {
      for (const key of keys) {
        const revoked = await revoke(key.credentialRef, key.organizationId);
        if (!revoked.ok) return revoked;
      }
      return ok(keys.length);
    });

  return {
    keys: {
      list: (organizationId) =>
        call("list_ai_provider_keys", { tenant: organizationId }, (value) =>
          recordsOf(value, "list_ai_provider_keys").map(keyOf),
        ),
      save: (organizationId, key) =>
        call(
          "save_ai_provider_key",
          {
            tenant: organizationId,
            provider: key.provider,
            credential_ref: key.credentialRef,
            name: key.name,
            settings: key.settings,
            enabled: key.enabled,
          },
          (value) => recordOf(value, "save_ai_provider_key"),
        ).andThen((saved) => {
          const stored = keyOf(saved["key"]);
          const replaced = saved["replaced"];
          return isRecord(replaced) &&
            !sameRef(refOf(replaced), stored.credentialRef)
            ? revoke(refOf(replaced), stored.organizationId).map(() => stored)
            : AsyncResult.ok(stored);
        }),
      remove: (keyId) =>
        call("delete_ai_provider_key", { id: keyId }, (value) =>
          value === null || value === undefined ? undefined : keyOf(value),
        ).andThen((key) =>
          key === undefined
            ? AsyncResult.ok(false)
            : revoke(key.credentialRef, key.organizationId).map(() => true),
        ),
      removeAll: (organizationId) =>
        service(
          "delete_ai_provider_keys",
          { tenant: organizationId },
          (value) => recordsOf(value, "delete_ai_provider_keys").map(keyOf),
        ).andThen(revokeAll),
      resolve: (organizationId, resolveOptions = {}) =>
        service(
          "ai_provider_keys_for",
          { tenant: organizationId, providers: resolveOptions.providers },
          (value) => recordsOf(value, "ai_provider_keys_for").map(keyOf),
        ).andThen((keys) =>
          AsyncResult.from(async () => {
            if (keys.length === 0) return ok([]);
            if (credentials === undefined) {
              return err(
                dbError(
                  "invalid_input",
                  "createAiProviders needs credentials to resolve provider keys",
                  { hint: "AI_PROVIDER_KEY_UNRESOLVED" },
                ),
              );
            }
            const foreign = keys.find(
              (key) =>
                !credentialRefInTenant(key.credentialRef, organizationId),
            );
            if (foreign !== undefined) {
              return err(foreignCredentialRef(organizationId));
            }
            const tokens = await Promise.all(
              keys.map((key) =>
                credentials.getToken(key.credentialRef, {
                  subject: { type: "app" },
                  ...(resolveOptions.signal === undefined
                    ? {}
                    : { signal: resolveOptions.signal }),
                }),
              ),
            );
            const resolved: ResolvedProviderKey[] = [];
            for (const [index, token] of tokens.entries()) {
              if (!token.ok) return token;
              const key = keys[index];
              if (key === undefined) continue;
              resolved.push({
                provider: key.provider,
                name: key.name,
                token: token.data.token,
                headers: token.data.headers,
                settings: key.settings,
              });
            }
            return ok(resolved);
          }),
        ),
    },
    batches: {
      record: (organizationId, batch) =>
        call(
          "record_ai_batch",
          {
            tenant: organizationId,
            provider: batch.provider,
            reference: batch.reference,
            fields: {
              ...(batch.userId === undefined ? {} : { user_id: batch.userId }),
              ...(batch.itemCount === undefined
                ? {}
                : { item_count: batch.itemCount }),
              ...(batch.metadata === undefined
                ? {}
                : { metadata: batch.metadata }),
              ...(batch.status === undefined ? {} : { status: batch.status }),
              ...(batch.rawStatus === undefined
                ? {}
                : { raw_status: batch.rawStatus }),
              ...(batch.counts === undefined ? {} : { counts: batch.counts }),
              ...(batch.expiresAt === undefined
                ? {}
                : { expires_at: batch.expiresAt.toString() }),
            },
          },
          batchOf,
        ),
      get: (batchId) =>
        call("get_ai_batch", { id: batchId }, (value) =>
          value === null || value === undefined ? undefined : batchOf(value),
        ),
      list: (organizationId, listOptions = {}) =>
        call(
          "list_ai_batches",
          {
            tenant: organizationId,
            status: listOptions.status,
            max_rows: listOptions.limit,
          },
          (value) => recordsOf(value, "list_ai_batches").map(batchOf),
        ),
      items: (batchId, itemOptions = {}) =>
        call(
          "list_ai_batch_items",
          {
            id: batchId,
            after: pageOf(itemOptions).cursor,
            max_rows: itemOptions.limit,
          },
          (value) => recordsOf(value, "list_ai_batch_items").map(itemOf),
        ),
      due: (dueOptions = {}) =>
        service(
          "due_ai_batches",
          { batch: dueOptions.batch, lease_seconds: dueOptions.leaseSeconds },
          (value) => recordsOf(value, "due_ai_batches").map(batchOf),
        ),
      update: (batchId, patch) => {
        const fields: Record<string, unknown> = {};
        if (patch.status !== undefined) fields["status"] = patch.status;
        if (patch.rawStatus !== undefined)
          fields["raw_status"] = patch.rawStatus;
        if (patch.counts !== undefined) fields["counts"] = patch.counts;
        if (patch.error !== undefined) fields["error"] = patch.error;
        if (patch.expiresAt !== undefined)
          fields["expires_at"] = patch.expiresAt.toString();
        if (patch.resultsSaved !== undefined)
          fields["results_saved"] = patch.resultsSaved;
        if (patch.nextPollAt !== undefined)
          fields["next_poll_at"] = instantArg(patch.nextPollAt);
        return service("update_ai_batch", { id: batchId, fields }, batchOf);
      },
      saveItems: (batchId, items) =>
        service(
          "save_ai_batch_items",
          {
            id: batchId,
            items: {
              items: items.map((item) => ({
                request_id: item.requestId,
                status: item.status,
                output: item.output ?? null,
                usage: item.usage ?? null,
                error: item.error ?? null,
              })),
            },
          },
          (value) => Number(value ?? 0),
        ),
    },
    sandboxes: aiSandboxes(call, service),
  };
}
