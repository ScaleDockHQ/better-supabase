import { formatMoney, money } from "better-supabase/commerce";
import { tenantOf } from "better-supabase/next";
import { getExtracted, getFormatter, getLocale } from "next-intl/server";
import { notFound } from "next/navigation";

import { Badge } from "@/components/reui/badge";
import {
  Card,
  CardAction,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { CommentThread } from "@/features/customers/components/comment-thread";
import { TagInput } from "@/features/customers/components/tag-input";
import { can } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";
import { Link } from "@/i18n/navigation";

import {
  getMemberOptions,
  getProject,
  getProjectHistory,
  getTasks,
  settle,
} from "../project-queries";
import { PROJECT_SUBJECT } from "../project-types";
import { ProjectHistory } from "./project-history";
import { ProjectLoadError } from "./project-load-error";
import { TaskFormDialog } from "./task-form-dialog";
import { TaskImportAction } from "./task-import-action";
import { TaskStatusBadge } from "./task-status-badge";

// #region recipe:record-page
/**
 * Render inside `<Suspense>`: one project as a record page. Its fields, its
 * tasks through the `project_id` reference, and the comments and tags that
 * reach it because `projects` is a subject.
 */
export async function ProjectPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const [{ id }, session] = await Promise.all([params, getSession()]);
  const organizationId = tenantOf(session);

  if (!organizationId) {
    notFound();
  }

  const [project, tasks, members, history, t, format, locale] =
    await Promise.all([
      settle(() => getProject(id)),
      settle(() => getTasks({ q: "", status: null, projectId: id })),
      settle(() => getMemberOptions(organizationId)),
      settle(() => getProjectHistory(id)),
      getExtracted("projects"),
      getFormatter(),
      getLocale(),
    ]);

  if (project.kind !== "ok" || tasks.kind !== "ok" || members.kind !== "ok") {
    return <ProjectLoadError title={t("The project didn't load")} />;
  }

  const record = project.data;

  if (record === undefined) {
    notFound();
  }

  const nameOf = (userId: string | null) =>
    userId === null
      ? t("Unassigned")
      : (members.data.find((member) => member.userId === userId)?.name ??
        userId);

  const subject = { type: PROJECT_SUBJECT, id: record.id };

  return (
    <div className="grid items-start gap-6 lg:grid-cols-3">
      <div className="flex flex-col gap-6 lg:col-span-2">
        <div className="flex flex-col gap-1">
          <h1 className="text-2xl font-semibold tracking-tight">
            {record.name}
          </h1>
          <p className="text-sm text-muted-foreground">
            {t("Created {date}", {
              date: format.dateTime(new Date(record.createdAt), {
                dateStyle: "long",
              }),
            })}
          </p>
        </div>

        <Card>
          <CardHeader>
            <CardTitle>{t("Tasks")}</CardTitle>
            <CardDescription>
              {t("{count, plural, one {# task} other {# tasks}}", {
                count: tasks.data.length,
              })}
            </CardDescription>
            <CardAction className="flex items-center gap-2">
              <TaskImportAction projectId={record.id} />
              <TaskFormDialog
                projects={[{ id: record.id, name: record.name }]}
                members={members.data}
                defaultProjectId={record.id}
              />
            </CardAction>
          </CardHeader>
          <CardContent>
            {tasks.data.length === 0 ? (
              <p className="text-sm text-muted-foreground">
                {t("No tasks yet. Add the first one with New task.")}
              </p>
            ) : (
              <ul className="flex flex-col divide-y">
                {tasks.data.map((task) => (
                  <li
                    key={task.id}
                    className="flex items-center justify-between gap-3 py-2"
                  >
                    <div className="flex min-w-0 flex-col">
                      <span className="truncate text-sm font-medium">
                        {task.title}
                      </span>
                      <span className="text-xs text-muted-foreground">
                        {nameOf(task.assigneeId)}
                        {task.dueOn
                          ? ` · ${t("due {date}", {
                              date: format.dateTime(
                                new Date(`${task.dueOn}T00:00:00Z`),
                                { dateStyle: "medium", timeZone: "UTC" },
                              ),
                            })}`
                          : null}
                      </span>
                    </div>
                    <TaskStatusBadge status={task.status} />
                  </li>
                ))}
              </ul>
            )}
          </CardContent>
        </Card>

        <Card data-recipe="comment-thread">
          <CardHeader>
            <CardTitle>{t("Comments")}</CardTitle>
          </CardHeader>
          <CardContent>
            <CommentThread
              subject={subject}
              authors={Object.fromEntries(
                members.data.map((member) => [member.userId, member.name]),
              )}
              canComment={can(session, "messages.send")}
            />
          </CardContent>
        </Card>
      </div>

      <div className="flex flex-col gap-6">
        <Card size="sm">
          <CardHeader>
            <CardTitle>{t("Details")}</CardTitle>
          </CardHeader>
          <CardContent>
            <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-2 text-sm">
              <dt className="text-muted-foreground">{t("Budget")}</dt>
              <dd>
                {formatMoney(
                  money(record.budgetMinor, record.currency),
                  locale,
                )}
              </dd>
              <dt className="text-muted-foreground">{t("Lead")}</dt>
              <dd>{nameOf(record.leadId)}</dd>
              <dt className="text-muted-foreground">{t("Open tasks")}</dt>
              <dd>
                <Badge variant="outline">
                  {tasks.data.filter((task) => task.status !== "done").length}
                </Badge>
              </dd>
            </dl>
          </CardContent>
        </Card>
        {history.kind === "ok" ? (
          <ProjectHistory
            projectId={record.id}
            versions={history.data}
            canSave={can(session, "versions.create")}
            canRestore={can(session, "versions.restore")}
          />
        ) : (
          <ProjectLoadError title={t("The history didn't load")} />
        )}
        <Card size="sm" data-recipe="tag-input">
          <CardHeader>
            <CardTitle>{t("Tags")}</CardTitle>
          </CardHeader>
          <CardContent>
            <TagInput subject={subject} />
          </CardContent>
        </Card>
        <Link
          href={`/projects?view=board&project=${record.id}`}
          className="text-sm text-muted-foreground transition-colors hover:text-foreground"
        >
          {t("Open this project's board")}
        </Link>
      </div>
    </div>
  );
}
// #endregion recipe:record-page

export function ProjectPageSkeleton() {
  return (
    <div className="grid items-start gap-6 lg:grid-cols-3" aria-busy="true">
      <div className="flex flex-col gap-6 lg:col-span-2">
        <Skeleton className="h-8 w-56" />
        <Skeleton className="h-72 rounded-xl" />
        <Skeleton className="h-48 rounded-xl" />
      </div>
      <div className="flex flex-col gap-6">
        <Skeleton className="h-32 rounded-xl" />
        <Skeleton className="h-48 rounded-xl" />
        <Skeleton className="h-32 rounded-xl" />
      </div>
    </div>
  );
}
