import { describe, expect, it } from "vitest";

import { SQL_MODULES } from "../../src/sql/registry.ts";

/**
 * Tenant tables that declare no `lifecycle` yet, so the data-lifecycle module
 * neither exports nor erases them with the tenant. The list only shrinks: a new
 * tenant table declares its lifecycle, and a table that gains one leaves it.
 */
const UNDECLARED = [
  "queue.schedules",
  "webhook-inbox.messages",
  "permissions.roles",
  "organizations.profiles",
  "organizations.paymentAccounts",
  "data-lifecycle.exports",
  "data-lifecycle.deletions",
  "data-lifecycle.holds",
  "sso.syncLog",
  "credentials.secrets",
  "share-links.views",
  "imports.refs",
  "imports.issues",
  "calendar.defaultAlarms",
  "calendar.grants",
  "calendar.rules",
  "calendar.recurrenceDates",
  "bookings.series",
  "orders.kitchenStations",
  "orders.kitchenRoutes",
  "orders.preparations",
  "activities.recordings",
  "activities.segments",
  "activities.notes",
  "activities.actions",
  "hiring.interviewers",
  "hiring.scorecardScores",
  "security-events.streams",
  "leave.balances",
  "vercel-marketplace.installations",
  "vercel-marketplace.resources",
  "assets.meterReadings",
  "assets.dueChecks",
  "assets.identifiers",
  "expenses.expenses",
];

function undeclared(): string[] {
  const found: string[] = [];

  for (const [name, module] of Object.entries(SQL_MODULES)) {
    for (const [logical, table] of Object.entries(module.names?.tables ?? {})) {
      if ("tenant" in table.columns && table.lifecycle === undefined) {
        found.push(`${name}.${logical}`);
      }
    }
  }

  return found;
}

describe("tenant table lifecycle", () => {
  it("every tenant table declares its lifecycle or is listed", () => {
    expect(undeclared()).toEqual(UNDECLARED);
  });
});
