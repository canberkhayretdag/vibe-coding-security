"use client";
import OpenAI from "openai";

// Runs in the browser. The key ends up in the JS bundle.
export const openai = new OpenAI({
  apiKey: process.env.NEXT_PUBLIC_OPENAI_API_KEY,
  dangerouslyAllowBrowser: true,
});
