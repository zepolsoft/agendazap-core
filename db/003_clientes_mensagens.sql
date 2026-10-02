-- ============================================================================
-- AgendaZap Core — migration 003: clientes e histórico de mensagens
--
-- SOMENTE ADITIVA: cria tipos, tabelas, uma coluna nova (nullable) em
-- agendamentos, índices, uma view e RLS nas tabelas novas. Não remove, não
-- renomeia e não altera nenhuma coluna existente.
--
-- Impacto nos workflows em produção (Agendamento, Lembrete, Notificação de
-- Erros): nenhum. Todas as queries deles usam lista explícita de colunas (sem
-- SELECT * / RETURNING *), e o único INSERT em agendamentos nomeia as colunas
-- — a coluna nova cliente_id fica NULL até o backfill (004) e não é lida nem
-- escrita por eles.
--
-- Requisitos: PostgreSQL 15+ (view com security_invoker) e
-- set_atualizado_em() já criada pela 001.
-- Pode ser reexecutada sem erro (IF NOT EXISTS / guardas), mas foi feita para
-- rodar uma vez.
-- ============================================================================

begin;

-- Se agendamentos estiver ocupada (ex.: uma query dos workflows em andamento),
-- falha em 5 s em vez de enfileirar as queries da produção atrás desta.
-- Nesse caso nada é aplicado (rollback) e o script pode ser rodado de novo.
set local lock_timeout = '5s';

-- ----------------------------------------------------------------------------
-- Tipos
-- ----------------------------------------------------------------------------
do $$
begin
  create type direcao_mensagem as enum ('entrada', 'saida');
exception when duplicate_object then null;
end $$;

do $$
begin
  create type status_mensagem as enum ('recebida', 'enviada', 'entregue', 'lida', 'falhou');
exception when duplicate_object then null;
end $$;


-- ----------------------------------------------------------------------------
-- clientes — uma linha por número de WhatsApp
-- ----------------------------------------------------------------------------
create table if not exists clientes (
  id                       uuid primary key default gen_random_uuid(),
  telefone                 text not null,          -- só dígitos, com DDI (ex.: 5511999990000)
  nome                     text,                   -- nome do perfil do WhatsApp / informado
  primeiro_contato_em      timestamptz not null default now(),
  ultimo_contato_em        timestamptz not null default now(),
  primeiro_agendamento_em  timestamptz,            -- quando o cliente fez o 1º agendamento
  aceita_promocoes         boolean not null default false,  -- opt-in explícito (LGPD)
  aceite_em                timestamptz,            -- quando deu o opt-in
  descadastro_em           timestamptz,            -- quando pediu para sair (opt-out)
  criado_em                timestamptz not null default now(),
  atualizado_em            timestamptz not null default now(),

  constraint clientes_telefone_unico unique (telefone),
  constraint clientes_telefone_so_digitos check (telefone ~ '^[0-9]{8,15}$'),
  constraint clientes_contato_ordem check (ultimo_contato_em >= primeiro_contato_em),
  -- opt-in só vale com data de aceite registrada
  constraint clientes_aceite_com_data check (not aceita_promocoes or aceite_em is not null)
);

create or replace trigger trg_clientes_atualizado_em
  before update on clientes
  for each row execute function set_atualizado_em();


-- ----------------------------------------------------------------------------
-- agendamentos.cliente_id — vínculo opcional com clientes
-- Coluna nova, nullable e sem default: no Postgres é só metadado (não
-- reescreve a tabela). Sem ON DELETE CASCADE: apagar um cliente com
-- agendamentos falha, para não perder histórico por engano.
-- ----------------------------------------------------------------------------
alter table agendamentos
  add column if not exists cliente_id uuid references clientes (id);

create index if not exists idx_agendamentos_cliente_id on agendamentos (cliente_id);


-- ----------------------------------------------------------------------------
-- mensagens — histórico de entrada/saída no WhatsApp
-- ----------------------------------------------------------------------------
create table if not exists mensagens (
  id              uuid primary key default gen_random_uuid(),
  cliente_id      uuid not null references clientes (id),
  agendamento_id  uuid references agendamentos (id) on delete set null,
  wa_message_id   text unique,                     -- id da Meta (wamid...); NULL se o envio falhou antes de ter id
  direcao         direcao_mensagem not null,
  tipo            text not null default 'texto',   -- texto, reacao, audio, imagem...
  conteudo        text,
  status          status_mensagem not null,
  criado_em       timestamptz not null default now(),

  -- entrada é sempre 'recebida'; saída nunca é 'recebida'
  constraint mensagens_status_coerente check (
    (direcao = 'entrada' and status = 'recebida')
    or (direcao = 'saida' and status <> 'recebida')
  )
);

create index if not exists idx_mensagens_cliente_criado_em on mensagens (cliente_id, criado_em desc);
-- para o ON DELETE SET NULL não varrer a tabela quando um agendamento é apagado
create index if not exists idx_mensagens_agendamento_id on mensagens (agendamento_id) where agendamento_id is not null;


-- ----------------------------------------------------------------------------
-- clientes_resumo — totais por cliente
-- security_invoker: a view respeita o RLS de quem consulta (sem isso, no
-- Supabase ela rodaria com os privilégios do dono e furaria o RLS).
-- "remarcados" conta o status ATUAL (um agendamento remarcado e depois
-- cancelado conta como cancelado). "último atendimento" = maior início entre
-- os concluídos e os que já passaram sem cancelamento/no-show (o status só
-- vira 'concluido' no job das 22h).
-- ----------------------------------------------------------------------------
create or replace view clientes_resumo
with (security_invoker = true) as
select
  c.id                 as cliente_id,
  c.telefone,
  c.nome,
  c.primeiro_contato_em,
  c.ultimo_contato_em,
  c.primeiro_agendamento_em,
  c.aceita_promocoes,
  c.descadastro_em,
  count(a.id)                                              as total_agendamentos,
  count(a.id) filter (where a.status = 'cancelado')        as total_cancelados,
  count(a.id) filter (where a.status = 'remarcado')        as total_remarcados,
  max(a.data_hora_inicio) filter (
    where a.status = 'concluido'
       or (a.status in ('agendado', 'confirmado', 'remarcado') and a.data_hora_fim <= now())
  )                                                        as ultimo_atendimento_em
from clientes c
left join agendamentos a on a.cliente_id = c.id
group by c.id;


-- ----------------------------------------------------------------------------
-- Segurança (Supabase): RLS ligado, SEM políticas -> anon/authenticated não
-- leem nem escrevem nada pela API. O dono das tabelas (o usuário da conexão
-- do n8n) continua acessando normalmente, porque o dono ignora RLS (não
-- usamos FORCE ROW LEVEL SECURITY).
-- Os REVOKE abaixo são uma segunda barreira contra os grants padrão do
-- Supabase para anon/authenticated.
-- ----------------------------------------------------------------------------
alter table clientes  enable row level security;
alter table mensagens enable row level security;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    revoke all on clientes, mensagens, clientes_resumo from anon;
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    revoke all on clientes, mensagens, clientes_resumo from authenticated;
  end if;
end $$;

commit;
