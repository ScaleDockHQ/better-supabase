import {
  type DbError,
  DbException,
  dbError,
  isDbError,
} from "../core/errors.ts";
import { toDbError } from "../core/result.ts";

interface StorageFailure {
  readonly message?: string;
  readonly name?: string;
  readonly status?: number;
  readonly statusCode?: string;
  readonly code?: string;
}

/** Maps a Storage error (`StorageApiError`, fetch failures) to a `DbError`. */
export function fromStorageError(raw: unknown, table?: string): DbError {
  if (isDbError(raw)) return raw;
  if (raw instanceof DbException) return raw.error;
  if (typeof raw !== "object" || raw === null) return toDbError(raw);
  // SAFETY: the check above narrows raw to an object; every StorageFailure
  // field is optional.
  const failure = raw as StorageFailure;
  if (failure.name === "AbortError") return toDbError(raw);
  const message = failure.message ?? "Storage request failed";
  const code = failure.code ?? failure.statusCode;
  const base = { ...(code ? { code } : {}), ...(table ? { table } : {}) };
  const statusCode = Number(failure.statusCode);
  const status =
    Number.isFinite(statusCode) && statusCode >= 400
      ? statusCode
      : (failure.status ?? 0);
  if (code === "FeatureNotEnabled" || /^Route \S+ not found$/.test(message))
    return dbError("unsupported", message, base);
  if (
    /row-level security|unauthorized to|AccessDenied/i.test(
      `${message} ${code ?? ""}`,
    )
  ) {
    return dbError("forbidden", message, base);
  }
  if (/already exists|duplicate/i.test(`${message} ${code ?? ""}`))
    return dbError("conflict", message, base);
  if (failure.name === "StorageUnknownError" && status === 0)
    return dbError("network", message, base);
  switch (status) {
    case 400:
      return dbError("invalid_request", message, base);
    case 401:
      return dbError("unauthorized", message, base);
    case 403:
      return dbError("forbidden", message, base);
    case 404:
      return dbError("not_found", message, base);
    case 409:
      return dbError("conflict", message, base);
    case 413:
    case 415:
      return dbError("invalid_input", message, { ...base, status });
    case 408:
    case 429:
      return dbError("network", message, { ...base, status });
    default:
      return status >= 500
        ? dbError("network", message, base)
        : dbError("unexpected", message, base);
  }
}
