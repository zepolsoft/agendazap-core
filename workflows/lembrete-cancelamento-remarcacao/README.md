# Lembrete, Cancelamento e Remarcação (Supabase)

Cópia adaptada do workflow de produção
`automacao-pmes-whatsapp/workflows/lembrete-cancelamento`, com a camada de dados trocada de
Google Sheets para Postgres/Supabase. Lógica de negócio, AI Agents e prompts **não foram
alterados** — veja `docs/migracao-supabase.md` na raiz do repo.

**Faz:** roda todo dia às 8h, busca os agendamentos de hoje no Postgres, envia lembrete por
WhatsApp e trata confirmação/cancelamento/remarcação da resposta do cliente. Também roda às 22h
marcando como `concluido` os agendamentos do dia que já passaram.

> **Diferença de comportamento em relação à produção (rodada 15):** depois de cada resposta do
> cliente (Wait retomado), o workflow relê o `status` do agendamento. Se ele não estiver mais
> `agendado`/`remarcado` (por exemplo, cancelado por outro canal durante a espera), avisa o cliente
> e não mexe no Calendar nem no banco. Os `UPDATE`s também exigem esse status. Ver
> `docs/migracao-supabase.md`, seção 6.

**Na instância n8n:** workflow `0mPYXZesloutZbek`, criado **desativado**, com as credenciais reais
da instância já vinculadas (no JSON deste repo elas ficam como placeholder ou omitidas) e Error
Workflow apontando para o "Notificação de Erros" de produção.

**Antes de importar no n8n:** mesmos passos do README de `workflows/agendamento-whatsapp/` —
schema/seed já rodados no Supabase, credencial Postgres trocada em cada node, workflow
desativado até validar.
