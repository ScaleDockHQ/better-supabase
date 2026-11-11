import "server-only";
import type {
  AdminListRaw,
  AdminListSource,
} from "@/features/admin-lists/admin-list-sql";

import type { SearchDocumentRow } from "./search-settings-list";

interface SearchDocumentRaw extends AdminListRaw {
  readonly title: string;
  readonly subject_type: string;
  readonly url: string | null;
  readonly updated_at: string;
}

/** Search index: the rows RLS lets the caller read. */
export const searchDocumentSource: AdminListSource<
  SearchDocumentRaw,
  SearchDocumentRow
> = {
  from: "better_supabase.search_documents d",
  idColumn: "(d.subject_type || ':' || d.subject_id)",
  idType: "text",
  timeColumn: "d.updated_at",
  scope: "d.tenant_id = $1",
  search: ["d.title"],
  facetSql: { type: "d.subject_type" },
  select: `d.title, d.subject_type, d.url, d.updated_at::text as updated_at`,
  map: (raw) => ({
    id: raw.id,
    title: raw.title,
    subjectType: raw.subject_type,
    url: raw.url,
    updatedAt: raw.updated_at,
  }),
};
