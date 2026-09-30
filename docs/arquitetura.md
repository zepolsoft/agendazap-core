# Arquitetura

## Visão geral

```
Cliente (WhatsApp)
      │
      ▼
[Buscar Profissional Ativo] ──► Postgres (profissionais): qual calendário usar
      │
      ▼
[Workflow: agendamento-whatsapp]  ──► Google Calendar do profissional (verifica/cria evento)
      │                          ──► Postgres/Supabase (salva agendamento: cliente, serviço,
      ▼                              data, beneficiário, google_event_id)
Resposta no WhatsApp

[Workflow: lembrete-cancelamento-remarcacao]  (roda todo dia às 8h; conclui às 22h)
      │
      ├─► Postgres: agendamentos de hoje (join com profissionais/serviços)
      ├─► WhatsApp: lembrete + aguarda resposta
      ├─► IA: classifica confirmar / cancelar / remarcar
      └─► Google Calendar + Postgres: aplica a decisão
```

Isso é a evolução direta da arquitetura de produção (`automacao-pmes-whatsapp/docs/arquitetura.md`):
o Google Calendar continua sendo a fonte de verdade do horário, mas o papel que era do Google
Sheets — dados do cliente, vínculo com o evento via `event_id`, catálogo de serviços — passa a
ser do Postgres, com integridade referencial real (FKs, `NOT NULL`, exclusion constraint
anti-double-booking) em vez de uma planilha sem validação.

## O que muda de verdade: de 1 calendário fixo para N calendários

Na versão de produção, o node de Calendar sempre aponta para um calendário fixo, escolhido uma
vez na criação do node ("Agenda do Negócio"). Aqui, o node "Buscar Profissional Ativo" (novo,
primeiro passo de cada workflow) lê `profissionais.google_calendar_id` no Postgres, e todos os
nodes de Calendar downstream usam esse valor dinamicamente. Isso é o que viabiliza
multi-calendário — um Google Calendar por profissional — sem duplicar workflow por profissional.

**Estado atual (v1):** como o prompt da IA e a conversa com o cliente ainda não têm o conceito de
"escolher um profissional", o node busca o único profissional `ativo` mais antigo — equivalente
ao comportamento de hoje (1 calendário só), mas já lendo do modelo relacional correto. Quando o
negócio realmente tiver mais de um profissional atendendo ao mesmo tempo, entra uma etapa nova:
ensinar a IA (ou uma regra de roteamento) a decidir qual profissional atende cada cliente — isso
é uma mudança de produto/prompt, não só de banco, e fica para depois.

## Decisões de design herdadas de produção (mantidas)

- **Data/hora por extenso em português** é gerada pela própria IA (Claude) junto com a data em
  ISO 8601, em vez de formatada depois em uma expressão n8n.
- **Duração do serviço vem sempre da tabela `servicos`** (`duracao_min`), nunca do que a IA
  supõe — a IA só usa 1h como fallback quando o serviço não é encontrado.
- **Estrutura de dados combinada** entre Calendar e banco: o Calendar é a fonte de verdade do
  horário; o Postgres guarda os dados do cliente, o serviço (via FK) e o vínculo
  (`google_event_id`) com o evento.

## Decisões de design novas desta migração

- **Integridade referencial real**: `agendamentos.servico_id` e `agendamentos.profissional_id`
  são FKs `NOT NULL` — ao contrário da planilha, não é possível gravar um agendamento com um
  serviço ou profissional que não existe. O efeito colateral disso é a decisão em aberto sobre
  nomes de serviço combinados, documentada em `docs/migracao-supabase.md`.
- **Prevenção de double-booking no banco**, não só na lógica do workflow: a exclusion constraint
  `agendamentos_sem_conflito` (GiST) rejeita qualquer `INSERT`/`UPDATE` que sobreponha o horário
  de um profissional com outro agendamento ativo dele — mesmo que, por algum bug futuro, o
  workflow não tivesse checado a disponibilidade antes.
- **`preco` e `criado_em` deixam de ser duplicados** por linha: `preco` vem de `servicos.preco`
  via `servico_id`; `criado_em` tem `DEFAULT now()` e nunca é sobrescrito.
- **Limitação conhecida herdada**: a mesma limitação do Wait node (`resume: webhook`) descrita no
  repo de produção continua valendo aqui — não foi alterada por esta migração.

## Próximos passos sugeridos

1. Importar os 3 workflows deste repo no n8n (desativados) e trocar a credencial Postgres
   placeholder pela credencial real.
2. Rodar o Grupo A do `docs/test-plan.md` (ver seção "Como rodar o Grupo A" para como fixar os
   nodes de Postgres/Calendar com pin data) contra os dados de `db/002_seed_exemplo.sql`.
3. Resolver a decisão em aberto sobre nome do serviço vs. `servico_id`
   (`docs/migracao-supabase.md`).
4. Só depois de validado ponta a ponta: decidir com o negócio a estratégia de cutover a partir da
   versão em produção (`automacao-pmes-whatsapp`), que continua intocada até lá.
