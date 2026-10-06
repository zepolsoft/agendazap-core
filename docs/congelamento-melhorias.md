# Congelamento das melhorias (05/10/2026)

As melhorias do pacote de qualidade de mensagem (A1, A2, B, D, templates, mini-CRM) estão
**congeladas**. O objetivo agora é manter a demonstração do AgendaZap funcionando como estava na
sexta (02/10/2026). Nada abaixo foi publicado; os rascunhos ficam parados até haver motivo para
publicar. Detalhes de cada rodada de testes: `docs/test-plan.md` (Round 24).

## Atualização de 06/10/2026: saldo regularizado, demonstração validada

A chamada mínima de IA respondeu 200 às 10:27Z (organização `2adb30ac…`). O fluxo **publicado**
(Agendamento `bc334c4a`, conteúdo idêntico restaurado no rascunho só para o teste) foi validado com um
número falso: conversa nova, agendar (evento criado no Google Agenda), remarcar, cancelar (evento
removido) e pergunta fora do escopo, todos com a intenção e o texto esperados. O histórico gravou 14
mensagens (7 de entrada, 7 de saída). Dados de teste, Data Tables e o evento foram limpos. O rascunho do
Agendamento voltou ao A2 (`e9e414a3`); nada foi publicado. Lembrete e Registrar Mensagem não precisaram
de teste novo (o Lembrete só roda às 8h e às 22h).

O texto abaixo descreve o bloqueio que existiu entre 10:13 SP e a regularização.

## Bloqueio atual: saldo da API da Anthropic

Desde ~10:13 (SP) de 05/10/2026 toda chamada de IA falha com `400 invalid_request_error`:
"Your credit balance is too low to access the Anthropic API". No n8n aparece como "Bad request -
please check your parameters", e o cliente recebe "Opa, me enrolei aqui…". Não é problema de
modelo, parâmetro ou chave (seria 401/429): é saldo da organização `2adb30ac…`, workspace
`wrkspc_01Daax…` (a resposta da API informa os dois). Quatro verificações depois da compra de crédito
(19:00 a 19:20Z) ainda falharam.

O que conferir no Console da Anthropic:

1. **Billing**: saldo acima de zero; em Invoices, compra paga (pendente ou recusada não libera).
2. **Organização**: o crédito entrou em `2adb30ac…` (o seletor fica no canto superior esquerdo).
3. **Workspace**: sem limite de gasto baixo ou zerado em Settings → Workspaces.
4. **Chave**: a colada na credencial "Anthropic account" do n8n é do workspace acima.
5. Saldo positivo e erro persistindo por mais de ~10 min: chamado no suporte com o `request_id`.

Depois de resolver: uma chamada mínima de IA; se responder, validar o fluxo **publicado** com
números falsos (conversa nova, agendar, remarcar, cancelar, pergunta fora do escopo), conferindo
evento no Google Agenda e histórico em `mensagens`, e limpar dados e eventos de teste.

## Publicado em produção (intocado)

| Workflow | ID | Versão publicada |
|---|---|---|
| Agendamento via WhatsApp (Supabase) | `ny0fqlw8ojzmId7C` | `bc334c4a` |
| Lembrete, Cancelamento e Remarcação (Supabase) | `0mPYXZesloutZbek` | `051b4e6b` |
| Registrar Mensagem [v2 historico] | `KcPWQc7VJbj2e4sf` | `38ec1e6c` |
| Notificação de Erros | `ZxJfBbFmiD5Hqp5o` | `be7b77da` |

Verificado em 05/10/2026: versões publicadas idênticas às acima e webhookId do gatilho do
Agendamento inalterado.

## Rascunhos (não publicados)

| Ciclo | Onde | Versão | Estado | Falta para publicar |
|---|---|---|---|---|
| **A1** | Agendamento | `7a8816bc` | Pronto e testado com números falsos (cancelamento, consulta, vínculo mensagem→agendamento, template `aviso_equipe_v1` só como texto). Versão intermediária do A2. | Publicação, só depois das 20h SP e com comando explícito. |
| **A2** | Agendamento | `e9e414a3` (inclui A1) | Prompt (estilo, honestidade, profissional, saudação, mesma data), contexto da conversa e textos fixos prontos. Parte da regressão passou. | Regressão curta de 5 cenários (pergunta mista, "quem atende hoje" com agendamento no dia, 2ª mensagem sem saudação, "você é uma pessoa?", confirmação) — **exige a API**. Texto de instabilidade ainda não inserido (ver abaixo). |
| **B** | Lembrete | `6c922351` (conteúdo = `fff68d93`) | Prompts, textos, cancelamento com profissional e aviso de timeout só com cliente ativo nas últimas 24h prontos. Testes sem IA passaram. | 3 testes pós-Wait (confirmo, remarcar, cancelar) — **exige a API**. Rascunho verificado: 110 nodes, nenhum desabilitado. |
| **D** | Workflow novo `U3P466VzvV30hWzk` (inativo) + Data Table `saude_ia_incidentes` | — | Verificação a cada 15 min (8h–20h), chamada mínima na Anthropic + GET do número no WhatsApp, incidente por serviço/tipo com cooldown de 30 min, aviso de "voltou". Testado com respostas simuladas; GET real da Graph API validado. | Credencial **"SMTP account"** (e-mail de backup) e os nodes de e-mail; exportar o JSON sanitizado para `workflows/`; publicar **só com a API funcionando** (senão alerta a cada falha). |
| **C** | Agendamento e Lembrete | — | Não iniciado. | Aprovação da Meta dos templates `lembrete_agendamento_v1` e `aviso_equipe_v1` (submissão é do dono). |

Ajuste aprovado e ainda não aplicado: novo texto de falha da IA ao cliente ("Estou com uma
instabilidade aqui e não consegui te responder agora. Tenta de novo em alguns minutos, por favor
🙏") no A2 (node "Avisar Cliente Sobre Falha da IA" + cópia do histórico) e no B ("Preparar Aviso de
Falha da IA" + cópia do histórico).

## Regras de publicação (valem para qualquer ciclo)

Só depois das 20h SP; só com comando explícito do dono ("publicar …") e `versionId` explícito;
antes, conferir que não há execuções em andamento nem conversas nos últimos 5 minutos; depois,
verificar o webhookId do gatilho e as versões, exportar os JSONs sanitizados, atualizar a docs e
commitar. Manter o rollback (restaurar a versão publicada anterior).

## Ordem recomendada quando surgir o primeiro cliente

1. Resolver o saldo da API e rodar a validação do fluxo publicado (acima).
2. **D** (com a credencial SMTP): a primeira coisa que um cliente real precisa é saber, em minutos, se
   a IA ou o token do WhatsApp caíram.
3. **A1** e, depois de validado pelo dono, **A2** (regressão curta antes), já com o texto de instabilidade.
4. **B** (3 testes pós-Wait antes), com o texto de instabilidade.
5. **C** quando a Meta aprovar os templates: avisos à equipe e lembrete fora da janela de 24h.

## Pendências de housekeeping

- Sanitizar `workflows/notificacao-erros/notificacao-erros.json` (ainda tem telefone do responsável e
  phoneNumberId reais) na próxima exportação. O histórico público do git já contém esses valores de
  exports antigos.
- Fazer `git push origin main` (o dono; sem credenciais no shell do Claude).
