-- ============================================================================
-- AgendaZap Core — schema inicial (Supabase / PostgreSQL)
-- Tabelas: profissionais, servicos, profissionais_servicos, agendamentos
--
-- Este schema é a base para os 3 workflows n8n já em produção:
--   1) Agendamento via WhatsApp
--   2) Lembrete, Cancelamento e Remarcação
--   3) Notificação de Erros
-- Não substitui a versão atual (Google Sheets) em produção — é o ponto de
-- partida de um projeto novo, separado.
-- ============================================================================

create extension if not exists "pgcrypto";   -- gen_random_uuid()
create extension if not exists "btree_gist"; -- exclusion constraint anti-conflito de horário

-- ----------------------------------------------------------------------------
-- Tipos (ENUMs)
-- ----------------------------------------------------------------------------

-- Público atendido. Reaproveitado em profissionais.categoria_atendida e
-- servicos.categoria — assim dá pra casar "serviço X é feminino" com
-- "só marca com profissional que atende feminino ou todos" numa query simples.
create type categoria_publico as enum ('masculino', 'feminino', 'infantil', 'todos');

-- Dia da semana, para o array de dias_trabalho. Um array de enum é mais
-- fácil de consultar do que texto livre tipo "Seg-Sáb" (ex: "esse profissional
-- trabalha quarta?" vira um `= ANY(dias_trabalho)`, sem parsear string).
create type dia_semana as enum ('dom', 'seg', 'ter', 'qua', 'qui', 'sex', 'sab');

-- Status do agendamento. Cobre o ciclo de vida que os workflows 1 e 2 já
-- tratam: agendar -> confirmar -> (remarcar | cancelar) -> concluir/no-show.
create type status_agendamento as enum (
  'agendado',
  'confirmado',
  'remarcado',
  'cancelado',
  'concluido',
  'no_show'
);

-- Função utilitária para manter atualizado_em em dia em qualquer UPDATE.
create or replace function set_atualizado_em()
returns trigger as $$
begin
  new.atualizado_em = now();
  return new;
end;
$$ language plpgsql;


-- ============================================================================
-- profissionais
-- ============================================================================
create table profissionais (
  id                  uuid primary key default gen_random_uuid(),
  nome                text not null,
  telefone            text,
  email               text,
  google_calendar_id  text,                         -- calendário próprio -> multi-calendar
  categoria_atendida  categoria_publico not null default 'todos',
  dias_trabalho       dia_semana[] not null default array['seg','ter','qua','qui','sex']::dia_semana[],
  horario_inicio      time not null,
  horario_fim         time not null,
  ativo               boolean not null default true, -- soft-delete: some da agenda sem apagar histórico
  criado_em           timestamptz not null default now(),
  atualizado_em       timestamptz not null default now(),

  constraint profissionais_horario_valido check (horario_fim > horario_inicio),
  constraint profissionais_dias_nao_vazio check (array_length(dias_trabalho, 1) > 0)
);

create trigger trg_profissionais_atualizado_em
  before update on profissionais
  for each row execute function set_atualizado_em();

create index idx_profissionais_ativo on profissionais (ativo);


-- ============================================================================
-- servicos
-- ============================================================================
create table servicos (
  id             uuid primary key default gen_random_uuid(),
  nome           text not null,
  categoria      categoria_publico not null default 'todos',
  duracao_min    integer not null,
  preco          numeric(10,2),
  ativo          boolean not null default true,
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now(),

  constraint servicos_duracao_positiva check (duracao_min > 0),
  constraint servicos_preco_nao_negativo check (preco is null or preco >= 0)
);

create trigger trg_servicos_atualizado_em
  before update on servicos
  for each row execute function set_atualizado_em();

create index idx_servicos_ativo on servicos (ativo);


-- ============================================================================
-- profissionais_servicos (N:N)
-- Nem todo profissional faz todo serviço — essa tabela de junção evita
-- duplicar "corte masculino" uma vez por profissional e mantém a lista de
-- serviços centralizada (preço/duração num único lugar).
-- ============================================================================
create table profissionais_servicos (
  profissional_id  uuid not null references profissionais (id) on delete cascade,
  servico_id       uuid not null references servicos (id) on delete cascade,
  ativo            boolean not null default true,
  criado_em        timestamptz not null default now(),

  primary key (profissional_id, servico_id)
);

create index idx_prof_servicos_servico on profissionais_servicos (servico_id);


-- ============================================================================
-- agendamentos
-- ============================================================================
create table agendamentos (
  id                 uuid primary key default gen_random_uuid(),
  profissional_id    uuid not null references profissionais (id),
  servico_id         uuid not null references servicos (id),

  cliente_nome       text not null,
  cliente_telefone   text not null,                 -- número de WhatsApp de quem conversa com a IA
  beneficiario       text,                           -- ex: "eu mesmo", "filho", "esposa" — quem de fato recebe o serviço

  data_hora_inicio   timestamptz not null,
  data_hora_fim      timestamptz not null,
  status             status_agendamento not null default 'agendado',

  google_event_id    text,                           -- id do evento no Google Calendar do profissional
  observacoes        text,

  criado_em          timestamptz not null default now(),
  atualizado_em      timestamptz not null default now(),

  constraint agendamentos_intervalo_valido check (data_hora_fim > data_hora_inicio),

  -- Trava de concorrência real: o mesmo profissional não pode ter dois
  -- agendamentos com horários que se sobrepõem, enquanto nenhum dos dois
  -- estiver cancelado. Isso resolve no banco o problema de double-booking
  -- que em Sheets dependia só da lógica do workflow.
  constraint agendamentos_sem_conflito exclude using gist (
    profissional_id with =,
    tstzrange(data_hora_inicio, data_hora_fim) with &&
  ) where (status <> 'cancelado')
);

create trigger trg_agendamentos_atualizado_em
  before update on agendamentos
  for each row execute function set_atualizado_em();

-- Consultas mais comuns dos workflows: agenda de um profissional por período,
-- histórico por telefone do cliente, e filtro por status (ex: lembrete só
-- busca status = 'agendado'/'confirmado').
create index idx_agendamentos_profissional_periodo on agendamentos (profissional_id, data_hora_inicio);
create index idx_agendamentos_cliente_telefone on agendamentos (cliente_telefone);
create index idx_agendamentos_status on agendamentos (status);


-- ============================================================================
-- Notas para evolução futura (não implementado agora, só documentado):
--
-- 1) Multi-tenant (vários estabelecimentos/clientes do AgendaZap):
--    adicionar tabela `estabelecimentos` e uma coluna `estabelecimento_id`
--    em profissionais/servicos/agendamentos, + Row Level Security (RLS) do
--    Supabase filtrando por estabelecimento. O uuid como PK já facilita
--    essa migração (não depende de IDs sequenciais por tabela).
--
-- 2) Tabela `clientes` própria (hoje cliente_nome/telefone ficam soltos em
--    agendamentos): vale quando o histórico por cliente crescer e for
--    preciso guardar preferências, LGPD/opt-out de mensagens, etc.
--
-- 3) Dashboard (dia/semana/mês/trimestre/semestre/ano): as queries batem
--    direto em agendamentos com GROUP BY date_trunc(...) — não precisa de
--    tabela agregada agora; só considerar materialized view se o volume
--    crescer muito.
-- ============================================================================
