import type {
  Count,
  FacetResult,
  ListPage,
  PageOptions,
} from "../../core/block-helpers.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type {
  CountOptions,
  FacetOptions,
  RequiredTenantOption,
} from "../../core/entity-list.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type {
  CredentialProvider,
  CredentialRef,
} from "../../credentials/provider.ts";
import type { BlockTemporalOptions, CursorPageOptions } from "../shared.ts";

/**
 * A tenant's own key for a provider. The key itself stays in the credential
 * provider.
 */
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
  /**
   * Store the key first, for example with `vaultCredentials().set(ref,
   * apiKey)`.
   */
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

export interface AiKeysOptions extends BlockTemporalOptions {
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<AiKeys>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  /** Calls as the user: `rpcTransport(supabase)`. */
  readonly transport: BlockTransport;
  /** Calls as the service role, for resolving keys, polling and the idle stop. */
  readonly service?: BlockTransport;
  /** Resolves and revokes the keys' credential refs. */
  readonly credentials?: CredentialProvider;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`. Default `better_supabase`.
   */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
}

export interface AiKeys {
  readonly keys: {
    /**
     * By provider and name.
     *
     * @deprecated Use `page`, which pages by keyset and takes `q`, sorts, array
     * filters and a count (ADR 1077).
     */
    list(
      organizationId: string,
      options?: { readonly limit?: number },
    ): AsyncResult<readonly AiProviderKey[]>;
    /**
     * One keyset page of the tenant's keys, by provider and name. `filters`
     * takes `provider` and `enabled` as lists; `q` searches the provider and
     * name.
     */
    page(
      options: PageOptions & RequiredTenantOption,
    ): AsyncResult<ListPage<AiProviderKey>>;
    /**
     * The values of each facet (`provider`, `enabled`) and how many keys hold
     * each.
     */
    facets(
      options: FacetOptions & RequiredTenantOption,
    ): AsyncResult<readonly FacetResult[]>;
    /** How many keys match the page's filters. */
    count(options: CountOptions & RequiredTenantOption): AsyncResult<Count>;
    /** One key by id, or a `not_found` error. */
    get(keyId: string): AsyncResult<AiProviderKey>;
    /**
     * Adds or replaces a key (`ai_keys.manage`), and revokes the credential it
     * replaced.
     */
    upsert(input: {
      organizationId: string;
      key: AiProviderKeyInput;
    }): AsyncResult<AiProviderKey>;
    /** Deletes a key and revokes its credential. `false` when there was none. */
    remove(keyId: string): AsyncResult<boolean>;
    /**
     * Deletes every key of a tenant and revokes each credential (service role):
     * the step to run when a tenant is deleted. Returns how many.
     */
    removeAll(organizationId: string): AsyncResult<number>;
    /**
     * The tenant's enabled keys with their tokens, for one request (service
     * role).
     */
    resolve(
      input: { organizationId: string } & {
        readonly providers?: readonly string[];
        readonly signal?: AbortSignal;
      },
    ): AsyncResult<readonly ResolvedProviderKey[]>;
  };
  readonly batches: {
    record(input: {
      organizationId: string;
      batch: NewAiBatch;
    }): AsyncResult<AiBatch>;
    /**
     * One batch, or undefined when there is none.
     *
     * @deprecated Use `getBatch`, which returns a `not_found` error for an
     * unknown id (ADR 1077).
     */
    get(batchId: string): AsyncResult<AiBatch | undefined>;
    /** One batch by id, or a `not_found` error. */
    getBatch(batchId: string): AsyncResult<AiBatch>;
    /**
     * Newest first.
     *
     * @deprecated Use `page`, which pages by keyset and takes sorts, array
     * filters and a count (ADR 1077).
     */
    list(
      input: { organizationId: string } & {
        readonly status?: AiBatchStatus;
        readonly limit?: number;
      },
    ): AsyncResult<readonly AiBatch[]>;
    /**
     * One keyset page of the tenant's batches, newest first. `filters` takes
     * `status` and `provider` as lists.
     */
    page(
      options: PageOptions & RequiredTenantOption,
    ): AsyncResult<ListPage<AiBatch>>;
    /**
     * The values of each facet (`status`, `provider`) and how many batches hold
     * each.
     */
    facets(
      options: FacetOptions & RequiredTenantOption,
    ): AsyncResult<readonly FacetResult[]>;
    /** How many batches match the page's filters. */
    count(options: CountOptions & RequiredTenantOption): AsyncResult<Count>;
    items(
      input: { batchId: string } & CursorPageOptions<string>,
    ): AsyncResult<readonly AiBatchItem[]>;
    /** Claims batches to poll for `leaseSeconds` (service role). */
    due(options?: {
      readonly batch?: number;
      readonly leaseSeconds?: number;
    }): AsyncResult<readonly AiBatch[]>;
    update(input: {
      batchId: string;
      patch: AiBatchPatch;
    }): AsyncResult<AiBatch>;
    saveItems(input: {
      batchId: string;
      items: readonly AiBatchItemInput[];
    }): AsyncResult<number>;
  };
}
