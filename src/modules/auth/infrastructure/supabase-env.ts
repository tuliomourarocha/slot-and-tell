// Infrastructure — variáveis de ambiente do Supabase, validadas na borda.
// Chamadas apenas em runtime de request (nunca no topo de um Server Component
// estático), para o build não depender de .env.local.
// `process.env` é acessado como global (sem import de node:process), para o
// arquivo poder ser bundlado em qualquer runtime sem erro estático.
export interface SupabaseEnv {
  url: string;
  publishableKey: string;
}

export function readSupabaseEnv(): SupabaseEnv {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const publishableKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  if (!url || !publishableKey) {
    throw new Error(
      "Variáveis NEXT_PUBLIC_SUPABASE_URL e NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY são obrigatórias (copie .env.example para .env.local).",
    );
  }
  return { url, publishableKey };
}
