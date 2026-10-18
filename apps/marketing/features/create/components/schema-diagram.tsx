"use client";

import type { ResolvedPreset } from "better-supabase/preset";
import type { ReactElement } from "react";

import {
  CircleAlertIcon,
  DatabaseIcon,
  FolderTreeIcon,
  RotateCwIcon,
} from "lucide-react";
import dynamic from "next/dynamic";
import { Suspense, use, useReducer } from "react";
import * as v from "valibot";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Button } from "@/components/ui/button";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Skeleton } from "@/components/ui/skeleton";
import { categoryStyle } from "@/features/blocks/categories";
import { blocks } from "@/lib/blocks";
import { CONFIG_FILE, packagePath } from "@/lib/create";
import { type SchemaTable, schemaRelations } from "@/lib/schema";

import { PlaceholderAccessNote } from "./placeholder-access-note";

function CanvasSkeleton(): ReactElement {
  return (
    <div aria-busy="true" className="flex flex-1 flex-col gap-3 p-4">
      <span className="sr-only">Drawing the schema</span>
      <Skeleton className="w-full flex-1" />
    </div>
  );
}

const SchemaCanvas = dynamic(
  async () => {
    const { SchemaCanvas: Canvas } = await import("./schema-canvas");

    return Canvas;
  },
  { ssr: false, loading: CanvasSkeleton },
);

type SchemaState =
  | { readonly status: "error"; readonly message: string }
  | { readonly status: "ready"; readonly tables: readonly SchemaTable[] };

const column = v.object({ name: v.string(), type: v.string() });

const schemaResponse = v.union([
  v.object({
    tables: v.array(
      v.object({
        id: v.string(),
        schema: v.string(),
        name: v.string(),
        module: v.string(),
        primaryKey: v.array(v.string()),
        foreignKeys: v.array(
          v.object({
            columns: v.array(v.string()),
            target: v.object({
              schema: v.string(),
              table: v.string(),
              columns: v.array(v.string()),
            }),
          }),
        ),
        tenantColumn: v.nullable(v.string()),
        keyColumns: v.array(column),
        columnCount: v.number(),
      }),
    ),
  }),
  v.object({ error: v.string() }),
]);

async function loadSchema(code: string): Promise<SchemaState> {
  try {
    const response = await fetch(`/create/schema?preset=${code}`);
    const body = v.parse(schemaResponse, await response.json());

    return "error" in body
      ? { status: "error", message: body.error }
      : { status: "ready", tables: body.tables };
  } catch (error) {
    return {
      status: "error",
      message:
        error instanceof Error
          ? error.message
          : "The schema could not be read.",
    };
  }
}

/**
 * One request per code for the session, so `use` sees the same promise on
 * every render. Retry drops the entry before it renders again.
 */
const schemaRequests = new Map<string, Promise<SchemaState>>();

function schemaFor(code: string): Promise<SchemaState> {
  const known = schemaRequests.get(code);

  if (known !== undefined) {
    return known;
  }

  const request = loadSchema(code);
  schemaRequests.set(code, request);

  return request;
}

const CATEGORY_BY_BLOCK = new Map(
  blocks.map((block) => [block.name, block.category]),
);

const FALLBACK_CATEGORY = "Database primitives";

function categoryOf(module: string): string {
  return CATEGORY_BY_BLOCK.get(module) ?? FALLBACK_CATEGORY;
}

function FolderLayout({ pkg }: { pkg: string }): ReactElement {
  return (
    <p className="flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-muted-foreground">
      <FolderTreeIcon aria-hidden="true" className="size-3.5 shrink-0" />
      <code className="font-mono">{packagePath(CONFIG_FILE, pkg)}</code>
      <code className="font-mono">{packagePath("lib/blocks.ts", pkg)}</code>
      <code className="font-mono">supabase/schemas/</code>
    </p>
  );
}

function SchemaView({
  code,
  pkg,
  placeholder,
  onRetry,
}: {
  code: string;
  pkg: string | undefined;
  placeholder: boolean;
  onRetry: () => void;
}): ReactElement {
  const state = use(schemaFor(code));

  if (state.status === "error") {
    return (
      <div className="p-4">
        <Alert variant="destructive">
          <CircleAlertIcon aria-hidden="true" />
          <AlertTitle>The schema could not be read</AlertTitle>
          <AlertDescription>{state.message}</AlertDescription>
          <AlertAction>
            <Button
              variant="outline"
              size="sm"
              onClick={() => {
                schemaRequests.delete(code);
                onRetry();
              }}
            >
              <RotateCwIcon aria-hidden="true" />
              Retry
            </Button>
          </AlertAction>
        </Alert>
      </div>
    );
  }

  const { tables } = state;
  const relations = schemaRelations(tables);

  const categories = [
    ...new Set(tables.map((table) => categoryOf(table.module))),
  ].toSorted();

  return (
    <>
      <div className="flex flex-col gap-2 border-b border-border px-4 py-2">
        <div className="flex flex-wrap items-center gap-x-4 gap-y-2">
          <p className="text-sm font-medium tabular-nums">
            {tables.length} tables, {relations.length} relations
          </p>
          <ul
            aria-label="Categories"
            className="flex flex-wrap items-center gap-x-3 gap-y-1"
          >
            {categories.map((category) => (
              <li
                key={category}
                className="flex items-center gap-1.5 text-xs text-muted-foreground"
              >
                <span
                  aria-hidden="true"
                  className={`size-2 rounded-full ${categoryStyle(category).solid}`}
                />
                {category}
              </li>
            ))}
          </ul>
        </div>
        {pkg === undefined ? null : <FolderLayout pkg={pkg} />}
        {placeholder ? <PlaceholderAccessNote /> : null}
      </div>
      <div className="sr-only">
        <h2>Tables in this schema</h2>
        <ul>
          {tables.map((table) => (
            <li key={table.id}>
              {table.id} from {table.module}, {table.columnCount} columns
              {table.foreignKeys.length > 0
                ? `, references ${table.foreignKeys
                    .map((key) => `${key.target.schema}.${key.target.table}`)
                    .join(", ")}`
                : ""}
            </li>
          ))}
        </ul>
      </div>
      <div className="relative flex min-h-[28rem] flex-1">
        <Suspense fallback={<CanvasSkeleton />}>
          <SchemaCanvas
            code={code}
            tables={tables}
            categories={Object.fromEntries(
              tables.map((table) => [table.module, categoryOf(table.module)]),
            )}
          />
        </Suspense>
      </div>
    </>
  );
}

/**
 * The tables the selection installs and their foreign keys, from
 * `/create/schema`. The canvas loads only when there is something to draw.
 */
export function SchemaDiagram({
  code,
  resolved,
  pkg,
  onStart,
}: {
  code: string;
  resolved: ResolvedPreset;
  pkg: string | undefined;
  onStart: () => void;
}): ReactElement {
  const [attempt, retry] = useReducer((count: number) => count + 1, 0);

  if (resolved.blocks.length === 0) {
    return (
      <Empty className="flex-1">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <DatabaseIcon aria-hidden="true" />
          </EmptyMedia>
          <EmptyTitle>Pick a block</EmptyTitle>
          <EmptyDescription>
            The tables each block creates show up here, with the foreign keys
            between them.
          </EmptyDescription>
        </EmptyHeader>
        <EmptyContent>
          <Button type="button" size="sm" onClick={onStart}>
            Start from the SaaS preset
          </Button>
        </EmptyContent>
      </Empty>
    );
  }

  return (
    <div className="flex flex-1 flex-col">
      <Suspense fallback={<CanvasSkeleton />}>
        <SchemaView
          key={attempt}
          code={code}
          pkg={pkg}
          placeholder={resolved.preset.access === "provider"}
          onRetry={retry}
        />
      </Suspense>
    </div>
  );
}
