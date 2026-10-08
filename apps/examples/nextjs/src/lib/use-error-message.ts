"use client";

import { type DbError, createErrorMessages } from "better-supabase";
import { useExtracted } from "next-intl";

/**
 * A translated sentence for an action's `DbError`. Server Actions can't read
 * the locale root param, so they return the error and the client words it.
 * `createErrorMessages` fails to compile when a new error kind has no entry.
 */
export function useErrorMessage(): (error: DbError) => string {
  const t = useExtracted("errors");
  const exists = t("That already exists.");
  const fields = t("Check the highlighted fields and try again.");
  const stale = t("Someone else changed this. Reload and try again.");
  const offline = t("The server didn't answer. Try again.");
  const generic = t("Something went wrong. Try again.");
  return createErrorMessages({
    unauthorized: t("Sign in again to continue."),
    forbidden: t("You don't have permission to do that."),
    not_found: t("That item no longer exists."),
    conflict: exists,
    exclusion: exists,
    multiple_rows: exists,
    rate_limited: t("Too many requests. Wait a moment and try again."),
    quota_exceeded: t("Your plan's limit is reached. Upgrade to continue."),
    validation: fields,
    check: fields,
    not_null: fields,
    invalid_input: fields,
    foreign_key: fields,
    stale,
    serialization: stale,
    timeout: offline,
    network: offline,
    aborted: offline,
    // Raised by the SQL modules with a specific message; shown as is.
    raised: (error) => error.message,
    invalid_value: generic,
    invalid_request: generic,
    max_affected: generic,
    unsupported: generic,
    unexpected: generic,
  });
}
