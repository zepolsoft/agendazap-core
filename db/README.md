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

Os workflows em produção não foram alterados; eles ainda não leem nem gravam as tabelas novas. O
backup deles no momento da migration está em `workflows/backup/`.
