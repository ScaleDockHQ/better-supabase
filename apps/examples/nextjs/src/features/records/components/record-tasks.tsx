import { getExtracted } from "next-intl/server";

import { Badge } from "@/components/reui/badge";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { Link } from "@/i18n/navigation";

import type { RecordSubject } from "../record-subject";

import { getRecordTasks } from "../records-queries";

/**
 * Render inside `<Suspense>`: the tasks linked to a record, with their status
 * and due date, each linking to the work screen. Renders nothing without
 * `tasks.read`.
 */
// skeleton: RecordSectionSkeleton in the record detail kit, rendered by the caller
export async function RecordTasks({ subject }: { subject: RecordSubject }) {
  const [t, permissions] = await Promise.all([
    getExtracted("records"),
    getPermissions(),
  ]);

  if (!can(permissions, "tasks.read")) {
    return null;
  }

  const tasks = await getRecordTasks(subject);

  return (
    <Card size="sm" id="tasks">
      <CardHeader>
        <CardTitle>{t("Tasks")}</CardTitle>
        <CardDescription>{t("Work linked to this record.")}</CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-2">
        {tasks.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            {t("No task is linked to this record.")}
          </p>
        ) : (
          tasks.map((task) => (
            <Link
              key={task.id}
              href="/work"
              className="flex items-center gap-2 text-sm hover:underline"
            >
              <span className="min-w-0 flex-1 truncate">{task.title}</span>
              {task.dueOn === null ? null : (
                <span className="text-xs text-muted-foreground">
                  {task.dueOn}
                </span>
              )}
              <Badge
                variant={task.status === "done" ? "success-light" : "secondary"}
              >
                {task.status}
              </Badge>
            </Link>
          ))
        )}
      </CardContent>
    </Card>
  );
}
