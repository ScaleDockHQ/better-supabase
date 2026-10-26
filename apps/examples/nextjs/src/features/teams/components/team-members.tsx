"use client";

import { useAction } from "better-supabase/react";
import { UserMinusIcon, UserPlusIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useOptimistic, useState, useTransition } from "react";
import { toast } from "sonner";

import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyTitle,
} from "@/components/ui/empty";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Link } from "@/i18n/navigation";
import { initials } from "@/lib/initials";
import { useErrorMessage } from "@/lib/use-error-message";

import { setTeamMember } from "../teams-actions";

/** A member of the organization as the team page lists them. */
export interface TeamMemberOption {
  readonly userId: string;
  readonly name: string | null;
  readonly email: string | null;
  readonly avatarUrl: string | null;
}

/**
 * A team's members, with a picker that adds a member of the organization and a
 * button that takes one off. Both show at once and roll back on an error.
 */
export function TeamMembers({
  teamId,
  memberIds,
  people,
  canManage,
}: {
  teamId: string;
  memberIds: readonly string[];
  people: readonly TeamMemberOption[];
  canManage: boolean;
}) {
  const t = useExtracted("teams");
  const errorMessage = useErrorMessage();
  const [, startTransition] = useTransition();
  const [candidate, setCandidate] = useState<string | null>(null);

  const [ids, setOptimistic] = useOptimistic(
    memberIds,
    (current, change: { userId: string; member: boolean }) =>
      change.member
        ? [...current, change.userId]
        : current.filter((id) => id !== change.userId),
  );

  const change = useAction(setTeamMember, {
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  const toggle = (userId: string, member: boolean) => {
    startTransition(async () => {
      setOptimistic({ userId, member });
      await change.run({ teamId, userId, member });
    });
  };

  const label = (person: TeamMemberOption) =>
    person.name ?? person.email ?? person.userId;

  const onTeam = people.filter((person) => ids.includes(person.userId));

  const others = people
    .filter((person) => !ids.includes(person.userId))
    .map((person) => ({ value: person.userId, label: label(person) }));

  return (
    <div className="flex flex-col gap-3" data-testid="team-members">
      {canManage && others.length > 0 ? (
        <div className="flex flex-wrap items-center gap-2">
          <Select
            value={candidate}
            items={others}
            onValueChange={(value) => {
              setCandidate(
                others.find((option) => option.value === value)?.value ?? null,
              );
            }}
          >
            <SelectTrigger
              size="sm"
              className="w-56"
              aria-label={t("Member to add")}
            >
              <SelectValue placeholder={t("Choose a member")} />
            </SelectTrigger>
            <SelectContent>
              {others.map((item) => (
                <SelectItem key={item.value} value={item.value}>
                  {item.label}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
          <Button
            size="sm"
            variant="outline"
            disabled={candidate === null}
            onClick={() => {
              if (candidate !== null) {
                toggle(candidate, true);
                setCandidate(null);
              }
            }}
          >
            <UserPlusIcon />
            {t("Add")}
          </Button>
        </div>
      ) : null}
      {onTeam.length === 0 ? (
        <Empty>
          <EmptyHeader>
            <EmptyTitle>{t("Nobody is on this team")}</EmptyTitle>
            <EmptyDescription>
              {canManage
                ? t("Choose a member above to add them.")
                : t("Ask an admin to add members.")}
            </EmptyDescription>
          </EmptyHeader>
        </Empty>
      ) : (
        <ul className="flex flex-col divide-y">
          {onTeam.map((person) => (
            <li
              key={person.userId}
              className="flex items-center justify-between gap-3 py-2"
            >
              <div className="flex min-w-0 items-center gap-3">
                <Avatar className="size-8">
                  {person.avatarUrl ? (
                    <AvatarImage src={person.avatarUrl} alt="" />
                  ) : null}
                  <AvatarFallback>
                    {initials(person.name, person.email)}
                  </AvatarFallback>
                </Avatar>
                <div className="grid min-w-0 leading-tight">
                  <Link
                    href={`/settings/members/${person.userId}`}
                    className="truncate text-sm font-medium hover:underline"
                  >
                    {label(person)}
                  </Link>
                  <span className="truncate text-xs text-muted-foreground">
                    {person.email}
                  </span>
                </div>
              </div>
              {canManage ? (
                <Button
                  variant="ghost"
                  size="icon-sm"
                  aria-label={t("Take {name} off the team", {
                    name: label(person),
                  })}
                  onClick={() => {
                    toggle(person.userId, false);
                  }}
                >
                  <UserMinusIcon />
                </Button>
              ) : null}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
