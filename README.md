# Sentinela

[![Licenca: MIT](https://img.shields.io/badge/licenca-MIT-blue.svg)](LICENSE)
[![Bash](https://img.shields.io/badge/bash-4.0%2B-lightgrey.svg)](#requisitos)

Monitor de servidor em Bash puro. **Um arquivo, sem dependencia, sem agente,
sem banco de dados.** Verifica CPU, memoria, disco, carga, portas, servicos e
endpoints HTTP, e te avisa no Telegram quando algo sai do limite.

Feito para o servidor pequeno que nao justifica um Zabbix, um Prometheus ou uma
mensalidade de SaaS — a VPS de R$ 20, o servidor da empresa, o Raspberry Pi.

```
$ sentinela check

2026-08-19 22:07:25  cpu                            OK    uso em 18% (limite 85%)
2026-08-19 22:07:26  memoria                        OK    uso em 41% (limite 85%)
2026-08-19 22:07:27  carga                          OK    load 0.42 (limite 16.00 para 8 nucleo(s))
2026-08-19 22:07:28  disco /                        OK    uso em 81% (limite 90%)
2026-08-19 22:07:28  http https://example.com       OK    respondeu 200
2026-08-19 22:07:29  porta example.com:443          OK    aberta

6 verificacao(oes), tudo dentro do limite.
```

E quando algo quebra:

```
2026-08-19 22:07:34  disco /                        FALHA uso em 94% (limite 90%)
2026-08-19 22:07:35  http https://example.com       FALHA respondeu 502, esperado 200

2 de 6 verificacao(oes) falharam.
```

No mesmo instante chega no seu Telegram:

> **[ALERTA] web-01:** disco /. uso em 94% (limite 90%)

E quando o problema passa, chega o aviso de volta:

> **[OK] web-01:** disco / voltou ao normal. uso em 62% (limite 90%)

## Instalar

```bash
git clone https://github.com/alexsilvan84/sentinela.git
cd sentinela
sudo ./install.sh
```

Sem root, instalando em `~/.local/bin`:

```bash
./install.sh --user
```

Ou simplesmente copie o arquivo `sentinela` para qualquer lugar do `PATH`. Ele
funciona sozinho — nao ha modulo, biblioteca nem pacote para baixar.

## Configurar

O instalador cria `/etc/sentinela/sentinela.conf`. Um exemplo real:

```ini
# limites
limite_cpu=85
limite_memoria=85
limite_disco=90
limite_carga=2.0

# o que verificar
disco=/, /var, /home
http=https://meusite.com.br, https://api.meusite.com.br/health|200
porta=localhost:22, localhost:3306
servico=nginx, mysql, docker

# para onde avisar
alerta_telegram_token=123456:ABC-DEF...
alerta_telegram_chat=987654321
alerta_cooldown=1800

nome_host=web-01
```

Confira se ficou tudo certo:

```bash
sentinela status    # mostra os valores atuais, sem avisar ninguem
sentinela testar    # manda uma mensagem de teste pelos canais configurados
sentinela config    # mostra a configuracao em uso e de onde ela veio
```

## Agendar

Com systemd, roda a cada 5 minutos:

```bash
sudo ./install.sh --systemd
systemctl status sentinela.timer
```

Ou com cron, se preferir:

```cron
*/5 * * * * /usr/local/bin/sentinela check --quiet
```

## Canais de alerta

Configure quantos quiser: a mensagem vai por todos ao mesmo tempo.

| Canal | Como configurar |
| --- | --- |
| **Telegram** | `alerta_telegram_token` e `alerta_telegram_chat`. Crie o bot com o [@BotFather](https://t.me/botfather) e pegue o chat id com o [@userinfobot](https://t.me/userinfobot). |
| **Discord / Slack / Mattermost** | `alerta_webhook` com a URL do webhook. O mesmo JSON atende os tres. |
| **E-mail** | `alerta_email`. Precisa do comando `mail` (pacote `mailutils`). |

Sem nenhum canal configurado o Sentinela continua util: imprime na tela e
devolve o codigo de saida, o que ja serve para cron e para pipeline de CI.

## O alerta nao vira spam

Tres decisoes de projeto cuidam disso:

- **Cooldown.** Depois de avisar, o mesmo problema so avisa de novo passados
  `alerta_cooldown` segundos (padrao: 30 minutos). Rodar a cada 5 minutos com
  um disco cheio manda uma mensagem por meia hora, nao seis por hora.
- **Aviso de recuperacao.** Quando a verificacao volta ao normal, chega um
  `[OK]`. Voce nao fica na duvida se resolveu.
- **Limite de carga por nucleo.** `limite_carga=2.0` num servidor de 4 CPUs
  dispara em 8.0. Copiar a mesma configuracao para maquinas de tamanhos
  diferentes continua fazendo sentido.

## Usar em CI

O codigo de saida permite usar o Sentinela como portao de deploy:

| Codigo | Significado |
| --- | --- |
| `0` | todas as verificacoes passaram |
| `1` | ao menos uma falhou |
| `2` | erro de uso ou de configuracao |

```yaml
- name: Conferir a saude apos o deploy
  run: ssh servidor 'sentinela check --quiet'
```

## O que e verificado

| Verificacao | Como e medido |
| --- | --- |
| **CPU** | duas leituras de `/proc/stat` com 1s de intervalo. Uma leitura so daria a media desde o boot. |
| **Memoria** | `MemAvailable` do `/proc/meminfo`. Cache e buffer sao reaproveitaveis e nao contam como ocupados. |
| **Carga** | `/proc/loadavg`, com o limite multiplicado pelo numero de nucleos. |
| **Disco** | `df -P`, localizando a coluna pelo `%`. Nome de sistema de arquivos com espaco desloca as colunas. |
| **HTTP** | `curl` comparando o codigo devolvido com o esperado. |
| **Porta** | `/dev/tcp` do proprio Bash, com timeout. |
| **Servico** | `systemctl is-active`. |

Quando algo nao esta disponivel (um `/proc` ausente, um sistema sem systemd), a
verificacao aparece como `PULADO` e nao conta como falha.

## Requisitos

- Bash 4.0 ou superior
- `awk`, `df`, `date`, `tr` — presentes em qualquer distribuicao
- `curl`, para as verificacoes HTTP e para os alertas
- `systemctl`, so se for verificar servicos
- `mail`, so se for alertar por e-mail

Desenvolvido e testado com Bash 4.4. Deve rodar em qualquer Linux com Bash 4 e
`/proc` — se falhar no seu, abra uma issue com a saida de `sentinela status`.

## Seguranca

- **O `.conf` nao e executado.** E lido como `chave=valor`, linha a linha, sem
  `source`. Um arquivo de configuracao nao deveria ser capaz de rodar comandos,
  e um teste garante que `$(...)` e crase continuam sendo texto.
- **Chave desconhecida e recusada** com aviso, em vez de ignorada em silencio.
  Erro de digitacao no nome do limite nao passa despercebido.
- **O `sentinela config` nao imprime segredo.** Token e webhook aparecem como
  `(definido)`, para o comando poder ir para um chamado ou um log.
- **O arquivo de configuracao e criado com permissao `600`**, porque guarda o
  token do Telegram.
- **A unidade systemd roda com privilegio reduzido** (`ProtectSystem=strict`,
  `NoNewPrivileges`, `ProtectHome=read-only`). O Sentinela so precisa ler.

## Testes

```bash
bash tests/run.sh
```

50 testes, sem dependencia externa. Cobrem o parsing da configuracao, o escape
de JSON, a comparacao com decimal, a leitura do `df`, a janela de cooldown e o
ciclo completo de alerta e recuperacao.

Para conferir o estilo do codigo tambem:

```bash
shellcheck -S warning sentinela install.sh tests/run.sh
```

## Licenca

[MIT](LICENSE)
