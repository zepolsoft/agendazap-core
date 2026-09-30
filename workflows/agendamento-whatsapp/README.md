# Agendamento via WhatsApp (Supabase)

Cópia adaptada do workflow de produção `automacao-pmes-whatsapp/workflows/agendamento`, com a
camada de dados trocada de Google Sheets para Postgres/Supabase. Lógica de negócio, AI Agent e
prompt **não foram alterados** — veja `docs/migracao-supabase.md` na raiz do repo para o
detalhamento completo do que mudou, node a node, e as decisões em aberto.

**Faz:** processa mensagens do WhatsApp a qualquer momento — interpreta agendar/remarcar/
cancelar/consultar/dúvida via IA, checa disponibilidade real no Google Calendar do profissional
ativo, efetiva a ação no Postgres (tabela `agendamentos`) e responde o cliente.

**Na instância n8n:** workflow `ny0fqlw8ojzmId7C`, criado **desativado**, com as credenciais reais
da instância já vinculadas (no JSON deste repo elas ficam como placeholder ou omitidas) e Error
Workflow apontando para o "Notificação de Erros" de produção. Não ativar enquanto o trigger for o
do WhatsApp: a ativação registra o webhook na Meta.

**Antes de importar no n8n:**
1. Rode `db/001_initial_schema.sql` e `db/002_seed_exemplo.sql` (na raiz do repo) no seu projeto
   Supabase, se ainda não tiver rodado.
2. Ao importar, troque a credencial Postgres placeholder (`Supabase - agendazap-core`) pela sua
   credencial real em cada node Postgres.
3. Mantenha o workflow **desativado** até validar contra `docs/test-plan.md` do repo de produção.
