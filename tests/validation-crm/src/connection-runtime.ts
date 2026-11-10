// Importing the client entry installs the connection runtime.
import { bindClient } from "better-supabase/client";

export const installed = bindClient;
