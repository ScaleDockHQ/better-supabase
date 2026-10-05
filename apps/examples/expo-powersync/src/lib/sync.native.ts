import { useEffect } from "react";

import { powersync, startSync } from "./powersync/database";

/** Opens the device database and syncs while the app runs. */
export function useSync(): void {
  useEffect(() => {
    void startSync();
    return () => {
      void powersync.disconnect();
    };
  }, []);
}
