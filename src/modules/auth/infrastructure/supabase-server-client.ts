// Infrastructure — cliente Supabase do lado do servidor (Server Components,
// Server Actions e Route Handlers). Sessão vive em cookies via @supabase/ssr.
import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";

import type { Database } from "./database.types";
import { readSupabaseEnv } from "./supabase-env";

export async function createSupabaseServerClient() {
  const cookieStore = await cookies();
  // Env validado DEPOIS do acesso a cookies: em prerender, o acesso a cookies
  // sinaliza a página como dinâmica antes de qualquer erro de configuração.
  const { url, publishableKey } = readSupabaseEnv();

  return createServerClient<Database>(url, publishableKey, {
    cookies: {
      getAll() {
        return cookieStore.getAll();
      },
      setAll(cookiesToSet) {
        try {
          for (const { name, value, options } of cookiesToSet) {
            cookieStore.set(name, value, options);
          }
        } catch {
          // Server Components não podem gravar cookies; o refresh de sessão
          // nesses casos fica a cargo do middleware (arquivo: src/middleware.ts).
        }
      },
    },
  });
}
