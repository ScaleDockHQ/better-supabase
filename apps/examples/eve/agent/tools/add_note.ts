import { approvalPolicy, supabaseTool } from "better-supabase/eve";
import { defineTool } from "eve/tools";
import * as v from "valibot";

import { bsb } from "../lib/server";

// The note is written as the member who asked, so the fixture's tenant policy
// on `public.notes` decides where it may go. The token carries the agent's
// `act` claim and no permission keys. Each call waits for a member to approve
// it in the approvals block, under
// `blocks.approvals.options.policies.eve_tool_call.add_note`.
export default defineTool(
  supabaseTool({
    server: bsb,
    agent: "assistant",
    description: "Adds a note to one of the organization's customers",
    inputSchema: v.object({
      customerId: v.pipe(v.string(), v.uuid()),
      body: v.pipe(v.string(), v.minLength(1), v.maxLength(4000)),
    }),
    approval: approvalPolicy({ server: bsb, agent: "assistant" }),
    async execute({ customerId, body }, { db, context }) {
      const note = await db.notes
        .create({ customerId, body, organizationId: context.tenant ?? "" })
        .orThrow();

      return { id: note.id };
    },
  }),
);
