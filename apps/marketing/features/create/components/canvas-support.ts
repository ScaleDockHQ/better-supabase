import type { Node } from "@xyflow/react";

import { getNodesBounds, getViewportForBounds } from "@xyflow/react";
import { toPng, toSvg } from "html-to-image";
import { toast } from "sonner";

import type { Design } from "@/lib/design";
import type { SchemaData } from "@/lib/schema";

import { isAppTable } from "@/lib/design";
import { toDbml, toJson, toMermaid } from "@/lib/schema-export";
import { layoutSchema, type SchemaLayout } from "@/lib/schema-layout";

import type { ExportFormat } from "./canvas-toolbar";

export interface LayoutInput {
  readonly data: SchemaData;
  readonly expanded: ReadonlySet<string>;
  readonly softRefs: boolean;
  readonly collapsed: ReadonlySet<string>;
  readonly visible: ReadonlySet<string> | undefined;
}

/**
 * One layout per input for the session, so `use` gets the same promise on
 * every render and going back to a view is instant.
 */
const layouts = new Map<string, Promise<SchemaLayout>>();

const LAYOUT_CACHE_LIMIT = 64;

function layoutKey(input: LayoutInput): string {
  return JSON.stringify([
    input.data.tables.map((table) => [
      table.id,
      table.columns.map((column) => column.name),
      table.foreignKeys.map((key) => [
        key.columns,
        key.target.schema,
        key.target.table,
      ]),
    ]),
    input.data.softRefs.map((ref) => [ref.from, ref.column, ref.to]),
    [...input.expanded].toSorted(),
    input.softRefs,
    [...input.collapsed].toSorted(),
    input.visible === undefined ? null : [...input.visible].toSorted(),
  ]);
}

export function layoutFor(input: LayoutInput): Promise<SchemaLayout> {
  const key = layoutKey(input);
  const known = layouts.get(key);

  if (known !== undefined) {
    return known;
  }

  if (layouts.size >= LAYOUT_CACHE_LIMIT) {
    layouts.clear();
  }

  const layout = layoutSchema(input.data, {
    expanded: input.expanded,
    softRefs: input.softRefs,
    collapsed: input.collapsed,
    visible: input.visible,
    isApp: isAppTable,
  });

  layouts.set(key, layout);

  return layout;
}

export function toggled<T>(
  set: ReadonlySet<T>,
  value: T,
  on?: boolean,
): ReadonlySet<T> {
  const next = new Set(set);

  if (on ?? !next.has(value)) {
    next.add(value);
  } else {
    next.delete(value);
  }

  return next;
}

/** The tables each table references or is referenced by, soft references included. */
export function neighboursOf(
  data: SchemaData,
): ReadonlyMap<string, ReadonlySet<string>> {
  const map = new Map<string, Set<string>>();

  const link = (a: string, b: string): void => {
    map.set(a, (map.get(a) ?? new Set()).add(b));
    map.set(b, (map.get(b) ?? new Set()).add(a));
  };

  for (const table of data.tables) {
    for (const key of table.foreignKeys) {
      link(table.id, `${key.target.schema}.${key.target.table}`);
    }
  }

  for (const ref of data.softRefs) {
    if (ref.to !== null) {
      link(ref.from, ref.to);
    }
  }

  return map;
}

export function pointerOf(
  event: MouseEvent | TouchEvent,
): { x: number; y: number } | undefined {
  if ("changedTouches" in event) {
    const touch = event.changedTouches[0];

    return touch === undefined
      ? undefined
      : { x: touch.clientX, y: touch.clientY };
  }

  return { x: event.clientX, y: event.clientY };
}

/** The node under the pointer, so dropping a connection anywhere on a table works. */
export function nodeUnder(event: MouseEvent | TouchEvent): string | undefined {
  const point = pointerOf(event);

  const element =
    point === undefined ? null : document.elementFromPoint(point.x, point.y);

  const node = element?.closest<HTMLElement>(".react-flow__node");

  return node?.dataset["id"];
}

function download(name: string, href: string): void {
  const anchor = document.createElement("a");
  anchor.href = href;
  anchor.download = name;
  anchor.click();
}

function downloadText(name: string, text: string, type: string): void {
  const url = URL.createObjectURL(new Blob([text], { type }));
  download(name, url);
  URL.revokeObjectURL(url);
}

export interface ExportSource {
  readonly code: string;
  readonly design: Design;
  readonly data: SchemaData;
  readonly nodes: Node[];
  /** The canvas element; images draw its `.react-flow__viewport`. */
  readonly container: HTMLElement | null;
}

/** Downloads the schema in `format` and reports the result in a toast. */
export async function exportSchema(
  format: ExportFormat,
  { code, design, data, nodes, container }: ExportSource,
): Promise<void> {
  switch (format) {
    case "mermaid": {
      downloadText("schema.mmd", toMermaid(data), "text/plain");
      break;
    }

    case "dbml": {
      downloadText("schema.dbml", toDbml(data), "text/plain");
      break;
    }

    case "json": {
      downloadText(
        "schema.json",
        toJson(code, design, data),
        "application/json",
      );
      break;
    }

    case "png":
    case "svg": {
      const viewport = container?.querySelector<HTMLElement>(
        ".react-flow__viewport",
      );

      if (viewport === undefined || viewport === null) {
        return;
      }

      const bounds = getNodesBounds(nodes);
      const width = Math.min(Math.max(bounds.width + 64, 640), 4096);
      const height = Math.min(Math.max(bounds.height + 64, 480), 4096);

      const transform = getViewportForBounds(
        bounds,
        width,
        height,
        0.1,
        2,
        0.05,
      );

      const options = {
        width,
        height,
        backgroundColor: getComputedStyle(document.body).backgroundColor,
        style: {
          width: `${width}px`,
          height: `${height}px`,
          transform: `translate(${transform.x}px, ${transform.y}px) scale(${transform.zoom})`,
        },
      };

      try {
        const url =
          format === "png"
            ? await toPng(viewport, options)
            : await toSvg(viewport, options);

        download(`schema.${format}`, url);
      } catch {
        toast.error(
          "The image could not be drawn. Try the SVG or Mermaid export.",
        );

        return;
      }

      break;
    }

    default: {
      const unreachable: never = format;

      return unreachable;
    }
  }

  toast.success(`Downloaded schema.${format === "mermaid" ? "mmd" : format}.`);
}
