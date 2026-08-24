import { z } from "zod";

import { isIsoInstant } from "./temporal-validation.js";

const opaqueIdentifierSchema = z.string().min(1);
const safeNonnegativeIntegerSchema = z
  .number()
  .int()
  .min(0)
  .max(Number.MAX_SAFE_INTEGER);
const safePositiveIntegerSchema = safeNonnegativeIntegerSchema.min(1);
const isoInstantSchema = z.string().refine(isIsoInstant, {
  message: "Expected a valid ISO 8601 instant with a UTC offset.",
});

export const appleBridgePermissionCategorySchema = z.enum([
  "notDetermined",
  "denied",
  "restricted",
  "granted",
  "unavailable",
]);

export const appleBridgeSourceDeliveryStatusSchema = z.enum([
  "idle",
  "applied",
  "unchangedDuplicate",
  "blockedTruncated",
  "blockedInvalid",
  "operatorActionStale",
  "operatorActionConflict",
  "retryPending",
  "permissionUnavailable",
  "sourceUnavailable",
]);

export const appleBridgeSelectedSourceStatusV1Schema = z
  .object({
    entityType: z.enum(["calendar", "reminder"]),
    sourceContainerId: opaqueIdentifierSchema,
    status: appleBridgeSourceDeliveryStatusSchema,
    acknowledgedSourceRevision: safeNonnegativeIntegerSchema,
    pendingSourceRevision: safePositiveIntegerSchema.optional(),
    lastAttemptedAt: isoInstantSchema.optional(),
    lastAcknowledgedAt: isoInstantSchema.optional(),
  })
  .strict()
  .superRefine((value, context) => {
    const hasPending = value.pendingSourceRevision !== undefined;
    const pendingRequired = new Set([
      "blockedTruncated",
      "operatorActionStale",
      "operatorActionConflict",
      "retryPending",
    ]).has(value.status);
    const pendingForbidden = new Set([
      "idle",
      "applied",
      "unchangedDuplicate",
      "permissionUnavailable",
      "sourceUnavailable",
    ]).has(value.status);

    if (
      hasPending &&
      value.pendingSourceRevision !== value.acknowledgedSourceRevision + 1
    ) {
      context.addIssue({
        code: "custom",
        path: ["pendingSourceRevision"],
        message:
          "A pending source revision must immediately follow the acknowledged revision.",
      });
    }
    if (pendingRequired && !hasPending) {
      context.addIssue({
        code: "custom",
        path: ["pendingSourceRevision"],
        message: "This delivery status requires a pending source revision.",
      });
    }
    if (pendingForbidden && hasPending) {
      context.addIssue({
        code: "custom",
        path: ["pendingSourceRevision"],
        message: "This delivery status cannot carry a pending source revision.",
      });
    }
    if (hasPending && value.lastAttemptedAt === undefined) {
      context.addIssue({
        code: "custom",
        path: ["lastAttemptedAt"],
        message: "A pending delivery must record an attempted instant.",
      });
    }
    if (
      value.acknowledgedSourceRevision === 0 &&
      value.lastAcknowledgedAt !== undefined
    ) {
      context.addIssue({
        code: "custom",
        path: ["lastAcknowledgedAt"],
        message: "Revision zero cannot have an acknowledged instant.",
      });
    }
    if (
      value.acknowledgedSourceRevision > 0 &&
      value.lastAcknowledgedAt === undefined
    ) {
      context.addIssue({
        code: "custom",
        path: ["lastAcknowledgedAt"],
        message: "An acknowledged source revision requires its instant.",
      });
    }
    if (
      (value.status === "applied" ||
        value.status === "unchangedDuplicate") &&
      (value.acknowledgedSourceRevision === 0 ||
        value.lastAttemptedAt === undefined)
    ) {
      context.addIssue({
        code: "custom",
        message:
          "A successful delivery status requires an acknowledged revision and attempted instant.",
      });
    }
    if (
      value.status === "idle" &&
      (value.acknowledgedSourceRevision !== 0 ||
        value.lastAttemptedAt !== undefined ||
        value.lastAcknowledgedAt !== undefined)
    ) {
      context.addIssue({
        code: "custom",
        message: "An idle selected source cannot carry delivery history.",
      });
    }
  });

function compareUnicodeScalars(left: string, right: string): number {
  const leftScalars = Array.from(left, (value) => value.codePointAt(0) ?? 0);
  const rightScalars = Array.from(right, (value) => value.codePointAt(0) ?? 0);
  const sharedLength = Math.min(leftScalars.length, rightScalars.length);

  for (let index = 0; index < sharedLength; index += 1) {
    const leftValue = leftScalars[index] ?? 0;
    const rightValue = rightScalars[index] ?? 0;
    if (leftValue !== rightValue) {
      return leftValue < rightValue ? -1 : 1;
    }
  }

  return leftScalars.length < rightScalars.length
    ? -1
    : leftScalars.length > rightScalars.length
      ? 1
      : 0;
}

export type AppleBridgeSelectedSourceStatusV1 = z.infer<
  typeof appleBridgeSelectedSourceStatusV1Schema
>;

export function compareAppleBridgeSelectedSourcesV1(
  left: AppleBridgeSelectedSourceStatusV1,
  right: AppleBridgeSelectedSourceStatusV1,
): number {
  const entityComparison = compareUnicodeScalars(
    left.entityType,
    right.entityType,
  );
  return entityComparison !== 0
    ? entityComparison
    : compareUnicodeScalars(left.sourceContainerId, right.sourceContainerId);
}

export const appleBridgeStatusSnapshotV1Schema = z
  .object({
    schemaVersion: z.literal(1),
    bridgeId: opaqueIdentifierSchema,
    statusRevision: safePositiveIntegerSchema,
    capturedAt: isoInstantSchema,
    permissions: z
      .object({
        calendar: appleBridgePermissionCategorySchema,
        reminders: appleBridgePermissionCategorySchema,
      })
      .strict(),
    selectedSources: z.array(appleBridgeSelectedSourceStatusV1Schema),
  })
  .strict()
  .superRefine((value, context) => {
    const capturedAt = Date.parse(value.capturedAt);
    for (const [index, source] of value.selectedSources.entries()) {
      for (const field of ["lastAttemptedAt", "lastAcknowledgedAt"] as const) {
        const instant = source[field];
        if (instant !== undefined && Date.parse(instant) > capturedAt) {
          context.addIssue({
            code: "custom",
            path: ["selectedSources", index, field],
            message: "A source status instant cannot be later than capture.",
          });
        }
      }
    }

    for (let index = 1; index < value.selectedSources.length; index += 1) {
      const previous = value.selectedSources[index - 1];
      const current = value.selectedSources[index];
      if (!previous || !current) {
        continue;
      }
      const comparison = compareAppleBridgeSelectedSourcesV1(
        previous,
        current,
      );
      if (comparison > 0) {
        context.addIssue({
          code: "custom",
          path: ["selectedSources", index],
          message: "Selected source coordinates are not deterministically ordered.",
        });
      } else if (comparison === 0) {
        context.addIssue({
          code: "custom",
          path: ["selectedSources", index],
          message: "Selected source coordinates must be unique.",
        });
      }
    }
  });

export type AppleBridgePermissionCategory = z.infer<
  typeof appleBridgePermissionCategorySchema
>;
export type AppleBridgeSourceDeliveryStatus = z.infer<
  typeof appleBridgeSourceDeliveryStatusSchema
>;
export type AppleBridgeStatusSnapshotV1 = z.infer<
  typeof appleBridgeStatusSnapshotV1Schema
>;

export function parseAppleBridgeStatusSnapshotV1(
  input: unknown,
): AppleBridgeStatusSnapshotV1 {
  return appleBridgeStatusSnapshotV1Schema.parse(input);
}
