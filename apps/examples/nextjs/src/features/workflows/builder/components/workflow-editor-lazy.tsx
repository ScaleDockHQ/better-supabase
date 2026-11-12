"use client";

import dynamic from "next/dynamic";

import type { BuilderDetail } from "../builder-queries";

import { BuilderEditorSkeleton } from "./builder-editor-skeleton";

// The canvas pulls in @xyflow/react, which only this route uses: it loads when
// the editor opens, and the skeleton holds the frame meanwhile.
const WorkflowEditor = dynamic(
  () => import("./workflow-editor").then((module) => module.WorkflowEditor),
  { ssr: false, loading: () => <BuilderEditorSkeleton /> },
);

export function WorkflowEditorLazy({ detail }: { detail: BuilderDetail }) {
  return <WorkflowEditor detail={detail} />;
}
