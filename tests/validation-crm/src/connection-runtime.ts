// Importing the server entry installs the full connection runtime ($many, $stats and the rest).
import { createServer } from "better-supabase/server";

export const installed = createServer;
