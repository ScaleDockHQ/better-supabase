import "server-only";
import type {
  AdminListRaw,
  AdminListSource,
} from "@/features/admin-lists/admin-list-sql";

import type { FlagRow } from "./flags-list";

interface FlagRaw extends AdminListRaw {
  readonly key: string;
  readonly description: string | null;
  readonly default_variant: string;
  readonly rollout_percentage: string | null;
  readonly state: string;
  readonly created_at: string;
}

/**
 * Flags: the rows the page reads as the database owner after its permission
 * check.
 */
export const flagSource: AdminListSource<FlagRaw, FlagRow> = {
  from: "better_supabase.flags f",
  idColumn: "f.key",
  idType: "text",
  timeColumn: "f.created_at",
  scope: "$1::text <> ''",
  search: ["f.key", "f.description"],
  facetSql: {
    state:
      "case when f.archived then 'archived' when f.enabled then 'on' else 'off' end",
  },
  select: `f.key, f.description, f.default_variant, f.rollout_percentage::text as rollout_percentage,
    case when f.archived then 'archived' when f.enabled then 'on' else 'off' end as state,
    f.created_at::text as created_at`,
  map: (raw) => ({
    id: raw.id,
    key: raw.key,
    description: raw.description,
    defaultVariant: raw.default_variant,
    rollout:
      raw.rollout_percentage === null ? null : Number(raw.rollout_percentage),
    state:
      raw.state === "archived" ? "archived" : raw.state === "on" ? "on" : "off",
    createdAt: raw.created_at,
  }),
};
