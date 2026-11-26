import "server-only";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import { readMembers } from "@/features/organization/organization-queries";
import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

export interface LearnerRow {
  readonly userId: string;
  readonly name: string;
  readonly status: string;
  readonly completed: number;
  readonly total: number;
  readonly enrolledAt: string;
}

export interface CourseLearnersData {
  readonly learners: readonly LearnerRow[];
  /** Members who are not enrolled yet. */
  readonly candidates: readonly {
    readonly value: string;
    readonly label: string;
  }[];
}

/** The course's learners with their names, and the members who could join. */
export async function getCourseLearners(
  courseId: string,
): Promise<CourseLearnersData | null> {
  "use cache: private";
  const scope = await bsb.cached();
  const { session, db } = scope;
  cacheTag(tags.courses());
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const [learners, members] = await Promise.all([
    db.courses.learners({ courseId }).orThrow(),
    readMembers(scope, tenant),
  ]);

  const names = new Map(
    members.map((member) => [
      member.userId,
      member.name ?? member.email ?? member.userId,
    ]),
  );

  const active = learners.filter((learner) => learner.status !== "cancelled");
  const enrolled = new Set(active.map((learner) => learner.userId));

  return {
    learners: learners.map((learner) => ({
      userId: learner.userId,
      name: names.get(learner.userId) ?? learner.userId,
      status: learner.status,
      completed: learner.completedLessons,
      total: learner.totalLessons,
      enrolledAt: learner.enrolledAt.toString(),
    })),
    candidates: members
      .filter((member) => !enrolled.has(member.userId))
      .map((member) => ({
        value: member.userId,
        label: member.name ?? member.email ?? member.userId,
      })),
  };
}
