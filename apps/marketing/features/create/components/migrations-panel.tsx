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
import { Frame, FramePanel } from "@/components/reui/frame";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";

import { PlaceholderAccessNote } from "./placeholder-access-note";
import { ValidateInPostgres } from "./validate-in-postgres";

export type MigrationState =
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

async function loadMigrations(
  code: string,
  designCode: string,
): Promise<MigrationState> {
  try {
    const query = new URLSearchParams({ preset: code });

    if (designCode !== "") {
      query.set("design", designCode);
    }

    const response = await fetch(`/create/migrations?${query.toString()}`);
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

/** The migration files for a preset code and a design code (`""` for none). */
export function migrationsFor(
  code: string,
  designCode = "",
): Promise<MigrationState> {
  const key = `${code}:${designCode}`;
  const known = migrationRequests.get(key);

  if (known !== undefined) {
    return known;
  }

  const request = loadMigrations(code, designCode);
  migrationRequests.set(key, request);

  return request;
}

/** Drops a failed request, so the next render starts a new one. */
export function forgetMigrations(code: string, designCode = ""): void {
  migrationRequests.delete(`${code}:${designCode}`);
}

export function MigrationsSkeleton() {
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
  designCode,
  placeholder,
  onRetry,
}: {
  code: string;
  designCode: string;
  placeholder: boolean;
  onRetry: () => void;
}) {
  const state = use(migrationsFor(code, designCode));

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
              forgetMigrations(code, designCode);
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
      {placeholder ? <PlaceholderAccessNote /> : null}
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
      <Frame spacing="sm">
        <FramePanel>
          <ul aria-label="SQL files" className="flex flex-col gap-0.5">
            {state.files.map((file) => (
              <li key={file.path}>
                <details className="group flex flex-col gap-1">
                  <summary className="flex cursor-pointer items-center gap-2 rounded-md px-2 py-1.5 font-mono text-xs transition-colors hover:bg-muted">
                    <FileCodeIcon
                      aria-hidden="true"
                      className="size-3.5 shrink-0 text-muted-foreground"
                    />
                    <span className="truncate">{file.path}</span>
                  </summary>
                  <pre className="max-h-96 overflow-auto rounded-md bg-muted/50 p-3 font-mono text-code leading-6">
                    <code>{file.contents}</code>
                  </pre>
                </details>
              </li>
            ))}
          </ul>
        </FramePanel>
      </Frame>
      <ValidateInPostgres
        key={`${code}:${designCode}`}
        code={code}
        designCode={designCode}
      />
    </div>
  );
}

/**
 * The migration files for a preset code, loaded from `/create/migrations`.
 * `placeholder` marks SQL rendered with the stand-in authorization provider.
 */
export function MigrationsPanel({
  code,
  designCode = "",
  placeholder,
}: {
  code: string;
  designCode?: string;
  placeholder: boolean;
}) {
  const [attempt, retry] = useReducer((count: number) => count + 1, 0);

  return (
    <Suspense fallback={<MigrationsSkeleton />}>
      <MigrationFiles
        key={attempt}
        code={code}
        designCode={designCode}
        placeholder={placeholder}
        onRetry={retry}
      />
    </Suspense>
  );
}
