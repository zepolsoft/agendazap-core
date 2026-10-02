-- ============================================================================
-- AgendaZap Core — 004: backfill de clientes a partir de agendamentos
--
-- Rodar DEPOIS da 003. Idempotente: pode rodar 2x (ou depois de novos
-- agendamentos) sem duplicar clientes nem sobrescrever vínculos já feitos.
--
-- 1) Cria um cliente por telefone distinto de agendamentos, normalizado para
--    só dígitos. Telefones que não ficam com 8 a 15 dígitos depois da
--    normalização são ignorados (aparecem na verificação como agendamentos
--    sem cliente_id).
--    - nome: o cliente_nome do agendamento mais recente daquele telefone
--    - primeiro_contato_em / primeiro_agendamento_em: criado_em do 1º agendamento
--    - ultimo_contato_em: criado_em do agendamento mais recente
--    (aproximação: ainda não existe histórico de conversa antes desta migration)
--    Se o cliente já existe, só amplia o intervalo de datas e preenche nome
--    vazio — nunca apaga dado, nunca mexe em aceite/descadastro.
-- 2) Preenche agendamentos.cliente_id onde ainda está NULL.
--
-- Sobre atualizado_em: o UPDATE do passo 2 dispararia
-- trg_agendamentos_atualizado_em e trocaria o atualizado_em de TODOS os
-- agendamentos para agora, apagando a informação de quando cada um mudou de
-- verdade. Por isso o trigger é desligado só durante este UPDATE, dentro da
-- mesma transação (se algo falhar, o ROLLBACK religa tudo). Enquanto a
-- transação estiver aberta, escritas em agendamentos esperam (milissegundos).
-- ============================================================================

begin;

-- Se agendamentos estiver ocupada (ex.: uma query dos workflows em andamento),
-- falha em 5 s em vez de enfileirar as queries da produção atrás desta.
-- Nesse caso nada é aplicado (rollback) e o script pode ser rodado de novo.
set local lock_timeout = '5s';

-- 1) clientes ----------------------------------------------------------------
with normalizados as (
  select
    regexp_replace(cliente_telefone, '\D', '', 'g') as telefone,
    cliente_nome,
    criado_em
  from agendamentos
),
por_telefone as (
  select
    telefone,
    (array_agg(nullif(btrim(cliente_nome), '') order by criado_em desc)
       filter (where nullif(btrim(cliente_nome), '') is not null))[1] as nome,
    min(criado_em) as primeiro,
    max(criado_em) as ultimo
  from normalizados
  where telefone ~ '^[0-9]{8,15}$'
  group by telefone
)
insert into clientes (telefone, nome, primeiro_contato_em, ultimo_contato_em, primeiro_agendamento_em)
select telefone, nome, primeiro, ultimo, primeiro
from por_telefone
on conflict (telefone) do update set
  nome                    = coalesce(clientes.nome, excluded.nome),
  primeiro_contato_em     = least(clientes.primeiro_contato_em, excluded.primeiro_contato_em),
  ultimo_contato_em       = greatest(clientes.ultimo_contato_em, excluded.ultimo_contato_em),
  primeiro_agendamento_em = least(coalesce(clientes.primeiro_agendamento_em, excluded.primeiro_agendamento_em),
                                  excluded.primeiro_agendamento_em)
where clientes.nome is null and excluded.nome is not null
   or excluded.primeiro_contato_em < clientes.primeiro_contato_em
   or excluded.ultimo_contato_em > clientes.ultimo_contato_em
   or clientes.primeiro_agendamento_em is null
   or excluded.primeiro_agendamento_em < clientes.primeiro_agendamento_em;

-- 2) agendamentos.cliente_id -------------------------------------------------
alter table agendamentos disable trigger trg_agendamentos_atualizado_em;

update agendamentos a
set cliente_id = c.id
from clientes c
where a.cliente_id is null
  and c.telefone = regexp_replace(a.cliente_telefone, '\D', '', 'g');

alter table agendamentos enable trigger trg_agendamentos_atualizado_em;

commit;
