"use client";

import dynamic from "next/dynamic";

import { Skeleton } from "@/components/ui/skeleton";

/**
 * The invitations grid in a chunk of its own: the data grid is about 150 KB raw
 * of first load that the page needs only to paint rows, and the server renders
 * the rows in the HTML either way.
 */
export const InvitationsGridLazy = dynamic(
  () => import("./invitations-grid").then((mod) => mod.InvitationsGrid),
  { loading: () => <Skeleton className="h-24" /> },
);
