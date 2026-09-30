---
name: n8n-node-conventions
description: Nomenclatura e organização dos nodes dentro dos workflows n8n deste projeto
---

# Convenções de nodes n8n

Mesma base do projeto de produção (`automacao-pmes-whatsapp`), com o acréscimo da convenção para
nodes de Postgres (item novo no final).

## Nomenclatura

- Nome do node sempre em português, descrevendo a ação (verbo + objeto), não o tipo técnico.
  - Bom: "Receber Mensagem WhatsApp", "Verificar Disponibilidade", "Criar Evento no Calendar",
    "Buscar Agendamentos Ativos do Cliente", "Responder Cliente"
  - Evitar: "Webhook1", "Postgres", "HTTP Request"
- Nodes de decisão (`If`/`Switch`) nomeados pela pergunta que respondem:
  "Horário Disponível?", "Cliente Confirmou, Cancelou ou Remarcou?"
- Cada saída de um `Switch`/`If` deve ter um nome de branch claro correspondente ao caso
  (ex.: "Confirmar", "Cancelar", "Remarcar").

## Organização

- Fluxo principal em linha reta da esquerda para a direita; ramificações (If/Switch) para
  baixo a partir do ponto de decisão.
- Um node = uma responsabilidade. Evitar node de Code fazendo múltiplas transformações não
  relacionadas — preferir Set/Edit Fields nomeados quando possível.
- AI Agent nodes: nomear pelo que o agente decide (ex.: "Interpretar Intenção do Cliente",
  "Classificar Resposta do Lembrete"), com o prompt do sistema em `prompts/` referenciado no
  node.

## Guard-rail obrigatório em todo node de IA com saída estruturada

Qualquer AI Agent com Structured Output Parser pode receber uma resposta fora do schema
("Model output doesn't fit required format"). Ninguém controla quando isso acontece, então todo
node desse tipo nasce com:

1. `retryOnFail: true`, `maxTries: 2`, `waitBetweenTries: 1000`, aplicados via `setNodeSettings`,
   nunca `setNodeParameter`. Os dois funcionam juntos com o item 2 no AI Agent v3.
2. `onError: "continueErrorOutput"`, com a saída de erro (índice 1) ligada a um fallback que:
   - avisa o cliente de forma educada, sem jargão, dizendo que alguém da equipe vai responder e
     que nada foi alterado;
   - avisa a equipe com o telefone, a mensagem original, o contexto e o `error`;
   - em workflow com **loop** (ex.: lembrete diário), volta para o loop e **não usa** Stop and
     Error, que encerraria o processamento dos outros itens. Fora de loop, Stop and Error depois
     do aviso ao cliente dispara o Error Workflow.
3. Regra no prompt: "o campo output é um OBJETO JSON, nunca uma string contendo JSON".
4. Teste em `docs/test-plan.md` (seção "Guard-rail de formato da IA"): trocar o parser
   temporariamente por um schema impossível, rodar, restaurar e conferir.

## Sticky notes

- Usar sticky notes para marcar as grandes seções do workflow (ex.: "1. Trigger", "2. IA",
  "3. Calendar", "4. Banco de dados", "5. Resposta") quando o workflow tiver mais de ~8 nodes.

## Nodes de Postgres (Supabase)

- Nome do node segue a mesma regra: verbo + objeto em português (ex.: "Buscar Profissional
  Ativo", "Salvar Cliente na Planilha" — mantido esse nome específico na migração para não
  quebrar as dezenas de referências `$('Salvar Cliente na Planilha')` já espalhadas pelo
  workflow; em node **novo**, prefira já nomear pensando no banco, ex. "Salvar Agendamento no
  Banco").
- Operação: `executeQuery` com SQL parametrizado (`$1, $2...`) via "Query Parameters" —
  **nunca** concatenar valor do cliente direto na string da query (SQL injection).
- Sempre que a query alimenta um node de Code já existente, usar `AS` para que as colunas
  devolvidas tenham o mesmo nome que o Code espera (ex.: `google_event_id AS event_id`,
  `data_hora_inicio AS data`) — evita ter que reescrever lógica downstream.
- Credencial: usar a credencial Postgres já configurada na instância n8n (nome real, não
  placeholder) ao editar de verdade; nos JSONs commitados nesse repo, a credencial fica como
  placeholder (`Supabase - agendazap-core`), igual à regra de "nunca commitar credenciais reais".
