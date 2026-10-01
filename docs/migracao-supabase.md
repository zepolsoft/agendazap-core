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

### 5. Fuso do início e escrita que não acha a linha (rodadas 11 e 12)

Duas diferenças em relação ao Sheets, que guardava texto e nunca "falhava":

- **Fuso do horário de início.** A sessão do Postgres está em UTC: um início sem offset vindo da
  IA seria gravado 3 horas errado. Nos três nodes que gravam o início ("Salvar Cliente na
  Planilha", "Atualizar Linha na Planilha" e, no Lembrete, "Atualizar Data na Planilha"), o
  parâmetro passa por `DateTime.fromISO(<início da IA>, { zone: 'America/Sao_Paulo' }).toISO()`.
  Com offset, o instante é o mesmo. Sem offset, assume São Paulo. O fim já vinha do Code com
  `-03:00`.
- **Zero linhas.** O node Postgres se comporta de forma diferente para leitura e escrita:
  - `SELECT` com 0 linhas não emite item. O fluxo para ali.
  - `UPDATE … RETURNING` com 0 linhas emite `{ "success": true }`. O fluxo segue como se tivesse
    gravado.

  Por isso:
  - Os `SELECT`s "Reverificar Agendamento Antes do Timeout" (Lembrete) e "Buscar Horário
    Original" (os dois workflows) usam `alwaysOutputData: true`. Cada "Buscar Horário Original"
    é seguido de um If "Encontrou Horário Original?": no Agendamento, "Encontrou Horário
    Original? (Remarcar)".
  - O `UPDATE` de cancelamento ("Atualizar Linha na Planilha (Cancelar)" no Agendamento,
    "Atualizar Status na Planilha (Cancelar)" no Lembrete) é seguido do If "Cancelamento Gravado
    no Banco?", que testa `id`.
  - "Atualizar Data na Planilha" virou uma CTE que sempre devolve 1 linha (`id`,
    `linhas_atualizadas`), checada por "Remarcação Gravada no Banco?". Esse node não usa
    `alwaysOutputData`, porque tem saída de erro: com as duas opções ligadas, um erro dispara
    as duas saídas, a de sucesso com `{}`.

  Quando a linha não é encontrada, o tratamento depende do workflow:
  - **Agendamento** (fora de loop): aviso neutro ao cliente ("probleminha técnico", sem afirmar
    nem negar o resultado), depois Stop and Error, que dispara o Error Workflow para a equipe.
  - **Lembrete** (em loop): aviso neutro ao cliente, notificação à equipe pelo WhatsApp (mesmo
    número das outras notificações de erro) e volta ao "Processar Cada Agendamento". Não usa
    Stop and Error, que cortaria os lembretes dos outros clientes do lote.

  Detalhes e testes em `docs/test-plan.md`, rodadas 11 e 12.

### 6. Concorrência com o lembrete (rodada 15)

Duas mudanças de comportamento em relação à produção, para corrigir os achados R14-1 e R14-2 do
Grupo B:

- **Lembrete relê o status depois de cada Wait (R14-1).** Antes, depois que o cliente respondia
  ao lembrete, o Lembrete usava a linha lida às 8h. Um agendamento cancelado por outro canal
  durante a espera podia ser remarcado e voltar a `remarcado`, sem evento visível no Calendar.
  - Agora, logo depois de "Normalizar Resposta do Lembrete" e de "Normalizar Confirmação da
    Remarcação", os nodes "Reler Agendamento Após Resposta" e "Reler Agendamento Após
    Confirmação" leem o `status` (`SELECT`, com `alwaysOutputData` e
    `onError: continueRegularOutput`).
  - Os Ifs "Agendamento Ainda Ativo?" e "Agendamento Ainda Ativo? (Confirmação)" só seguem se o
    status for `agendado` ou `remarcado`.
  - Se não for (linha cancelada, concluída ou apagada), "Avisar Agendamento Inativo no WhatsApp"
    diz ao cliente que o horário não está mais ativo, que nada foi alterado, e convida a marcar
    outro. Depois volta ao loop, sem Calendar, sem banco e sem avisar a equipe, porque é um
    estado esperado e não um erro.
  - Se a releitura der **erro** de banco, o If deixa seguir, para não afirmar ao cliente algo que
    não foi verificado. O erro real é tratado adiante pelo caminho de erro de banco que já
    existe.
  - Segunda camada: os `UPDATE`s do Lembrete ("Atualizar Status na Planilha (Cancelar)" e
    "Atualizar Data na Planilha") passaram a exigir `AND status IN ('agendado', 'remarcado')`. Na
    corrida entre a releitura e o `UPDATE`, o resultado é 0 linhas. Isso cai nos caminhos de 0
    linhas da rodada 12 (aviso neutro ao cliente e notificação à equipe), porque nesse ponto o
    Calendar já foi alterado.
  - Para encaixar a releitura, "Classificar Confirmação da Remarcação" lê a resposta por
    `$('Normalizar Confirmação da Remarcação').item.json.resposta_confirmacao` em vez de
    `$json.resposta_confirmacao`. O texto do prompt não mudou.
- **Espera do lembrete antes do lock do telefone (R14-2).** A ordem no Agendamento era dedup →
  lock → espera. Uma resposta ao lembrete que chegasse até 10 s depois de outra mensagem do
  cliente era descartada.
  - Agora a ordem é dedup → "Verificar Espera de Lembrete" → (sem espera) lock.
  - A resposta ao lembrete é encaminhada sem passar pelo lock.
  - Depois de um encaminhamento bem-sucedido, "Registrar Lock do Telefone (Encaminhamento)"
    grava o lock.
  - Se o encaminhamento falhar (por exemplo, `409 "execution is running already"`, quando o
    Lembrete ainda processa a mensagem anterior), a mensagem cai no lock normal e é ignorada.
    Assim ela nunca roda no Agendamento ao mesmo tempo que o Lembrete.
  - A versão de produção (Sheets) tem a mesma ordem dedup → lock → espera; isso foi conferido
    numa execução real de produção. Se ela também sofre do R14-1 não foi verificado.

Detalhes e testes em `docs/test-plan.md`, rodada 15.

## Decisão em aberto: nome do serviço vs. `servico_id`

> **Decisão adiada para depois do cutover (01/10/2026, rodada 17).** José decidiu não escolher
> agora um dos caminhos abaixo. Motivo: com o achado R16-1 corrigido na rodada 17, a falha
> deixou de ser silenciosa e virou uma falha **tratada**. Se um nome de serviço fora do catálogo
> chegar ao `INSERT`:
> - o evento recém-criado é desfeito no Calendar;
> - o cliente recebe o aviso neutro de erro ("tive um probleminha técnico… nossa equipe já foi
>   avisada…");
> - a equipe recebe a notificação do Error Workflow com o erro do banco.
>
> Somado a isso, na conversa real a IA se limita ao catálogo (rodada 16, cenário 34a). O risco
> restante é o cliente precisar ser atendido manualmente nesse caso raro. A decisão continua
> aberta e deve ser retomada depois do cutover.

**Este era o ponto que precisava de uma decisão antes de considerar a migração pronta para
produção** (ver o aviso acima: adiada para depois do cutover).

> **Bloqueio original (superado):** a recomendação era não rodar testes sem pin no Postgres nem
> usar esta versão em produção enquanto a decisão não fosse tomada. O Grupo B rodou mesmo assim
> (rodadas 14 a 17), com o comportamento confirmado no cenário 34, e a decisão foi adiada para
> depois do cutover pelo motivo do aviso acima.

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

**Comportamento real confirmado (rodada 16, cenário 34; detalhes em `docs/test-plan.md`):**
- Na conversa real, pedindo "corte, barba e sobrancelha", a IA **não** gerou um nome fora do
  catálogo. Ela respondeu que sobrancelha não existe e propôs só "Corte + Barba". O `INSERT`
  resolveu o `servico_id` normalmente.
- Forçando o nome inexistente "Corte + Barba + Sobrancelha" na saída da IA (pin só nesse node), o
  `INSERT` falhou com `null value in column "servico_id" … violates not-null constraint`. A
  execução terminou no Stop and Error "Escalar Erro ao Gravar Agendamento no Banco", que em
  produção dispara o Error Workflow para a equipe.
- Efeitos colaterais desse caminho, que valem para **qualquer** erro de `INSERT` que não seja
  conflito, não só para o serviço:
  - o evento já criado no Calendar **fica órfão**, porque "Desfazer Evento Criado no Calendar" só
    roda no caminho de conflito;
  - o cliente **não recebe nenhuma mensagem**.
  - Registrado como achado R16-1 no `docs/test-plan.md`. **Corrigido na rodada 17:** o evento é
    desfeito e o cliente avisado antes do Stop and Error. Validado de verdade em produção no
    cenário 23.

## Como importar e testar

1. No n8n, importe os 3 arquivos JSON de `workflows/*/`. Eles chegam **desativados** por padrão.
2. Em cada node Postgres, troque a credencial `Supabase - agendazap-core` (placeholder) pela sua
   credencial real já configurada (a mesma usada nos testes de `db/001_initial_schema.sql`).
3. Rode os testes do Grupo A do `docs/test-plan.md` (do repo `automacao-pmes-whatsapp`) contra
   esta versão, usando os 2 profissionais de `db/002_seed_exemplo.sql` como dado de teste — sem
   tocar nos workflows de produção.

## Checklist de cutover: reverter o trigger temporário

> **Executado na rodada 17 (01/10/2026), itens 1 a 6.** O Agendamento voltou ao WhatsApp Trigger
> original: mesmo `id`, `webhookId` `15600388-12a1-4b4f-97c3-9ac5c8e3f5b0` e credencial. A
> referência em "Encaminhar Mensagem para Lembrete" foi restaurada. O workflow está desativado e
> **sem versão publicada**: o item 7 (ativar) é a decisão de cutover, separada. Detalhes em
> `docs/test-plan.md`, rodada 17. O texto abaixo fica como registro do procedimento.

Desde a rodada 13 (`docs/test-plan.md`), o "Agendamento via WhatsApp (Supabase)" está com um
trigger **temporário**, só para rodar o Grupo B:
- **"Receber Mensagem (Webhook Temporário)"**: Webhook `POST`, path aleatório, `responseMode:
  onReceived`;
- **"Extrair Mensagem do Webhook"**: Set `raw` com `jsonOutput = {{ $json.body }}`.

Esse trigger **não pode ir para produção**: a Meta não chama esse Webhook, e ele aceita qualquer
`POST` de quem souber a URL. Antes de qualquer cutover (e antes de ativar o workflow para receber
mensagens reais), reverta nesta ordem:

1. **Confirme que nada do Grupo B depende mais do Webhook.** Se o workflow estiver publicado,
   despublique.
2. **Remova** os nodes "Receber Mensagem (Webhook Temporário)" e "Extrair Mensagem do Webhook".
3. **Recoloque o WhatsApp Trigger original**, exatamente como estava até a rodada 12 (commit
   `8d63880`):
   ```json
   {
     "name": "Receber Mensagem WhatsApp",
     "type": "n8n-nodes-base.whatsAppTrigger",
     "typeVersion": 1,
     "position": [240, 1936],
     "parameters": { "updates": ["messages"], "options": {} },
     "webhookId": "15600388-12a1-4b4f-97c3-9ac5c8e3f5b0"
   }
   ```
   Use a credencial de WhatsApp Trigger já configurada na instância ("WhatsApp OAuth account").
   O nome do node tem que ser exatamente "Receber Mensagem WhatsApp".
4. **Religue** "Receber Mensagem WhatsApp" → "Filtrar Apenas Mensagens".
5. **Restaure a referência** em "Encaminhar Mensagem para Lembrete":
   `jsonBody = {{ $('Receber Mensagem WhatsApp').item.json }}`. Hoje ela aponta para
   `$('Extrair Mensagem do Webhook')`. Nenhum outro node cita o trigger pelo nome.
6. **Confira** com um diff contra o JSON do commit `8d63880`: só podem sobrar as mudanças feitas
   depois da rodada 13. Rode `validate_workflow` e re-exporte o JSON.
7. **Só então ative** (isso registra o webhook na Meta), seguindo o plano de cutover.

O Lembrete não muda de trigger: os Schedule e os Waits dele são os originais.
