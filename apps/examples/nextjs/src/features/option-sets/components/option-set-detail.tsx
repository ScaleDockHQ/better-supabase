import { getExtracted } from "next-intl/server";
import { forbidden, notFound } from "next/navigation";

import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { Badge } from "@/components/reui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import { getOptionSet } from "../option-sets-queries";
import {
  ArchiveOptionItemButton,
  EditOptionItemDialog,
} from "./option-set-controls";

/** Render inside `<Suspense>`; the fallback is `OptionSetDetailSkeleton`. */
export async function OptionSetDetail({ id }: { id: string }) {
  const [set, t, permissions] = await Promise.all([
    getOptionSet(id),
    getExtracted("optionSets"),
    getPermissions(),
  ]);

  if (!can(permissions, "option_sets.read")) {
    forbidden();
  }

  if (!set) {
    notFound();
  }

  const manage = can(permissions, "option_sets.manage");

  return (
    <RecordDetailFrame
      title={set.name}
      description={t("{type}, field {field}", {
        type: set.subjectType,
        field: set.field,
      })}
      status={
        set.archived ? (
          <Badge variant="secondary">{t("Archived")}</Badge>
        ) : (
          <Badge variant="success-light">{t("Active")}</Badge>
        )
      }
    >
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>{t("Label")}</TableHead>
            <TableHead>{t("Key")}</TableHead>
            <TableHead>{t("Level")}</TableHead>
            <TableHead>{t("Color")}</TableHead>
            <TableHead>{t("State")}</TableHead>
            {manage ? (
              <TableHead className="text-right">{t("Actions")}</TableHead>
            ) : null}
          </TableRow>
        </TableHeader>
        <TableBody>
          {set.items.map((item) => (
            <TableRow key={item.id}>
              <TableCell className="font-medium">{item.label}</TableCell>
              <TableCell className="font-mono text-xs">{item.key}</TableCell>
              <TableCell className="tabular-nums">{item.level}</TableCell>
              <TableCell>{item.color ?? "–"}</TableCell>
              <TableCell>
                {item.archived ? (
                  <Badge variant="secondary">{t("Archived")}</Badge>
                ) : (
                  <Badge variant="success-light">{t("Active")}</Badge>
                )}
              </TableCell>
              {manage ? (
                <TableCell>
                  {item.archived ? null : (
                    <div className="flex justify-end gap-1">
                      <EditOptionItemDialog
                        setId={set.id}
                        itemId={item.id}
                        label={item.label}
                        color={item.color}
                      />
                      <ArchiveOptionItemButton
                        itemId={item.id}
                        label={item.label}
                      />
                    </div>
                  )}
                </TableCell>
              ) : null}
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </RecordDetailFrame>
  );
}

export function OptionSetDetailSkeleton() {
  return <Skeleton className="h-64 rounded-xl" aria-busy="true" />;
}
