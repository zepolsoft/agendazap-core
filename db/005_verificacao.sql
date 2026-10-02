-- ============================================================================
-- AgendaZap Core — 005: verificação da 003 (migration) e da 004 (backfill)
--
-- NÃO altera nada. Três partes:
--   A) "Impressão digital" das consultas dos workflows em produção.
--      Rodar ANTES da 003 e DEPOIS da 004, e comparar: as linhas têm que ser
--      idênticas. Só os hashes (md5) são exibidos, nenhum dado.
--   B) Conferências do resultado (rodar só DEPOIS da 004).
--   C) Opcional: os comandos de ESCRITA dos workflows numa transação desfeita
--      com ROLLBACK (não deixa rastro).
--
-- As 9 consultas da parte A são o texto exato dos nodes Postgres dos
-- workflows publicados (backup em workflows/backup/, 02/10/2026):
--   Q1 Buscar Profissional Ativo                      (AG e LB)
--   Q2 Buscar Serviços e Preços / Duração dos Serviços (AG e LB)
--   Q3 Buscar Agendamentos Ativos do Cliente / para Remarcar / para Cancelar
--      / do Cliente (Consultar)                       (AG) — por telefone
--   Q4 Buscar Horário Original (Remarcar / Erro no Banco / Remarcação) — por evento
--   Q5 Buscar Profissionais Ativos                    (AG)
--   Q6 Buscar Agendamentos de Hoje (Planilha)         (LB)
--   Q7 Reverificar Agendamento Antes do Timeout       (LB) — por evento
--   Q8 Buscar Todos os Agendamentos                   (LB)
--   Q9 Reler Agendamento Após Resposta / Confirmação  (LB) — por evento
-- As consultas com $1 rodam para TODOS os telefones / event_ids existentes.
--
-- Atenção: a produção continua recebendo mensagens. Se um cliente marcar,
-- remarcar ou cancelar entre o "antes" e o "depois", os hashes mudam por
-- motivo legítimo — por isso a parte A também mostra total de linhas e o
-- último atualizado_em de agendamentos. Rode antes/003/004/depois em
-- sequência, de preferência num horário sem movimento.
-- ============================================================================


-- ============================================================================
-- A) IMPRESSÃO DIGITAL — rodar ANTES da 003 e DEPOIS da 004
-- ============================================================================
with
q1 as (
  SELECT id AS profissional_id, google_calendar_id, nome AS profissional_nome
  FROM profissionais
  WHERE ativo = true
  ORDER BY criado_em, id
  LIMIT 1
),
q2 as (
  SELECT nome AS servico, categoria, duracao_min AS duracao_minutos, preco
  FROM servicos
  WHERE ativo = true
  ORDER BY nome
),
telefones as (select distinct cliente_telefone as p from agendamentos),
eventos   as (select distinct google_event_id  as p from agendamentos where google_event_id is not null),
q3 as (
  select t.p as param, r.*
  from telefones t
  cross join lateral (
    SELECT a.google_event_id AS event_id, a.status, to_char(a.data_hora_inicio AT TIME ZONE 'America/Sao_Paulo', 'YYYY-MM-DD"T"HH24:MI:SS') || '-03:00' AS data,
           a.beneficiario, s.nome AS servico
    FROM agendamentos a
    JOIN servicos s ON s.id = a.servico_id
    WHERE a.cliente_telefone = t.p
    ORDER BY a.data_hora_inicio
  ) r
),
q4 as (
  select e.p as param, r.*
  from eventos e
  cross join lateral (
    SELECT
      to_char(data_hora_inicio AT TIME ZONE 'America/Sao_Paulo', 'YYYY-MM-DD"T"HH24:MI:SS') || '-03:00' AS data_hora_inicio,
      to_char(data_hora_fim AT TIME ZONE 'America/Sao_Paulo', 'YYYY-MM-DD"T"HH24:MI:SS') || '-03:00' AS data_hora_fim
    FROM agendamentos
    WHERE google_event_id = e.p
    LIMIT 1
  ) r
),
q5 as (
  SELECT p.nome,
         p.dias_trabalho::text[] AS dias_trabalho,
         to_char(p.horario_inicio, 'HH24:MI') AS horario_inicio,
         to_char(p.horario_fim, 'HH24:MI') AS horario_fim,
         COALESCE(string_agg(s.nome, ', ' ORDER BY s.nome) FILTER (WHERE s.id IS NOT NULL), '') AS servicos
  FROM profissionais p
  LEFT JOIN profissionais_servicos ps ON ps.profissional_id = p.id AND ps.ativo = true
  LEFT JOIN servicos s ON s.id = ps.servico_id AND s.ativo = true
  WHERE p.ativo = true
  GROUP BY p.id, p.nome, p.dias_trabalho, p.horario_inicio, p.horario_fim
  ORDER BY p.nome
),
q6 as (
  SELECT
    a.google_event_id AS event_id,
    a.cliente_nome AS nome,
    a.cliente_telefone AS telefone,
    s.nome AS servico,
    a.beneficiario,
    a.status,
    to_char(a.data_hora_inicio AT TIME ZONE 'America/Sao_Paulo', 'YYYY-MM-DD"T"HH24:MI:SS') || '-03:00' AS data
  FROM agendamentos a
  JOIN servicos s ON s.id = a.servico_id
),
q7 as (
  select e.p as param, r.*
  from eventos e
  cross join lateral (
    SELECT a.google_event_id AS event_id, a.status, to_char(a.data_hora_inicio AT TIME ZONE 'America/Sao_Paulo', 'YYYY-MM-DD"T"HH24:MI:SS') || '-03:00' AS data
    FROM agendamentos a
    WHERE a.google_event_id = e.p
    LIMIT 1
  ) r
),
q8 as (
  SELECT google_event_id AS event_id, status, to_char(data_hora_inicio AT TIME ZONE 'America/Sao_Paulo', 'YYYY-MM-DD"T"HH24:MI:SS') || '-03:00' AS data
  FROM agendamentos
  WHERE status IN ('agendado', 'remarcado')
),
q9 as (
  select e.p as param, r.*
  from eventos e
  cross join lateral (
    SELECT a.status
    FROM agendamentos a
    WHERE a.google_event_id = e.p
    LIMIT 1
  ) r
),
-- Colunas ORIGINAIS de agendamentos (sem a cliente_id nova), incluindo
-- atualizado_em: prova que o backfill não mexeu em nenhum dado existente.
t_agendamentos as (
  select id, profissional_id, servico_id, cliente_nome, cliente_telefone, beneficiario,
         data_hora_inicio, data_hora_fim, status, google_event_id, observacoes,
         criado_em, atualizado_em
  from agendamentos
)
-- Q6 e Q8 não têm ORDER BY no workflow; aqui as linhas são ordenadas pelo
-- próprio texto antes do hash, então a comparação não depende da ordem física.
select 'Q1 Buscar Profissional Ativo'        as consulta, count(*) as linhas, md5(coalesce(string_agg(x::text, '|' order by x::text), '')) as hash from q1 x
union all select 'Q2 Buscar Serviços e Preços',       count(*), md5(coalesce(string_agg(x::text, '|' order by x::text), '')) from q2 x
union all select 'Q3 Agendamentos do Cliente (por telefone)', count(*), md5(coalesce(string_agg(x::text, '|' order by x::text), '')) from q3 x
union all select 'Q4 Horário Original (por evento)',  count(*), md5(coalesce(string_agg(x::text, '|' order by x::text), '')) from q4 x
union all select 'Q5 Buscar Profissionais Ativos',    count(*), md5(coalesce(string_agg(x::text, '|' order by x::text), '')) from q5 x
union all select 'Q6 Agendamentos de Hoje (sem filtro)', count(*), md5(coalesce(string_agg(x::text, '|' order by x::text), '')) from q6 x
union all select 'Q7 Reverificar (por evento)',       count(*), md5(coalesce(string_agg(x::text, '|' order by x::text), '')) from q7 x
union all select 'Q8 Buscar Todos os Agendamentos',   count(*), md5(coalesce(string_agg(x::text, '|' order by x::text), '')) from q8 x
union all select 'Q9 Reler Agendamento (por evento)', count(*), md5(coalesce(string_agg(x::text, '|' order by x::text), '')) from q9 x
union all select 'T  agendamentos (colunas originais)', count(*), md5(coalesce(string_agg(x::text, '|' order by x::text), '')) from t_agendamentos x
union all select 'T  último atualizado_em: ' || coalesce((select max(atualizado_em)::text from agendamentos), '-'), null, null
order by 1;


-- ============================================================================
-- B) CONFERÊNCIAS — rodar só DEPOIS da 004
-- ============================================================================

-- B1. Clientes x telefones distintos (normalizados, válidos) de agendamentos.
--     Esperado: clientes_criados = telefones_validos, sem_cliente_valido = 0.
select
  (select count(*) from clientes) as clientes_criados,
  (select count(distinct regexp_replace(cliente_telefone, '\D', '', 'g'))
     from agendamentos
    where regexp_replace(cliente_telefone, '\D', '', 'g') ~ '^[0-9]{8,15}$') as telefones_validos,
  (select count(distinct cliente_telefone) from agendamentos) as telefones_brutos_distintos,
  (select count(*) from agendamentos a
    where regexp_replace(a.cliente_telefone, '\D', '', 'g') ~ '^[0-9]{8,15}$'
      and not exists (select 1 from clientes c
                       where c.telefone = regexp_replace(a.cliente_telefone, '\D', '', 'g'))) as sem_cliente_valido;
-- (telefones_brutos_distintos > telefones_validos indica o mesmo número
--  gravado em formatos diferentes, ou telefones inválidos — ver B2.)

-- B2. Agendamentos sem cliente_id. Esperado: 0 linhas, ou só telefones
--     inválidos (fora de 8–15 dígitos), listados aqui para decidir à mão.
select a.id, a.cliente_telefone, a.cliente_nome, a.status, a.criado_em
from agendamentos a
where a.cliente_id is null
order by a.criado_em;

-- B3. Vínculo coerente: cliente_id aponta para o cliente do mesmo telefone.
--     Esperado: 0.
select count(*) as vinculos_incoerentes
from agendamentos a
join clientes c on c.id = a.cliente_id
where c.telefone <> regexp_replace(a.cliente_telefone, '\D', '', 'g');

-- B4. Datas do cliente batem com os agendamentos. Esperado: 0.
select count(*) as clientes_com_datas_divergentes
from clientes c
join (
  select cliente_id, min(criado_em) as primeiro, max(criado_em) as ultimo
  from agendamentos where cliente_id is not null group by cliente_id
) a on a.cliente_id = c.id
where c.primeiro_agendamento_em <> a.primeiro
   or c.primeiro_contato_em > a.primeiro
   or c.ultimo_contato_em < a.ultimo;

-- B5. Segurança: RLS ligado, nenhuma política, view com security_invoker,
--     anon/authenticated sem privilégios. Esperado: rls = true,
--     politicas = 0, security_invoker = true, privilegios_publicos = 0.
select
  c.relname,
  c.relrowsecurity as rls,
  (select count(*) from pg_policies p where p.schemaname = 'public' and p.tablename = c.relname) as politicas,
  coalesce((select option_value from pg_options_to_table(c.reloptions) where option_name = 'security_invoker'), '-') as security_invoker,
  (select count(*) from information_schema.role_table_grants g
    where g.table_schema = 'public' and g.table_name = c.relname
      and g.grantee in ('anon', 'authenticated')) as privilegios_publicos
from pg_class c
join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
where c.relname in ('clientes', 'mensagens', 'clientes_resumo')
order by c.relname;

-- B6. Trigger de atualizado_em religado depois do backfill. Esperado: 'O' (enabled).
select tgname, tgenabled
from pg_trigger
where tgrelid = 'agendamentos'::regclass and tgname = 'trg_agendamentos_atualizado_em';

-- B7. A view responde e os totais batem com agendamentos. Esperado: 0.
select count(*) as resumos_divergentes
from clientes_resumo r
where r.total_agendamentos <> (select count(*) from agendamentos a where a.cliente_id = r.cliente_id);

-- B8. Idempotência: rode a 004 de novo e repita B1–B4 e a parte A —
--     contagens e hashes têm que continuar iguais.


-- ============================================================================
-- C) OPCIONAL — escritas dos workflows, desfeitas no fim (ROLLBACK)
-- Mesmo SQL dos nodes "Salvar Cliente na Planilha", "Atualizar Linha na
-- Planilha (Cancelar)" e "Marcar Como Concluído", com valores de teste num
-- horário de 2030 (sem conflito com a agenda real). Nada é gravado.
-- Esperado: cada comando retorna 1 linha e cliente_id fica NULL (os
-- workflows atuais não preenchem a coluna nova — isso é a fase 2).
-- ============================================================================
begin;

INSERT INTO agendamentos (
  profissional_id, servico_id, cliente_nome, cliente_telefone,
  beneficiario, data_hora_inicio, data_hora_fim, status,
  google_event_id, observacoes
)
VALUES (
  (SELECT id FROM profissionais WHERE ativo = true ORDER BY criado_em, id LIMIT 1),
  (SELECT id FROM servicos WHERE ativo = true AND lower(nome) = lower('Corte Masculino') LIMIT 1),
  'Verificacao 005', '5511091000099', 'Eu mesmo',
  '2030-01-07T10:00:00-03:00', '2030-01-07T10:30:00-03:00', 'agendado',
  'verificacao-005-rollback', 'teste da migration 003 — desfeito com ROLLBACK'
)
RETURNING id, google_event_id AS event_id, cliente_id;

UPDATE agendamentos SET status = 'cancelado' WHERE google_event_id = 'verificacao-005-rollback' RETURNING id;
UPDATE agendamentos SET status = 'concluido' WHERE google_event_id = 'verificacao-005-rollback' RETURNING id;

rollback;
