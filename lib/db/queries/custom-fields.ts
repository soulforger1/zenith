import "server-only";

import { asc, eq, max } from "drizzle-orm";

import { db } from "@/lib/db";
import { customFields, type CustomFieldType, type FieldOption, type IterationOption } from "@/lib/db/schema";
import { positionAtEnd } from "@/lib/position";

export async function getCustomFieldsForSpace(spaceId: string) {
  return db
    .select()
    .from(customFields)
    .where(eq(customFields.spaceId, spaceId))
    .orderBy(asc(customFields.position), asc(customFields.createdAt));
}

export async function getCustomFieldById(id: string) {
  const [field] = await db.select().from(customFields).where(eq(customFields.id, id)).limit(1);
  return field ?? null;
}

export async function createCustomField(input: {
  spaceId: string;
  key: string;
  name: string;
  type: CustomFieldType;
  options?: FieldOption[] | IterationOption[];
}) {
  const [{ value: maxPosition }] = await db
    .select({ value: max(customFields.position) })
    .from(customFields)
    .where(eq(customFields.spaceId, input.spaceId));

  const [field] = await db
    .insert(customFields)
    .values({
      spaceId: input.spaceId,
      key: input.key,
      name: input.name,
      type: input.type,
      options: input.options ?? [],
      position: positionAtEnd(maxPosition ?? null),
    })
    .returning();
  return field;
}

export async function updateCustomField(
  id: string,
  input: Partial<{
    name: string;
    options: FieldOption[] | IterationOption[];
    position: number;
  }>,
) {
  const [field] = await db
    .update(customFields)
    .set({ ...input, updatedAt: new Date() })
    .where(eq(customFields.id, id))
    .returning();
  return field ?? null;
}

export async function deleteCustomField(id: string) {
  await db.delete(customFields).where(eq(customFields.id, id));
}
