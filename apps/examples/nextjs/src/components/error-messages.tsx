"use client";

import type { ReactNode } from "react";

import { createErrorMessages } from "better-supabase";
import { blockErrorMessage } from "better-supabase/blocks/messages";
import { ErrorMessagesProvider } from "better-supabase/react";
import { useExtracted } from "next-intl";

/**
 * Words a `DbError` once for every component below it that calls
 * `useErrorMessage`. A block error shows the message of its hint code; the
 * other kinds get a translated sentence. Server Actions can't read the locale
 * root param, so they return the error and the client words it.
 * `createErrorMessages` fails to compile when a new error kind has no entry.
 * The layouts that render it list the `errors` namespace.
 */
export function ErrorMessages({ children }: { children: ReactNode }) {
  const t = useExtracted("errors");
  const exists = t("That already exists.");
  const fields = t("Check the highlighted fields and try again.");
  const stale = t("Someone else changed this. Reload and try again.");
  const offline = t("The server didn't answer. Try again.");
  const generic = t("Something went wrong. Try again.");

  const kindMessage = createErrorMessages({
    unauthorized: t("Sign in again to continue."),
    forbidden: t("You don't have permission to do that."),
    not_found: t("That item no longer exists."),
    conflict: exists,
    exclusion: exists,
    multiple_rows: exists,
    rate_limited: t("Too many requests. Wait a moment and try again."),
    quota_exceeded: t("Your plan's limit is reached. Upgrade to continue."),
    truncated: t("The list was cut off. Ask for a page instead."),
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
    raised: (error) => error.message,
    invalid_value: generic,
    invalid_request: generic,
    max_affected: generic,
    unsupported: generic,
    unexpected: generic,
  });

  return (
    <ErrorMessagesProvider
      messages={(error) => blockErrorMessage(error) ?? kindMessage(error)}
    >
      {children}
    </ErrorMessagesProvider>
  );
}
