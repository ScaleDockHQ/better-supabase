"use server";

import * as v from "valibot";

import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

/** Creates an invoice template with a plain body, to start from. */
export const addStarterTemplate = bsb.blockAction(
  ({ db }) => db.documentTemplates,
  "saveTemplate",
  {
    input: v.object({}),
    requireTenant: true,
    permission: "document_templates.manage",
    tags: () => [tags.documentTemplates()],
    refresh: true,
    args: (_) => [
      {
        documentType: "invoice",
        name: "standard",
        language: "en",
        body: "<h1>Invoice</h1>",
      },
    ],
  },
  (saved) => ({ id: saved.id }),
);

/** Takes a template out of the fallback chain, or puts it back. */
export const setTemplateActive = bsb.blockAction(
  ({ db }) => db.documentTemplates,
  "setTemplateActive",
  {
    input: v.object({ id: v.pipe(v.string(), v.uuid()), active: v.boolean() }),
    requireTenant: true,
    permission: "document_templates.manage",
    tags: () => [tags.documentTemplates()],
    refresh: true,
  },
  (updated) => ({ active: updated.active }),
);
