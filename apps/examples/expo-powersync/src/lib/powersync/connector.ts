import type { DbError, DbErrorKind, Result } from "better-supabase";

import {
  type CommonPowerSyncDatabase,
  type CrudEntry,
  type PowerSyncBackendConnector,
  UpdateType,
} from "@powersync/react-native";

import { bs, supabase } from "../supabase/native";

type Outcome = "retry" | "discard" | "conflict";

/** What an upload error means for the queued change. */
function outcomeOf(kind: DbErrorKind): Outcome {
  switch (kind) {
    case "network":
    case "timeout":
    case "aborted":
    case "rate_limited":
    case "quota_exceeded":
    case "serialization":
    case "unauthorized":
    case "unexpected":
      return "retry";
    case "conflict":
    case "stale":
    case "foreign_key":
      return "conflict";
    case "not_found":
    case "forbidden":
    case "check":
    case "not_null":
    case "exclusion":
    case "invalid_input":
    case "invalid_value":
    case "raised":
    case "invalid_request":
    case "max_affected":
    case "validation":
    case "multiple_rows":
    case "unsupported":
      return "discard";
    default: {
      const unhandled: never = kind;
      throw new TypeError(`Unhandled error kind ${String(unhandled)}`);
    }
  }
}

/** Replays one local change through the repository, so RLS and validation run. */
async function upload(entry: CrudEntry): Promise<Result<unknown>> {
  const customers = bs.db.customers;
  const data = entry.opData ?? {};
  switch (entry.op) {
    case UpdateType.PUT:
      // SAFETY: PowerSync recorded these columns from an insert into the
      // local customers table, whose columns mirror public.customers.
      return customers.upsert({ ...data, id: entry.id } as Parameters<
        typeof customers.upsert
      >[0]);
    case UpdateType.PATCH:
      return customers.update(entry.id, data);
    case UpdateType.DELETE:
      return customers.delete(entry.id);
    default: {
      const unhandled: never = entry.op;
      throw new TypeError(`Unhandled op ${String(unhandled)}`);
    }
  }
}

/** Changes the server refused, for the UI to show next to the row. */
export const conflicts: { entry: CrudEntry; error: DbError }[] = [];

export const connector: PowerSyncBackendConnector = {
  async fetchCredentials() {
    const { data } = await supabase.auth.getSession();
    if (!data.session) return null;
    return {
      endpoint: process.env.EXPO_PUBLIC_POWERSYNC_URL,
      token: data.session.access_token,
    };
  },

  async uploadData(database: CommonPowerSyncDatabase) {
    const transaction = await database.getNextCrudTransaction();
    if (!transaction) return;
    for (const entry of transaction.crud) {
      if (entry.table !== "customers") continue;
      const result = await upload(entry);
      if (result.ok) continue;
      const outcome = outcomeOf(result.error.kind);
      switch (outcome) {
        case "retry":
          // PowerSync keeps the transaction queued and calls uploadData again.
          throw new Error(result.error.message);
        case "conflict":
          conflicts.push({ entry, error: result.error });
          break;
        case "discard":
          break;
        default: {
          const unhandled: never = outcome;
          throw new TypeError(`Unhandled outcome ${String(unhandled)}`);
        }
      }
    }
    await transaction.complete();
  },
};
