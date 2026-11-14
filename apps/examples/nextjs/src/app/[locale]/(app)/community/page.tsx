import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  PostBoard,
  PostBoardSkeleton,
} from "@/features/community/components/post-board";
import { PermissionGate } from "@/features/user/components/permission-gate";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function CommunityPage() {
  const t = useExtracted("community");

  return (
    <>
      <PageHeader
        title={t("Community")}
        description={t(
          "Post ideas and questions, and vote on the ones you want.",
        )}
      />
      <Suspense fallback={<PostBoardSkeleton />}>
        <PermissionGate permission="posts.read">
          <PostBoard />
        </PermissionGate>
      </Suspense>
    </>
  );
}
