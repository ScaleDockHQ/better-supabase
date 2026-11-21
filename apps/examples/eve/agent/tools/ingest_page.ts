import { toStandardJsonSchema } from "@valibot/to-json-schema";
import { approvalPolicy, supabaseTool } from "better-supabase/eve";
import { defineTool } from "eve/tools";
import * as v from "valibot";

import { urlSource } from "../lib/blocks";
import { bsb } from "../lib/server";

// The page is fetched by the server with the source's host and size guards, so
// a member has to approve each call, like `add_note`.
export default defineTool(
  supabaseTool({
    server: bsb,
    agent: "assistant",
    description: "Reads a documentation page into the organization's knowledge",
    inputSchema: toStandardJsonSchema(
      v.object({ url: v.pipe(v.string(), v.url()) }),
    ),
    approval: approvalPolicy({ server: bsb, agent: "assistant" }),
    async execute({ url }, { context }) {
      const document = await urlSource
        .ingest({ organizationId: context.tenant ?? null, url })
        .orThrow();

      return { id: document.id, title: document.title };
    },
  }),
);
