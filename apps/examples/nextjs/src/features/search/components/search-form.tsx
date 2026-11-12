"use client";

import { SearchIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useSearchParams } from "next/navigation";
import { useEffect, useRef, useState, useTransition } from "react";

import {
  InputGroup,
  InputGroupAddon,
  InputGroupInput,
} from "@/components/ui/input-group";
import { Skeleton } from "@/components/ui/skeleton";
import { Spinner } from "@/components/ui/spinner";
import { useRouter } from "@/i18n/navigation";

/**
 * The query box of `/search`. Typing writes `?q=` after a pause and keeps the
 * chosen type; the server renders the rows again in a transition, so the page
 * frame stays and only the results suspend.
 */
export function SearchForm() {
  const t = useExtracted("search");
  const router = useRouter();
  const params = useSearchParams();
  const type = params.get("type") ?? undefined;
  const initial = params.get("q") ?? "";
  const [value, setValue] = useState(() => initial);
  const [pending, startTransition] = useTransition();
  const timer = useRef<ReturnType<typeof setTimeout>>(undefined);

  useEffect(
    () => () => {
      clearTimeout(timer.current);
    },
    [],
  );

  const write = (next: string) => {
    const query = new URLSearchParams();

    if (next.trim() !== "") {
      query.set("q", next);
    }

    if (type !== undefined && next.trim() !== "") {
      query.set("type", type);
    }

    const search = query.toString();

    startTransition(() => {
      router.replace(search === "" ? "/search" : `/search?${search}`);
    });
  };

  return (
    <InputGroup className="max-w-xl">
      <InputGroupInput
        type="search"
        value={value}
        onChange={(event) => {
          const next = event.target.value;
          setValue(next);
          clearTimeout(timer.current);

          timer.current = setTimeout(() => {
            write(next);
          }, 250);
        }}
        placeholder={t("Search every record you can read")}
        aria-label={t("Search every record you can read")}
      />
      <InputGroupAddon>
        {pending ? <Spinner /> : <SearchIcon />}
      </InputGroupAddon>
    </InputGroup>
  );
}

export function SearchFormSkeleton() {
  return <Skeleton className="h-8 w-full max-w-xl" />;
}
