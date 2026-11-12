import "server-only";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import type { Loaded } from "@/features/people/people-queries";

import { settle } from "@/features/people/people-queries";
import { bsb } from "@/lib/supabase/server";

import type { TemplateRow } from "./document-templates-list";

import { DOCUMENT_TEMPLATES_TAG } from "./document-templates-cache";

type Db = Awaited<ReturnType<typeof bsb.cached>>["db"];

/** Every template of the organization; the list kit pages them (EX-901). */
export async function readTemplateRows(
  db: Db,
): Promise<readonly TemplateRow[]> {
  const templates = await db.documentTemplates.listTemplates().orThrow();

  return templates.map((template): TemplateRow => ({
    id: template.id,
    name: template.name,
    documentType: template.documentType,
    language: template.language,
    version: template.version,
    active: template.active,
    updatedAt: template.updatedAt.toString(),
  }));
}

async function loadTemplates(): Promise<readonly TemplateRow[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(DOCUMENT_TEMPLATES_TAG);

  return tenantOf(session) ? readTemplateRows(db) : null;
}

export function getTemplates(): Promise<Loaded<readonly TemplateRow[]>> {
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

  const rows = await readTemplateRows(db);
  const row = rows.find((entry) => entry.id === id);

  if (!row) {
    return "not-found";
  }

  const template = await db.documentTemplates.getTemplate(id).orThrow();

  return { row, body: template.body };
}

export function getTemplate(
  id: string,
): Promise<Loaded<TemplateDetailData | "not-found">> {
  return settle(() => loadTemplate(id));
}
