import { Suspense } from "react";

import type { RecordSubject } from "@/features/records/record-subject";

import { RecordConversations } from "@/features/records/components/record-conversations";
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
import {
  RecordApprovals,
  RecordFields,
  RecordReminders,
  RecordTags,
} from "@/features/records/components/record-side-sections";
import { RecordTasks } from "@/features/records/components/record-tasks";
import { RecordWorkflows } from "@/features/records/components/record-workflows";

import { AfterNavigation } from "./after-navigation";
import { RecordSectionSkeleton } from "./record-section-states";

export type BoundSection =
  | "approvals"
  | "conversations"
  | "discussion"
  | "fields"
  | "files"
  | "history"
  | "relations"
  | "reminders"
  | "tags"
  | "tasks"
  | "workflows";

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

          case "approvals": {
            return (
              <Suspense key={section} fallback={<RecordSectionSkeleton />}>
                <AfterNavigation>
                  <RecordApprovals subject={subject} />
                </AfterNavigation>
              </Suspense>
            );
          }

          case "fields": {
            return (
              <Suspense key={section} fallback={<RecordSectionSkeleton />}>
                <AfterNavigation>
                  <RecordFields subject={subject} />
                </AfterNavigation>
              </Suspense>
            );
          }

          case "reminders": {
            return (
              <Suspense key={section} fallback={<RecordSectionSkeleton />}>
                <AfterNavigation>
                  <RecordReminders subject={subject} />
                </AfterNavigation>
              </Suspense>
            );
          }

          case "tags": {
            return (
              <Suspense key={section} fallback={<RecordSectionSkeleton />}>
                <AfterNavigation>
                  <RecordTags subject={subject} />
                </AfterNavigation>
              </Suspense>
            );
          }

          case "conversations": {
            return (
              <Suspense key={section} fallback={<RecordSectionSkeleton />}>
                <AfterNavigation>
                  <RecordConversations subject={subject} />
                </AfterNavigation>
              </Suspense>
            );
          }

          case "tasks": {
            return (
              <Suspense key={section} fallback={<RecordSectionSkeleton />}>
                <AfterNavigation>
                  <RecordTasks subject={subject} />
                </AfterNavigation>
              </Suspense>
            );
          }

          case "workflows": {
            return (
              <Suspense key={section} fallback={<RecordSectionSkeleton />}>
                <AfterNavigation>
                  <RecordWorkflows subject={subject} />
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
