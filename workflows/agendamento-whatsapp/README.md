# Agendamento via WhatsApp (Supabase)

Cópia adaptada do workflow de produção `automacao-pmes-whatsapp/workflows/agendamento`, com a
camada de dados trocada de Google Sheets para Postgres/Supabase. Lógica de negócio, AI Agent e
prompt **não foram alterados** — veja `docs/migracao-supabase.md` na raiz do repo para o
detalhamento completo do que mudou, node a node, e as decisões em aberto.

**Faz:** processa mensagens do WhatsApp a qualquer momento — interpreta agendar/remarcar/
cancelar/consultar/dúvida via IA, checa disponibilidade real no Google Calendar do profissional
ativo, efetiva a ação no Postgres (tabela `agendamentos`) e responde o cliente.

**Na instância n8n:** workflow `ny0fqlw8ojzmId7C`, criado **desativado**, com as credenciais reais
da instância já vinculadas (no JSON deste repo elas ficam como placeholder ou omitidas) e Error
Workflow apontando para o "Notificação de Erros" de produção. Não ativar enquanto o trigger for o
do WhatsApp: a ativação registra o webhook na Meta.

> **Trigger:** o WhatsApp Trigger original ("Receber Mensagem WhatsApp", mesmo `webhookId` de
> antes) foi **recolocado na rodada 17**. O Webhook temporário usado no Grupo B (rodadas 13 a 17)
> foi removido. O workflow continua **desativado**: ativá-lo registra o webhook na Meta e faz parte
> do cutover (`docs/migracao-supabase.md`).

> **Diferença de comportamento em relação à produção (rodada 15):** a espera de lembrete é
> checada **antes** do lock do telefone (dedup → espera → lock). Uma resposta ao lembrete é
> encaminhada mesmo que chegue menos de 10 s depois de outra mensagem do cliente. Ver
> `docs/migracao-supabase.md`, seção 6.

> **Rodada 17 (R16-1):** quando o `INSERT` do agendamento falha por qualquer motivo que não seja
> conflito de horário, o workflow desfaz o evento recém-criado no Calendar, avisa o cliente com o
> texto neutro de erro de banco e só então para com erro, acionando o Error Workflow.

> **Rodada 18 (R17-1):** o mesmo vale para a remarcação. Se o `UPDATE` falha sem ser conflito, o
> workflow relê o horário original, devolve o evento do Calendar para ele, avisa o cliente e só
> então para com erro. A mensagem para a equipe diz se o Calendar foi restaurado.

**Antes de importar no n8n:**
1. Rode `db/001_initial_schema.sql` e `db/002_seed_exemplo.sql` (na raiz do repo) no seu projeto
   Supabase, se ainda não tiver rodado.
2. Ao importar, troque a credencial Postgres placeholder (`Supabase - agendazap-core`) pela sua
   credencial real em cada node Postgres.
3. Mantenha o workflow **desativado** até validar contra `docs/test-plan.md` do repo de produção.
