import "server-only";

import { createCustomField, updateCustomField } from "@/lib/db/queries/custom-fields";
import { customFieldTypeValues, type CustomFieldType, type FieldOption, type IterationOption } from "@/lib/db/schema";
import { fieldColorValues } from "@/lib/fields/colors";
import { slugify } from "@/lib/slug";

export type CustomFieldRow = {
  id: string;
  key: string;
  name: string;
  type: string;
  options: FieldOption[] | IterationOption[];
};

export type AiNewField = { key: string; name: string; type: string; options?: string[] };
export type AiFieldValue = { fieldKey: string; value: string };

function isValidType(type: string): type is CustomFieldType {
  return (customFieldTypeValues as readonly string[]).includes(type);
}

function isSelectType(type: CustomFieldType) {
  return type === "single_select" || type === "multi_select";
}

/** Applies the AI's proposed new fields + field values to the space's real
 * custom fields: creates any genuinely-missing field (matched by key,
 * case-insensitive, so a repeat paste never double-creates "Size") and
 * auto-grows select options for values that don't match an existing one —
 * this is the "AI task-creation agent can create necessary fields" behavior,
 * extended naturally to select options too. Mirrors resolveIdByName's role
 * for repo/milestone matching, just with DB writes since fields/options are
 * genuinely new data rather than a fixed set to match against.
 *
 * Returns a ready-to-persist `customFieldValues` map keyed by field id, plus
 * the (possibly grown) field list — including any field/option the AI just
 * created — so the caller can hand fresh field metadata back to the client
 * without a separate refetch. */
export async function resolveAiCustomFields(input: {
  spaceId: string;
  customFields: CustomFieldRow[];
  newFields?: AiNewField[];
  fieldValues?: AiFieldValue[];
}): Promise<{ customFieldValues: Record<string, unknown>; fields: CustomFieldRow[] }> {
  const fields = [...input.customFields];

  function findByKey(key: string) {
    return fields.find((f) => f.key.toLowerCase() === key.toLowerCase());
  }

  for (const proposal of (input.newFields ?? []).slice(0, 3)) {
    if (!proposal.key || !proposal.name || !isValidType(proposal.type)) continue;
    if (findByKey(proposal.key)) continue;

    const options: FieldOption[] = isSelectType(proposal.type)
      ? (proposal.options ?? []).slice(0, 10).map((label, i) => ({
          id: crypto.randomUUID(),
          name: label,
          color: fieldColorValues[i % fieldColorValues.length],
        }))
      : [];

    const created = await createCustomField({
      spaceId: input.spaceId,
      key: slugify(proposal.key) || slugify(proposal.name) || `field-${fields.length + 1}`,
      name: proposal.name,
      type: proposal.type,
      options,
    });
    fields.push({ id: created.id, key: created.key, name: created.name, type: created.type, options: created.options });
  }

  async function resolveOrCreateOptionId(field: CustomFieldRow, label: string): Promise<string | null> {
    const options = field.options as FieldOption[];
    const existing = options.find((o) => o.name.toLowerCase() === label.toLowerCase());
    if (existing) return existing.id;

    const newOption: FieldOption = {
      id: crypto.randomUUID(),
      name: label,
      color: fieldColorValues[options.length % fieldColorValues.length],
    };
    const nextOptions = [...options, newOption];
    await updateCustomField(field.id, { options: nextOptions });
    field.options = nextOptions; // keep the in-memory copy in sync for later lookups in this same request
    return newOption.id;
  }

  const result: Record<string, unknown> = {};

  for (const entry of (input.fieldValues ?? []).slice(0, 10)) {
    const field = findByKey(entry.fieldKey);
    const value = entry.value?.trim();
    if (!field || !value) continue;

    if (field.type === "text") {
      result[field.id] = value;
    } else if (field.type === "number") {
      const n = Number(value);
      if (!Number.isNaN(n)) result[field.id] = n;
    } else if (field.type === "date") {
      if (/^\d{4}-\d{2}-\d{2}$/.test(value)) result[field.id] = value;
    } else if (field.type === "single_select") {
      const id = await resolveOrCreateOptionId(field, value);
      if (id) result[field.id] = id;
    } else if (field.type === "multi_select") {
      const labels = value.split(",").map((v) => v.trim()).filter(Boolean);
      const ids: string[] = [];
      for (const label of labels) {
        const id = await resolveOrCreateOptionId(field, label);
        if (id) ids.push(id);
      }
      if (ids.length > 0) result[field.id] = ids;
    } else if (field.type === "iteration") {
      const opt = (field.options as IterationOption[]).find((o) => o.title.toLowerCase() === value.toLowerCase());
      if (opt) result[field.id] = opt.id;
    }
  }

  return { customFieldValues: result, fields };
}
