import "server-only";
import { tenantOf } from "better-supabase/next";

import { bsb } from "@/lib/supabase/server";

/** A legal entity as the list shows it, serializable. */
export interface LegalEntityRow {
  readonly id: string;
  readonly code: string;
  readonly name: string;
  readonly vatNumber: string | null;
  readonly defaultCurrency: string | null;
  readonly taxPeriod: "monthly" | "quarterly";
  readonly isDefault: boolean;
  readonly archived: boolean;
}

async function loadLegalEntities(): Promise<readonly LegalEntityRow[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();

  if (!tenantOf(session)) {
    return null;
  }

  const entities = await db.legalEntities
    .list({ includeArchived: true })
    .orThrow();

  return entities.map((entity) => ({
    id: entity.id,
    code: entity.code,
    name: entity.name,
    vatNumber: entity.vatNumber,
    defaultCurrency: entity.defaultCurrency,
    taxPeriod: entity.fiscal.taxPeriod,
    isDefault: entity.isDefault,
    archived: entity.archivedAt !== null,
  }));
}

/** The organization's legal entities, the default first. */
export function getLegalEntities(): Promise<readonly LegalEntityRow[] | null> {
  return loadLegalEntities();
}
