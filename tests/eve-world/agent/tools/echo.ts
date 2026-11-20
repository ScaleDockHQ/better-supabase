import { defineTool } from "eve/tools";
import { z } from "zod";

export default defineTool({
  description: "Echo a word back.",
  inputSchema: z.object({ word: z.string() }),
  execute: ({ word }) => ({ echoed: word }),
});
