/**
 * Public holidays as dated rules over a fixed list of years. A rule is pure
 * arithmetic on the year, so the rows are the same on every build.
 */

/** A date as `[month, day]` (1-based month) plus the year. */
export interface HolidayDate {
  readonly year: number;
  readonly month: number;
  readonly day: number;
}

/** The years every holiday calendar covers. Extending it is a new release. */
export const HOLIDAY_YEARS: readonly number[] = [2026, 2027, 2028, 2029, 2030];

const DAY_MS = 86_400_000;

function fromUtc(ms: number): HolidayDate {
  const date = new Date(ms);

  return {
    year: date.getUTCFullYear(),
    month: date.getUTCMonth() + 1,
    day: date.getUTCDate(),
  };
}

function toUtc(date: HolidayDate): number {
  return Date.UTC(date.year, date.month - 1, date.day);
}

/** `days` after `date`, which may be negative. */
export function addDays(date: HolidayDate, days: number): HolidayDate {
  return fromUtc(toUtc(date) + days * DAY_MS);
}

/** 0 is Sunday, 6 is Saturday. */
export function weekday(date: HolidayDate): number {
  return new Date(toUtc(date)).getUTCDay();
}

/** Easter Sunday of `year` (the Gregorian computus). */
export function easter(year: number): HolidayDate {
  const a = year % 19;
  const b = Math.floor(year / 100);
  const c = year % 100;
  const d = Math.floor(b / 4);
  const e = b % 4;
  const f = Math.floor((b + 8) / 25);
  const g = Math.floor((b - f + 1) / 3);
  const h = (19 * a + b - d - g + 15) % 30;
  const i = Math.floor(c / 4);
  const k = c % 4;
  const l = (32 + 2 * e + 2 * i - h - k) % 7;
  const m = Math.floor((a + 11 * h + 22 * l) / 451);
  const month = Math.floor((h + l - 7 * m + 114) / 31);
  const day = ((h + l - 7 * m + 114) % 31) + 1;

  return { year, month, day };
}

/** The `n`th `day` of the week (0 Sunday) in a month; `n` of -1 is the last. */
export function nthWeekday(
  year: number,
  month: number,
  day: number,
  n: number,
): HolidayDate {
  if (n > 0) {
    const first = weekday({ year, month, day: 1 });

    return { year, month, day: 1 + ((day - first + 7) % 7) + (n - 1) * 7 };
  }

  const last = fromUtc(Date.UTC(year, month, 0));

  return addDays(last, -((weekday(last) - day + 7) % 7));
}

/** One holiday: a stable key, a name and the date in a year. */
export interface HolidayRule {
  readonly key: string;
  readonly name: string;
  readonly on: (year: number) => HolidayDate;
}

const fixed =
  (month: number, day: number) =>
  (year: number): HolidayDate => ({ year, month, day });

const afterEaster =
  (days: number) =>
  (year: number): HolidayDate =>
    addDays(easter(year), days);

const rule = (
  key: string,
  name: string,
  on: (year: number) => HolidayDate,
): HolidayRule => ({ key, name, on });

/** The Monday after a weekend date, as UK substitute days work. */
const monday =
  (month: number, day: number, shift: { sat: number; sun: number }) =>
  (year: number): HolidayDate => {
    const date = { year, month, day };
    const at = weekday(date);

    if (at === 6) {
      return addDays(date, shift.sat);
    }

    return at === 0 ? addDays(date, shift.sun) : date;
  };

/** King's Day moves to the 26th when the 27th is a Sunday. */
const kingsDay = (year: number): HolidayDate => {
  const date = { year, month: 4, day: 27 };

  return weekday(date) === 0 ? addDays(date, -1) : date;
};

/**
 * The public holidays per locale. `nl`, `de` and `fr` are the national days of
 * those countries (Germany: the ones every state observes), `en-gb` the bank
 * holidays of England and Wales with their substitute days, and `en-us` the
 * federal holidays on their actual dates, without the observed weekday shift.
 */
export const HOLIDAYS: Readonly<
  Record<
    string,
    {
      readonly name: string;
      readonly tz: string;
      readonly rules: readonly HolidayRule[];
    }
  >
> = {
  nl: {
    name: "Public holidays (NL)",
    tz: "Europe/Amsterdam",
    rules: [
      rule("new-year", "Nieuwjaarsdag", fixed(1, 1)),
      rule("good-friday", "Goede Vrijdag", afterEaster(-2)),
      rule("easter", "Eerste Paasdag", afterEaster(0)),
      rule("easter-monday", "Tweede Paasdag", afterEaster(1)),
      rule("kings-day", "Koningsdag", kingsDay),
      rule("ascension", "Hemelvaartsdag", afterEaster(39)),
      rule("whit-sunday", "Eerste Pinksterdag", afterEaster(49)),
      rule("whit-monday", "Tweede Pinksterdag", afterEaster(50)),
      rule("christmas", "Eerste Kerstdag", fixed(12, 25)),
      rule("boxing-day", "Tweede Kerstdag", fixed(12, 26)),
    ],
  },
  de: {
    name: "Public holidays (DE)",
    tz: "Europe/Berlin",
    rules: [
      rule("new-year", "Neujahr", fixed(1, 1)),
      rule("good-friday", "Karfreitag", afterEaster(-2)),
      rule("easter-monday", "Ostermontag", afterEaster(1)),
      rule("labour-day", "Tag der Arbeit", fixed(5, 1)),
      rule("ascension", "Christi Himmelfahrt", afterEaster(39)),
      rule("whit-monday", "Pfingstmontag", afterEaster(50)),
      rule("unity-day", "Tag der Deutschen Einheit", fixed(10, 3)),
      rule("christmas", "1. Weihnachtstag", fixed(12, 25)),
      rule("boxing-day", "2. Weihnachtstag", fixed(12, 26)),
    ],
  },
  fr: {
    name: "Public holidays (FR)",
    tz: "Europe/Paris",
    rules: [
      rule("new-year", "Jour de l'An", fixed(1, 1)),
      rule("easter-monday", "Lundi de Pâques", afterEaster(1)),
      rule("labour-day", "Fête du Travail", fixed(5, 1)),
      rule("victory-day", "Victoire 1945", fixed(5, 8)),
      rule("ascension", "Ascension", afterEaster(39)),
      rule("whit-monday", "Lundi de Pentecôte", afterEaster(50)),
      rule("bastille-day", "Fête nationale", fixed(7, 14)),
      rule("assumption", "Assomption", fixed(8, 15)),
      rule("all-saints", "Toussaint", fixed(11, 1)),
      rule("armistice", "Armistice 1918", fixed(11, 11)),
      rule("christmas", "Noël", fixed(12, 25)),
    ],
  },
  "en-gb": {
    name: "Public holidays (GB)",
    tz: "Europe/London",
    rules: [
      rule("new-year", "New Year's Day", monday(1, 1, { sat: 2, sun: 1 })),
      rule("good-friday", "Good Friday", afterEaster(-2)),
      rule("easter-monday", "Easter Monday", afterEaster(1)),
      rule("early-may", "Early May bank holiday", (year) =>
        nthWeekday(year, 5, 1, 1),
      ),
      rule("spring", "Spring bank holiday", (year) =>
        nthWeekday(year, 5, 1, -1),
      ),
      rule("summer", "Summer bank holiday", (year) =>
        nthWeekday(year, 8, 1, -1),
      ),
      rule("christmas", "Christmas Day", monday(12, 25, { sat: 2, sun: 2 })),
      rule("boxing-day", "Boxing Day", monday(12, 26, { sat: 2, sun: 2 })),
    ],
  },
  "en-us": {
    name: "Public holidays (US)",
    tz: "America/New_York",
    rules: [
      rule("new-year", "New Year's Day", fixed(1, 1)),
      rule("mlk-day", "Martin Luther King Jr. Day", (year) =>
        nthWeekday(year, 1, 1, 3),
      ),
      rule("presidents-day", "Presidents' Day", (year) =>
        nthWeekday(year, 2, 1, 3),
      ),
      rule("memorial-day", "Memorial Day", (year) =>
        nthWeekday(year, 5, 1, -1),
      ),
      rule("juneteenth", "Juneteenth", fixed(6, 19)),
      rule("independence-day", "Independence Day", fixed(7, 4)),
      rule("labor-day", "Labor Day", (year) => nthWeekday(year, 9, 1, 1)),
      rule("columbus-day", "Columbus Day", (year) =>
        nthWeekday(year, 10, 1, 2),
      ),
      rule("veterans-day", "Veterans Day", fixed(11, 11)),
      rule("thanksgiving", "Thanksgiving Day", (year) =>
        nthWeekday(year, 11, 4, 4),
      ),
      rule("christmas", "Christmas Day", fixed(12, 25)),
    ],
  },
};
