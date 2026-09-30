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
├── db/
│   ├── 001_initial_schema.sql   # schema inicial (tabelas, enums, triggers, constraint anti-conflito)
│   └── 002_seed_exemplo.sql     # dados de exemplo para testes (2 profissionais + serviços)
├── workflows/
│   ├── agendamento-whatsapp/                  # export do workflow n8n "Agendamento via WhatsApp"
│   ├── lembrete-cancelamento-remarcacao/      # export do workflow n8n "Lembrete, Cancelamento e Remarcação"
│   └── notificacao-erros/                     # export do workflow n8n "Notificação de Erros"
└── docs/
    └── arquitetura.md            # decisões de arquitetura e notas do projeto
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

Os workflows partem dos 3 workflows já em produção:

1. **Agendamento via WhatsApp**
2. **Lembrete, Cancelamento e Remarcação**
3. **Notificação de Erros**

As regras de negócio e prompts da IA são mantidos; apenas os nós de dados
(Google Sheets/Calendar) são trocados por nós Postgres/Supabase.
