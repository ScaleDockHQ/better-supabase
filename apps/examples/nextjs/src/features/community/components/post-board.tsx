import type { PostModeration, PostStatus } from "better-supabase/blocks/posts";

import {
  LockIcon,
  MessageSquareIcon,
  MessageSquareTextIcon,
  PinIcon,
  TriangleAlertIcon,
} from "lucide-react";
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
import { Card, CardContent } from "@/components/ui/card";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Skeleton } from "@/components/ui/skeleton";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { Link } from "@/i18n/navigation";

import { getBoard } from "../posts-queries";
import { CreateBoardButton, NewPostDialog, VoteButton } from "./post-controls";

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

// #region recipe:post-board
const statusVariants = {
  open: "outline",
  under_review: "info-light",
  planned: "primary-light",
  in_progress: "warning-light",
  done: "success-light",
  closed: "secondary",
} as const satisfies Record<PostStatus, string>;

const moderationVariants = {
  visible: null,
  pending: "warning-light",
  hidden: "destructive-light",
  removed: "destructive-light",
} as const satisfies Record<PostModeration, string | null>;

/** Render inside `<Suspense>`: the board's posts, top voted first. */
export async function PostBoard() {
  const [view, t, permissions] = await Promise.all([
    getBoard(),
    getExtracted("community"),
    getPermissions(),
  ]);

  if (view.kind === "no-organization") {
    return null;
  }

  if (view.kind === "error") {
    return (
      <Alert variant="destructive">
        <TriangleAlertIcon />
        <AlertTitle>{t("The board didn't load")}</AlertTitle>
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

  const board = view.data;

  if (board === null) {
    const manage = can(permissions, "posts.manage");

    return (
      <Empty className="border">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <MessageSquareTextIcon />
          </EmptyMedia>
          <EmptyTitle>{t("No board yet")}</EmptyTitle>
          <EmptyDescription>
            {manage
              ? t("Open a feedback board where members post and vote on ideas.")
              : t("An admin opens the board your team posts on.")}
          </EmptyDescription>
        </EmptyHeader>
        <EmptyContent>
          {manage ? (
            <CreateBoardButton />
          ) : (
            <Link href="/" className={buttonVariants({ variant: "outline" })}>
              {t("Back to the dashboard")}
            </Link>
          )}
        </EmptyContent>
      </Empty>
    );
  }

  const write = can(permissions, "posts.write");

  const statusLabels: Record<PostStatus, string> = {
    open: t("Open"),
    under_review: t("Under review"),
    planned: t("Planned"),
    in_progress: t("In progress"),
    done: t("Done"),
    closed: t("Closed"),
  };

  const moderationLabels: Record<PostModeration, string> = {
    visible: t("Visible"),
    pending: t("Awaiting review"),
    hidden: t("Hidden"),
    removed: t("Removed"),
  };

  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-center justify-between gap-2">
        <h2 className="text-sm font-medium">{board.name}</h2>
        {write ? <NewPostDialog boardId={board.id} /> : null}
      </div>
      {board.posts.length === 0 ? (
        <Empty className="border">
          <EmptyHeader>
            <EmptyMedia variant="icon">
              <MessageSquareIcon />
            </EmptyMedia>
            <EmptyTitle>{t("No posts yet")}</EmptyTitle>
            <EmptyDescription>
              {t("Post the first idea for others to vote on.")}
            </EmptyDescription>
          </EmptyHeader>
          {write ? (
            <EmptyContent>
              <NewPostDialog boardId={board.id} />
            </EmptyContent>
          ) : null}
        </Empty>
      ) : (
        <ul className="flex flex-col gap-3">
          {board.posts.map((post) => {
            const moderation = moderationVariants[post.moderation];

            return (
              <li key={post.id}>
                <Card size="sm">
                  <CardContent className="flex items-start gap-3">
                    <VoteButton
                      postId={post.id}
                      score={post.score}
                      voted={post.vote > 0}
                      disabled={post.moderation !== "visible"}
                    />
                    <div className="flex min-w-0 flex-1 flex-col gap-1">
                      <div className="flex flex-wrap items-center gap-2">
                        {post.pinned ? (
                          <PinIcon
                            aria-label={t("Pinned")}
                            className="size-4 text-muted-foreground"
                          />
                        ) : null}
                        <span className="text-sm font-medium">
                          {post.title}
                        </span>
                        <Badge variant={statusVariants[post.status]}>
                          {statusLabels[post.status]}
                        </Badge>
                        {moderation === null ? null : (
                          <Badge variant={moderation}>
                            {moderationLabels[post.moderation]}
                          </Badge>
                        )}
                      </div>
                      {post.body ? (
                        <p className="line-clamp-2 text-sm text-muted-foreground">
                          {post.body}
                        </p>
                      ) : null}
                      <div className="flex items-center gap-3 text-xs text-muted-foreground tabular-nums">
                        <span className="flex items-center gap-1">
                          <MessageSquareIcon aria-hidden className="size-3.5" />
                          {t("{count} replies", {
                            count: String(post.replyCount),
                          })}
                        </span>
                        {post.locked ? (
                          <span className="flex items-center gap-1">
                            <LockIcon aria-hidden className="size-3.5" />
                            {t("Locked")}
                          </span>
                        ) : null}
                      </div>
                    </div>
                  </CardContent>
                </Card>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
// #endregion recipe:post-board

export function PostBoardSkeleton() {
  return <Skeleton className="h-48 rounded-xl" aria-busy="true" />;
}
