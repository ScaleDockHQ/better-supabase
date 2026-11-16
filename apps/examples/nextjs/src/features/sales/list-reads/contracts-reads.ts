import type { Money } from "better-supabase/commerce";
import type { EntityListReads } from "better-supabase/list";

import { moneyToJson } from "better-supabase/commerce";

import type { AppDb, EntityListMap } from "@/lib/block-entity-page";

import { blockEntityReads, organizationPager } from "@/lib/block-entity-page";

import type { ContractRow } from "../revenue/revenue-queries";

/** The contracts list's sorts on the contracts block's. */
const contractSorts: EntityListMap["sorts"] = {
  ending: { by: "endsOn" },
  starting: { by: "startsOn" },
  // The block has no notice sort, so the notice sort of the entity page is the end date.
  notice: { by: "endsOn" },
  title: { by: "title" },
};

/** The contracts overview's URL names on the contracts block's page. */
export const contractsMap: EntityListMap = {
  sorts: contractSorts,
  filters: { f: "status" },
  facets: { f: "status" },
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

/** The contracts block's `page` and `facets` for an organization. */
export function contractsPager(db: AppDb, organizationId: string) {
  return organizationPager(organizationId, {
    page: (options) => db.contracts.page(options),
    facets: (options) => db.contracts.facets(options),
  });
}

/** The contract row with its value as JSON, which has no bigint. */
export type ContractWire = Omit<ContractRow, "value"> & {
  readonly value: ReturnType<typeof moneyToJson> | null;
};

/** The reads module of the `app.contracts` entity page (ADR 0894). */
export function contractsReads(db: AppDb): EntityListReads<ContractWire> {
  return blockEntityReads({
    pager: (organizationId) => contractsPager(db, organizationId),
    map: { sorts: contractSorts },
    wire: (contract) => {
      const row = contractOf(contract);

      return { ...row, value: row.value ? moneyToJson(row.value) : null };
    },
  });
}
