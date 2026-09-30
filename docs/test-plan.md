# Roteiro de testes — Agendamento, Lembrete e Notificação de Erros (Supabase)

Adaptado do `docs/test-plan.md` do repo de produção (`automacao-pmes-whatsapp`) para esta versão
com Postgres/Supabase. Os cenários são os mesmos — a lógica de negócio não mudou — só a forma de
fixar (pin) os nodes de dados é diferente (Postgres em vez de Google Sheets). O "Registro de
execuções" do roteiro original (histórico de bugs e rodadas já feitas em produção) não se aplica
aqui: este projeto ainda não foi testado ponta a ponta. Ao rodar cada rodada, registre o
resultado numa seção nova no final deste arquivo, no mesmo formato.

**Antes de rodar qualquer cenário:** `db/001_initial_schema.sql` e `db/002_seed_exemplo.sql`
precisam estar aplicados no seu projeto Supabase, e as credenciais Postgres/WhatsApp/Calendar
reais precisam estar configuradas nos workflows importados (ver README de cada
`workflows/<nome>/`).

Os cenários estão em dois grupos, porque o tipo de teste muda o que ele consegue provar:

- **Grupo A — Simulação** (`test_workflow` com pin data): lógica pura — interpretação da IA,
  sinônimos, cálculo de duração, roteamento por disponibilidade/expediente. Rápido, sem efeito
  colateral, mas **não pega** bugs que só existem no estado real do Calendar/Postgres/Data
  Tables.
- **Grupo B — Integração real**: tudo que depende de efeito colateral de verdade, concorrência ou
  do relógio real.

---

## Como rodar o Grupo A (simulação)

Regras que valem para todo cenário:

1. **Fixe (pin) todo node com efeito externo**: WhatsApp (envio), Google Calendar, Postgres
   (todas as queries de leitura/escrita em `profissionais`, `servicos`, `agendamentos`), Data
   Tables (`Checar/Registrar Mensagem`, `Checar/Registrar Lock`, `Verificar/Registrar Espera`) e
   HTTP (`Ativar Indicador de Digitação`, `Encaminhar Mensagem para Lembrete`).
   ⚠️ Node com credencial que **não** estiver fixado roda de verdade — um envio de WhatsApp sem
   pin manda mensagem real, e uma query de Postgres sem pin lê/escreve no banco real.
   - Para fixar o node "Buscar Profissional Ativo", o pin precisa ter `profissional_id` e
     `google_calendar_id` de um profissional real do seed (`db/002_seed_exemplo.sql`).
2. **Não fixe os agentes de IA** (`Interpretar Intenção do Cliente`, `Classificar Resposta do
   Lembrete`, `Classificar Confirmação da Remarcação`) quando o objetivo é testar interpretação —
   o modelo Claude roda de verdade.
3. Use telefones fictícios `55119000001xx`, um por cenário. A memória da IA é por telefone:
   cenários de várias mensagens usam o **mesmo** número, em execuções **sequenciais**.
4. Serviços fixados = cópia dos serviços do seed (`Corte Masculino` 30 min, `Barba` 20 min,
   `Corte + Barba` 50 min — ajuste os valores do pin conforme os serviços reais cadastrados na
   tabela `servicos` no momento do teste).
5. Lembrete: a linha fixada em "Buscar Agendamentos de Hoje (Planilha)" precisa ter `data` =
   **hoje** (senão "Filtrar Data de Hoje" descarta), e horários de remarcação "hoje" precisam
   estar no futuro e dentro do expediente no momento da execução.
6. Conferir o resultado com `get_workflow_execution` (includeData) nos nodes: saída da IA,
   "Validar Horário de Funcionamento" (`data_hora_fim`/`novo_horario_fim`, `duracao_minutos`,
   `duracao_fonte`) e qual node terminal executou.

## Como rodar o Grupo B (integração)

**Ainda não existe ambiente isolado.** Para montar (a decidir):

- Cópia **desativada** dos dois workflows, com o trigger do WhatsApp trocado por um Webhook (para
  injetar payloads reais do WhatsApp via `execute_workflow`), apontando para um **projeto
  Supabase de teste** (ou um schema/linhas isoladas com telefones fictícios), um **calendário de
  teste** e **Data Tables de teste** (dedup, lock, esperas).
- Envio de WhatsApp da cópia para um número de teste (ou desabilitado), nunca para clientes.
- Cenários que dependem do WhatsApp real (reenvio da Meta, mídia real) exigem uma pessoa mandando
  mensagem de um celular para o número de teste.

Até esse ambiente existir, o Grupo B fica **não executado** — não marcar como aprovado.

---

## Grupo A — Simulação

| # | Cenário | Esperado |
|---|---|---|
| 1 | Cliente novo, mensagem completa (serviço + data + hora) | IA extrai serviço/data; fim = início + duração do serviço (tabela `servicos`); propõe e pede confirmação (`Propor Horário`); após "sim", `Criar Evento` + `INSERT` em `agendamentos` |
| 2 | Mensagem vaga ("quero cortar o cabelo") | Pergunta serviço e data/hora; nada criado |
| 3 | Serviço por gíria/sinônimo ("baixo", "degradê") | Mapeia para o nome oficial quando inequívoco; se ambíguo, pergunta — nunca inventa serviço |
| 4 | Horário já ocupado (`Verificar Disponibilidade` → `available:false`) | `Sugerir Outro Horário`; `Criar Evento` não executa |
| 5 | Data no passado / fora do expediente / término depois das 18h | Avisa e pede outro horário; nada criado |
| 6 | Cliente muda de ideia antes de confirmar | Nova proposta com o dado novo; nada criado |
| 7 | Mensagem incompleta, completada em mensagens separadas | Na 2ª mensagem junta os dados e propõe |
| 8 | Cliente com agendamento ativo tenta marcar outro | Avisa que já existe agendamento e pergunta se quer remarcar ou marcar outro |
| 10 | Serviço mais curto e mais longo | `data_hora_fim` = início + duração do serviço (tabela `servicos`), `duracao_fonte: planilha` |
| 11 | Confirmação com variações ("sim", "blz", "pode", "👍") | Todas reconhecidas como confirmação → `Criar Evento` |
| 12 | Áudio / imagem / figurinha em vez de texto | Não quebra; pede para escrever; nada criado |
| 13 | Lembrete: confirma presença | `Enviar Confirmação Final` |
| 14 | Lembrete: cancela | `Cancelar Evento` + `UPDATE agendamentos SET status = 'cancelado'` |
| 15 | Lembrete: remarca para outro horário do mesmo dia | Propõe; após "sim", `Atualizar Evento` com fim = início + duração |
| 16 | Lembrete: remarca para outro dia | Idem 15, com a data nova |
| 18 | Lembrete: remarca para horário ocupado | `Pedir Outro Horário`; `Atualizar Evento` não executa |
| 19 | Lembrete: cliente não responde (timeout) | `Reverificar Agendamento` → `Avisar Timeout`; execução termina com sucesso |
| 24 | Situações esperadas (ocupado, fora do expediente) não disparam erro | Execução termina com `status: success` |
| 25a | Fuso horário perto da virada do dia (lógica) | Validação usa o dia/hora de São Paulo mesmo com servidor em UTC |
| 27 | Cliente pede pra IA sugerir uma data livre | Oferece 2-3 opções concretas dentro das janelas livres calculadas a partir do Calendar; nunca em horário ocupado/domingo/passado |
| 30 | Cliente com 2+ agendamentos ativos, referência ambígua ao cancelar | `agendamento_alvo = ""` → pergunta qual, listando os agendamentos reais lidos do Postgres; `Cancelar Evento` não executa |
| 31a | `beneficiario` resolve sozinho (só um agendamento com esse beneficiário) | Age direto no agendamento certo, sem perguntar |
| 31e | Agendar para outra pessoa ("...pra minha esposa Ana...") | `beneficiario: "Ana - esposa"` gravado em `agendamentos.beneficiario` no `INSERT` |
| G1–G3 | Guard-rail de formato da IA (ver seção própria abaixo) | Fallback correto, nada quebra o loop |
| E1–E24 | Escopo da conversa (ver seção própria abaixo) | Comportamento idêntico ao de produção |

> Esta tabela resume os cenários do roteiro original; a lista completa e mais granular (incluindo
> variações 27b–31f, M1–M8 de múltiplos agendamentos simultâneos, e G1–G3/E1–E24 detalhados) está
> em `automacao-pmes-whatsapp/docs/test-plan.md` — os mesmos cenários se aplicam aqui, trocando
> apenas "planilha" por "Postgres" na forma de fixar os nodes.

## Múltiplos agendamentos ativos simultâneos

Mesma lógica de produção: rodar com **2+ agendamentos ativos para o mesmo telefone**, misturando
beneficiários ("Eu mesmo", "Esposa", "Filho"). Para fixar, use linhas de pin no formato que as
queries Postgres devolvem (`event_id`, `status`, `data`, `beneficiario`, `servico` — ver
`docs/migracao-supabase.md` para o mapeamento exato de colunas).

## Guard-rail de formato da IA (todos os nodes com saída estruturada)

Não dá pra fazer o modelo errar o formato de propósito. Para testar, troque **temporariamente**,
no rascunho, o parser do node por um schema impossível (`schemaType: manual`, com uma propriedade
obrigatória `{"not": {}}`), rode e **restaure o parser original** — conferir depois que o
parâmetro voltou idêntico.

| # | Node | Esperado |
|---|---|---|
| G1 | `Interpretar Intenção do Cliente` (Agendamento) | Parser roda 2x; `Avisar Cliente Sobre Falha da IA` → `Escalar Falha da IA para a Equipe` (execução termina em erro de propósito → Error Workflow notifica) |
| G2 | `Classificar Resposta do Lembrete` (Lembrete) | Parser 2x por lembrete; cliente avisado; equipe notificada; loop segue para o próximo agendamento; nada confirmado/cancelado |
| G3 | `Classificar Confirmação da Remarcação` (Lembrete) | Mesmo fallback; `Atualizar Evento` **não** executa; loop segue |

## Escopo da conversa (encaminhar ao responsável / fora do escopo)

Mesmos cenários E1–E24 do roteiro de produção (perguntas fora do catálogo, fora de escopo,
jailbreak/prompt injection, endereço, forma de pagamento, nome do estabelecimento,
estacionamento) — o prompt da IA não mudou, então o comportamento esperado é idêntico. Ver
`automacao-pmes-whatsapp/docs/test-plan.md` para a tabela completa.

## Grupo B — Integração real

| # | Cenário | Esperado |
|---|---|---|
| 9 | Duas mensagens quase simultâneas do mesmo número | Só uma execução processa (lock); a outra é ignorada sem efeito colateral |
| 17 | Remarca duas vezes seguidas | Calendar fica com **1** evento, no horário final; **1** linha em `agendamentos` |
| 20 | Responde ao lembrete depois de já ter cancelado por outro canal | Não reativa nem remarca um agendamento cancelado |
| 21 | Resposta ao lembrete chega enquanto o Agendamento processa outra mensagem do mesmo cliente | Resposta não é descartada |
| 22 | Linha apagada manualmente no Postgres e cliente tenta remarcar | Não cria evento duplicado (depende de fallback pelo Calendar — não implementado) |
| 23 | Erro real (ex.: credencial inválida) | Notificação de erro chega no WhatsApp |
| 25b | Mensagem enviada entre 23h e 1h ("amanhã às 10h") | IA resolve "amanhã" pelo relógio real de São Paulo |
| 26 | Webhook do WhatsApp reenviando a mesma mensagem | Dedup por `message_id`; nenhum agendamento duplicado |
| 29 | Falha real de formato da IA em produção | Cliente recebe o aviso; notificação do Error Workflow chega no WhatsApp do responsável |
| 32 | Envio real do Lembrete com telefone numérico | O node devolve `messages[0].id` (wamid); nunca `{"error": "phoneNumber.replace is not a function"}` |
| **33 (novo)** | Dois clientes tentam marcar o mesmo profissional no mesmo horário exato, quase ao mesmo tempo | A exclusion constraint `agendamentos_sem_conflito` do Postgres garante que só um `INSERT` sobrevive, mesmo se a checagem de disponibilidade no Calendar tiver uma condição de corrida |
| **34 (novo)** | Serviço combinado sem item exato na tabela `servicos` (ex.: "corte e barba" quando só existem "Corte Masculino", "Barba" e "Corte + Barba" separados, mas o cliente pede uma combinação diferente) | Ver decisão em aberto em `docs/migracao-supabase.md` — hoje o `INSERT`/`UPDATE` falha; confirmar comportamento real e decidir o caminho antes de aprovar este cenário |

---

## Registro de execuções

_(registre aqui cada rodada de teste, no mesmo formato do roteiro de produção: data, versão do
workflow testada, resultado por cenário e evidência da execução)._

### Rodada 1 — Grupo A, cenários 1 a 8 (30/09/2026)

- **Workflow:** "Agendamento via WhatsApp (Supabase)" (`ny0fqlw8ojzmId7C`), versão
  `a85d413b-65a5-468b-803b-2c25f9807df4`, desativado. Repo no commit `1e2a570`.
- **Como:** `test_workflow` com pin em todos os nodes de WhatsApp, Google Calendar, Postgres, Data
  Tables e HTTP; o agente "Interpretar Intenção do Cliente" rodou de verdade (Claude Sonnet 5).
  Execuções entre 11h36 e 11h56 (horário de São Paulo), todas com `status: success`.
- **Pins:** serviços = os 3 do seed, com `preco` como texto (`"35.00"`), do jeito que o Postgres
  devolve `numeric`. "Buscar Profissional Ativo" com o `google_calendar_id` real do PROF-01 do seed
  e um `profissional_id` **fictício** (o seed não fixa UUIDs e o valor real não foi consultado no
  banco).
- **Resultado:** 7 cenários passaram; o cenário 8 falhou e fica registrado como **bug herdado,
  fora do escopo desta migração** (ver observações).

| # | Mensagem(ns) | Telefone | Resultado | Evidência |
|---|---|---|---|---|
| 1 | "Oi, quero marcar um Corte Masculino amanhã às 15h" → "sim, pode confirmar" | 5511900000101 | ✅ 1ª: `servico: Corte Masculino`, início 01/10 15h, fim 15h30 (`duracao_minutos: 30`, `duracao_fonte: planilha`), `confirmado: false` → `Propor Horário no WhatsApp`. 2ª: `confirmado: true` → `Criar Evento no Calendar` → `Salvar Cliente na Planilha` → `Confirmar Agendamento no WhatsApp` | exec. 1555, 1556 |
| 2 | "quero cortar o cabelo" | 5511900000102 | ✅ Datas vazias, pergunta dia e horário → `Responder Dúvida no WhatsApp`; nada criado. A IA já assumiu `Corte Masculino` e não perguntou o serviço | exec. 1557 |
| 3 | (a) "queria fazer cabelo e barba na sexta às 10h"; (b) "quero fazer um degradê amanhã às 14h" | 5511900000103, 5511900000113 | ✅ (a) mapeou para o nome oficial `Corte + Barba`, 50 min, propôs. (b) `servico: não especificado`, perguntou se é Corte Masculino ou Corte + Barba → `Responder Dúvida no WhatsApp`; não inventou serviço | exec. 1558, 1559 |
| 4 | "quero marcar Barba amanhã às 11h", com `Verificar Disponibilidade` → `available: false` | 5511900000104 | ✅ `Sugerir Outro Horário no WhatsApp`; `Criar Evento no Calendar` não executou | exec. 1560 |
| 5 | (a) "quero um Corte Masculino hoje às 9h" (já passado); (b) "...amanhã às 20h"; (c) "quero Corte + Barba amanhã às 17h30" (terminaria 18h20) | 5511900000105, 5511900000115, 5511900000125 | ✅ Nos três a IA deixou as datas vazias, explicou o motivo e pediu outro horário → `Responder Dúvida no WhatsApp`; nada criado | exec. 1561, 1562, 1563 |
| 6 | "quero marcar um Corte Masculino amanhã às 15h" → "pensando bem, melhor às 16h" | 5511900000106 | ✅ Nova proposta para 16h–16h30, `confirmado: false` → `Propor Horário no WhatsApp`; nada criado | exec. 1564, 1565 |
| 7 | "quero agendar uma barba" → "sexta às 10h" | 5511900000107 | ✅ 1ª pergunta dia e horário; 2ª junta os dados: `Barba`, 02/10 10h–10h20, propõe | exec. 1566, 1568 |
| 8 | Cliente com `Corte Masculino` ativo no sábado 03/10 às 10h: (a) "quero marcar uma Barba na sexta às 14h"; (b) "quero marcar um Corte Masculino sábado às 11h" | 5511900000108, 5511900000118 | ❌ **Bug herdado, fora do escopo.** Nas duas a IA recebeu o agendamento ativo na lista (`[evt_ativo_108] Corte Masculino — sábado, 03/10 ... às 10:00`), mas propôs o novo horário direto (`Propor Horário no WhatsApp`), sem avisar que já existe agendamento nem perguntar se quer remarcar ou marcar outro | exec. 1567, 1569 |

**Observações desta rodada**

- **Cenário 8 — bug herdado, fora do escopo desta migração.** O prompt do agente não tem regra
  mandando avisar sobre agendamento já existente ao marcar um novo. Esse prompt e toda a lógica de
  negócio (nodes de Code) são idênticos aos de produção — a migração só trocou a camada de dados —,
  então o mesmo input produziria a mesma falha em produção. Isso é conclusão por construção: o
  cenário não foi executado no workflow de produção nesta rodada. Não houve tentativa de correção,
  porque o prompt da IA não muda no escopo deste projeto; a correção, se for feita, é no repo de
  produção (`automacao-pmes-whatsapp`) e depois replicada aqui.
- **O que o pin não prova:** node fixado não avalia os próprios parâmetros. Esta rodada não
  exercitou o SQL, os `queryReplacement`, nem as expressions
  `$('Buscar Profissional Ativo').item.json.google_calendar_id` dos nodes de Calendar — isso só
  aparece em execução sem pin (Grupo B).
- **Cenário 5:** a própria IA recusou os três horários, então o ramo do Code "Validar Horário de
  Funcionamento" → `Avisar Horário Fora do Expediente no WhatsApp` não chegou a rodar.
- **Decisão do `servico_id`:** não foi tocada. Nos cenários 1–8 a IA devolveu sempre o nome exato
  do seed (`Corte Masculino`, `Barba`, `Corte + Barba`), então o `INSERT` casaria; com pin isso não
  é verificado de qualquer forma.
- **Preço:** a lista de serviços chega ao prompt como `R$ 35.00`, `R$ 75.00`, `R$ 50.00`.
- **Memória da IA:** funcionou entre execuções sequenciais do mesmo telefone (cenários 1, 6 e 7).
- Uma chamada de `test_workflow` (cenário 3b) expirou sem criar execução e foi repetida; a
  repetição é a exec. 1559.
