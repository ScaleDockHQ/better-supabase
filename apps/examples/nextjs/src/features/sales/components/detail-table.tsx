import type { ReactNode } from "react";

import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyTitle,
} from "@/components/ui/empty";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";

// skeleton: renders from props, so nothing of its own suspends
/** A small card with a table, an empty state and an optional action. */
export function DetailTable({
  title,
  description,
  head,
  rows,
  emptyTitle,
  emptyDescription,
  action,
}: {
  title: string;
  description?: string | undefined;
  head: readonly string[];
  rows: readonly {
    readonly key: string;
    readonly cells: readonly ReactNode[];
  }[];
  emptyTitle: string;
  emptyDescription?: string | undefined;
  action?: ReactNode;
}) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>{title}</CardTitle>
        {description ? <CardDescription>{description}</CardDescription> : null}
        {action ? <div className="pt-2">{action}</div> : null}
      </CardHeader>
      <CardContent>
        {rows.length === 0 ? (
          <Empty className="border">
            <EmptyHeader>
              <EmptyTitle>{emptyTitle}</EmptyTitle>
              {emptyDescription ? (
                <EmptyDescription>{emptyDescription}</EmptyDescription>
              ) : null}
            </EmptyHeader>
          </Empty>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                {head.map((label) => (
                  <TableHead key={label}>{label}</TableHead>
                ))}
              </TableRow>
            </TableHeader>
            <TableBody>
              {rows.map((row) => (
                <TableRow key={row.key}>
                  {head.map((label, column) => (
                    <TableCell key={label}>{row.cells[column]}</TableCell>
                  ))}
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </CardContent>
    </Card>
  );
}

// skeleton: renders from props, so nothing of its own suspends
/** A row of labelled figures at the top of a detail page. */
export function FactGrid({
  facts,
}: {
  facts: readonly { readonly label: string; readonly value: string }[];
}) {
  return (
    <dl className="grid gap-4 rounded-xl border p-4 sm:grid-cols-3">
      {facts.map((fact) => (
        <div key={fact.label} className="flex flex-col gap-1">
          <dt className="text-xs text-muted-foreground">{fact.label}</dt>
          <dd className="text-sm font-medium tabular-nums">{fact.value}</dd>
        </div>
      ))}
    </dl>
  );
}
