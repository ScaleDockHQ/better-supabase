import "server-only";
import type { DocumentTemplate } from "better-supabase/blocks/document-templates";

import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import type {
  RecordListPage,
  RecordListUrlQuery,
} from "@/components/record-list/record-list-types";
import type { Loaded } from "@/features/people/people-queries";

import { settle } from "@/features/people/people-queries";
import { pageEntityRows } from "@/lib/block-entity-page";
import { bsb } from "@/lib/supabase/server";

import type { TemplateRow } from "./document-templates-list";

import { DOCUMENT_TEMPLATES_TAG } from "./document-templates-cache";
import { templateList, templateMap } from "./document-templates-list";

type Db = Awaited<ReturnType<typeof bsb.cached>>["db"];

function templateRowOf(template: DocumentTemplate): TemplateRow {
  return {
    id: template.id,
    name: template.name,
    documentType: template.documentType,
    language: template.language,
    version: template.version,
    active: template.active,
    updatedAt: template.updatedAt.toString(),
  };
}

/**
 * One page of templates for a list query, searched, filtered and sorted by the
 * document templates block's `templatePage` and counted by `templateFacets`.
 */
export function getTemplatePage(
  db: Db,
  query: RecordListUrlQuery,
): Promise<RecordListPage<TemplateRow>> {
  const { documentTemplates } = db;

  return pageEntityRows({
    pager: {
      page: (options) => documentTemplates.templatePage(options),
      facets: (options) => documentTemplates.templateFacets(options),
    },
    map: templateMap,
    query,
    pageSize: templateList.config.pageSize,
    rowsOf: (items) => items.map(templateRowOf),
  });
}

async function loadTemplates(): Promise<RecordListPage<TemplateRow> | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(DOCUMENT_TEMPLATES_TAG);

  return tenantOf(session) ? getTemplatePage(db, templateList.defaults) : null;
}

export function getTemplates(): Promise<Loaded<RecordListPage<TemplateRow>>> {
  return settle(loadTemplates);
}

export interface TemplateDetailData {
  readonly row: TemplateRow;
  readonly body: string;
}

async function loadTemplate(
  id: string,
): Promise<TemplateDetailData | "not-found" | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(DOCUMENT_TEMPLATES_TAG);

  if (!tenantOf(session)) {
    return null;
  }

  const found = await db.documentTemplates.getTemplate(id);

  if (!found.ok) {
    if (found.error.kind === "not_found") {
      return "not-found";
    }

    throw new Error(found.error.message);
  }

  return { row: templateRowOf(found.data), body: found.data.body };
}

export function getTemplate(
  id: string,
): Promise<Loaded<TemplateDetailData | "not-found">> {
  return settle(() => loadTemplate(id));
}
