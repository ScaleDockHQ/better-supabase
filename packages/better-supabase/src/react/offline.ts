import type { Context } from "react";

import { createContext } from "react";

/**
 * Whether the app is offline, for the data hooks and `RecordProvider` (ADR
 * 0420).
 */
export const OfflineContext: Context<boolean> = createContext(false);
