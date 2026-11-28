"use client";

// error.tsx do grupo do portal: estado de erro acionável em pt-BR.
import { ErrorState } from "@/components/ui";

export default function PortalError({ reset }: { reset: () => void }) {
  return (
    <ErrorState
      title="Não foi possível exibir esta área"
      description="Ocorreu um erro inesperado ao carregar o conteúdo."
    >
      <button type="button" onClick={reset}>
        Tentar de novo
      </button>
    </ErrorState>
  );
}
