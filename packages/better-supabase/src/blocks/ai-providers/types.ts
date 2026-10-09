import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { AsyncResult } from "../../core/result.ts";
import type {
  CredentialProvider,
  CredentialRef,
} from "../../credentials/provider.ts";
import type { BlockTemporalOptions, CursorPageOptions } from "../shared.ts";

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
    /** Adds or replaces a key (`ai.admin`), and revokes the credential it replaced. */
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
      options?: CursorPageOptions<string>,
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
}
