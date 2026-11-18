# Agente de IA no WhatsApp (WAHA + n8n + Postgres)

Um agente de atendimento no WhatsApp que roda inteiro na sua máquina com Docker. Ele já vem com:

- **Conexão com o WhatsApp** pelo [WAHA](https://waha.devlike.pro/) (lê o QR code, sem API oficial).
- **Agente de IA** no [n8n](https://n8n.io/) usando Google Gemini, com memória da conversa no Postgres.
- **Áudio do cliente vira texto**: o agente entende mensagens de voz.
- **Português e espanhol**: detecta o idioma e responde no mesmo.
- **Pausa automática**: quando um humano responde pelo celular ou o cliente pede um atendente, o bot para de responder.
- **Agenda**: o agente consulta horários livres, marca, remarca e cancela, e envia lembretes.
- **Painel CRM** em Kanban para acompanhar as conversas.
- **Áudios prontos (opcional)**: mensagens de voz que você grava ou gera no ElevenLabs.

```
WhatsApp ⇄ WAHA ──webhook──► n8n (agente + Gemini) ⇄ Postgres
                                 │
               painel CRM ◄──────┘  (nginx: /painel e /api)
```

## Do que você precisa

- [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- Uma chave da API do Google Gemini ([Google AI Studio](https://aistudio.google.com/apikey))
- Um número de WhatsApp para o agente (de preferência um chip só para isso)

## Instalação

**1. Configure as senhas**

```bash
cp .env.example .env
```

Abra o `.env` e preencha todas as senhas e a `WHATSAPP_API_KEY`. Use valores fortes e não publique esse arquivo.

**2. Suba os containers**

```bash
docker compose up -d
docker compose ps
```

Na primeira subida, o Postgres cria sozinho as tabelas do agente (pasta `sql/init`).

| Serviço | Endereço |
|---|---|
| WAHA (WhatsApp) | http://localhost:3000/dashboard |
| n8n (o fluxo) | http://localhost:5678 |
| Painel CRM | http://localhost:8081/painel/ |
| Postgres | 127.0.0.1:5433 |

Tudo fica só no `localhost`. Nada é exposto na rede.

**3. Configure o n8n**

1. Abra http://localhost:5678 e crie sua conta de dono.
2. Crie duas credenciais em **Credentials**:
   - **Postgres**: host `postgres`, porta `5432`, banco, usuário e senha iguais aos do `.env`.
   - **Google Gemini (PaLM) API**: sua chave do Google AI Studio.
3. Vá em **Workflows → Import from File** e escolha `n8n-workflows/agente-whatsapp.json`.
4. Abra os nós que mostram aviso de credencial e selecione as que você criou.
5. Ative o workflow (botão **Active**).

**4. Conecte o WhatsApp**

Abra http://localhost:3000/dashboard, entre com o login do `.env`, abra a sessão `default` e leia o QR code no celular: WhatsApp → Aparelhos conectados → Conectar aparelho.

Mande uma mensagem para o número de outro celular. O agente deve responder.

**5. Crie o login do painel**

```bash
docker exec -it postgres psql -U <POSTGRES_USER> -d <POSTGRES_DB> \
  -c "select crm_usuario_criar('admin', 'uma-senha-forte', 'Seu Nome');"
```

Entre em http://localhost:8081/painel/ com esse usuário.

## Personalização

| O quê | Onde |
|---|---|
| Nome, empresa, tom de voz, regras do negócio | Nó **Agente de IA**, campo *System Message*. Troque tudo que está entre `[colchetes]` |
| Modelo de IA | Nó **Gemini**. Dá para trocar por OpenAI, Claude etc. com outro nó de chat model |
| Palavras que pedem um humano | Nó **Pediu humano?** |
| Mensagem de transferência | Nó **Texto transferencia** |
| Temas que disparam áudio | Nó **Analisa** (listas `temImpressora` e `temErroTecnico` são exemplos) |
| Horários da agenda | Tabela `agenda_config` (horas, duração, antecedência, fuso) e o texto do prompt |
| Dias bloqueados (feriados) | Tabela `agenda_bloqueios` |
| Tempo de pausa após um humano responder | Tabela `crm_parametros` (`pausa_minutos`) |
| Colunas do Kanban | Tabela `crm_estagios` |
| Áudios | Pasta `audios/`. Veja [audios/LEIA-ME.md](audios/LEIA-ME.md) |

## Comandos úteis

```bash
docker compose up -d        # sobe tudo
docker compose stop         # para sem apagar nada
docker compose logs -f n8n  # acompanha o n8n
```

As pastas `postgres-data/`, `n8n-data/` e `waha-sessions/` guardam os dados. Apagar qualquer uma delas apaga o banco, os fluxos ou a sessão do WhatsApp.

## Avisos

- O WAHA usa o WhatsApp Web, que não é a API oficial da Meta. Use com bom senso: mandar mensagens em massa pode bloquear o número.
- Siga a LGPD: as conversas ficam salvas no seu Postgres.
- Antes de colocar em um servidor, coloque HTTPS e autenticação na frente de tudo.
