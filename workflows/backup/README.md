# Backup dos workflows publicados — 02/10/2026

Cópia dos 3 workflows em produção, tirada **antes** da migration de `clientes`/`mensagens`
(`db/003_clientes_mensagens.sql`), como ponto de rollback. Desde a fase 2 (rodada 23, 02/10/2026) os workflows publicados são
Agendamento `bc334c4a…` e Lembrete `051b4e6b…`; estes arquivos continuam sendo a versão anterior.

| Workflow | ID na instância | Versão publicada (`activeVersionId`) | Nodes | Arquivo |
|---|---|---|---|---|
| Agendamento via WhatsApp (Supabase) | `ny0fqlw8ojzmId7C` | `68c7d91c-a5d0-47e7-926c-d0a6b905f5ac` | 114 | `agendamento-whatsapp.json` |
| Lembrete, Cancelamento e Remarcação (Supabase) | `0mPYXZesloutZbek` | `56eb95e1-aeb2-41e6-8b1d-8f88dc85aed5` | 88 | `lembrete-cancelamento-remarcacao.json` |
| Notificação de Erros | `ZxJfBbFmiD5Hqp5o` | `be7b77da-b1cc-40e2-9c95-86ae05eeec1c` | 3 | `notificacao-erros.json` |

## Como usar para rollback

1. **Caminho preferido (exato):** na instância n8n, restaurar a versão da tabela acima pelo
   histórico do workflow (`restore_workflow_version` + `publish_workflow` com o `versionId`). É
   uma cópia byte a byte, com as credenciais reais.
2. **Se o histórico não estiver disponível:** importar o JSON desta pasta. O repositório é
   público, então três tipos de valor foram trocados por placeholders:
   - IDs de credencial → `SUBSTITUA_PELO_ID_DA_CREDENCIAL`. Depois de importar, reapontar cada node
     para a credencial real (Postgres, WhatsApp, Google Calendar, Anthropic);
   - `webhookId` do WhatsApp Trigger ("Receber Mensagem WhatsApp") →
     `SUBSTITUA_PELO_WEBHOOK_ID_DO_TRIGGER`. É o caminho do webhook de produção; ao importar, o n8n
     gera um novo e é preciso reativar o trigger para ele se registrar na Meta;
   - telefone do responsável (destino dos alertas e notificações de erro) →
     `SUBSTITUA_PELO_TELEFONE_DO_RESPONSAVEL`.

   Fora isso — nodes, parâmetros, conexões e settings — o conteúdo é o da versão publicada.
