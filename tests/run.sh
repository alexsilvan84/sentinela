#!/usr/bin/env bash
#
# Testes do Sentinela. Sem dependencia externa: roda com `bash tests/run.sh`.
#
# O script principal e carregado com `source`, o que funciona porque ele so
# chama main() quando executado direto.

set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Isola o estado para nao encostar no estado real da maquina.
XDG_STATE_HOME="$(mktemp -d)"
XDG_CONFIG_HOME="$(mktemp -d)"
TEMP="$(mktemp -d)"
SENTINELA_CONFIG=""
export XDG_STATE_HOME XDG_CONFIG_HOME SENTINELA_CONFIG

trap 'rm -rf "$XDG_STATE_HOME" "$XDG_CONFIG_HOME" "$TEMP"' EXIT

# O caminho e montado em tempo de execucao, entao o shellcheck precisa da
# dica abaixo para achar o arquivo: SCRIPTDIR o faz resolver ../sentinela a
# partir da pasta deste script, e nao da pasta de onde o comando foi rodado.
# shellcheck source-path=SCRIPTDIR source=../sentinela
source "$RAIZ/sentinela"

PASSOU=0
FALHOU=0

ok() {
    PASSOU=$((PASSOU + 1))
    printf '  \033[32mok\033[0m   %s\n' "$1"
}

falha() {
    FALHOU=$((FALHOU + 1))
    printf '  \033[31mFALHA\033[0m %s\n' "$1"
    printf '        esperado: [%s]\n        obtido:   [%s]\n' "$2" "$3"
}

igual() {
    local descricao="$1" esperado="$2" obtido="$3"
    if [ "$esperado" = "$obtido" ]; then
        ok "$descricao"
    else
        falha "$descricao" "$esperado" "$obtido"
    fi
}

verdadeiro() {
    local descricao="$1"; shift
    if "$@"; then ok "$descricao"; else falha "$descricao" "sucesso" "falha"; fi
}

falso() {
    local descricao="$1"; shift
    if "$@"; then falha "$descricao" "falha" "sucesso"; else ok "$descricao"; fi
}

grupo() { printf '\n\033[1m%s\033[0m\n' "$1"; }

# ---------------------------------------------------------------------------

grupo "apara() - remove espacos das pontas"
igual "espacos nas duas pontas" "abc" "$(apara "   abc   ")"
igual "tabulacao" "abc" "$(apara $'\tabc\t')"
igual "texto sem espacos" "abc" "$(apara "abc")"
igual "string vazia" "" "$(apara "")"
igual "espaco interno preservado" "a b" "$(apara "  a b  ")"

grupo "tira_aspas() - aspas opcionais no valor"
igual "aspas duplas" "abc" "$(tira_aspas '"abc"')"
igual "aspas simples" "abc" "$(tira_aspas "'abc'")"
igual "sem aspas" "abc" "$(tira_aspas "abc")"
igual "aspa so de um lado fica" '"abc' "$(tira_aspas '"abc')"
igual "aspas no meio ficam" 'a"b' "$(tira_aspas 'a"b')"

grupo "divide_lista() - separa por virgula"
igual "tres itens" "a b c" "$(divide_lista "a,b,c" | tr '\n' ' ' | sed 's/ $//')"
igual "espacos em volta" "a b" "$(divide_lista " a , b " | tr '\n' ' ' | sed 's/ $//')"
igual "itens vazios ignorados" "a b" "$(divide_lista "a,,b," | tr '\n' ' ' | sed 's/ $//')"
igual "lista vazia" "" "$(divide_lista "")"

grupo "maior_que() - comparacao com decimal"
verdadeiro "2.5 > 2.0" maior_que 2.5 2.0
falso      "2.0 > 2.5" maior_que 2.0 2.5
falso      "iguais nao e maior" maior_que 2.0 2.0
verdadeiro "10 > 9 (nao compara como texto)" maior_que 10 9
verdadeiro "0.51 > 0.5" maior_que 0.51 0.5

grupo "escapa_json() - saida precisa ser JSON valido"
igual "aspas escapadas" 'ele disse \"oi\"' "$(escapa_json 'ele disse "oi"')"
igual "barra invertida escapada" 'a\\b' "$(escapa_json 'a\b')"
igual "quebra de linha vira \\n" 'a\nb' "$(escapa_json $'a\nb')"

# Procura um Python que realmente rode. No Windows o `python3` do PATH costuma
# ser o atalho da Microsoft Store, que existe mas nao executa nada.
PY=""
for candidato in python3 python; do
    if command -v "$candidato" >/dev/null 2>&1 &&
       "$candidato" -c 'print(1)' >/dev/null 2>&1; then
        PY="$candidato"
        break
    fi
done

if [ -n "$PY" ]; then
    entrada=$'texto com "aspas", \\barra e\nquebra'
    json="{\"content\":\"$(escapa_json "$entrada")\"}"
    if printf '%s' "$json" | "$PY" -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
        ok "JSON gerado e parseavel"
    else
        falha "JSON gerado e parseavel" "JSON valido" "$json"
    fi

    # JSON proibe byte de controle cru dentro de string. Se um nome de servico
    # ou a resposta de um comando trouxer um, o webhook receberia lixo.
    controle=$'servicocomcontrole'
    json="{\"content\":\"$(escapa_json "$controle")\"}"
    if printf '%s' "$json" | "$PY" -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
        ok "caractere de controle cru nao invalida o JSON"
    else
        falha "caractere de controle cru nao invalida o JSON" "JSON valido" "$json"
    fi
fi

grupo "chave_estado() - nome de arquivo seguro"
igual "barra vira underscore" "disco__" "$(chave_estado "disco:/")"
igual "URL sem caractere especial" "http_https___exemplo_com" "$(chave_estado "http:https://exemplo.com")"
igual "ponto vira underscore" "porta_host_22" "$(chave_estado "porta:host:22")"

grupo "carrega_config() - leitura do arquivo"
cat > "$TEMP/basico.conf" <<'CONF'
# comentario no comeco
limite_cpu = 70

limite_memoria=75
alerta_email = "eu@exemplo.com"
http=https://exemplo.com/pagina#secao
CONF
carrega_config "$TEMP/basico.conf"
igual "valor com espacos em volta do =" "70" "${CONFIG[limite_cpu]}"
igual "valor sem espacos" "75" "${CONFIG[limite_memoria]}"
igual "aspas removidas" "eu@exemplo.com" "${CONFIG[alerta_email]}"
igual "URL com # preservada" "https://exemplo.com/pagina#secao" "${CONFIG[http]}"

grupo "carrega_config() - o .conf nao pode executar comandos"
cat > "$TEMP/malicioso.conf" <<'CONF'
limite_cpu=$(touch /tmp/sentinela_invadido)
alerta_email=`touch /tmp/sentinela_invadido2`
CONF
rm -f /tmp/sentinela_invadido /tmp/sentinela_invadido2
carrega_config "$TEMP/malicioso.conf" 2>/dev/null
falso "substituicao de comando nao executa" test -f /tmp/sentinela_invadido
falso "crase nao executa" test -f /tmp/sentinela_invadido2
igual "valor guardado como texto literal" '$(touch /tmp/sentinela_invadido)' "${CONFIG[limite_cpu]}"

grupo "carrega_config() - chave desconhecida e recusada"
cat > "$TEMP/desconhecida.conf" <<'CONF'
chave_que_nao_existe=1
CONF
carrega_config "$TEMP/desconhecida.conf" 2>/dev/null
falso "chave desconhecida nao entra na config" test -n "${CONFIG[chave_que_nao_existe]:-}"

grupo "percentual_disco() - coluna localizada pelo %"
df() {
    # Nome de sistema de arquivos com espaco desloca as colunas. Era o bug que
    # fazia ler os bytes livres como se fossem o percentual.
    printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
    printf 'C:/Program Files/Git 468589564 379140108 89449456 81%% /\n'
}
igual "le 81 por cento mesmo com espaco no nome" "81" "$(percentual_disco / )"
unset -f df

df() {
    printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
    printf '/dev/sda1 100 5 95 5%% /\n'
}
igual "le percentual de um digito" "5" "$(percentual_disco / )"
unset -f df

grupo "cooldown_vencido() - nao repete alerta cedo demais"
CONFIG[alerta_cooldown]=1800
limpa_alerta "teste_cd"
verdadeiro "sem estado anterior, pode alertar" cooldown_vencido "teste_cd"
marca_alerta "teste_cd"
falso "logo apos alertar, segura" cooldown_vencido "teste_cd"
verdadeiro "estado ficou marcado" em_alerta "teste_cd"

# Envelhece o registro para alem da janela.
printf '%s' "$(( $(date +%s) - 3600 ))" > "$(diretorio_estado)/$(chave_estado "teste_cd")"
verdadeiro "passada a janela, alerta de novo" cooldown_vencido "teste_cd"

limpa_alerta "teste_cd"
falso "limpa_alerta remove o estado" em_alerta "teste_cd"

grupo "avalia() - ciclo alerta / recuperacao"
ENVIADAS=()
notifica() { ENVIADAS+=("$1"); return 0; }

SILENCIOSO=1
CONFIG[nome_host]="host-teste"
limpa_alerta "svc"

avalia "svc" "servico x" 1 "parado"
igual "primeira falha notifica" "1" "${#ENVIADAS[@]}"
case "${ENVIADAS[0]}" in
    "[ALERTA]"*) ok "mensagem marcada como ALERTA" ;;
    *) falha "mensagem marcada como ALERTA" "[ALERTA]..." "${ENVIADAS[0]}" ;;
esac

avalia "svc" "servico x" 1 "parado"
igual "falha repetida nao notifica de novo" "1" "${#ENVIADAS[@]}"

avalia "svc" "servico x" 0 "ativo"
igual "recuperacao notifica" "2" "${#ENVIADAS[@]}"
case "${ENVIADAS[1]}" in
    "[OK]"*) ok "mensagem de volta marcada como OK" ;;
    *) falha "mensagem de volta marcada como OK" "[OK]..." "${ENVIADAS[1]}" ;;
esac

avalia "svc" "servico x" 0 "ativo"
igual "seguir normal nao notifica" "2" "${#ENVIADAS[@]}"

grupo "contadores"
igual "TOTAL contou as quatro chamadas" "4" "$TOTAL"
igual "FALHAS contou as duas falhas" "2" "$FALHAS"

# ---------------------------------------------------------------------------

printf '\n'
if [ "$FALHOU" -eq 0 ]; then
    printf '\033[32m%d testes, todos passaram.\033[0m\n' "$PASSOU"
    exit 0
fi

printf '\033[31m%d de %d testes falharam.\033[0m\n' "$FALHOU" "$((PASSOU + FALHOU))"
exit 1
