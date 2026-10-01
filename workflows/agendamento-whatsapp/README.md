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

> ⚠️ **Trigger temporário (desde a rodada 13, só durante o Grupo B).** O WhatsApp Trigger
> "Receber Mensagem WhatsApp" foi trocado por:
> - **"Receber Mensagem (Webhook Temporário)"**: Webhook `POST` com path aleatório, que responde
>   200 na hora (`responseMode: onReceived`);
> - **"Extrair Mensagem do Webhook"**: Set que repassa só o `body`.
>
> O `body` esperado tem o mesmo shape que o WhatsApp Trigger entregava: `messaging_product`,
> `metadata`, `contacts` e `messages`. Não é o envelope bruto da Meta (`entry[].changes[].value`).
>
> "Encaminhar Mensagem para Lembrete" passou a ler do Set. Nenhum outro node mudou.
>
> O path real do Webhook fica **só na instância**: o repo é público, então no JSON ele aparece como
> `SUBSTITUA_PELO_PATH_ALEATORIO`. Ao reimportar este JSON, gere um path aleatório novo.
>
> O workflow continua **desativado**. Ele só é publicado durante os cenários 23 e 29, numa janela
> curta e monitorada (`docs/test-plan.md`). **Antes de qualquer cutover**, reverta a troca
> seguindo o checklist "Reverter o trigger temporário" em `docs/migracao-supabase.md`.

> **Diferença de comportamento em relação à produção (rodada 15):** a espera de lembrete é
> checada **antes** do lock do telefone (dedup → espera → lock). Uma resposta ao lembrete é
> encaminhada mesmo que chegue menos de 10 s depois de outra mensagem do cliente. Ver
> `docs/migracao-supabase.md`, seção 6.

**Antes de importar no n8n:**
1. Rode `db/001_initial_schema.sql` e `db/002_seed_exemplo.sql` (na raiz do repo) no seu projeto
   Supabase, se ainda não tiver rodado.
2. Ao importar, troque a credencial Postgres placeholder (`Supabase - agendazap-core`) pela sua
   credencial real em cada node Postgres.
3. Mantenha o workflow **desativado** até validar contra `docs/test-plan.md` do repo de produção.
