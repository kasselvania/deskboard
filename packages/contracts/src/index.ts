import { z } from "zod";

import {
  isCalendarDate,
  isIsoInstant,
  isLocalDateTime,
} from "./temporal-validation.js";

export {
  isCalendarDate,
  isIsoInstant,
  isLocalDateTime,
} from "./temporal-validation.js";
export * from "./apple-source-contract.js";
export * from "./apple-bridge-status.js";

// These limits keep the wire document display-ready. Titles and labels stay
// compact enough for the reference Board, while reasons and the prompt retain
// room for a concise human explanation rather than becoming generic notes.
export const BOARD_TEXT_LIMITS = {
  id: 96,
  boardVersion: 64,
  title: 72,
  reason: 120,
  whenLabel: 48,
  sidewaysPrompt: 160,
  timeZone: 128,
} as const;

function boundedTextSchema(maxLength: number) {
  return z.string().trim().min(1).max(maxLength);
}

const idSchema = boundedTextSchema(BOARD_TEXT_LIMITS.id);
const boardVersionSchema = boundedTextSchema(BOARD_TEXT_LIMITS.boardVersion);
const titleSchema = boundedTextSchema(BOARD_TEXT_LIMITS.title);
const reasonSchema = boundedTextSchema(BOARD_TEXT_LIMITS.reason);
const whenLabelSchema = boundedTextSchema(BOARD_TEXT_LIMITS.whenLabel);
const sidewaysPromptTextSchema = boundedTextSchema(
  BOARD_TEXT_LIMITS.sidewaysPrompt,
);
const timeZoneSchema = boundedTextSchema(BOARD_TEXT_LIMITS.timeZone);
const calendarDateSchema = z.string().refine(isCalendarDate, {
  message: "Expected a real calendar date in YYYY-MM-DD form.",
});
const localDateTimeSchema = z.string().refine(isLocalDateTime, {
  message: "Expected a real local date-time without a UTC offset.",
});
const isoInstantSchema = z.string().refine(isIsoInstant, {
  message: "Expected a valid ISO 8601 instant with a UTC offset.",
});

export const dateOnlySchema = z
  .object({
    kind: z.literal("date"),
    localDate: calendarDateSchema,
  })
  .strict();

export const timedValueSchema = z
  .object({
    kind: z.literal("dateTime"),
    localDateTime: localDateTimeSchema,
    timeZone: timeZoneSchema.nullable(),
  })
  .strict();

export const allDayValueSchema = z
  .object({
    kind: z.literal("allDay"),
    startDate: calendarDateSchema,
    endDate: calendarDateSchema,
  })
  .strict();

export const sourceFreshnessSchema = z
  .object({
    status: z.enum(["fixture", "fresh", "stale", "unavailable"]),
    updatedAt: isoInstantSchema.nullable(),
  })
  .strict();

export const taskItemSchema = z
  .object({
    id: idSchema,
    kind: z.literal("task"),
    title: titleSchema,
    reason: reasonSchema,
    whenLabel: whenLabelSchema.optional(),
    temporal: z.union([dateOnlySchema, timedValueSchema]).optional(),
  })
  .strict();

export const commitmentItemSchema = z
  .object({
    id: idSchema,
    kind: z.literal("commitment"),
    title: titleSchema,
    reason: reasonSchema,
    whenLabel: whenLabelSchema,
    temporal: z.union([timedValueSchema, allDayValueSchema]),
  })
  .strict();

const schemaVersionSchema = z
  .number()
  .int()
  .superRefine((value, context) => {
    if (value !== 1) {
      context.addIssue({
        code: "custom",
        message: `Unsupported schemaVersion ${value}; expected 1.`,
      });
    }
  })
  .transform(() => 1 as const);

export const boardSnapshotSchema = z
  .object({
    schemaVersion: schemaVersionSchema,
    boardVersion: boardVersionSchema,
    generatedAt: isoInstantSchema,
    freshness: z
      .object({
        reminders: sourceFreshnessSchema,
        calendar: sourceFreshnessSchema,
      })
      .strict(),
    today: z
      .object({
        label: z.literal("Today"),
        items: z.array(taskItemSchema).max(3),
      })
      .strict(),
    next: z
      .object({
        label: z.literal("Next"),
        items: z.array(commitmentItemSchema).max(2),
      })
      .strict(),
    sidewaysPrompt: z
      .object({
        label: z.literal("Sideways"),
        text: sidewaysPromptTextSchema,
      })
      .strict()
      .optional(),
  })
  .strict();

export type DateOnly = z.infer<typeof dateOnlySchema>;
export type TimedValue = z.infer<typeof timedValueSchema>;
export type AllDayValue = z.infer<typeof allDayValueSchema>;
export type SourceFreshness = z.infer<typeof sourceFreshnessSchema>;
export type TaskItem = z.infer<typeof taskItemSchema>;
export type CommitmentItem = z.infer<typeof commitmentItemSchema>;
export type BoardSnapshot = z.infer<typeof boardSnapshotSchema>;

export function parseBoardSnapshot(input: unknown): BoardSnapshot {
  return boardSnapshotSchema.parse(input);
}
