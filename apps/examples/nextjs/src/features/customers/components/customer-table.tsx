"use client";

import { SearchIcon, UsersIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";
import Image from "next/image";
import { useState } from "react";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Input } from "@/components/ui/input";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Link } from "@/i18n/navigation";
import { initials } from "@/lib/initials";

import { useStatusLabel } from "../use-status-label";

export interface CustomerRow {
  readonly id: string;
  readonly name: string;
  readonly status: string;
  readonly logoUrl: string | null;
  readonly notes: number;
  readonly lastNoteAt: string | null;
}

/**
 * The first page from the server, filtered and searched in the browser.
 * Deeper pages and server-side filters go through `/api/customers/list`.
 */
export function CustomerTable({
  customers,
  statusCounts,
  canWrite,
}: {
  customers: readonly CustomerRow[];
  statusCounts: Readonly<Record<string, number>>;
  canWrite: boolean;
}) {
  const t = useExtracted("customers");
  const statusLabel = useStatusLabel();
  const format = useFormatter();
  const [status, setStatus] = useState<string | null>(null);
  const [query, setQuery] = useState("");
  const needle = query.trim().toLowerCase();
  const rows = customers.filter(
    (customer) =>
      (status === null || customer.status === status) &&
      (needle === "" || customer.name.toLowerCase().includes(needle)),
  );
  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-2">
        <div className="relative w-full max-w-sm">
          <SearchIcon className="text-muted-foreground absolute top-1/2 left-2.5 size-4 -translate-y-1/2" />
          <Input
            type="search"
            value={query}
            onChange={(event) => {
              setQuery(event.target.value);
            }}
            placeholder={t("Search customers")}
            aria-label={t("Search customers")}
            className="pl-8"
          />
        </div>
        <fieldset className="flex flex-wrap gap-1" data-testid="status-facets">
          <legend className="sr-only">{t("Status")}</legend>
          <Button
            size="sm"
            variant={status === null ? "secondary" : "ghost"}
            aria-pressed={status === null}
            onClick={() => {
              setStatus(null);
            }}
          >
            {t("All")}
          </Button>
          {Object.entries(statusCounts).map(([value, count]) => (
            <Button
              key={value}
              size="sm"
              variant={status === value ? "secondary" : "ghost"}
              aria-pressed={status === value}
              onClick={() => {
                setStatus(value);
              }}
            >
              {statusLabel(value)}
              <Badge variant="outline" className="tabular-nums">
                {count}
              </Badge>
            </Button>
          ))}
        </fieldset>
      </div>
      {rows.length === 0 ? (
        <Empty className="border">
          <EmptyHeader>
            <EmptyMedia variant="icon">
              <UsersIcon />
            </EmptyMedia>
            <EmptyTitle>{t("No customers found")}</EmptyTitle>
            <EmptyDescription>
              {canWrite
                ? t("Add a customer, or change the filters.")
                : t("Change the filters to see more.")}
            </EmptyDescription>
          </EmptyHeader>
        </Empty>
      ) : (
        <div className="rounded-xl border">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{t("Name")}</TableHead>
                <TableHead>{t("Status")}</TableHead>
                <TableHead className="text-right">{t("Notes")}</TableHead>
                <TableHead className="hidden md:table-cell">
                  {t("Last note")}
                </TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {rows.map((customer) => (
                <TableRow key={customer.id}>
                  <TableCell>
                    {/* The detail reads `params`, which the shared App Shell can't
                        carry; a per-link prefetch resolves its cached reads. */}
                    <Link
                      href={`/customers/${customer.id}`}
                      prefetch
                      className="flex items-center gap-3 font-medium hover:underline"
                    >
                      {customer.logoUrl ? (
                        <Image
                          src={customer.logoUrl}
                          width={28}
                          height={28}
                          alt=""
                          className="rounded-md"
                        />
                      ) : (
                        <span className="bg-muted text-muted-foreground flex size-7 items-center justify-center rounded-md text-xs font-semibold">
                          {initials(customer.name, null)}
                        </span>
                      )}
                      {customer.name}
                    </Link>
                  </TableCell>
                  <TableCell>
                    <Badge
                      variant={
                        customer.status === "active" ? "default" : "secondary"
                      }
                    >
                      {statusLabel(customer.status)}
                    </Badge>
                  </TableCell>
                  <TableCell className="text-right tabular-nums">
                    {customer.notes}
                  </TableCell>
                  <TableCell className="text-muted-foreground hidden md:table-cell">
                    {customer.lastNoteAt
                      ? format.dateTime(new Date(customer.lastNoteAt), {
                          dateStyle: "medium",
                        })
                      : "–"}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      )}
    </div>
  );
}
