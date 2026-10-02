# Banco de dados (Supabase / Postgres)

Scripts em ordem de aplicação. Todos rodam no SQL Editor do Supabase.

| Arquivo | O que faz | Status |
|---|---|---|
| `001_initial_schema.sql` | Schema inicial: `profissionais`, `servicos`, `profissionais_servicos`, `agendamentos` (com a exclusion constraint anti-double-booking) | Aplicado (setembro/2026) |
| `002_seed_exemplo.sql` | Seed de exemplo (2 profissionais, 3 serviços) | Aplicado (adaptado) |
| `003_clientes_mensagens.sql` | Migration **só aditiva**: `clientes`, `mensagens`, enums `direcao_mensagem`/`status_mensagem`, `agendamentos.cliente_id` (nullable), view `clientes_resumo` (`security_invoker`), RLS sem políticas em `clientes`/`mensagens` | **Aplicado em 02/10/2026** |
| `004_backfill_clientes.sql` | Backfill idempotente: um cliente por telefone distinto de `agendamentos` (só dígitos) e preenchimento de `agendamentos.cliente_id` | **Aplicado em 02/10/2026** (e rodado 2x) |
| `005_verificacao.sql` | Verificação somente leitura: hashes das 9 consultas dos workflows (antes/depois) e conferências pós-backfill | **Rodado em 02/10/2026** |

## Aplicação da 003/004 (02/10/2026)

Aplicadas pelo José no SQL Editor, num horário tranquilo, seguindo o roteiro:
1. 005 parte A ("antes").
2. 003.
3. 004.
4. 005 parte A ("depois").
5. 005 parte B.
6. 004 de novo.
7. B1–B4 e A de novo.

Resultado:
- **003 e 004:** "Success".
- **005 parte A:** sem diferenças entre "antes" e "depois" — as consultas usadas pelos workflows
  continuaram retornando o mesmo resultado.
- **005 parte B:** tudo como esperado. Em B5: `rls = true` em `clientes` e `mensagens`,
  `politicas = 0`, `security_invoker = true` na view e `privilegios_publicos = 0`.
- **004 rodada de novo:** sem efeito; continua idempotente.

Na época, os workflows em produção não foram alterados. Desde 02/10/2026 (fase 2, rodada 23 de
`docs/test-plan.md`) o Agendamento e o Lembrete **gravam** em `clientes` e `mensagens`:
- Agendamento: mensagem recebida (`entrada`/`recebida`), status da Meta (`enviada`/`entregue`/`lida`/
  `falhou`), `agendamentos.cliente_id` e `clientes.primeiro_agendamento_em`;
- ambos: mensagens enviadas (`saida`), pelo sub-workflow "Registrar Mensagem [v2 historico]".

Nenhuma query antiga foi alterada e nenhum workflow lê essas tabelas. O backup anterior à fase 2
(versões `68c7d91c…`/`56eb95e1…`) está em `workflows/backup/`.
