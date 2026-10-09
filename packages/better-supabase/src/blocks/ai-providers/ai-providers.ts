import type { CredentialRef } from "../../credentials/provider.ts";
import type {
  AiProviderKey,
  AiProviders,
  AiProvidersOptions,
  ResolvedProviderKey,
} from "./types.ts";

import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import { revokeIfConfigured } from "../../credentials/compose.ts";
import {
  credentialRefInTenant,
  foreignCredentialRef,
} from "../../credentials/provider.ts";
import {
  applyTemporal,
  blockCall,
  instantArg,
  isRecord,
  recordOf,
  recordsOf,
  pageOf,
} from "../shared.ts";
import { batchOf, itemOf, keyOf, refOf } from "./rows.ts";

export type {
  AiBatch,
  AiBatchCounts,
  AiBatchItem,
  AiBatchItemInput,
  AiBatchItemStatus,
  AiBatchPatch,
  AiBatchStatus,
  AiProviderKey,
  AiProviderKeyInput,
  AiProviders,
  AiProvidersOptions,
  NewAiBatch,
  ResolvedProviderKey,
} from "./types.ts";

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
  };
}
