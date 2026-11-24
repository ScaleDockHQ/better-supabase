import { GraduationCapIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";

import { Badge } from "@/components/reui/badge";
import {
  Card,
  CardAction,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Skeleton } from "@/components/ui/skeleton";
import { assignCourse } from "@/features/composites/composites-actions";
import { PeopleLoadError } from "@/features/people/components/people-load-error";
import { settle } from "@/features/people/people-queries";
import { ActionDialog } from "@/features/sales/components/action-dialog";
import {
  dateFormatter,
  holds,
  requirePermission,
} from "@/features/sales/components/overview-support";

import { loadCourseLearners } from "../course-learners-queries";

export function CourseLearnersSkeleton() {
  return <Skeleton className="h-64 rounded-xl" aria-busy="true" />;
}

/** The enrollments of one course, with the action that assigns a member. */
export async function CourseLearners({ courseId }: { courseId: string }) {
  await requirePermission("courses.read");

  const [t, loaded, fmtDate, canAssign] = await Promise.all([
    getExtracted("courses"),
    settle(() => loadCourseLearners(courseId)),
    dateFormatter(),
    holds("courses.enroll"),
  ]);

  if (loaded.kind === "no-organization") {
    return null;
  }

  if (loaded.kind === "error") {
    return <PeopleLoadError title={t("The enrollments didn't load")} />;
  }

  const { learners, candidates } = loaded.data;

  const statuses = new Map([
    ["active", t("In progress")],
    ["completed", t("Completed")],
    ["cancelled", t("Cancelled")],
  ]);

  return (
    <Card>
      <CardHeader>
        <CardTitle>{t("Enrollments")}</CardTitle>
        <CardDescription>
          {t("Who takes this course and how far they are.")}
        </CardDescription>
        {canAssign && candidates.length > 0 ? (
          <CardAction>
            <ActionDialog
              action={assignCourse}
              title={t("Assign this course")}
              description={t("Enrolls a member and notifies them.")}
              trigger={t("Assign")}
              submitLabel={t("Assign")}
              successMessage={t("Course assigned")}
              hidden={{ courseId }}
              fields={[
                {
                  name: "userId",
                  label: t("Member"),
                  kind: "select",
                  required: true,
                  options: candidates,
                },
              ]}
            />
          </CardAction>
        ) : null}
      </CardHeader>
      <CardContent>
        {learners.length === 0 ? (
          <Empty className="border">
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <GraduationCapIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No learners yet")}</EmptyTitle>
              <EmptyDescription>
                {t("Assign the course to a member to start.")}
              </EmptyDescription>
            </EmptyHeader>
          </Empty>
        ) : (
          <ul className="flex flex-col gap-2 text-sm">
            {learners.map((learner) => (
              <li
                key={learner.userId}
                className="flex items-center justify-between gap-4"
              >
                <span>{learner.name}</span>
                <span className="flex items-center gap-2 text-muted-foreground">
                  <span className="tabular-nums">
                    {learner.completed} / {learner.total}
                  </span>
                  <span>{fmtDate(learner.enrolledAt)}</span>
                  <Badge
                    variant={
                      learner.status === "completed"
                        ? "success-light"
                        : learner.status === "active"
                          ? "info-light"
                          : "secondary"
                    }
                  >
                    {statuses.get(learner.status) ?? learner.status}
                  </Badge>
                </span>
              </li>
            ))}
          </ul>
        )}
      </CardContent>
    </Card>
  );
}
