# agendazap-core

Nova versão do backend de agendamento via WhatsApp: os mesmos 3 workflows n8n que já estão em
produção no repo [`automacao-pmes-whatsapp`](https://github.com/zepolsoft/automacao-pmes-whatsapp),
adaptados para usar **Postgres/Supabase** no lugar de Google Sheets, com suporte a múltiplos
profissionais (um Google Calendar por profissional).

> **A versão de produção continua intocada**, em `automacao-pmes-whatsapp`, com suas próprias
> planilhas Google Sheets separadas. Este repo é um projeto novo e independente para validar a
> migração antes de qualquer cutover. Ver `docs/migracao-supabase.md` para o que mudou e por quê.

## Instância n8n

- URL: https://n8n-n8n.wg1izd.easypanel.host (mesma instância de produção — os workflows deste
  repo são importados como cópias **desativadas**, nunca substituem os workflows em produção).
- Todos os workflows são criados/editados via MCP do n8n conectado a essa instância.

## Banco de dados

- Supabase (Postgres). Schema em `db/001_initial_schema.sql`, seed de exemplo em
  `db/002_seed_exemplo.sql`.
- Tabelas: `profissionais`, `servicos`, `profissionais_servicos` (N:N), `agendamentos`.
- Prevenção de double-booking garantida no próprio banco (exclusion constraint GiST), não só na
  lógica do workflow.
- Credencial Postgres no n8n: usar a credencial real já configurada na instância (não recriar
  nem commitar credenciais reais — mesma regra do repo de produção, ver `.gitignore`).

## Convenções

- Nomes de node em português (ex.: "Receber Mensagem WhatsApp", "Verificar Disponibilidade").
- Depois de criar ou editar um workflow via MCP, sempre exportar o JSON resultante para
  `workflows/<nome-do-workflow>/`.
- Nunca commitar credenciais reais. Usar placeholders/fictícias nos JSONs (ex.:
  `Supabase - agendazap-core` como nome de credencial placeholder); credenciais reais ficam só na
  instância n8n.

## O que muda em relação a `automacao-pmes-whatsapp`

- Nodes de **Google Sheets** viram nodes de **Postgres** (`executeQuery`, parâmetros via
  `$1, $2...`), sempre devolvendo colunas com os mesmos nomes que os nodes de Code já esperavam
  (`event_id`, `data`, `servico`, `beneficiario`, etc.) — para não precisar tocar em nenhuma
  lógica de negócio.
- Nodes de **Google Calendar continuam sendo Google Calendar**, mas o calendário passa a ser
  resolvido dinamicamente a partir do profissional ativo (node "Buscar Profissional Ativo"), em
  vez de um calendário fixo — isso é o que viabiliza multi-calendário.
- **AI Agents, prompts e toda a lógica de negócio (nodes de Code) são idênticos** aos de
  produção — não foram alterados nesta migração.
- Ver `docs/migracao-supabase.md` para o mapeamento completo node a node e uma decisão em aberto
  (nome do serviço vs. `servico_id`) que precisa de definição antes de ir pra produção.

## Skills disponíveis

- `n8n-workflow-builder` — como estruturar e criar/editar workflows via MCP neste projeto,
  incluindo os nodes de Postgres.
- `whatsapp-message-style` — tom e formato das mensagens enviadas ao cliente no WhatsApp (idêntico
  ao de produção — o texto que o cliente recebe não muda com a migração de banco).
- `n8n-node-conventions` — nomenclatura e organização dos nodes dentro dos workflows, incluindo a
  convenção para nodes de Postgres.
