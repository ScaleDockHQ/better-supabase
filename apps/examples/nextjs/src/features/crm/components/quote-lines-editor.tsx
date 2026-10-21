"use client";

import type { Money } from "better-supabase/commerce";

import { toDecimal } from "better-supabase/commerce";
import { useAction } from "better-supabase/react";
import { PlusIcon, Trash2Icon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useState } from "react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { useErrorMessage } from "@/lib/use-error-message";

import { saveQuoteLines } from "../crm-actions";

interface Row {
  readonly key: string;
  readonly description: string;
  readonly quantity: string;
  readonly unitAmount: string;
  readonly discount: string;
  readonly tax: string;
}

export interface EditableLine {
  readonly description: string;
  readonly quantity: number;
  readonly unitAmount: Money;
  readonly discountBps: number;
  readonly taxRateBps: number;
}

type Currency = "EUR" | "USD" | "GBP";

function currencyOf(code: string): Currency | undefined {
  switch (code) {
    case "EUR":
    case "USD":
    case "GBP": {
      return code;
    }

    default: {
      return undefined;
    }
  }
}

const EMPTY_ROW = {
  description: "",
  quantity: "1",
  unitAmount: "",
  discount: "0",
  tax: "0",
};

/**
 * A draft's line items. Save sends every line; the database computes the totals
 * the page shows after the refresh.
 */
export function QuoteLinesEditor({
  quoteId,
  currency,
  initialLines,
}: {
  quoteId: string;
  currency: string;
  initialLines: readonly EditableLine[];
}) {
  const t = useExtracted("crm");
  const errorMessage = useErrorMessage();

  const [rows, setRows] = useState<readonly Row[]>(() =>
    initialLines.map((line) => ({
      key: crypto.randomUUID(),
      description: line.description,
      quantity: String(line.quantity),
      unitAmount: toDecimal(line.unitAmount),
      discount: String(line.discountBps / 100),
      tax: String(line.taxRateBps / 100),
    })),
  );

  const save = useAction(saveQuoteLines, {
    onSuccess: () => {
      toast.success(t("Lines saved"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  const code = currencyOf(currency);

  const update = (
    key: string,
    field: keyof Omit<Row, "key">,
    value: string,
  ) => {
    setRows((current) =>
      current.map((row) =>
        row.key === key ? { ...row, [field]: value } : row,
      ),
    );
  };

  return (
    <div className="flex flex-col gap-4">
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>{t("Description")}</TableHead>
            <TableHead className="w-20">{t("Qty")}</TableHead>
            <TableHead className="w-32">
              {t("Unit price ({currency})", { currency })}
            </TableHead>
            <TableHead className="w-24">{t("Discount %")}</TableHead>
            <TableHead className="w-24">{t("Tax %")}</TableHead>
            <TableHead className="w-10">
              <span className="sr-only">{t("Remove")}</span>
            </TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {rows.length === 0 ? (
            <TableRow>
              <TableCell
                colSpan={6}
                className="text-center text-sm text-muted-foreground"
              >
                {t("No lines yet. Add the first one below.")}
              </TableCell>
            </TableRow>
          ) : (
            rows.map((row) => (
              <TableRow key={row.key}>
                <TableCell>
                  <Input
                    value={row.description}
                    aria-label={t("Description")}
                    maxLength={200}
                    onChange={(event) => {
                      update(row.key, "description", event.target.value);
                    }}
                  />
                </TableCell>
                <TableCell>
                  <Input
                    value={row.quantity}
                    inputMode="numeric"
                    aria-label={t("Qty")}
                    onChange={(event) => {
                      update(row.key, "quantity", event.target.value);
                    }}
                  />
                </TableCell>
                <TableCell>
                  <Input
                    value={row.unitAmount}
                    inputMode="decimal"
                    placeholder="0.00"
                    aria-label={t("Unit price")}
                    onChange={(event) => {
                      update(row.key, "unitAmount", event.target.value);
                    }}
                  />
                </TableCell>
                <TableCell>
                  <Input
                    value={row.discount}
                    inputMode="decimal"
                    aria-label={t("Discount %")}
                    onChange={(event) => {
                      update(row.key, "discount", event.target.value);
                    }}
                  />
                </TableCell>
                <TableCell>
                  <Input
                    value={row.tax}
                    inputMode="decimal"
                    aria-label={t("Tax %")}
                    onChange={(event) => {
                      update(row.key, "tax", event.target.value);
                    }}
                  />
                </TableCell>
                <TableCell>
                  <Button
                    type="button"
                    size="icon-sm"
                    variant="ghost"
                    aria-label={t("Remove line")}
                    onClick={() => {
                      setRows((current) =>
                        current.filter((item) => item.key !== row.key),
                      );
                    }}
                  >
                    <Trash2Icon aria-hidden />
                  </Button>
                </TableCell>
              </TableRow>
            ))
          )}
        </TableBody>
      </Table>
      <div className="flex flex-wrap gap-2">
        <Button
          type="button"
          size="sm"
          variant="outline"
          onClick={() => {
            setRows((current) => [
              ...current,
              { key: crypto.randomUUID(), ...EMPTY_ROW },
            ]);
          }}
        >
          <PlusIcon />
          {t("Add line")}
        </Button>
        <Button
          type="button"
          size="sm"
          disabled={save.pending || code === undefined}
          onClick={() => {
            if (code === undefined) {
              return;
            }

            void save.run({
              quoteId,
              currency: code,
              lines: rows.map((row) => ({
                description: row.description,
                quantity: Number(row.quantity),
                unitAmount: row.unitAmount,
                discountPercent: Number(row.discount),
                taxPercent: Number(row.tax),
              })),
            });
          }}
        >
          {t("Save lines")}
        </Button>
      </div>
    </div>
  );
}
