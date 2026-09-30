# Migração dos workflows de produção para Supabase

Este documento registra exatamente o que mudou ao adaptar os 3 workflows n8n de produção
(`automacao-pmes-whatsapp`) para usar Postgres/Supabase no lugar de Google Sheets, e o que
**não** mudou.

> A versão de produção (Google Sheets + planilhas separadas) continua intocada. Os JSONs deste
> repositório são cópias adaptadas, para importar como novos workflows (desativados) no n8n e
> testar em paralelo antes de qualquer cutover.

## O que foi preservado 100%

- **AI Agents e prompts** — "Interpretar Intenção do Cliente", "Classificar Resposta do
  Lembrete", "Classificar Confirmação da Remarcação": nenhuma linha do `systemMessage` ou dos
  prompts foi alterada.
- **Toda a lógica de negócio em nodes de Code** — validação de horário de funcionamento, cálculo
  de horários livres, desambiguação de agendamento por beneficiário, guard-rails de formato da
  IA, dedup de mensagem, lock por telefone, escopo da conversa (encaminhar/fora do escopo) — nada
  disso foi tocado.
- **Todos os nomes de node** foram mantidos idênticos. Isso é proposital: dezenas de expressões
  em outros nodes referenciam dados por `$('Nome do Node')`, e manter o nome evita ter que
  caçar e atualizar cada referência.
- **n8n Data Tables** (dedup de mensagem, lock de telefone, espera de lembrete,
  `encaminhamentos_duvida`) não foram alteradas — já são um recurso nativo do n8n, fora do escopo
  desta migração (que troca Sheets/Calendar, não Data Tables).

## O que mudou

### 1. Novo node "Buscar Profissional Ativo"

Adicionado no início de cada workflow (logo após o trigger / indicador de digitação). Faz:

```sql
SELECT id AS profissional_id, google_calendar_id, nome AS profissional_nome
FROM profissionais
WHERE ativo = true
ORDER BY criado_em
LIMIT 1;
```

Motivo: os workflows de produção têm **um único** Google Calendar fixo, escolhido na hora de
criar o node ("Agenda do Negócio"). Não existe hoje nenhum conceito de "qual profissional" no
prompt da IA nem na conversa com o cliente. Para já deixar o schema multi-calendário (uma linha
por profissional, cada um com seu `google_calendar_id`) funcionando sem reescrever a lógica de
negócio, este node busca o **profissional ativo mais antigo** e todo o resto do workflow passa a
usar `google_calendar_id` dele em vez do calendário fixo.

**Isso é uma simplificação deliberada para a v1**, equivalente ao comportamento atual (1
calendário só). Quando houver de fato mais de um profissional atendendo ao mesmo tempo, é
necessário decidir com o negócio como o cliente escolhe (ou é atribuído a) um profissional — isso
muda o prompt da IA e várias regras, o que é um passo à parte, fora do escopo desta migração de
camada de dados.

### 2. Google Sheets → Postgres

Todo node `n8n-nodes-base.googleSheets` virou `n8n-nodes-base.postgres` (operação
`executeQuery`, com parâmetros via `$1, $2...`). Mapeamento de campos — as queries usam `AS` para
que as colunas devolvidas tenham exatamente os mesmos nomes que os nodes de Code já esperavam
(`event_id`, `data`, `servico`, `beneficiario`, `status`, `nome`, `telefone`), então nenhum node
de Code downstream precisou ser alterado:

| Coluna esperada pelo Code | Origem no Supabase |
|---|---|
| `event_id` | `agendamentos.google_event_id` |
| `data` | `agendamentos.data_hora_inicio` |
| `servico` | `servicos.nome` (via `JOIN`) |
| `nome` | `agendamentos.cliente_nome` |
| `telefone` | `agendamentos.cliente_telefone` |
| `beneficiario` | `agendamentos.beneficiario` |
| `status` | `agendamentos.status` |
| `duracao_minutos` | `servicos.duracao_min` |

Nodes afetados (agendamento): Buscar Serviços e Preços, Buscar Agendamentos Ativos do Cliente,
Buscar Agendamento para Remarcar/Cancelar, Buscar Agendamentos do Cliente (Consultar), Salvar
Cliente na Planilha (agora `INSERT`), Atualizar Linha na Planilha / (Cancelar) (agora `UPDATE`).

Nodes afetados (lembrete): Buscar Agendamentos de Hoje, Reverificar Agendamento Antes do
Timeout, Atualizar Status na Planilha (Cancelar), Buscar Duração dos Serviços, Atualizar Data na
Planilha, Buscar Todos os Agendamentos, Marcar Como Concluído.

### 3. Google Calendar

Os nodes de Calendar **continuam sendo Google Calendar** (não fazia parte do pedido trocar o
Calendar em si). A única mudança: o campo `calendar` deixou de apontar para um calendário fixo
("Agenda do Negócio") e passou a ser resolvido dinamicamente:

```
={{ $('Buscar Profissional Ativo').item.json.google_calendar_id }}
```

### 4. Preço e `criado_em` deixaram de ser duplicados

Na planilha, cada linha guardava `preco` e `criado_em` como cópia, nunca recalculados depois de
criados. No modelo relacional, `preco` já vem de `servicos.preco` (via `servico_id`), e
`criado_em` tem `DEFAULT now()` e nunca é sobrescrito pelos `UPDATE`s (só `atualizado_em` muda,
via trigger). Por isso os `UPDATE`s gerados não escrevem mais essas duas colunas — elas nunca
precisaram ser reescritas.

## Decisão em aberto: nome do serviço vs. `servico_id`

**Este é o ponto que precisa de uma decisão sua antes de considerar a migração pronta para
produção.**

Hoje a IA extrai o serviço como texto livre (`"corte e barba"`, `"baixo"` → mapeado para "Corte
Baixo na Máquina" pelo próprio prompt, etc.), e a planilha aceitava qualquer texto — não havia
integridade referencial. No banco relacional, `agendamentos.servico_id` é uma FK **obrigatória**
para `servicos.id`. Os `INSERT`/`UPDATE` resolvem o nome do serviço assim:

```sql
(SELECT id FROM servicos WHERE ativo = true AND lower(nome) = lower($1) LIMIT 1)
```

Ou seja: **o texto que a IA extraiu precisa bater exatamente (ignorando maiúsculas/minúsculas)
com um `servicos.nome` cadastrado.** Isso funciona bem quando a IA usa o nome oficial do serviço
(ela já tende a fazer isso, guiada pela lista de serviços do prompt). O caso que quebra é uma
**combinação** de serviços sem um item específico na lista (ex.: prompt permite "corte e barba"
somando as durações de "Corte" + "Barba" quando não existe o item "Corte e Barba" na planilha) —
nesse caso a subquery não encontra nada, `servico_id` fica `NULL`, e o `INSERT`/`UPDATE` falha
por violar a constraint `NOT NULL` (pior do que antes: no Sheets isso sempre "funcionava",
silenciosamente).

Guardei o texto original da IA em `agendamentos.observacoes` em todo `INSERT` (auditoria), mas
isso não evita a falha do `INSERT`. Quatro caminhos possíveis, para decidir com calma antes de ir
pra produção:

1. **Cadastrar as combinações mais comuns como serviços de verdade** na tabela `servicos` (ex.:
   "Corte + Barba" já existe no seed) — mais simples, mas não cobre combinações arbitrárias.
2. **Matching mais tolerante na query** (`ILIKE`, `pg_trgm`/`similarity()`) em vez de igualdade
   exata — cobre mais casos, mas pode casar errado com nomes parecidos.
3. **Ajustar o prompt da IA** para sempre escolher um serviço exato da lista, sem combinar
   (mudança de comportamento/regra de negócio, teria que ser testada no `docs/test-plan.md`).
4. **Modelar agendamento com múltiplos serviços** (tabela de junção agendamento↔serviço em vez de
   uma FK única) — mais correto a longo prazo, mas é uma mudança de schema.

Não escolhi nenhuma dessas sozinho porque são trade-offs de produto, não só técnicos.

## Como importar e testar

1. No n8n, importe os 3 arquivos JSON de `workflows/*/`. Eles chegam **desativados** por padrão.
2. Em cada node Postgres, troque a credencial `Supabase - agendazap-core` (placeholder) pela sua
   credencial real já configurada (a mesma usada nos testes de `db/001_initial_schema.sql`).
3. Rode os testes do Grupo A do `docs/test-plan.md` (do repo `automacao-pmes-whatsapp`) contra
   esta versão, usando os 2 profissionais de `db/002_seed_exemplo.sql` como dado de teste — sem
   tocar nos workflows de produção.
