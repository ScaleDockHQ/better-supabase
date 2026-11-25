import { AREAS } from "./areas";

/**
 * A page of a product area for the command center: the area's hub, a step of
 * its flow or the page one of its composites runs on. The labels are product
 * vocabulary from `areas.ts`, like the hubs themselves.
 */
export interface AreaCommand {
  readonly id: string;
  readonly kind: "area" | "step" | "action";
  /** Without the locale prefix. */
  readonly href: string;
  readonly area: string;
  readonly label: string;
}

/**
 * The area entries the caller may open. `visibleHrefs` are the menu entries the
 * caller sees; a route counts as reachable when one of them is the route or a
 * parent of it, so the palette never offers a page the proxy answers with a 403.
 * The hubs need the "Areas" menu entry.
 */
export function areaCommands({
  visibleHrefs,
  hubs,
}: {
  visibleHrefs: readonly string[];
  hubs: boolean;
}): AreaCommand[] {
  const reachable = (route: string): boolean =>
    visibleHrefs.some((href) => route === href || route.startsWith(`${href}/`));

  return AREAS.flatMap((area) => [
    ...(hubs
      ? [
          {
            id: area.id,
            kind: "area" as const,
            href: `/areas/${area.id}`,
            area: area.name,
            label: area.flow,
          },
        ]
      : []),
    ...area.steps
      .filter((step) => reachable(step.route))
      .map((step) => ({
        id: `${area.id}:step:${step.route}`,
        kind: "step" as const,
        href: step.route,
        area: area.name,
        label: step.label,
      })),
    ...area.actions
      .filter((action) => reachable(action.route))
      .map((action) => ({
        id: `${area.id}:action:${action.name}`,
        kind: "action" as const,
        href: action.route,
        area: area.name,
        label: action.label,
      })),
  ]);
}
