-- ============================================================================
-- Seed de exemplo: 2 profissionais + serviços + vínculo profissional-serviço
-- Ajuste os campos marcados com <<...>> antes de rodar no SQL Editor do Supabase.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Profissionais
-- ---------------------------------------------------------------------------
insert into profissionais (nome, telefone, google_calendar_id, categoria_atendida, dias_trabalho, horario_inicio, horario_fim)
values
  (
    '<<Nome do PROF-01>>',
    '<<telefone do PROF-01, ex: +5511999990001>>',
    '93f642021adc0f2a1d448267a4869343a049d47152f5133a950a6bec5fd592a1@group.calendar.google.com',
    'todos',                                        -- ajuste: masculino | feminino | infantil | todos
    array['seg','ter','qua','qui','sex','sab']::dia_semana[],
    '09:00',
    '19:00'
  ),
  (
    '<<Nome do PROF-02>>',
    '<<telefone do PROF-02, ex: +5511999990002>>',
    'c3cf9382df842aafcee7543dec8a1dbf837637e5e21f94df966fb9bf27deb732@group.calendar.google.com',
    'todos',
    array['ter','qua','qui','sex','sab']::dia_semana[],
    '10:00',
    '20:00'
  );

-- ---------------------------------------------------------------------------
-- Serviços (compartilhados entre os profissionais que os oferecem)
-- ---------------------------------------------------------------------------
insert into servicos (nome, categoria, duracao_min, preco)
values
  ('Corte Masculino', 'masculino', 30, 50.00),
  ('Barba',            'masculino', 20, 35.00),
  ('Corte + Barba',    'masculino', 50, 75.00);

-- ---------------------------------------------------------------------------
-- Vínculo profissional <-> serviço
-- (ajuste se PROF-01/PROF-02 não fizerem exatamente os mesmos 3 serviços)
-- ---------------------------------------------------------------------------
insert into profissionais_servicos (profissional_id, servico_id)
select p.id, s.id
from profissionais p
cross join servicos s
where p.google_calendar_id in (
  '93f642021adc0f2a1d448267a4869343a049d47152f5133a950a6bec5fd592a1@group.calendar.google.com',
  'c3cf9382df842aafcee7543dec8a1dbf837637e5e21f94df966fb9bf27deb732@group.calendar.google.com'
);

-- ---------------------------------------------------------------------------
-- Conferência rápida
-- ---------------------------------------------------------------------------
select
  p.nome,
  p.google_calendar_id,
  s.nome as servico,
  s.duracao_min,
  s.preco
from profissionais_servicos ps
join profissionais p on p.id = ps.profissional_id
join servicos s on s.id = ps.servico_id
order by p.nome, s.nome;
