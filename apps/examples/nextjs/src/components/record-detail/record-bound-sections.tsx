import { Suspense } from "react";

import type { RecordSubject } from "@/features/records/record-subject";

import {
  RecordDiscussion,
  RecordDiscussionSkeleton,
  RecordFiles,
  RecordFilesSkeleton,
  RecordHistory,
  RecordHistorySkeleton,
  RecordRelations,
  RecordRelationsSkeleton,
} from "@/features/records/components/record-sections";

import { AfterNavigation } from "./after-navigation";

export type BoundSection = "discussion" | "files" | "history" | "relations";

/**
 * The sections every record binds through `bsbCore.record`: each one reads its
 * own payload behind its own `<Suspense>`, after the navigation, and renders
 * nothing when the caller's keys hide it. Pick the ones a tab shows.
 */
export function RecordBoundSections({
  subject,
  sections,
}: {
  subject: RecordSubject;
  sections: readonly BoundSection[];
}) {
  return (
    <>
      {sections.map((section) => {
        switch (section) {
          case "discussion": {
            return (
              <Suspense key={section} fallback={<RecordDiscussionSkeleton />}>
                <AfterNavigation>
                  <RecordDiscussion subject={subject} />
                </AfterNavigation>
              </Suspense>
            );
          }

          case "files": {
            return (
              <Suspense key={section} fallback={<RecordFilesSkeleton />}>
                <AfterNavigation>
                  <RecordFiles subject={subject} />
                </AfterNavigation>
              </Suspense>
            );
          }

          case "history": {
            return (
              <Suspense key={section} fallback={<RecordHistorySkeleton />}>
                <AfterNavigation>
                  <RecordHistory subject={subject} />
                </AfterNavigation>
              </Suspense>
            );
          }

          case "relations": {
            return (
              <Suspense key={section} fallback={<RecordRelationsSkeleton />}>
                <AfterNavigation>
                  <RecordRelations subject={subject} />
                </AfterNavigation>
              </Suspense>
            );
          }

          default: {
            const unreachable: never = section;

            return unreachable;
          }
        }
      })}
    </>
  );
}
