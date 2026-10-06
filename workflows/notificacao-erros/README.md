# Notificação de Erros

Idêntico ao workflow de produção `automacao-pmes-whatsapp/workflows/notificacao-erros` — não
usa Google Sheets nem Google Calendar (só Error Trigger + WhatsApp), então não precisou de
nenhuma adaptação. Copiado aqui sem alterações para o Error Workflow dos dois outros workflows
deste repo poder apontar para ele.

## Alteração de 06/10/2026 (publicada)

Além do WhatsApp, o resumo do erro agora também é enviado por **e-mail** (node "Notificar Erro por
E-mail", SMTP), em paralelo. Os dois nodes de envio usam `onError: continueRegularOutput`, então uma
recusa da Meta (por exemplo, fora da janela de 24h) não impede o e-mail, e vice-versa. O node "Formatar
Resumo do Erro" passou a devolver também o `assunto`. No JSON do repo, telefone, phoneNumberId e e-mails
são placeholders (`<RESPONSAVEL_PHONE>`, `<PHONE_NUMBER_ID>`, `<EMAIL_REMETENTE>`, `<EMAIL_RESPONSAVEL>`).
