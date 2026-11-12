"use client";

import { useAction } from "better-supabase/react";
import { useExtracted } from "next-intl";
import { useState } from "react";

import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import { FormSelect } from "@/features/crm/components/form-select";
import { toast } from "@/lib/toast";
import { useErrorMessage } from "@/lib/use-error-message";

import { setQueueMembers } from "../sales-actions";

interface Member {
  readonly userId: string;
  readonly name: string;
  readonly weight: number;
  readonly active: boolean;
  readonly assigned: number;
}

/**
 * The members of a queue with their weight and active flag. Every change
 * replaces the member list, as `assignment.setMembers` does.
 */
export function QueueMembersEditor({
  queueId,
  members,
  candidates,
  canManage,
}: {
  queueId: string;
  members: readonly Member[];
  candidates: readonly { readonly userId: string; readonly name: string }[];
  canManage: boolean;
}) {
  const t = useExtracted("sales");
  const errorMessage = useErrorMessage();
  const [pick, setPick] = useState(candidates[0]?.userId ?? "");

  const save = useAction(setQueueMembers, {
    onSuccess: () => {
      toast.success(t("Members saved"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  const run = (
    next: readonly Pick<Member, "userId" | "weight" | "active">[],
  ) => {
    void save.run({
      queueId,
      members: next.map(({ userId, weight, active }) => ({
        userId,
        weight,
        active,
      })),
    });
  };

  const current = members.map(({ userId, weight, active }) => ({
    userId,
    weight,
    active,
  }));

  const free = candidates.filter(
    (candidate) =>
      !members.some((member) => member.userId === candidate.userId),
  );

  const chosen = free.some((candidate) => candidate.userId === pick)
    ? pick
    : (free[0]?.userId ?? "");

  return (
    <div className="flex flex-col gap-4">
      {members.length === 0 ? (
        <p className="text-sm text-muted-foreground">
          {t("Nobody is in this queue yet.")}
        </p>
      ) : (
        <ul className="flex flex-col divide-y rounded-xl border">
          {members.map((member) => (
            <li
              key={member.userId}
              className="flex flex-wrap items-center gap-3 p-3"
            >
              <span className="min-w-0 flex-1 truncate text-sm font-medium">
                {member.name}
              </span>
              <Badge variant="secondary">
                {t("Weight {weight}", { weight: String(member.weight) })}
              </Badge>
              <span className="text-xs text-muted-foreground tabular-nums">
                {t("{count} assigned", { count: String(member.assigned) })}
              </span>
              {canManage ? (
                <>
                  <Button
                    size="sm"
                    variant="outline"
                    disabled={save.pending}
                    onClick={() => {
                      run(
                        current.map((entry) =>
                          entry.userId === member.userId
                            ? { ...entry, active: !entry.active }
                            : entry,
                        ),
                      );
                    }}
                  >
                    {member.active ? t("Pause") : t("Resume")}
                  </Button>
                  <Button
                    size="sm"
                    variant="ghost"
                    disabled={save.pending}
                    onClick={() => {
                      run(
                        current.filter(
                          (entry) => entry.userId !== member.userId,
                        ),
                      );
                    }}
                  >
                    {t("Remove")}
                  </Button>
                </>
              ) : null}
            </li>
          ))}
        </ul>
      )}
      {canManage && free.length > 0 ? (
        <div className="flex flex-wrap items-center gap-2">
          <div className="w-64">
            <FormSelect
              name="member"
              label={t("Member")}
              value={chosen}
              items={free.map((candidate) => ({
                value: candidate.userId,
                label: candidate.name,
              }))}
              onValueChange={setPick}
            />
          </div>
          <Button
            size="sm"
            disabled={save.pending || chosen === ""}
            onClick={() => {
              run([...current, { userId: chosen, weight: 1, active: true }]);
            }}
          >
            {t("Add member")}
          </Button>
        </div>
      ) : null}
    </div>
  );
}
