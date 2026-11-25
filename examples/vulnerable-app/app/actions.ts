"use server";
import { db } from "@/lib/db";

// Server Actions are public POST endpoints. This one has no session check.
export async function deleteProject(projectId: string) {
  await db.project.delete({ where: { id: projectId } });
}
