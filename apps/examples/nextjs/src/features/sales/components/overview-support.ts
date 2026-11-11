import "server-only";
import type { Money } from "better-supabase/commerce";

import { formatMoney } from "better-supabase/commerce";
import { getLocale } from "next-intl/server";
import { forbidden } from "next/navigation";

import type { Permission } from "@/features/user/user-permissions";

import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

/** Ends the render with the 403 page when the caller lacks `permission`. */
export async function requirePermission(permission: Permission): Promise<void> {
  if (!can(await getPermissions(), permission)) {
    forbidden();
  }
}

/** Whether the caller holds `permission`, for the actions a page offers. */
export async function holds(permission: Permission): Promise<boolean> {
  return can(await getPermissions(), permission);
}

/** A formatter for amounts, in the request's locale. */
export async function moneyFormatter(): Promise<
  (amount: Money | null) => string
> {
  const locale = await getLocale();

  return (amount) => (amount === null ? "–" : formatMoney(amount, locale));
}

const instantFormats = new Map<string, Intl.DateTimeFormat>();
const plainFormats = new Map<string, Intl.DateTimeFormat>();

function formatterFor(
  cache: Map<string, Intl.DateTimeFormat>,
  locale: string,
  timeZone?: string,
): Intl.DateTimeFormat {
  const cached = cache.get(locale);

  if (cached) {
    return cached;
  }

  const options: Intl.DateTimeFormatOptions = { dateStyle: "medium" };

  if (timeZone !== undefined) {
    options.timeZone = timeZone;
  }

  const created = new Intl.DateTimeFormat(locale, options);

  cache.set(locale, created);

  return created;
}

/** A date or an instant as the locale's medium date, `–` when absent. */
export async function dateFormatter(): Promise<
  (value: string | null | undefined) => string
> {
  const locale = await getLocale();
  const instant = formatterFor(instantFormats, locale);
  // A plain date has no zone: read it as UTC so no zone moves it a day.
  const plain = formatterFor(plainFormats, locale, "UTC");

  return (value) => {
    if (value === null || value === undefined) {
      return "–";
    }

    const date = new Date(value);

    if (Number.isNaN(date.getTime())) {
      return value;
    }

    return (value.length === 10 ? plain : instant).format(date);
  };
}
