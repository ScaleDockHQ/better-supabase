import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { afterEach, describe, expect, it } from "vitest";

import { checkRoot } from "./check-app-architecture.ts";

const allow = {
  roots: [],
  pendingRoots: [],
  suspenseInFeatures: {},
  connection: {},
  findings: [],
};

const dirs: string[] = [];

const project = (files: Record<string, string>): string => {
  const root = mkdtempSync(join(tmpdir(), "app-arch-"));
  dirs.push(root);

  for (const [path, body] of Object.entries(files)) {
    const full = join(root, path);
    mkdirSync(dirname(full), { recursive: true });
    writeFileSync(full, body);
  }

  return root;
};

const rules = (files: Record<string, string>): string[] =>
  checkRoot(project(files), allow).map((finding) => finding.rule);

afterEach(() => {
  for (const dir of dirs.splice(0)) {
    rmSync(dir, { recursive: true, force: true });
  }
});

describe("checkRoot", () => {
  it("accepts a synchronous page that composes a feature with its skeleton", () => {
    expect(
      rules({
        "app/notes/page.tsx": `import { Suspense } from "react";
import { Notes, NotesSkeleton } from "@/features/notes/components/notes";
export default function Page({ params }: { params: Promise<{ id: string }> }) {
  return <Suspense fallback={<NotesSkeleton />}><Notes id={params.then((p) => p.id)} /></Suspense>;
}`,
        "features/notes/components/notes.tsx": `export async function Notes() { return null; }
export function NotesSkeleton() { return null; }`,
        "features/notes/notes-queries.ts": `import "server-only";\nexport const a = 1;`,
        "features/notes/notes-actions.ts": `"use server";\nexport const b = 1;`,
      }),
    ).toEqual([]);
  });

  it("flags a page that imports queries, is async and awaits params", () => {
    expect(
      rules({
        "app/notes/page.tsx": `import { getNotes } from "@/features/notes/notes-queries";
export default async function Page({ params }) { const { id } = await params; return getNotes(id); }`,
      }),
    ).toEqual(["page-imports-queries", "async-page", "await-params"]);
  });

  it("flags route props, missing directives, wrong prefixes and missing skeletons", () => {
    expect(
      rules({
        "features/notes/components/notes.tsx": `export async function Notes({ params }: { params: Promise<string> }) { return null; }`,
        "features/notes/note-queries.ts": `export const a = 1;`,
        "features/notes/notes-actions.ts": `export const b = 1;`,
      }).toSorted(),
    ).toEqual(
      [
        "actions-use-server",
        "file-prefix",
        "queries-server-only",
        "route-prop",
        "skeleton",
      ].toSorted(),
    );
  });

  it("flags Suspense in a feature, an uncommented connection and a client file that imports an async component", () => {
    expect(
      rules({
        "features/notes/components/notes.tsx": `import { Suspense } from "react";
import { connection } from "next/server";
export async function Notes() { await connection(); return <Suspense />; }
export function NotesSkeleton() { return null; }`,
        "features/notes/components/client.tsx": `"use client";
import { Notes } from "./notes";
export function Client() { return <Notes />; }`,
      }).toSorted(),
    ).toEqual(["client-imports-async", "connection", "suspense-in-feature"]);
  });

  it("flags a cache file that imports server code and accepts a pure one", () => {
    expect(
      rules({
        "features/notes/notes-cache.ts": `import { cacheTag } from "next/cache";\nexport const a = cacheTag;`,
      }),
    ).toEqual(["cache-pure"]);
    expect(
      rules({
        "features/notes/notes-cache.ts": `export const tag = (id: string) => \`notes:\${id}\`;`,
      }),
    ).toEqual([]);
  });

  it("accepts a connection call with a reason on the line before", () => {
    expect(
      rules({
        "features/notes/components/notes.tsx": `import { connection } from "next/server";
export async function Notes() {
  // Reads the wall clock, so rendering waits for a real request.
  await connection();
  return null;
}
export function NotesSkeleton() { return null; }`,
      }),
    ).toEqual([]);
  });

  it("checks a pending root as soon as it exists and fails on a missing root", () => {
    const root = project({
      "scripts/app-architecture-allow.json": JSON.stringify({
        roots: ["app-src"],
        pendingRoots: ["init-src"],
        suspenseInFeatures: {},
        connection: {},
        findings: [],
      }),
      "app-src/features/notes/notes-queries.ts": `import "server-only";`,
      "init-src/app/page.tsx": `export default async function Page() { return null; }`,
    });

    const run = (): string => {
      try {
        return execFileSync(
          "node",
          [resolve("scripts/check-app-architecture.ts")],
          { cwd: root, encoding: "utf-8", stdio: "pipe" },
        );
      } catch (error) {
        return String((error as { stderr?: string }).stderr);
      }
    };

    expect(run()).toContain("[async-page]");
    rmSync(join(root, "init-src"), { recursive: true });
    expect(run()).toContain("app architecture: 0 findings");
    rmSync(join(root, "app-src"), { recursive: true });
    expect(run()).toContain("the root app-src does not exist");
  });
});
