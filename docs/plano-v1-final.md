# Plano para fechar a v1 (piloto com cliente real)

Criado em 06/10/2026. Complementa `docs/congelamento-melhorias.md`. **Nada deste plano é publicado sem
o comando explícito do dono, só depois das 20h (horário de SP), uma publicação por vez e sempre com
rollback.** Dados reais (telefone, e-mails, IDs de conta) nunca entram no repositório: use os
placeholders de `.env.example`.

## Regras de negócio que valem para todas as etapas

- O lembrete sai **somente às 8h** e **somente para agendamentos do dia atual** (fuso de SP).
- Nenhuma mensagem espontânea a clientes depois das 20h. Respostas a mensagens que o próprio cliente
  mandou não são espontâneas.
- Alertas ao responsável saem por WhatsApp e por e-mail em paralelo (e-mail não depende do WhatsApp).
- O bot se apresenta como assistente virtual e avisa, na primeira conversa, que guarda nome, telefone e
  histórico.

## Estado de partida (06/10/2026)

Publicado: Agendamento `bc334c4a`, Lembrete `051b4e6b`, Registrar Mensagem `38ec1e6c`, Notificação de
Erros `044473ce`, D (Verificação de Saúde) `f5e9917a`.

Pré-requisitos fora do n8n (não dependem de código, mas bloqueiam o que vem depois):

1. Método de pagamento válido na conta WhatsApp Business (hoje a conta está `BLOCKED` para conversas
   iniciadas pelo negócio, erro 141006) e verificação do negócio (erro 141010).
2. Submeter e aprovar os templates `lembrete_agendamento_v1` e `aviso_equipe_v1` (Utility, pt_BR).
3. Nome de exibição do número e quem é o "responsável" que recebe os alertas.

## Fase 1: rascunhos prontos, publicação em duas etapas

### 1A. Remendo do Lembrete atual (rascunho `d48ce044`)

- **Entregável:** só a query de "Buscar Agendamentos de Hoje (Planilha)" muda: `WHERE data_hora_inicio
  >= now() + interval '30 minutes'` e `ORDER BY data_hora_inicio, criado_em`. O restante é idêntico à
  publicada `051b4e6b` (diff de um node). O rascunho **não** contém o B (que continua no histórico:
  `fff68d93` e `6c922351`).
- **Testes feitos (06/10):** 4 agendamentos fictícios inseridos fora de ordem (+3h07, 1h13 no passado,
  +1h03, +19 min) mais um real do dia. Saída do filtro: 09:44, 11:48 e depois o real das 16:00; o
  passado e o de 19 min ficaram de fora. Dados de teste apagados.
- **Limite conhecido:** a fila continua sequencial (até 10 min por cliente sem resposta); o remendo só
  garante a ordem e evita avisar quem está a menos de 30 min do horário. O texto de falha da IA do
  Lembrete continua o antigo até a Etapa 3 (o Lembrete novo não tem IA).
- **Critério de pronto:** publicada a `d48ce044`; no dia seguinte, o disparo das 8h termina com sucesso,
  na ordem dos horários, sem lembrete para horário passado.
- **Rollback:** publicar de novo `051b4e6b`.

### 1B. A2 completo (rascunho `b0ca5857`)

- **Entregável (sobre o A2 `e9e414a3`):** aviso de privacidade em mensagem separada na primeira conversa
  do cliente (nodes "Cliente Novo?", "Enviar Aviso de Privacidade no WhatsApp", histórico e "Retomar
  Contexto da Conversa"); regra de privacidade (pedido de apagar dados vira `encaminhar`; vive em
  "Formatar Contexto da Conversa" para não reenviar o prompt inteiro); texto de instabilidade da IA sem
  prometer uma pessoa, na mensagem ao cliente, no histórico e na mensagem à equipe. Persona de
  assistente virtual, saudação uma vez por dia, profissional nas confirmações e pergunta mista já
  estavam no A2.
- **Textos:** privacidade: "Antes de começar: sou o assistente virtual da Barbearia ZAP e guardo seu
  nome, telefone e o histórico desta conversa só para cuidar do seu atendimento. Se preferir que eu
  apague, é só me avisar por aqui." Instabilidade: "Estou com uma instabilidade aqui e não consegui te
  responder agora. Tenta de novo em alguns minutos, por favor 🙏".
- **Testes feitos (06/10, IA real, números fictícios, envios fixados):** cliente novo ("Oi") recebe o
  aviso e depois a boas-vindas; segunda mensagem sem aviso e sem nova saudação; "você é uma pessoa de
  verdade?" responde que é assistente virtual; agendar com pergunta sem resposta (Red Bull) agenda e
  diz que não sabe; confirmação cria o evento e informa o profissional; pedido de apagar dados vira
  `encaminhar`; falha da IA (modelo inválido temporário, restaurado) envia o texto novo e escala à
  equipe. Dados e evento de teste apagados.
- **Regra da mesma data (completada em 06/10, versão `b0ca5857`):** na primeira rodada (`9c1084ff`) o pedido
  de um segundo horário livre no mesmo dia respondeu "…também tá disponível" sem citar o agendamento
  existente. Foi acrescentada a "REGRA — NOVO HORÁRIO NO MESMO DIA" ao contexto da conversa (node "Formatar
  Contexto da Conversa", junto da regra de privacidade). Reteste com cliente fictício que já tinha corte hoje
  às 13h e pediu barba hoje às 15h: "Você já tem o corte masculino hoje às 13h — esse seria um segundo
  horário. Barba às 15h está livre, quer marcar mesmo assim?". "Quem atende hoje?" menciona o agendamento do
  dia e lista os profissionais que atendem. Remarcar/cancelar foram validados no fluxo publicado em 06/10.
- **Critério de pronto:** publicada a `b0ca5857`; webhookId do gatilho `15600388…` inalterado; uma
  mensagem real do dono é respondida; uma hora sem execuções com erro.
- **Rollback:** publicar de novo `bc334c4a`.

### Plano de publicação da Fase 1 (hoje, depois das 20h SP)

Pré-checagens para cada publicação: relógio em SP ≥ 20:00; nenhuma execução em andamento; nenhuma
conversa nos últimos 5 minutos; versões publicadas atuais conferidas (`bc334c4a`, `051b4e6b`).

1. **Primeiro o remendo do Lembrete** (`d48ce044`): publicar com `versionId` explícito; conferir versão
   ativa e os dois agendadores (8h e 22h); nada para testar na hora (o gatilho é diário). Conferência
   no dia seguinte, depois das 8h. Exportar JSON sanitizado, atualizar docs, commitar.
2. **Depois o A2** (`b0ca5857`): publicar com `versionId` explícito; verificar `webhookId` e a versão; o
   dono manda uma mensagem real; conferir a execução e a linha em `mensagens`. Exportar, docs, commit.
3. Entre uma publicação e outra, esperar a verificação da anterior terminar. Se algo falhar, rollback
   imediato para a versão anterior e parar.

## Fase 2: sequência planejada (nada executado ainda)

Ordem e dependências: **006 → E2 → E3 → E4**; E5 é independente e pode ir junto com a 006.

### Etapa 1: migração `db/006_lembretes_estabelecimentos.sql` (as duas tabelas juntas)

- **Entregáveis:**
  - `lembretes`: `id`, `agendamento_id` (FK), `data_ref` (data do lembrete, fuso de SP), `enviado_em`,
    `wa_message_id`, `status` (`enviado`, `falhou`), `respondido_em`; **índice único em
    `(agendamento_id, data_ref)`** para impedir lembrete duplicado.
  - `estabelecimentos` (uma linha por enquanto): `nome`, `nome_exibicao`, `telefone_responsavel` (só
    dígitos), `email_alertas`, `phone_number_id`, `fuso`, `hora_lembrete` (8), `hora_limite_envio` (20),
    `usa_template_lembrete`, `ativo`.
  - RLS ligado sem políticas nas duas tabelas (igual a `clientes` e `mensagens`); só aditiva, com
    `lock_timeout` e transação como a 003; um `006_rollback.sql` ao lado.
  - O seed com os valores reais (telefone, e-mails) é inserido pelo dono no SQL Editor; o repositório
    guarda só placeholders.
- **Testes:** rodar a migração duas vezes (idempotente); inserir e apagar um `lembretes` de teste; tentar
  inserir duplicado (deve falhar pelo índice); `clientes_resumo` e as queries dos workflows publicados
  continuam funcionando (nenhuma usa `SELECT *`).
- **Critério de pronto:** tabelas criadas, seed inserido, workflows publicados sem erro por uma hora,
  `db/README.md` atualizado.
- **Rollback:** reverter qualquer workflow que já use as tabelas e então `006_rollback.sql` (as tabelas
  são novas, sem dado a preservar).

### Etapa 2: Agendamento (nova intenção `confirmar`, bloco LEMBRETE DE HOJE, leitura da configuração)

- **Entregáveis:**
  - Primeiro node lê `estabelecimentos` (telefone do responsável, `phone_number_id`, nome); os nodes de
    envio ao responsável e o nome da barbearia passam a usar essa leitura.
  - Bloco "LEMBRETE DE HOJE" no prompt, vindo de `lembretes` (+ status do agendamento) para o telefone.
  - Intenção `confirmar` que grava `status = 'confirmado'` e responde com texto fixo; se houver mais de um
    agendamento no dia, pergunta qual; "ok"/"sim" sem lembrete enviado continua `duvida`.
  - Remoção do ramo "Verificar Espera de Lembrete / Encaminhar Mensagem para Lembrete" (4 nodes).
  - Cancelar e remarcar continuam como estão.
- **Testes de regressão (IA real, números fictícios):** conversa nova, agendar, remarcar, cancelar,
  fora do escopo, pergunta mista, privacidade; novos: "confirmo" com um e com dois agendamentos no dia,
  "ok" sem lembrete, "cancela" depois do lembrete, remarcar depois do lembrete; falha da IA; confirmar
  evento criado e removido no Calendar e `mensagens` gravada; limpeza.
- **Critério de pronto:** todos os cenários acima passam; nenhuma regressão no fluxo publicado
  comparado com `bc334c4a`/A2; uma hora sem erros em produção.
- **Rollback:** publicar a versão anterior do Agendamento (A2 `b0ca5857`).

**Anotação para esta etapa (pedida em 06/10):** quando o cliente já tem agendamento no dia e pede **outro
serviço**, a IA deve oferecer **juntar os serviços no mesmo atendimento**, se houver tempo livre logo após o
horário existente (somando as durações). Ex.: tem corte às 13h e pede barba: "Dá pra fazer a barba logo
depois do corte, às 13h30 (corte + barba, 50 min no total). Quer juntar?". Pontos a decidir ao implementar:
verificar na agenda a janela livre imediatamente após o fim do agendamento existente; ao aceitar,
estender o evento do Calendar e o registro em `agendamentos` (ou criar um segundo agendamento colado, o
que a exclusion constraint do banco já permite) e ajustar o serviço (existe o serviço "Corte + Barba");
se não houver tempo livre, manter o fluxo de segundo horário atual. Fica na Etapa 2 (Agendamento), com
regressão própria.

### Etapa 3: Lembrete novo (envio em paralelo às 8h, sem esperas)

- **Entregáveis (de 108 para uns 15 nodes):** gatilho 8h; leitura da configuração; query de hoje (data
  de hoje em SP, status `agendado`/`remarcado`, início ≥ agora + 30 min, sem linha em `lembretes` para a
  data, `ORDER BY` horário); guarda: aborta se a hora for ≥ `hora_limite_envio`; envio em lote rápido;
  registro em `lembretes` (enviado/falhou) e no histórico; falha de um envio não bloqueia os demais e gera
  um aviso único ao responsável no fim. Sem IA, sem Wait, sem aviso de timeout. O job das 22h (marcar
  concluídos) fica igual. A Data Table `esperas_lembrete` é aposentada.
- **Testes:** 3, 10 e 25 agendamentos fictícios (ordem, tempo total, nenhum envio duplicado se rodar
  duas vezes), agendamento a menos de 30 min e já passado ficam de fora, execução simulada às 21h aborta,
  falha forçada de um envio (número inválido) não impede os outros e gera o aviso.
- **Critério de pronto:** primeiro disparo real das 8h termina em segundos, na ordem, com `lembretes`
  preenchida; respostas tratadas pelo Agendamento (Etapa 2).
- **Rollback:** republicar o remendo `d48ce044` do Lembrete antigo (ou `051b4e6b`) e a Etapa 2 anterior
  continua compatível (o ramo de espera só deixa de ser usado).

### Etapa 4: template ligado por `usa_template_lembrete` (ciclo C)

- **Pré-requisitos:** pagamento e templates aprovados na Meta (ver acima).
- **Entregáveis:** no Lembrete novo, um Switch por `usa_template_lembrete`: falso envia texto livre
  (só chega dentro da janela de 24h), verdadeiro envia `lembrete_agendamento_v1` com 4 variáveis (nome,
  serviço, horário, estabelecimento). Alertas ao responsável passam a `aviso_equipe_v1` (variáveis sem
  quebra de linha). Ligar a opção é uma mudança de dado na tabela, sem republicar.
- **Testes:** envio real de template a um número do dono; falha de template (nome errado) gera aviso;
  resposta do cliente ao template chega ao Agendamento e é tratada.
- **Critério de pronto:** lembrete entregue a um cliente fora da janela de 24h.
- **Rollback:** `usa_template_lembrete = false` (volta ao texto livre) sem republicar.

### Etapa 5: Notificação de Erros e D com configuração fora do Supabase

- **Entregáveis:** uma Data Table do n8n `configuracao_alertas` (telefone e e-mail do responsável, nome do
  estabelecimento) lida pela Notificação de Erros e pela D; assim, se o banco cair, o alerta ainda sai.
  Valor atual fica como fallback. A D passa a consultar também o `health_status` da conta WhatsApp Business
  (pagamento e verificação).
- **Testes:** erro controlado e falha simulada com leitura da tabela; tabela vazia usa o fallback; os dois
  canais continuam independentes.
- **Critério de pronto:** trocar o telefone na tabela muda o destino dos alertas sem editar workflows.
- **Rollback:** restaurar as versões anteriores (`044473ce` da Notificação de Erros e `f5e9917a` da D).

## Itens de fora do código (para o piloto)

Dados reais do barbeiro (serviços, horários, profissionais, calendário), troca do bloco "barbearia de
demonstração" do prompt e dos textos fixos pelo nome real, procedimento documentado para apagar os dados
de um cliente a pedido, e ensaio com 5 a 10 clientes reais acompanhando `mensagens` e as execuções.
