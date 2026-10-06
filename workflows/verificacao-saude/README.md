# Verificação de Saúde da IA e do WhatsApp

Workflow novo (ciclo D), independente dos três de produção. Publicado em 06/10/2026.

- **Gatilho:** a cada 15 min, das 8h às 20h (America/Sao_Paulo).
- **Verifica** (em paralelo): uma chamada mínima na API da Anthropic (`claude-sonnet-5`, `max_tokens: 1`)
  e um `GET` do número na Graph API (token do WhatsApp).
- **Incidentes:** um por serviço e tipo de falha (`credito`, `autenticacao`, `limite`, `indisponivel`,
  `sem_resposta`, `token`, `outro`), na Data Table `saude_ia_incidentes` (`servico`, `tipo`, `falhas`,
  `primeira_falha_em`, `ultimo_alerta_em`). Primeira falha avisa na hora; repetições só incrementam a
  contagem e avisam de novo após 30 min (29 min na prática, folga do agendador). Quando volta ao normal
  envia "voltou" e fecha o incidente.
- **Canais, em paralelo e independentes:** WhatsApp (texto livre, só chega dentro da janela de 24h da
  Meta) e e-mail (SMTP) como reserva. Cada node tem `onError: continueRegularOutput`.
- **Erro do próprio workflow:** vai para "Notificação de Erros".

O JSON está sanitizado: `<PHONE_NUMBER_ID>`, `<RESPONSAVEL_PHONE>`, `<EMAIL_REMETENTE>`,
`<EMAIL_RESPONSAVEL>` e `<ID_DO_WORKFLOW_NOTIFICACAO_DE_ERROS>` precisam ser trocados ao importar;
credenciais (Anthropic, WhatsApp, SMTP) são ligadas na instância.
