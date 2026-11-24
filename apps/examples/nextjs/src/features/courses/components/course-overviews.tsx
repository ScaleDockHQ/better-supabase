import type { Course } from "better-supabase/blocks/courses";

import {
  BookOpenCheckIcon,
  FileTextIcon,
  GraduationCapIcon,
  ArchiveIcon,
} from "lucide-react";
import { getExtracted } from "next-intl/server";

import type { RecordListUrlQuery } from "@/components/record-list/record-list-types";

import { KpiBand } from "@/components/record-list/kpi-band";
import { PeopleLoadError } from "@/features/people/components/people-load-error";
import { BlockOverview } from "@/features/sales/components/block-overview";
import { requirePermission } from "@/features/sales/components/overview-support";

import { getCourses } from "../courses-queries";

/** The figures above the course views. */
// skeleton: the page's Suspense fallback is KpiBandSkeleton
export async function CourseKpis() {
  await requirePermission("courses.read");

  const [t, courses] = await Promise.all([
    getExtracted("courses"),
    getCourses(),
  ]);

  if (courses.kind === "no-organization") {
    return null;
  }

  if (courses.kind === "error") {
    return <PeopleLoadError title={t("The courses didn't load")} />;
  }

  const count = (status: string) =>
    courses.data.filter((course) => course.status === status).length;

  return (
    <KpiBand
      kpis={[
        {
          label: t("Courses"),
          value: String(courses.data.length),
          icon: <GraduationCapIcon className="size-4" />,
        },
        {
          label: t("Published"),
          hint: t("Open for enrollment"),
          value: String(count("published")),
          icon: <BookOpenCheckIcon className="size-4" />,
        },
        {
          label: t("Drafts"),
          hint: t("Not published yet"),
          value: String(count("draft")),
          icon: <FileTextIcon className="size-4" />,
        },
        {
          label: t("Archived"),
          value: String(count("archived")),
          icon: <ArchiveIcon className="size-4" />,
        },
      ]}
    />
  );
}

/** Every course the caller reads as a table. */
// skeleton: the page's Suspense fallback is the skeleton of this view
export async function CourseTable({ query }: { query: RecordListUrlQuery }) {
  await requirePermission("courses.read");

  const t = await getExtracted("courses");

  return (
    <BlockOverview<Course>
      pager={({ db }) => ({
        page: (options) => db.courses.page(options),
        facets: (options) => db.courses.facets(options),
      })}
      map={{ sorts: { title: { by: "title" } } }}
      query={query}
      toRow={(course) => ({
        id: course.id,
        title: course.title,
        summary: course.summary ?? null,
        status: course.status,
      })}
      columns={[
        {
          key: "title",
          header: t("Course"),
          kind: "link",
          href: "/courses/{id}",
          size: 260,
        },
        { key: "summary", header: t("Summary"), kind: "muted", size: 320 },
        {
          key: "status",
          header: t("Status"),
          kind: "badge",
          size: 120,
          labels: {
            draft: t("Draft"),
            published: t("Published"),
            archived: t("Archived"),
          },
          tones: {
            draft: "secondary",
            published: "success-light",
            archived: "secondary",
          },
        },
      ]}
      sorts={[{ value: "title", label: t("Course") }]}
      errorTitle={t("The courses didn't load")}
      emptyIcon={<GraduationCapIcon />}
      emptyTitle={t("No courses yet")}
      emptyDescription={t("Published courses appear here.")}
    />
  );
}
