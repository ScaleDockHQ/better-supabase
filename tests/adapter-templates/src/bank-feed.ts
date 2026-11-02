import type { BankFeed } from "better-supabase/blocks/banking";

import { AsyncResult, ok } from "better-supabase";
import { money } from "better-supabase/commerce";

import type { HttpOptions } from "./http.ts";

import { list, record, requestJson, text } from "./http.ts";

/**
 * A `BankFeed` over an aggregator's REST API (ADR 0153). Replace the paths and
 * the field names with your provider's; keep `externalId` stable, because an
 * import of the same id adds nothing.
 */
export function createBankFeed(options: HttpOptions): BankFeed {
  return {
    apiVersion: 1,
    name: "example-aggregator",
    listAccounts: () =>
      AsyncResult.from(async () => {
        const body = await requestJson(options, "/accounts");

        if (!body.ok) {
          return body;
        }

        return ok(
          list(record(body.data, "accounts").accounts, "accounts").map(
            (item) => {
              const account = record(item, "account");

              return {
                ref: text(account.id, "account.id"),
                currency: text(account.currency, "account.currency"),
                ...(typeof account.name === "string"
                  ? { name: account.name }
                  : {}),
                ...(typeof account.iban === "string"
                  ? { iban: account.iban }
                  : {}),
              };
            },
          ),
        );
      }),
    transactions: (accountRef, since) =>
      AsyncResult.from(async () => {
        const path = `/accounts/${encodeURIComponent(accountRef)}/transactions?since=${encodeURIComponent(String(since))}`;
        const body = await requestJson(options, path);

        if (!body.ok) {
          return body;
        }

        return ok(
          list(
            record(body.data, "transactions").transactions,
            "transactions",
          ).map((item) => {
            const row = record(item, "transaction");
            const remittance = row.remittance;

            return {
              externalId: text(row.id, "transaction.id"),
              bookedOn: text(row.booked, "transaction.booked"),
              // The provider sends a signed amount in minor units.
              amount: money(
                BigInt(text(row.amountMinor, "transaction.amountMinor")),
                text(row.currency, "transaction.currency"),
              ),
              ...(typeof remittance === "string" ? { remittance } : {}),
            };
          }),
        );
      }),
  };
}
