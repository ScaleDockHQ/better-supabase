import type { CourseStatus } from "better-supabase/blocks/courses";

import { PresentationIcon, TriangleAlertIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";
import { refresh } from "next/cache";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Badge } from "@/components/reui/badge";
import { Button, buttonVariants } from "@/components/ui/button";
import {
  Card,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Skeleton } from "@/components/ui/skeleton";
import { can } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";
import { Link } from "@/i18n/navigation";

import { getCourses } from "../courses-queries";
import { SampleCourseButton } from "./course-controls";

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

const statusVariants = {
  draft: "secondary",
  published: "success-light",
  archived: "outline",
} as const satisfies Record<CourseStatus, string>;

/** Render inside `<Suspense>`: the courses the caller can take. */
export async function CourseList() {
  const [view, session, t] = await Promise.all([
    getCourses(),
    getSession(),
    getExtracted("courses"),
  ]);

  if (view.kind === "no-organization") {
    return null;
  }

  if (view.kind === "error") {
    return (
      <Alert variant="destructive">
        <TriangleAlertIcon />
        <AlertTitle>{t("The courses didn't load")}</AlertTitle>
        <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
        <AlertAction>
          <form action={retry}>
            <Button size="sm" variant="outline" type="submit">
              {t("Retry")}
            </Button>
          </form>
        </AlertAction>
      </Alert>
    );
  }

  if (view.data.length === 0) {
    return (
      <Empty className="border">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <PresentationIcon />
          </EmptyMedia>
          <EmptyTitle>{t("No courses yet")}</EmptyTitle>
          <EmptyDescription>
            {can(session, "courses.manage")
              ? t("Create a sample course to try the learner flow.")
              : t("An admin publishes courses for your team.")}
          </EmptyDescription>
        </EmptyHeader>
        <EmptyContent>
          {can(session, "courses.manage") ? (
            <SampleCourseButton />
          ) : (
            <Link href="/" className={buttonVariants({ variant: "outline" })}>
              {t("Back to the dashboard")}
            </Link>
          )}
        </EmptyContent>
      </Empty>
    );
  }

  const statusLabels: Record<CourseStatus, string> = {
    draft: t("Draft"),
    published: t("Published"),
    archived: t("Archived"),
  };

  return (
    <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
      {view.data.map((course) => (
        <Card key={course.id}>
          <CardHeader>
            <div className="flex items-center gap-2">
              <CardTitle>
                <Link
                  href={`/courses/${course.id}`}
                  className="transition-colors hover:text-primary"
                >
                  {course.title}
                </Link>
              </CardTitle>
              <Badge variant={statusVariants[course.status]}>
                {statusLabels[course.status]}
              </Badge>
            </div>
            {course.summary ? (
              <CardDescription>{course.summary}</CardDescription>
            ) : null}
          </CardHeader>
        </Card>
      ))}
    </div>
  );
}

export function CourseListSkeleton() {
  return <Skeleton className="h-32 rounded-xl" aria-busy="true" />;
}
