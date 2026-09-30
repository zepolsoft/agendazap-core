---
name: n8n-workflow-builder
description: Como estruturar e criar workflows n8n via MCP neste projeto (agendazap-core)
---

# n8n Workflow Builder

Como criar/editar workflows n8n via MCP para este projeto. Mesma base do projeto de produção
(`automacao-pmes-whatsapp`), com o acréscimo dos nodes de Postgres/Supabase.

## Antes de escrever qualquer workflow

1. Chamar `get_workflow_sdk_reference` — nunca adivinhar sintaxe do SDK.
2. Chamar `get_workflow_best_practices` para cada técnica relevante (ex.: "scheduling",
   "chatbot", "triage", "database") antes de decidir nodes/padrões.
3. Chamar `search_nodes` para descobrir os nodes necessários (WhatsApp, Google Calendar,
   **Postgres**, AI Agent, Switch, Wait, Cron/Schedule Trigger etc.).
4. Chamar `get_node_types` com todos os node IDs escolhidos (incluindo discriminators de
   resource/operation/mode) antes de escrever parâmetros — nunca adivinhar nomes de parâmetro.
   Isso vale especialmente para o node Postgres: a forma exata de passar parâmetros
   (`$1, $2...`) e o nome do campo de credencial variam entre versões — confira sempre antes de
   editar.
5. Para valores de resource locator/load-options (ex.: seletor de calendário, credencial
   Postgres), usar `explore_node_resources` em vez de inventar IDs.

## Estrutura no repo

- Cada workflow criado/editado via MCP vive em `workflows/<nome-do-workflow>/`.
- Depois de criar/editar o workflow na instância n8n, sempre exportar o JSON atualizado
  para essa pasta (ex.: `workflows/agendamento-whatsapp/agendamento.json`).
- Cada pasta de workflow tem um `README.md` curto explicando o que o workflow faz, o
  trigger, as integrações usadas, e — por serem cópias adaptadas de produção — o que mudou em
  relação à versão original (ver `docs/migracao-supabase.md`).

## Banco de dados (Postgres/Supabase)

- Nunca escrever SQL com valor do cliente concatenado direto na string — sempre usar parâmetros
  (`$1, $2...`).
- Ao ler dados que alimentam um node de Code já existente, usar `AS` na query para bater com os
  nomes de campo que o Code espera (ver `n8n-node-conventions`).
- Antes de alterar uma query que mexe em `agendamentos`, `profissionais` ou `servicos`, reler
  `db/001_initial_schema.sql` — em especial a exclusion constraint `agendamentos_sem_conflito`,
  que já impede double-booking no banco (não precisa reimplementar essa checagem em Code).
- Testar queries novas primeiro direto no SQL Editor do Supabase (ou num Postgres local) antes de
  colocar no node, igual ao que já foi feito para validar o schema inicial.

## Credenciais

- Usar a credencial Postgres real já configurada na instância n8n ao editar workflows de
  verdade. Nos JSONs commitados neste repo, deixar como credencial placeholder
  (`Supabase - agendazap-core`) — nunca commitar credenciais reais, nem tokens/chaves de API.
- Mesma regra para WhatsApp e Google Calendar: credenciais fictícias/placeholder nos JSONs.

## Validação

- Depois de montar ou editar o workflow, rodar `validate_workflow` (e `validate_node_config`
  para nodes críticos, especialmente os de Postgres) antes de considerar o workflow pronto.
