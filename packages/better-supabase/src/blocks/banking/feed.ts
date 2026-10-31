import type { AsyncResult } from "../../core/result.ts";
import type { BankDate, BankTransactionInput } from "./statement.ts";

/** An account a bank feed can read. */
export interface BankFeedAccount {
  /** The provider's id of the account, passed back to `transactions`. */
  readonly ref: string;
  readonly name?: string;
  readonly iban?: string;
  readonly currency: string;
}

/**
 * Reads accounts and transactions from a bank or an aggregator over `fetch`.
 * Versioned: a breaking change ships a new `apiVersion`. better-supabase
 * bundles no feed; a provider package implements this port, and
 * `banking.syncFeed` imports what it returns.
 */
export interface BankFeed {
  readonly apiVersion: 1;
  /** The provider's name, such as `gocardless`. */
  readonly name: string;
  listAccounts(): AsyncResult<readonly BankFeedAccount[]>;
  /**
   * The booked transactions on or after `since`, each with a stable
   * `externalId`.
   */
  transactions(
    accountRef: string,
    since: BankDate,
  ): AsyncResult<readonly BankTransactionInput[]>;
}

/** Checks the feed's `apiVersion` before reading from it. */
export function bankFeedOf(feed: BankFeed): BankFeed {
  const version: unknown = feed.apiVersion;

  if (version !== 1) {
    throw new TypeError(
      `bank feed "${feed.name}" targets bank feed API ${String(version)}; this better-supabase supports 1. Upgrade better-supabase or use a release of the feed for API 1.`,
    );
  }

  return feed;
}
