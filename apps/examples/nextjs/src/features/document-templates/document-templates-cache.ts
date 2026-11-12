import { tagFor } from "better-supabase/next";

/** Every read of document templates carries this tag; its actions expire it. */
export const DOCUMENT_TEMPLATES_TAG = tagFor("documentTemplates");
