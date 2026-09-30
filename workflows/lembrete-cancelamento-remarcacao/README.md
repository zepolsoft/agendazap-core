# Lembrete, Cancelamento e Remarcação (Supabase)

Cópia adaptada do workflow de produção
`automacao-pmes-whatsapp/workflows/lembrete-cancelamento`, com a camada de dados trocada de
Google Sheets para Postgres/Supabase. Lógica de negócio, AI Agents e prompts **não foram
alterados** — veja `docs/migracao-supabase.md` na raiz do repo.

**Faz:** roda todo dia às 8h, busca os agendamentos de hoje no Postgres, envia lembrete por
WhatsApp e trata confirmação/cancelamento/remarcação da resposta do cliente. Também roda às 22h
marcando como `concluido` os agendamentos do dia que já passaram.

**Antes de importar no n8n:** mesmos passos do README de `workflows/agendamento-whatsapp/` —
schema/seed já rodados no Supabase, credencial Postgres trocada em cada node, workflow
desativado até validar.
