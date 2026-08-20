# Como funciona

Este documento explica **como cada numero e medido** e por que cada decisao foi
tomada. Serve tanto para confiar no que o Sentinela reporta quanto para aprender
de onde o Linux tira essas informacoes.

Todos os comandos abaixo voce pode rodar no seu servidor agora.

---

## O sistema de arquivos `/proc`

Quase tudo que o Sentinela le vem do `/proc`. Ele parece um diretorio comum,
mas nao existe em disco: e uma janela para dentro do kernel. Cada leitura
devolve o estado do sistema naquele instante.

```bash
ls /proc/stat /proc/meminfo /proc/loadavg
cat /proc/loadavg
```

Por isso o Sentinela nao precisa de agente nem de biblioteca: a informacao ja
esta ali, exposta como arquivo de texto.

---

## CPU

### O problema

O kernel nao guarda "uso atual de CPU". Ele guarda **contadores acumulados
desde o boot**, em `/proc/stat`:

```bash
grep '^cpu ' /proc/stat
```

```
cpu  6434527 12043 6257746 126401747 8912 0 4471 0 0 0
```

Os campos, em ordem, sao o tempo gasto em: `user`, `nice`, `system`, `idle`,
`iowait`, `irq`, `softirq`, `steal`, `guest`, `guest_nice`.

Se voce dividir `idle` pelo total, obtem a media **desde que a maquina ligou**.
Num servidor com 200 dias no ar, um pico de CPU agora mal move esse numero. Nao
serve para alerta.

### A solucao

Ler duas vezes e comparar a diferenca:

```bash
grep '^cpu ' /proc/stat; sleep 1; grep '^cpu ' /proc/stat
```

O que mudou entre as duas leituras e o que aconteceu naquele segundo. E assim
que o `top` e o `htop` funcionam tambem.

No codigo:

```bash
total  = soma de todos os campos
ocioso = idle + iowait
uso%   = 100 * (Δtotal - Δocioso) / Δtotal
```

### Por que `iowait` conta como ocioso

`iowait` e tempo em que a CPU ficou parada **esperando o disco**. O processador
nao estava trabalhando, estava aguardando. Contar isso como uso faria um
servidor com disco lento parecer um servidor com CPU sobrecarregada — dois
problemas bem diferentes, com solucoes bem diferentes.

> Este e o unico ponto do Sentinela que demora: 1 segundo de espera entre as
> duas leituras. E o preco de ter um numero que significa alguma coisa.

---

## Memoria

### O engano do `free`

O jeito obvio seria ler a coluna `used` do `free`:

```bash
free -h
```

```
              total        used        free      shared  buff/cache   available
Mem:           11Gi       3.2Gi       1.1Gi       0.3Gi       7.4Gi       7.6Gi
```

O problema: o Linux usa toda memoria sobrando como **cache de disco**. Isso e
bom — deixa o sistema mais rapido — e essa memoria e devolvida na hora em que
algum programa precisar dela.

Se voce olhar so `free`, vai ver 1.1 GB livres de 11 GB e concluir que o
servidor esta afogado. Na verdade ha 7.6 GB disponiveis.

Existe um site inteiro dedicado a esse mal-entendido:
[linuxatemyram.com](https://www.linuxatemyram.com/).

### O que o Sentinela usa

O campo `MemAvailable` do `/proc/meminfo`:

```bash
grep -E '^(MemTotal|MemFree|MemAvailable):' /proc/meminfo
```

```
MemTotal:       12454628 kB
MemFree:         1145236 kB
MemAvailable:    7912440 kB
```

`MemAvailable` e a estimativa do proprio kernel de quanta memoria um programa
novo conseguiria usar, ja descontando o cache que da para liberar. E o numero
honesto.

```bash
uso% = 100 * (MemTotal - MemAvailable) / MemTotal
```

> `MemAvailable` existe desde o Linux 3.14 (2014). Em kernel mais antigo o
> campo nao aparece e a verificacao sai como `PULADO`.

---

## Carga (load average)

```bash
cat /proc/loadavg
```

```
0.42 0.51 0.48 2/431 18294
```

Os tres primeiros numeros sao a media de processos **rodando ou esperando** nos
ultimos 1, 5 e 15 minutos. O Sentinela usa o de 1 minuto.

### Carga nao e percentual

Este e o ponto que mais confunde. Load `4.0` **nao** quer dizer 400% nem 4%.
Quer dizer: em media, 4 processos disputavam a CPU.

O que torna esse numero bom ou ruim e **quantos nucleos a maquina tem**:

| Load | Maquina de 1 nucleo | Maquina de 8 nucleos |
| --- | --- | --- |
| `1.0` | no limite | tranquila |
| `4.0` | fila de espera, lenta | tranquila |
| `8.0` | travando | no limite |
| `16.0` | inutilizavel | fila de espera |

Por isso o `limite_carga` do Sentinela e **por nucleo**:

```bash
limite_real = limite_carga * numero_de_nucleos
```

Com `limite_carga=2.0`, o alerta dispara em `2.0` numa maquina de 1 nucleo e em
`16.0` numa de 8. A mesma configuracao funciona em servidores de tamanhos
diferentes — o que importa quando voce cuida de mais de um.

Para ver quantos nucleos voce tem:

```bash
grep -c '^processor' /proc/cpuinfo
```

---

## Disco

```bash
df -P /
```

```
Filesystem     1024-blocks      Used Available Capacity Mounted on
/dev/sda1        468589564 379193920  89395644      81% /
```

O `-P` pede o formato POSIX, que garante uma linha por sistema de arquivos.
Sem ele, nomes longos podem quebrar em duas linhas.

### O bug que isso escondia

A primeira versao do Sentinela lia a coluna 5 (`Capacity`) direto:

```bash
df -P "$ponto" | awk 'NR == 2 { print $5 }'    # errado
```

Funcionou ate um teste real, num sistema de arquivos chamado
`C:/Program Files/Git`. O espaco no nome vira **dois campos** para o `awk`, e
tudo desloca:

```
$1=C:/Program  $2=Files/Git  $3=468589564  $4=379193920  $5=89395644  $6=81%
```

A coluna 5 devolveu os bytes livres. O Sentinela reportou **89.395.644% de
disco em uso**.

Nao e caso raro nem coisa de Windows: montagem de rede (`//servidor/pasta com
espaco`) faz exatamente o mesmo no Linux.

A correcao foi parar de contar colunas e procurar o campo pelo formato:

```bash
for (i = NF; i >= 1; i--) {
    if ($i ~ /^[0-9]+%$/) { gsub("%", "", $i); print $i; exit }
}
```

Ha um teste que trava esse comportamento, com um `df` falso que devolve um nome
com espaco.

**A licao:** parsear saida de comando por posicao de coluna e fragil. Sempre que
der, identifique o campo pelo que ele **e**, nao por onde ele **esta**.

---

## Porta TCP

Sem `nc`, sem `telnet`, sem instalar nada — o proprio Bash abre conexao:

```bash
timeout 5 bash -c "exec 3<>/dev/tcp/localhost/22" && echo aberta || echo fechada
```

`/dev/tcp/host/porta` nao e um arquivo de verdade: e um recurso do Bash. Ao
redirecionar para esse caminho, ele tenta abrir um socket. Se conectar, o
comando devolve sucesso.

O `timeout 5` e essencial: sem ele, uma porta filtrada por firewall deixa o
Sentinela pendurado ate o timeout do sistema, que pode passar de um minuto.

---

## HTTP

```bash
curl -s -o /dev/null -w '%{http_code}' --max-time 10 https://example.com
```

| Trecho | Para que serve |
| --- | --- |
| `-s` | nao mostra barra de progresso |
| `-o /dev/null` | joga fora o corpo da resposta, so o codigo interessa |
| `-w '%{http_code}'` | imprime so o codigo HTTP |
| `--max-time 10` | desiste em 10 segundos |

Voce pode exigir um codigo diferente de 200, util para checar redirecionamento
ou uma pagina que deve mesmo devolver erro:

```ini
http=https://site.com|200, https://site.com/admin|403
```

Quando o `curl` falha (DNS, conexao recusada, timeout), o Sentinela registra
`000` — que nunca coincide com o esperado, entao vira alerta.

---

## Por que o alerta nao repete

Um monitor que roda a cada 5 minutos e avisa toda vez manda **288 mensagens por
dia** enquanto o problema durar. Depois da terceira, voce silencia o bot. Ai o
monitor virou enfeite.

O Sentinela guarda um arquivo por verificacao em `/var/lib/sentinela/`:

```bash
sudo ls -la /var/lib/sentinela/
```

```
disco__          # a verificacao "disco:/" esta em estado de alerta
http_https___meusite_com_br
```

O nome vem da chave da verificacao com todo caractere especial trocado por `_`.
O conteudo e o horario do ultimo alerta, em segundos desde 1970.

A logica:

| Situacao | O que acontece |
| --- | --- |
| falhou e nao havia arquivo | **alerta** e cria o arquivo |
| falhou e o arquivo e recente | silencio (dentro do cooldown) |
| falhou e o arquivo e antigo | **alerta de novo** e atualiza o horario |
| passou e existia arquivo | **avisa a recuperacao** e apaga o arquivo |
| passou e nao havia arquivo | silencio (segue tudo normal) |

O aviso de recuperacao importa tanto quanto o alerta: sem ele voce fica sem
saber se o problema passou ou se o monitor morreu.

---

## Por que o `.conf` nao e executado

O jeito tradicional de ler configuracao em shell e:

```bash
source /etc/sentinela.conf     # o Sentinela NAO faz isso
```

E comodo, mas significa que **todo o arquivo de configuracao e codigo**. Quem
conseguir escrever nele executa comandos como o usuario que roda o monitor —
que muitas vezes e o root.

O Sentinela le linha a linha e separa no primeiro `=`:

```bash
chave="${linha%%=*}"
valor="${linha#*=}"
```

Um `$(comando)` no arquivo fica guardado como o texto `$(comando)`, e nada roda.
Ha um teste que garante isso: ele escreve um `.conf` que tentaria criar um
arquivo, carrega a configuracao e verifica que o arquivo nao apareceu.

O preco e nao ter variavel nem condicional na configuracao. Para um monitor, e
uma troca boa.

---

## Por que comparar numero com `awk`

O `[` do shell so compara inteiro:

```bash
[ 2.5 -gt 2.0 ]     # erro: integer expression expected
```

A saida tradicional e o `bc`, mas ele nem sempre esta instalado — e uma
ferramenta que falta justo na hora do alerta e pior que ferramenta nenhuma.

O `awk` esta em qualquer sistema POSIX e resolve:

```bash
maior_que() {
    awk -v a="$1" -v b="$2" 'BEGIN { exit !(a > b) }'
}
```

O `awk` sai com codigo 0 quando `a > b`, que e o que o `if` do shell espera.
Como o `awk` ja e usado para ler o `/proc`, nao entra dependencia nova.

---

## Estrutura do codigo

O `sentinela` e um arquivo so, dividido em blocos:

| Bloco | O que faz |
| --- | --- |
| Saida | `log_ok`, `log_alerta`, cor so quando e terminal |
| Configuracao | leitura do `.conf`, valores padrao, busca do arquivo |
| Coleta | `percentual_cpu`, `percentual_memoria`, `percentual_disco`, ... |
| Estado | cooldown, marcar e limpar alerta |
| Envio | Telegram, webhook, e-mail |
| Motor | `avalia()`, que decide alertar ou nao |
| Comandos | `check`, `status`, `testar`, `config` |

A funcao central e `avalia()`. Toda verificacao termina chamando ela com quatro
argumentos: chave, rotulo, passou ou nao, e a mensagem. Toda a logica de
cooldown e recuperacao mora num lugar so — acrescentar uma verificacao nova nao
exige repetir nada disso.

No fim do arquivo:

```bash
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
```

Executado direto, roda. Carregado com `source`, so define as funcoes. E o que
permite os testes chamarem cada funcao isoladamente sem disparar verificacao.

---

## Rodar os testes

```bash
bash tests/run.sh
```

50 testes, sem instalar nada. Um deles vale destacar: para provar que um teste
serve para alguma coisa, **desligue a correcao que ele cobre e veja se ele
reprova**. Um teste que passa nos dois casos nao esta testando nada.
