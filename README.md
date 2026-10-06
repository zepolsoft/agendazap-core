# AgendaZap Core

Novo projeto de automação de agendamento via WhatsApp, usando **Supabase
(PostgreSQL)** como camada de dados no lugar das planilhas Google Sheets.

> **Importante:** este projeto é separado e independente da versão atual em
> produção (baseada em Google Sheets), que continua intacta e funcionando.
> A ideia aqui é validar uma nova versão, com banco relacional e suporte a
> múltiplos calendários (um Google Calendar por profissional), antes de
> qualquer eventual migração.

## Estrutura

```
agendazap-core/
├── .claude/skills/
│   ├── n8n-node-conventions/SKILL.md
│   ├── n8n-workflow-builder/SKILL.md
│   └── whatsapp-message-style/SKILL.md
├── db/
│   ├── 001_initial_schema.sql   # schema inicial (tabelas, enums, triggers, constraint anti-conflito)
│   └── 002_seed_exemplo.sql     # dados de exemplo para testes (2 profissionais + serviços)
├── docs/
│   ├── arquitetura.md            # visão geral da arquitetura e decisões de design
│   ├── migracao-supabase.md      # mapeamento node a node da migração + decisões em aberto
│   └── test-plan.md              # roteiro de testes (adaptado do repo de produção)
├── prompts/
│   ├── agendamento-interpretar-intencao.md
│   └── lembrete-classificar-resposta.md
├── workflows/
│   ├── agendamento-whatsapp/                  # export do workflow n8n "Agendamento via WhatsApp"
│   ├── lembrete-cancelamento-remarcacao/      # export do workflow n8n "Lembrete, Cancelamento e Remarcação"
│   └── notificacao-erros/                     # export do workflow n8n "Notificação de Erros"
└── CLAUDE.md                     # contexto do projeto para o Claude Code
```

## Banco de dados

- **Supabase (PostgreSQL)**, com 4 tabelas: `profissionais`, `servicos`,
  `profissionais_servicos` (N:N) e `agendamentos`.
- Prevenção de conflito de horário (double-booking) garantida no próprio
  banco via `exclusion constraint` (GiST), não apenas na lógica do workflow.
- `profissionais.google_calendar_id` permite um Google Calendar por
  profissional (multi-calendar).

Veja `db/001_initial_schema.sql` para o schema completo e comentado.

## Workflows (n8n)

Os JSONs em `workflows/` são cópias adaptadas dos 3 workflows já em produção no repo
[`automacao-pmes-whatsapp`](https://github.com/zepolsoft/automacao-pmes-whatsapp), prontas para
importar no n8n (desativadas):

1. **[Agendamento via WhatsApp](workflows/agendamento-whatsapp/)**
2. **[Lembrete, Cancelamento e Remarcação](workflows/lembrete-cancelamento-remarcacao/)**
3. **[Notificação de Erros](workflows/notificacao-erros/)** — sem alteração (não usa Sheets/Calendar)

### Importar um JSON no n8n (substituir os placeholders)

Os JSONs do repositório são **sanitizados**: o repo é público, então telefone, IDs e e-mails reais não
ficam nele. Antes de importar, troque os placeholders pelos seus valores:

1. `cp .env.example .env.local` e preencha o `.env.local` (ele está no `.gitignore`; nunca commite).
2. Gere uma cópia pronta para importar, fora do repositório:
   `python3 scripts/preparar_json.py workflows/<pasta>/<arquivo>.json > /tmp/importar.json`
   O script troca `<PHONE_NUMBER_ID>`, `<RESPONSAVEL_PHONE>`, `<EMAIL_REMETENTE>`, `<EMAIL_RESPONSAVEL>`
   e `<ID_DO_WORKFLOW_NOTIFICACAO_DE_ERROS>` e avisa se faltar algum valor.
3. No n8n: Workflows → Import from File → `/tmp/importar.json`. Importe primeiro a **Notificação de
   Erros** e use o ID dela (veja na URL) em `ID_DO_WORKFLOW_NOTIFICACAO_DE_ERROS` ao preparar os demais.
4. Depois de importar, reabra cada node com credencial e selecione a sua (Postgres, Google Calendar,
   WhatsApp, Anthropic, SMTP). Os `SUBSTITUA_PELO_ID_DA_CREDENCIAL` e os `webhookId`
   (`SUBSTITUA_PELO_WEBHOOK_ID_*`) **não** vão no `.env.local`: o n8n gera o `webhookId` ao importar e
   as credenciais reais ficam só na instância.
5. Apague o `/tmp/importar.json` quando terminar, e **não** reexporte um workflow real para o repo sem
   antes trocar os valores de volta pelos placeholders (e rodar uma busca por telefone e IDs).

As regras de negócio e os prompts da IA foram mantidos 100% intactos; só os nós de dados (Google
Sheets → Postgres, Google Calendar apontando para um calendário fixo → calendário dinâmico por
profissional) foram trocados. Veja **[`docs/migracao-supabase.md`](docs/migracao-supabase.md)**
para o mapeamento completo node a node, o que foi preservado, e uma decisão em aberto sobre nomes
de serviço que precisa de definição antes de ir para produção.
