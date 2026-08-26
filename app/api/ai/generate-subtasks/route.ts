import { NextResponse } from "next/server";

import { generateSubtasks } from "@/lib/ai/prompts";
import { generateSubtasksRequestSchema } from "@/lib/ai/schemas";

export const maxDuration = 30;

export async function POST(request: Request) {
  const body = await request.json().catch(() => null);
  const parsed = generateSubtasksRequestSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.issues[0]?.message ?? "Invalid request." }, { status: 400 });
  }

  try {
    const subtasks = await generateSubtasks(parsed.data);
    return NextResponse.json({ subtasks });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Failed to generate subtasks.";
    return NextResponse.json({ error: message }, { status: 502 });
  }
}
