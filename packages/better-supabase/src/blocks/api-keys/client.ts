import type { DbError } from "../../core/errors.ts";
import type { Result } from "../../core/result.ts";
import type { AuthPort, Controller } from "../controller.ts";
import type {
  ApiKey,
  ApiKeys,
  CreateApiKeyInput,
  CreatedApiKey,
} from "./api-keys.ts";

import { toDbError } from "../../core/result.ts";
import { defineController, whileSignedIn } from "../controller.ts";

/** What `create` takes: the organization comes from the controller. */
export type ApiKeyDraft = Omit<CreateApiKeyInput, "organizationId">;

/** A key change that committed, for `onChanged`. */
export type ApiKeyChange =
  | { readonly kind: "created"; readonly key: ApiKey }
  | { readonly kind: "revoked"; readonly id: string };

export interface ApiKeysControllerOptions {
  readonly client: Pick<ApiKeys, "list" | "create" | "revoke">;
  readonly auth: AuthPort;
  /**
   * The organization whose keys to list and create: all of them for its
   * managers, the caller's own for everyone else. `null` lists the caller's
   * personal keys.
   */
  readonly organizationId: string | null;
  /**
   * Runs after a key was created or revoked, such as a server action that
   * completes an onboarding step. A throw is kept in `error`.
   */
  readonly onChanged?: (change: ApiKeyChange) => void | Promise<void>;
}

export interface ApiKeysSnapshot {
  /** Newest first; `undefined` until the first load. */
  readonly keys: readonly ApiKey[] | undefined;
  /** Whether a key is being created. */
  readonly creating: boolean;
  /**
   * The key `create` made, with its token, which is shown once; until
   * `dismiss`.
   */
  readonly created: CreatedApiKey | undefined;
  /** The key ids with a revoke in flight. */
  readonly revoking: readonly string[];
  readonly error: DbError | undefined;
}

export interface ApiKeysActions {
  /**
   * Creates a key and keeps its token in `created`; a failure is also kept in
   * `error`.
   */
  readonly create: (draft: ApiKeyDraft) => Promise<Result<CreatedApiKey>>;
  /** Revokes a key at once, then loads the list again. */
  readonly revoke: (id: string) => Promise<Result<boolean>>;
  /** Forgets `created` and `error`, such as when the token dialog closes. */
  readonly dismiss: () => void;
  readonly refresh: () => Promise<void>;
}

export type ApiKeysController = Controller<ApiKeysSnapshot, ApiKeysActions>;

const newestFirst = (keys: readonly ApiKey[]): readonly ApiKey[] =>
  keys.toSorted(
    (a, b) => b.createdAt.epochMilliseconds - a.createdAt.epochMilliseconds,
  );

/**
 * The API keys of an organization (or the caller's personal keys) for an API
 * keys table: `create` returns the token once, `revoke` revokes a key, and both
 * load the list again.
 */
export function createApiKeysController(
  options: ApiKeysControllerOptions,
): ApiKeysController {
  const { client, organizationId } = options;

  return defineController<ApiKeysSnapshot, ApiKeysActions>(
    {
      keys: undefined,
      creating: false,
      created: undefined,
      revoking: [],
      error: undefined,
    },
    (state) => {
      let ticket = 0;

      const refresh = async (): Promise<void> => {
        const request = ++ticket;
        const result = await client.list(organizationId ?? undefined);

        if (request !== ticket) {
          return;
        }

        state.set(
          result.ok
            ? { keys: newestFirst(result.data), error: undefined }
            : { error: result.error },
        );
      };

      const changed = async (change: ApiKeyChange): Promise<void> => {
        try {
          await options.onChanged?.(change);
        } catch (cause) {
          state.set({ error: toDbError(cause) });
        }
      };

      return {
        actions: {
          refresh,
          dismiss: () => {
            state.set({ created: undefined, error: undefined });
          },
          create: async (draft) => {
            state.set({ creating: true, created: undefined, error: undefined });

            const result = await client.create(
              organizationId === null ? draft : { ...draft, organizationId },
            );

            state.set(
              result.ok
                ? { creating: false, created: result.data }
                : { creating: false, error: result.error },
            );

            if (result.ok) {
              await refresh();
              await changed({ kind: "created", key: result.data.key });
            }

            return result;
          },
          revoke: async (id) => {
            state.set((current) => ({
              revoking: [...current.revoking, id],
              error: undefined,
            }));
            const result = await client.revoke(id);
            state.set((current) => ({
              revoking: current.revoking.filter((each) => each !== id),
              ...(result.ok ? {} : { error: result.error }),
            }));

            if (result.ok) {
              await refresh();
              await changed({ kind: "revoked", id });
            }

            return result;
          },
        },
        start: () =>
          whileSignedIn(options.auth, () => {
            void refresh();

            return;
          }),
      };
    },
  );
}
