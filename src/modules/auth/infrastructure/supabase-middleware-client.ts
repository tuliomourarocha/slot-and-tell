// Infrastructure — cliente Supabase para o middleware (runtime Edge, sem
// next/headers). Padrão @supabase/ssr: grava cookies atualizados no request
// (para o downstream) e os acumula em `jar` para reemissão na resposta,
// inclusive em redirects.
import { createServerClient } from "@supabase/ssr";
import type { CookieOptions } from "@supabase/ssr";
import type { NextRequest } from "next/server";

import type { Database } from "./database.types";
import { readSupabaseEnv } from "./supabase-env";

export interface MiddlewareCookieJar {
  writes: Array<{ name: string; value: string; options: CookieOptions | undefined }>;
}

export function createSupabaseMiddlewareClient(request: NextRequest, jar: MiddlewareCookieJar) {
  const { url, publishableKey } = readSupabaseEnv();
  return createServerClient<Database>(
    url,
    publishableKey,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          for (const { name, value } of cookiesToSet) {
            request.cookies.set(name, value);
          }
          jar.writes.push(...cookiesToSet);
        },
      },
    },
  );
}
