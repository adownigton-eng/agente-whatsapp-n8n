# Áudios do agente

Esta pasta guarda as mensagens de voz que o agente envia. Ela vem vazia: cada um coloca os seus. O container `audios` serve os arquivos para o WAHA em `http://audios/<nome>.ogg`, só dentro da rede do Docker.

Os áudios vêm **desligados**. Depois de colocar os arquivos aqui, ligue no n8n:

- Nó **Analisa**: troque `const USAR_AUDIOS = false;` por `true`.
- Nó **Voz transferencia**: ative o nó (ele vem desativado).

## Nomes dos arquivos

Um arquivo por idioma (`-pt` português, `-es` espanhol):

| Arquivo | Quando é enviado |
|---|---|
| `saudacao-pt.ogg` / `saudacao-es.ogg` | Primeira mensagem do cliente |
| `transferencia-pt.ogg` / `transferencia-es.ogg` | Quando o cliente pede um humano |
| `impressora-pt.ogg` / `impressora-es.ogg` | Exemplo de tema. Troque pelas palavras do seu negócio no nó **Analisa** |
| `erro-tecnico-pt.ogg` / `erro-tecnico-es.ogg` | Exemplo de tema (erro, travou, não funciona...) |

O áudio de um tema é enviado no máximo uma vez a cada 24 horas por cliente. Quando um áudio sai, o agente recebe um aviso para complementar por texto sem repetir o que foi dito.

Para criar um tema novo: adicione a lista de palavras e o nome do áudio no nó **Analisa** e a nota correspondente no nó **Guarda dados**.

## Gerando os áudios no ElevenLabs

1. Entre em [elevenlabs.io](https://elevenlabs.io) → **Text to Speech**.
2. Escolha uma voz (ou clone a sua em **Voices → Add a new voice**) e o modelo **Eleven Multilingual**, que fala português e espanhol.
3. Escreva o texto curto e natural, como você falaria no WhatsApp (15 a 40 segundos).
4. Gere e baixe o arquivo em MP3.

## Convertendo para o formato do WhatsApp

O WhatsApp só toca como "mensagem de voz" arquivos **OGG com codec Opus**. Converta com o [ffmpeg](https://ffmpeg.org/download.html):

```bash
ffmpeg -i saudacao-pt.mp3 -c:a libopus -b:a 32k -ar 48000 -ac 1 saudacao-pt.ogg
```

Coloque o `.ogg` nesta pasta. Não precisa reiniciar nada: o arquivo já fica disponível na hora.

Os arquivos de áudio não vão para o Git (estão no `.gitignore`). Só este guia vai.
