// #region recipe:can
"use client";

import { Can } from "@/hooks/use-permissions";
import { permissions } from "@/lib/supabase/blocks.generated";

import { TaskImportDialog } from "./task-import-dialog";

/**
 * The import button, for members with `imports.manage` in the active
 * organization. The `<Can>` checks of one render share one `my_permissions`
 * call; the import action checks the key again on the server.
 */
export function TaskImportAction({ projectId }: { projectId: string }) {
  return (
    <Can permission={permissions.imports.manage}>
      <TaskImportDialog projectId={projectId} />
    </Can>
  );
}
// #endregion recipe:can
