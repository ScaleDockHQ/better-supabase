"use client";

import { useAction, useErrorMessage } from "better-supabase/react";
import { ArrowRightIcon, ChevronDownIcon } from "lucide-react";
import { useExtracted } from "next-intl";

import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { toast } from "@/lib/toast";

import type { ChangeStage } from "../change-request-lifecycle";

import { moveChangeRequest } from "../change-requests-actions";

/** The stages the published workflow lets this request move to. */
export function MoveChangeRequestMenu({
  id,
  title,
  moves,
}: {
  id: string;
  title: string;
  moves: readonly ChangeStage[];
}) {
  const t = useExtracted("changeRequests");
  const errorMessage = useErrorMessage();

  const move = useAction(moveChangeRequest, {
    onSuccess: () => {
      toast.success(t("Change request moved"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  if (moves.length === 0) {
    return null;
  }

  return (
    <DropdownMenu>
      <DropdownMenuTrigger
        render={
          <Button
            size="sm"
            variant="outline"
            disabled={move.pending}
            aria-label={t("Move {title}", { title })}
          />
        }
      >
        {t("Move")}
        <ChevronDownIcon />
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        {moves.map((stage) => (
          <DropdownMenuItem
            key={stage.id}
            onClick={() => {
              void move.run({ id, to: stage.id });
            }}
          >
            <ArrowRightIcon />
            {stage.label}
          </DropdownMenuItem>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
