"use client";

import { SearchIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useEffect, useRef, useState } from "react";

import {
  InputGroup,
  InputGroupAddon,
  InputGroupInput,
} from "@/components/ui/input-group";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

import type { RecordListSort } from "./record-list-types";

const SEARCH_WAIT = 250;

/** A search box that follows typing at once and writes the URL after a pause. */
function SearchInput({
  value,
  label,
  onSearch,
}: {
  value: string;
  label: string;
  onSearch: (value: string) => void;
}) {
  const [text, setText] = useState(value);
  const [seen, setSeen] = useState(value);
  const [written, setWritten] = useState(value);
  const timer = useRef<ReturnType<typeof setTimeout>>(undefined);

  if (value !== seen) {
    setSeen(value);

    if (value !== written) {
      setWritten(value);
      setText(value);
    }
  }

  useEffect(
    () => () => {
      clearTimeout(timer.current);
    },
    [],
  );

  return (
    <InputGroup className="w-full max-w-sm">
      <InputGroupAddon>
        <SearchIcon />
      </InputGroupAddon>
      <InputGroupInput
        type="search"
        value={text}
        placeholder={label}
        aria-label={label}
        onChange={(event) => {
          const next = event.target.value;
          setText(next);
          clearTimeout(timer.current);

          timer.current = setTimeout(() => {
            setWritten(next);
            onSearch(next);
          }, SEARCH_WAIT);
        }}
      />
    </InputGroup>
  );
}

/** Search, facet filters and the sort of a list. Every control writes the URL. */
export function RecordListToolbar({
  q,
  searchLabel,
  sort,
  sorts,
  filters,
  onSearch,
  onSort,
}: {
  q: string;
  searchLabel: string;
  sort: string;
  sorts: readonly RecordListSort[];
  filters: React.ReactNode;
  onSearch: (value: string) => void;
  onSort: (value: string) => void;
}) {
  const t = useExtracted("recordList");

  return (
    <search className="flex flex-wrap items-center gap-2">
      <SearchInput value={q} label={searchLabel} onSearch={onSearch} />
      {filters}
      {sorts.length > 1 ? (
        <Select
          value={sort}
          items={sorts}
          onValueChange={(value) => {
            if (value !== null) {
              onSort(value);
            }
          }}
        >
          <SelectTrigger className="ml-auto w-44" aria-label={t("Sort by")}>
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {sorts.map((item) => (
              <SelectItem key={item.value} value={item.value}>
                {item.label}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      ) : null}
    </search>
  );
}
