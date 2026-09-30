# Interpretar Intenção do Cliente

Usado no AI Agent node "Interpretar Intenção do Cliente" do workflow
[`agendamento-whatsapp`](../workflows/agendamento-whatsapp/).

> **Fonte da verdade:** o texto completo do `systemMessage` vive no node, dentro de
> `workflows/agendamento-whatsapp/agendamento.json`. Este arquivo é só um resumo — não o copie
> para outro lugar nem edite o prompt aqui, edite direto no node via MCP e reexporte o JSON,
> senão os dois ficam dessincronizados.

## O que não mudou

O prompt em si é **idêntico** ao de produção (`automacao-pmes-whatsapp`): mesmas regras de
intenção (agendar/cancelar/remarcar/consultar/dúvida/encaminhar/fora_do_escopo), mesmo tom,
mesma lógica de desambiguação de agendamento por beneficiário, mesmas regras de horário de
funcionamento e sugestão de horários livres. Nenhuma linha foi tocada nesta migração.

## O que mudou: de onde vêm os dados que alimentam o prompt

O prompt recebe, via variáveis do node (`{{ $json.lista_servicos }}`,
`{{ $json.horarios_livres }}`, `{{ $json.agendamentos_ativos }}`), três blocos de contexto que
antes vinham do Google Sheets e agora vêm do Postgres/Supabase:

| Bloco no prompt | Antes (Sheets) | Agora (Postgres) |
|---|---|---|
| SERVIÇOS DISPONÍVEIS E PREÇOS | leitura da aba "Serviços" | `SELECT nome, categoria, duracao_min, preco FROM servicos WHERE ativo = true` |
| HORÁRIOS LIVRES | Google Calendar (inalterado) + duração mínima da planilha | Google Calendar do profissional ativo (dinâmico) + duração mínima de `servicos` |
| AGENDAMENTOS ATIVOS DESTE CLIENTE | leitura da aba "Agendamentos" filtrada por telefone | `agendamentos` + `JOIN servicos`, filtrado por `cliente_telefone` |

A IA não sabe (nem precisa saber) que a origem mudou — o formato dos blocos de texto que ela
recebe é o mesmo.

## Saída esperada (JSON estruturado) — sem mudança

```json
{
  "intencao": "agendar",
  "servico": "corte de cabelo",
  "nome_cliente": "João Silva",
  "data_hora_inicio": "2026-09-18T15:00:00",
  "data_hora_fim": "2026-09-18T16:00:00",
  "confirmado": true,
  "agendamento_alvo": "",
  "beneficiario": "Eu mesmo",
  "confirmacao_texto": "Combinado! Corte marcado pra quinta-feira, dia 18 de setembro, às 15h. Até lá! 💈"
}
```

## Atenção ao editar

O campo `servico` continua sendo texto livre — a IA não escolhe um `servico_id`. É o node
"Validar Horário de Funcionamento" (e o `INSERT`/`UPDATE` no Postgres) que tenta casar esse texto
com um `servicos.nome` cadastrado. Ver a decisão em aberto sobre isso em
`docs/migracao-supabase.md` antes de mudar a lista de serviços ou o texto que a IA usa pra se
referir a eles.
