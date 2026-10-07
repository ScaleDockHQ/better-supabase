"use client";

import type { DbError } from "better-supabase";

import { useExtracted } from "next-intl";

/**
 * A translated sentence for an action's `DbError`. Server Actions can't read
 * the locale root param, so they return the error and the client words it.
 */
export function useErrorMessage(): (error: DbError) => string {
  const t = useExtracted("errors");
  return (error) => {
    switch (error.kind) {
      case "unauthorized":
        return t("Sign in again to continue.");
      case "forbidden":
        return t("You don't have permission to do that.");
      case "not_found":
        return t("That item no longer exists.");
      case "conflict":
      case "exclusion":
      case "multiple_rows":
        return t("That already exists.");
      case "rate_limited":
        return t("Too many requests. Wait a moment and try again.");
      case "quota_exceeded":
        return t("Your plan's limit is reached. Upgrade to continue.");
      case "validation":
      case "check":
      case "not_null":
      case "invalid_input":
      case "foreign_key":
        return t("Check the highlighted fields and try again.");
      case "stale":
      case "serialization":
        return t("Someone else changed this. Reload and try again.");
      case "timeout":
      case "network":
      case "aborted":
        return t("The server didn't answer. Try again.");
      // Raised by the SQL modules with a specific message; shown as is.
      case "raised":
        return error.message;
      case "invalid_value":
      case "invalid_request":
      case "max_affected":
      case "unsupported":
      case "unexpected":
        return t("Something went wrong. Try again.");
      default: {
        const unknown: never = error;
        return String(unknown);
      }
    }
  };
}
