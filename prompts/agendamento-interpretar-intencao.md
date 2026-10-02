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
funcionamento e sugestão de horários livres. Nenhuma linha foi tocada nesta migração — as
únicas mudanças posteriores, já com o workflow em produção, estão na seção abaixo.

## Ajustes em produção (rodada 19, 02/10/2026)

- **Barbearia ZAP como demonstração do AgendaZap.** Nova seção `## CONTEXTO: BARBEARIA DE
  DEMONSTRAÇÃO DO AGENDAZAP`, logo depois de INFORMAÇÕES DA BARBEARIA:
  - a barbearia é fictícia e muitos contatos chegam pelo site só para testar;
  - saudações e menções a "site", "demonstração", "demo", "teste"/"testar" ou "AgendaZap" são
    `duvida` (nunca `fora_do_escopo`), respondidas com boas-vindas da demonstração + lista de
    serviços, sem as palavras "agendado", "marcado", "confirmado" ou "reservado";
  - perguntas sobre o AgendaZap em si (preço, planos, contratação) são `encaminhar`.

  A definição de `fora_do_escopo` (item 1, "REGRA — O QUE VOCÊ NÃO SABE…" e REGRAS GERAIS) e a
  regra de saudação do item 7 passaram a citar essa exceção.
- **Texto fixo de recusa (`fora_do_escopo`).** A frase que o prompt manda usar "EXATAMENTE" passou
  a ser:

  > Isso eu não consigo responder por aqui 😅 Mas posso te ajudar com a Barbearia ZAP: quer marcar
  > um horário? É só me dizer o serviço e o dia.

  É o mesmo texto do node "Recusar Assunto Fora do Escopo no WhatsApp", que é quem de fato envia a
  recusa. Os dois precisam continuar idênticos — e iguais ao prompt e ao node de mesmo nome no
  workflow de Lembrete.
- Os espaços no fim das linhas do prompt foram removidos (sem efeito no comportamento).

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
