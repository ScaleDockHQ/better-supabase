import type { DbError } from "../../core/errors.ts";
import type { Result } from "../../core/result.ts";
import type { BankFeed, BankFeedAccount } from "./feed.ts";
import type { BankDate, BankTransactionInput } from "./statement.ts";

import { parseMoney } from "../../commerce/money.ts";
import { dbError } from "../../core/errors.ts";
import { isRecord } from "../../core/guards.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";

export interface BerlinGroupFeedOptions {
  /**
   * The bank's XS2A base URL up to the version, such as
   * `https://api.bank.example/xs2a/v1`.
   */
  readonly baseUrl: string;
  /**
   * The consent id the account holder gave. Creating a consent needs the
   * holder's strong customer authentication in a browser redirect, which this
   * adapter does not run: create it with the bank's flow and pass the id.
   */
  readonly consentId: string;
  /**
   * Headers for the call: the TPP's `Authorization` bearer token, or the
   * signing headers (`Digest`, `Signature`, `TPP-Signature-Certificate`) for a
   * bank that requires message signing. Called once per request.
   */
  readonly headers?: () => Promise<Readonly<Record<string, string>>>;
  /** The holder's IP, sent as `PSU-IP-Address` for banks that ask for it. */
  readonly psuIpAddress?: string;
  readonly fetch?: typeof fetch;
  /** Pages followed before the feed stops with an error. Default 50. */
  readonly maxPages?: number;
}

function failure(status: number, message: string): DbError {
  if (status === 401 || status === 403) {
    return dbError("unauthorized", message, { code: String(status) });
  }

  if (status === 429) {
    return dbError("rate_limited", message, { code: String(status) });
  }

  return dbError("unexpected", message, { code: String(status) });
}

function text(value: unknown): string | undefined {
  return typeof value === "string" && value !== "" ? value : undefined;
}

function dateText(date: BankDate): string {
  return typeof date === "string" ? date : date.toString();
}

function accountOf(value: unknown): BankFeedAccount | undefined {
  if (!isRecord(value)) {
    return undefined;
  }

  const ref = text(value["resourceId"]);
  const currency = text(value["currency"]);

  if (ref === undefined || currency === undefined) {
    return undefined;
  }

  const name = text(value["name"]) ?? text(value["product"]);
  const iban = text(value["iban"]);

  return {
    ref,
    currency,
    ...(name === undefined ? {} : { name }),
    ...(iban === undefined ? {} : { iban }),
  };
}

function ibanOf(value: unknown): string | undefined {
  return isRecord(value) ? text(value["iban"]) : undefined;
}

/**
 * Reads one booked transaction of a Berlin Group `transactionDetails`. The
 * amount is signed in the bank's answer: a debit is negative. The counterparty
 * is the creditor of a debit and the debtor of a credit.
 */
function transactionOf(value: unknown): BankTransactionInput | undefined {
  if (!isRecord(value) || !isRecord(value["transactionAmount"])) {
    return undefined;
  }

  const amount = text(value["transactionAmount"]["amount"]);
  const currency = text(value["transactionAmount"]["currency"]);
  const bookedOn = text(value["bookingDate"]) ?? text(value["valueDate"]);

  if (
    amount === undefined ||
    currency === undefined ||
    bookedOn === undefined
  ) {
    return undefined;
  }

  const money = parseMoney(amount, currency);
  const debit = money.amount < 0n;
  const name = debit ? text(value["creditorName"]) : text(value["debtorName"]);

  const iban = ibanOf(
    debit ? value["creditorAccount"] : value["debtorAccount"],
  );

  const remittance =
    text(value["remittanceInformationUnstructured"]) ??
    (Array.isArray(value["remittanceInformationUnstructuredArray"])
      ? value["remittanceInformationUnstructuredArray"]
          .filter((line): line is string => typeof line === "string")
          .join(" ")
      : undefined);

  const externalId =
    text(value["transactionId"]) ?? text(value["entryReference"]);

  const valueOn = text(value["valueDate"]);
  const reference = text(value["creditorReference"]);
  const endToEnd = text(value["endToEndId"]);

  return {
    ...(externalId === undefined ? {} : { externalId }),
    bookedOn,
    ...(valueOn === undefined ? {} : { valueOn }),
    amount: money,
    ...(name === undefined ? {} : { counterpartyName: name }),
    ...(iban === undefined ? {} : { counterpartyIban: iban }),
    ...(remittance === undefined || remittance === "" ? {} : { remittance }),
    ...(reference === undefined ? {} : { structuredReference: reference }),
    ...(endToEnd === undefined ? {} : { endToEndId: endToEnd }),
  };
}

/**
 * A `BankFeed` over the Berlin Group NextGenPSD2 XS2A framework, version
 * 1.3.12: `GET /accounts` and `GET /accounts/{id}/transactions` with
 * `bookingStatus=booked`, following `_links.next`. It uses the bank's existing
 * consent and bundles no TPP certificate handling: pass the signing headers in.
 * Banks differ in optional fields, so a transaction without an amount, currency
 * or date is skipped instead of failing the page; a transaction without
 * `transactionId` is imported with a content hash.
 */
export function berlinGroupFeed(options: BerlinGroupFeedOptions): BankFeed {
  const send = options.fetch ?? fetch;
  const base = options.baseUrl.replace(/\/+$/, "");
  const maxPages = options.maxPages ?? 50;

  async function get(url: string): Promise<Result<unknown>> {
    const response = await send(url, {
      headers: {
        ...(await options.headers?.()),
        accept: "application/json",
        "consent-id": options.consentId,
        "x-request-id": crypto.randomUUID(),
        ...(options.psuIpAddress === undefined
          ? {}
          : { "psu-ip-address": options.psuIpAddress }),
      },
    });

    if (!response.ok) {
      return err(
        failure(
          response.status,
          `The bank answered ${response.status} to ${new URL(url).pathname}`,
        ),
      );
    }

    return ok(await response.json());
  }

  return {
    apiVersion: 1,
    name: "berlin-group",
    listAccounts: () =>
      AsyncResult.from(async () => {
        const page = await get(`${base}/accounts`);

        if (!page.ok) {
          return page;
        }

        const body = page.data;

        const accounts = isRecord(body) ? body["accounts"] : undefined;

        return ok(
          (Array.isArray(accounts) ? accounts : []).flatMap((value) => {
            const account = accountOf(value);

            return account === undefined ? [] : [account];
          }),
        );
      }),
    transactions: (accountRef, since) =>
      AsyncResult.from(async () => {
        const out: BankTransactionInput[] = [];

        let url: string | undefined =
          `${base}/accounts/${encodeURIComponent(accountRef)}/transactions?${new URLSearchParams(
            { bookingStatus: "booked", dateFrom: dateText(since) },
          )}`;

        for (let page = 0; url !== undefined; page += 1) {
          if (page >= maxPages) {
            return err(
              dbError(
                "unexpected",
                "The bank returned more pages than allowed",
              ),
            );
          }

          const fetched = await get(url);

          if (!fetched.ok) {
            return fetched;
          }

          const body = fetched.data;

          const booked =
            isRecord(body) && isRecord(body["transactions"])
              ? body["transactions"]["booked"]
              : undefined;

          for (const value of Array.isArray(booked) ? booked : []) {
            const transaction = transactionOf(value);

            if (transaction !== undefined) {
              out.push(transaction);
            }
          }

          const links =
            isRecord(body) && isRecord(body["transactions"])
              ? body["transactions"]["_links"]
              : undefined;

          const next =
            isRecord(links) && isRecord(links["next"])
              ? text(links["next"]["href"])
              : undefined;

          // Resolve against the base so a relative link stays on the bank's host.
          url =
            next === undefined
              ? undefined
              : new URL(next, `${base}/`).toString();

          if (
            url !== undefined &&
            new URL(url).origin !== new URL(base).origin
          ) {
            return err(
              dbError("unexpected", "The bank's next link leaves its own host"),
            );
          }
        }

        return ok(out);
      }),
  };
}
