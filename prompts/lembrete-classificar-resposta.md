# Classificar Resposta do Lembrete

Usado no AI Agent node "Classificar Resposta do Lembrete" do workflow
[`lembrete-cancelamento-remarcacao`](../workflows/lembrete-cancelamento-remarcacao/).

> **Fonte da verdade:** o texto completo do `systemMessage` vive no node, dentro de
> `workflows/lembrete-cancelamento-remarcacao/lembrete-cancelamento.json`. Este arquivo é só um
> resumo — edite direto no node via MCP e reexporte o JSON.

## O que não mudou

O prompt é **idêntico** ao de produção: classifica a resposta do cliente ao lembrete em
"confirmar", "cancelar", "remarcar" ou "indefinido", com as mesmas regras de escopo (perguntas
fora do catálogo → encaminhar; fora de escopo/jailbreak → recusa) e o mesmo tratamento de
ambiguidade entre agendamentos do mesmo cliente. Nenhuma linha foi tocada nesta migração.

## O que mudou: de onde vêm os dados

O agendamento do dia que dispara o lembrete (nome, telefone, serviço, beneficiário, horário) vem
de uma leitura em `agendamentos JOIN servicos` no Postgres, em vez da planilha "Clientes -
Automação PMEs" (ver `docs/migracao-supabase.md` para o mapeamento de colunas). O texto do
lembrete e a forma como o prompt recebe esses dados não mudaram.

## Saída esperada (JSON estruturado) — sem mudança

```json
{
  "decisao": "confirmar",
  "novo_horario_inicio": "2026-09-19T10:00:00",
  "novo_horario_fim": "2026-09-19T11:00:00",
  "resposta_sugerida": "sexta-feira, dia 19 de setembro, às 10h"
}
```

`decisao` pode ser `"confirmar"`, `"cancelar"`, `"remarcar"` ou `"indefinido"` (cai no branch de
fallback do Switch, que pede esclarecimento ao cliente).

## Atenção ao editar

Igual ao workflow de agendamento: se `novo_horario` envolver troca de serviço, o texto ainda é
livre e passa pelo mesmo casamento com `servicos.nome` no Postgres antes do `UPDATE` — ver
decisão em aberto em `docs/migracao-supabase.md`.
