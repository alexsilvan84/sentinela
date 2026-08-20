# Guia de configuracao

Passo a passo para monitorar um servidor do zero. Ao final voce recebe uma
mensagem no celular quando o servidor tiver problema, e outra quando ele voltar
ao normal.

Leva uns 15 minutos.

---

## 1. Instalar

Entre no servidor por SSH e rode:

```bash
git clone https://github.com/alexsilvan84/sentinela.git
cd sentinela
sudo ./install.sh
```

O instalador confere se voce tem tudo que o Sentinela precisa (`awk`, `df`,
`date`, `curl`, `tr` e Bash 4) e para com uma mensagem clara se faltar algo.

Confirme que funcionou:

```bash
sentinela versao
```

Se aparecer `Sentinela 1.0.0`, esta instalado.

### Sem acesso root

```bash
./install.sh --user
```

Instala em `~/.local/bin`. Se o aviso sobre o `PATH` aparecer, acrescente ao
seu `~/.bashrc`:

```bash
export PATH="$PATH:$HOME/.local/bin"
```

---

## 2. Ver o estado atual

Antes de configurar limite nenhum, olhe como o servidor esta agora:

```bash
sentinela status
```

```
2026-08-19 22:07:25  cpu                            OK    uso em 18% (limite 85%)
2026-08-19 22:07:26  memoria                        OK    uso em 41% (limite 85%)
2026-08-19 22:07:27  carga                          OK    load 0.42 (limite 16.00 para 8 nucleo(s))
2026-08-19 22:07:28  disco /                        OK    uso em 81% (limite 90%)

4 verificacao(oes), tudo dentro do limite.
```

O `status` nunca envia alerta. Use a vontade para experimentar.

Anote esses numeros: eles sao a base para escolher os limites no passo 4.

---

## 3. Criar o bot do Telegram

Voce precisa de duas informacoes: o **token do bot** e o **chat id**.

### 3.1 O token

1. Abra o Telegram e procure por **@BotFather**
2. Envie `/newbot`
3. Escolha um nome (ex.: `Sentinela do meu servidor`)
4. Escolha um usuario, que precisa terminar em `bot` (ex.: `meu_servidor_bot`)
5. O BotFather responde com um token assim:

```
123456789:AAHdqTcvCH1vGWJxfSeofSAs0K5PALDsaw
```

Esse token da controle total do bot. Trate como senha.

### 3.2 O chat id

O bot so consegue te mandar mensagem se voce falar com ele primeiro.

1. Procure o bot que voce acabou de criar pelo nome de usuario
2. Envie qualquer coisa para ele, um `/start` serve
3. Agora procure por **@userinfobot** e envie `/start`
4. Ele responde com o seu `Id`, um numero como `987654321`

Esse e o seu chat id.

> Para receber os alertas em **grupo**, adicione o bot ao grupo, mande uma
> mensagem la, e depois abra no navegador:
> `https://api.telegram.org/bot<SEU_TOKEN>/getUpdates`
> O chat id do grupo aparece em `"chat":{"id":-100...}`. Ele e negativo.

---

## 4. Configurar

Abra o arquivo:

```bash
sudo nano /etc/sentinela/sentinela.conf
```

### Os limites

Use os numeros que voce anotou no passo 2 e deixe uma folga. Se o disco esta em
81% e nao cresce rapido, um limite de 90% te avisa com antecedencia sem encher
o saco.

```ini
limite_cpu=85
limite_memoria=85
limite_disco=90
limite_carga=2.0
```

Um erro comum e colocar limite baixo demais "para nao perder nada". O efeito e
o contrario: voce recebe tanto alerta que para de olhar. Prefira comecar
folgado e apertar depois.

### O que verificar

```ini
# pontos de montagem
disco=/, /var, /home

# sites e APIs (url ou url|codigo_esperado)
http=https://meusite.com.br, https://meusite.com.br/api/health|200

# portas TCP
porta=localhost:22, localhost:3306

# servicos do systemd
servico=nginx, mysql
```

Deixe vazia a linha do que voce nao usa.

### Os alertas

```ini
alerta_telegram_token=123456789:AAHdqTcvCH1vGWJxfSeofSAs0K5PALDsaw
alerta_telegram_chat=987654321
alerta_cooldown=1800

nome_host=web-01
```

O `nome_host` e o que aparece na mensagem. Com varios servidores, e ele que te
diz qual deles esta com problema.

Salve com `Ctrl+O`, `Enter`, `Ctrl+X`.

---

## 5. Testar

```bash
sentinela testar
```

Deve chegar no seu Telegram:

> **[TESTE] web-01:** o Sentinela esta configurado corretamente.

Se nao chegar, veja [Problemas comuns](#problemas-comuns) no fim deste guia.

Confira tambem se a configuracao foi lida como voce espera:

```bash
sentinela config
```

O token e o webhook aparecem como `(definido)`, nunca com o valor. Assim voce
pode colar essa saida num chamado sem vazar segredo.

---

## 6. Agendar

De nada adianta um monitor que so roda quando voce lembra.

### Com systemd

```bash
cd sentinela
sudo ./install.sh --systemd
```

Roda a cada 5 minutos. Para conferir:

```bash
systemctl status sentinela.timer     # esta ativo?
systemctl list-timers sentinela      # quando roda de novo?
journalctl -u sentinela -n 20        # o que aconteceu nas ultimas execucoes
```

### Com cron

```bash
sudo crontab -e
```

Acrescente:

```cron
*/5 * * * * /usr/local/bin/sentinela check --quiet
```

O `--quiet` evita que o cron te mande e-mail a cada execucao bem-sucedida.

---

## 7. Provocar uma falha de proposito

Um monitor que nunca alertou e um monitor que voce nao sabe se funciona. Force
uma falha e veja a mensagem chegar.

O jeito mais seguro e baixar um limite:

```bash
# cria uma configuracao temporaria que vai falhar de proposito
sudo cp /etc/sentinela/sentinela.conf /tmp/teste.conf
sudo sed -i 's/^limite_disco=.*/limite_disco=1/' /tmp/teste.conf

sentinela -c /tmp/teste.conf check
```

Deve chegar no Telegram:

> **[ALERTA] web-01:** disco /. uso em 81% (limite 1%)

Agora rode com a configuracao normal para ver o aviso de recuperacao:

```bash
sentinela check
```

> **[OK] web-01:** disco / voltou ao normal. uso em 81% (limite 90%)

Apague o arquivo de teste:

```bash
sudo rm /tmp/teste.conf
```

Pronto. Voce sabe que o caminho inteiro funciona.

---

## Problemas comuns

### A mensagem de teste nao chega

Confira nesta ordem:

```bash
sentinela config     # o token e o chat aparecem como "(definido)"?
```

Se aparecerem como `(vazio)`, o arquivo nao foi lido. Veja qual arquivo o
Sentinela esta usando — a primeira linha do `sentinela config` mostra o caminho.

Se estiverem definidos mas a mensagem nao chega, teste o Telegram direto:

```bash
curl -s "https://api.telegram.org/bot<SEU_TOKEN>/getMe"
```

- `{"ok":true,...}` — o token esta certo, o problema e o chat id
- `{"ok":false,"error_code":401}` — o token esta errado

Com o token certo e o chat errado, o erro mais comum e nao ter mandado `/start`
para o bot. O Telegram nao deixa um bot iniciar conversa.

### "chave desconhecida" ao rodar

Voce escreveu o nome de uma opcao errado. O Sentinela avisa em vez de ignorar
em silencio — foi de proposito, para erro de digitacao nao passar despercebido.
Compare com o [`sentinela.conf.example`](../sentinela.conf.example).

### A verificacao aparece como PULADO

Significa que aquela medicao nao esta disponivel naquele sistema:

| Aparece | Motivo |
| --- | --- |
| `PULADO /proc/meminfo indisponivel` | nao e Linux, ou o `/proc` nao esta montado |
| `PULADO systemctl indisponivel` | o sistema nao usa systemd |

`PULADO` nao conta como falha e nao gera alerta.

### Recebo alerta demais

Aumente o `alerta_cooldown`. Com `3600`, o mesmo problema so repete de hora em
hora.

Se o alerta e legitimo mas frequente demais, o limite esta apertado. Rode
`sentinela status` algumas vezes ao longo do dia e veja a variacao real antes
de escolher o numero.

### Quero saber o que rodou e quando

```bash
journalctl -u sentinela --since today
```

---

## Proximo passo

Para entender **como** cada numero e medido — por que a CPU precisa de duas
leituras, por que a memoria nao usa a coluna `used` do `free`, o que significa
o load average — veja [Como funciona](como-funciona.md).
