import { defineTool } from "eve/tools";
import { always } from "eve/tools/approval";
import { z } from "zod";

export default defineTool({
  description: "Delete a record. Needs approval.",
  inputSchema: z.object({ id: z.string() }),
  approval: always(),
  execute: ({ id }) => ({ deleted: id }),
});
