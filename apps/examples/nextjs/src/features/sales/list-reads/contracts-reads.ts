import type { Money } from "better-supabase/commerce";
import type { EntityListReads } from "better-supabase/list";

import { moneyToJson } from "better-supabase/commerce";

import type { BlockListSpec } from "@/lib/array-list";
import type { AppDb } from "@/lib/array-reads";

import { arrayReads } from "@/lib/array-reads";
import { readAllPagesResult } from "@/lib/read-all-pages";

import type { ContractRow } from "../revenue/revenue-queries";

/** The search, sort and facet of the contracts list, shared with its overview. */
export const contractsSpec: BlockListSpec<ContractRow> = {
  search: (contract) => contract.title,
  facet: (contract) => contract.status,
  defaultSort: "ending",
  sorts: {
    ending: (a, b) => (a.endsOn ?? "9999").localeCompare(b.endsOn ?? "9999"),
    notice: (a, b) =>
      (a.noticeDeadline ?? "9999").localeCompare(b.noticeDeadline ?? "9999"),
    title: (a, b) => a.title.localeCompare(b.title),
  },
};

type ContractLike = {
  readonly id: string;
  readonly title: string;
  readonly status: string;
  readonly value?: Money | undefined;
  readonly startsOn?: { toString(): string } | undefined;
  readonly endsOn?: { toString(): string } | undefined;
  readonly noticeDeadline?: { toString(): string } | undefined;
  readonly autoRenew: boolean;
  readonly ownerId?: string | undefined;
  readonly counterparty?: { readonly id: string } | undefined;
};

/** The contract as the list shows it. */
export function contractOf(contract: ContractLike): ContractRow {
  return {
    id: contract.id,
    title: contract.title,
    status: contract.status,
    value: contract.value ?? null,
    startsOn: contract.startsOn?.toString() ?? null,
    endsOn: contract.endsOn?.toString() ?? null,
    noticeDeadline: contract.noticeDeadline?.toString() ?? null,
    autoRenew: contract.autoRenew,
    ownerId: contract.ownerId ?? null,
    counterpartyId: contract.counterparty?.id ?? null,
  };
}

/** The newest 200 contracts of the organization. */
export function contractsFrom(db: AppDb, tenant: string) {
  return readAllPagesResult((page) =>
    db.contracts.page({ organizationId: tenant, ...page }),
  ).map((contracts) => contracts.map(contractOf));
}

/** The contract row with its value as JSON, which has no bigint. */
export type ContractWire = Omit<ContractRow, "value"> & {
  readonly value: ReturnType<typeof moneyToJson> | null;
};

/** The reads module of the `app.contracts` entity page (ADR 0894). */
export function contractsReads(db: AppDb): EntityListReads<ContractWire> {
  return arrayReads({
    load: (tenant) => contractsFrom(db, tenant),
    facet: "status",
    spec: contractsSpec,
    wire: (contract) => ({
      ...contract,
      value: contract.value ? moneyToJson(contract.value) : null,
    }),
  });
}
