"use client";

import { CircleAlertIcon, FileCodeIcon, RotateCwIcon } from "lucide-react";
import { Suspense, use, useReducer } from "react";
import * as v from "valibot";

import type { PresetMigrationFile } from "@/lib/create";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";

type MigrationState =
  | { readonly status: "error"; readonly message: string }
  | {
      readonly status: "ready";
      readonly files: readonly PresetMigrationFile[];
    };

const migrationsResponse = v.union([
  v.object({
    files: v.array(
      v.object({ path: v.string(), module: v.string(), contents: v.string() }),
    ),
  }),
  v.object({ error: v.string() }),
]);

async function loadMigrations(code: string): Promise<MigrationState> {
  try {
    const response = await fetch(`/create/migrations?preset=${code}`);
    const body = v.parse(migrationsResponse, await response.json());

    return "error" in body
      ? { status: "error", message: body.error }
      : { status: "ready", files: body.files };
  } catch (error) {
    return {
      status: "error",
      message:
        error instanceof Error
          ? error.message
          : "The migrations could not be rendered.",
    };
  }
}

/**
 * One request per code, kept for the session, so `use` gets the same
 * promise on every render and switching back to a selection is instant.
 * Retry drops the entry, so the next render starts a new request.
 */
const migrationRequests = new Map<string, Promise<MigrationState>>();

function migrationsFor(code: string): Promise<MigrationState> {
  const known = migrationRequests.get(code);

  if (known !== undefined) {
    return known;
  }

  const request = loadMigrations(code);
  migrationRequests.set(code, request);

  return request;
}

function MigrationsSkeleton() {
  return (
    <div aria-busy="true" className="flex flex-col gap-2">
      <span className="sr-only">Rendering the migrations</span>
      <Skeleton className="h-4 w-3/4" />
      {["a", "b", "c", "d"].map((key) => (
        <Skeleton key={key} className="h-9 w-full" />
      ))}
    </div>
  );
}

function MigrationFiles({
  code,
  onRetry,
}: {
  code: string;
  onRetry: () => void;
}) {
  const state = use(migrationsFor(code));

  if (state.status === "error") {
    return (
      <Alert variant="destructive">
        <CircleAlertIcon aria-hidden="true" />
        <AlertTitle>The migrations could not be rendered</AlertTitle>
        <AlertDescription>{state.message}</AlertDescription>
        <AlertAction>
          <Button
            variant="outline"
            size="sm"
            onClick={() => {
              migrationRequests.delete(code);
              onRetry();
            }}
          >
            <RotateCwIcon aria-hidden="true" />
            Retry
          </Button>
        </AlertAction>
      </Alert>
    );
  }

  return (
    <div className="flex flex-col gap-3">
      <p className="text-sm leading-6 text-muted-foreground">
        {state.files.length} files that{" "}
        <code className="font-mono text-code">sql sync</code> writes into{" "}
        <code className="font-mono text-code">supabase/</code>. Turn them into a
        migration with{" "}
        <code className="font-mono text-code">
          supabase db schema declarative sync
        </code>
        .
      </p>
      <ul className="flex flex-col divide-y divide-border rounded-lg border border-border">
        {state.files.map((file) => (
          <li key={file.path}>
            <details className="group">
              <summary className="flex cursor-pointer items-center gap-2 px-3 py-2 font-mono text-xs transition-colors hover:bg-muted/60">
                <FileCodeIcon
                  aria-hidden="true"
                  className="size-3.5 shrink-0 text-muted-foreground"
                />
                <span className="truncate">{file.path}</span>
              </summary>
              <pre className="max-h-96 overflow-auto border-t border-border bg-muted/30 p-4 font-mono text-code leading-6">
                <code>{file.contents}</code>
              </pre>
            </details>
          </li>
        ))}
      </ul>
    </div>
  );
}

/** The migration files for a preset code, loaded from `/create/migrations`. */
export function MigrationsPanel({ code }: { code: string }) {
  const [attempt, retry] = useReducer((count: number) => count + 1, 0);

  return (
    <Suspense fallback={<MigrationsSkeleton />}>
      <MigrationFiles key={attempt} code={code} onRetry={retry} />
    </Suspense>
  );
}
