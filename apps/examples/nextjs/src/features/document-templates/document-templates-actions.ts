"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { refreshCaller } from "@/lib/refresh-caller";
import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

/** Creates an invoice template with a plain body, to start from. */
export const addStarterTemplate = bsb.action(
  {
    input: v.object({}),
    requireTenant: true,
    permission: "document_templates.manage",
  },
  async (_input, { db, auth }) => {
    const saved = await db.documentTemplates.saveTemplate({
      documentType: "invoice",
      name: "standard",
      language: "en",
      body: "<h1>Invoice</h1>",
    });

    if (!saved.ok) {
      return saved;
    }

    await refreshCaller(auth, [tags.documentTemplates()]);

    return ok({ id: saved.data.id });
  },
);

/** Takes a template out of the fallback chain, or puts it back. */
export const setTemplateActive = bsb.action(
  {
    input: v.object({ id: v.pipe(v.string(), v.uuid()), active: v.boolean() }),
    requireTenant: true,
    permission: "document_templates.manage",
  },
  async (input, { db, auth }) => {
    const updated = await db.documentTemplates.setTemplateActive(input);

    if (!updated.ok) {
      return updated;
    }

    await refreshCaller(auth, [tags.documentTemplates()]);

    return ok({ active: updated.data.active });
  },
);
