import type { AbstractIntlMessages } from "next-intl";

/** What the signed-in shell (sidebar, header, banners) reads on the client. */
export const APP_NAMESPACES = [
  "announcements",
  "app",
  "dashboard",
  "errors",
  "inbox",
  "navigation",
  "notifications",
  "offline",
  "organization",
  "search",
  "settings",
  "user",
] as const;

/**
 * The messages for the listed top-level namespaces, for the `messages` prop of
 * a `NextIntlClientProvider` (the "providing individual messages" option in the
 * next-intl docs).
 */
export function pick(
  messages: AbstractIntlMessages,
  namespaces: readonly string[],
): AbstractIntlMessages {
  const picked: AbstractIntlMessages = {};

  for (const namespace of namespaces) {
    const value = messages[namespace];

    if (value !== undefined) {
      picked[namespace] = value;
    }
  }

  return picked;
}
