#!/usr/bin/env bash
#
# Instalador do Sentinela.
#
#   sudo ./install.sh              instala em /usr/local/bin
#   ./install.sh --user            instala em ~/.local/bin, sem sudo
#   sudo ./install.sh --systemd    instala e agenda a cada 5 minutos
#   sudo ./install.sh --remover    desinstala

set -euo pipefail

ORIGEM="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MODO_USUARIO=0
COM_SYSTEMD=0
REMOVER=0

while [ $# -gt 0 ]; do
    case "$1" in
        --user|--usuario) MODO_USUARIO=1 ;;
        --systemd)        COM_SYSTEMD=1 ;;
        --remover|--uninstall) REMOVER=1 ;;
        -h|--help)
            sed -n '3,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) printf 'opcao desconhecida: %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done

if [ "$MODO_USUARIO" -eq 1 ]; then
    DESTINO_BIN="$HOME/.local/bin"
    DESTINO_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/sentinela"
else
    DESTINO_BIN="/usr/local/bin"
    DESTINO_CONF="/etc/sentinela"
fi

info()  { printf '  %s\n' "$*"; }
erro()  { printf 'erro: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------

if [ "$REMOVER" -eq 1 ]; then
    printf 'Removendo o Sentinela...\n'

    if [ "$MODO_USUARIO" -eq 0 ] && command -v systemctl >/dev/null 2>&1; then
        systemctl disable --now sentinela.timer 2>/dev/null || true
        rm -f /etc/systemd/system/sentinela.service /etc/systemd/system/sentinela.timer
        systemctl daemon-reload 2>/dev/null || true
        info "agendamento removido"
    fi

    rm -f "$DESTINO_BIN/sentinela"
    info "$DESTINO_BIN/sentinela removido"
    info "a configuracao em $DESTINO_CONF foi mantida"
    exit 0
fi

# ---------------------------------------------------------------------------

if [ "$MODO_USUARIO" -eq 0 ] && [ "$(id -u)" -ne 0 ]; then
    erro "instalar em $DESTINO_BIN precisa de root. Use sudo, ou rode com --user."
fi

[ -f "$ORIGEM/sentinela" ] || erro "arquivo 'sentinela' nao encontrado em $ORIGEM"

printf 'Instalando o Sentinela...\n'

# Dependencias: tudo que o script usa alem do proprio bash.
faltando=()
for programa in awk df date curl tr; do
    command -v "$programa" >/dev/null 2>&1 || faltando+=("$programa")
done

if [ "${#faltando[@]}" -gt 0 ]; then
    erro "faltam os comandos: ${faltando[*]}"
fi

if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
    erro "o Sentinela precisa do Bash 4 ou superior (voce tem ${BASH_VERSION})"
fi

install -d "$DESTINO_BIN"
install -m 0755 "$ORIGEM/sentinela" "$DESTINO_BIN/sentinela"
info "$DESTINO_BIN/sentinela"

install -d "$DESTINO_CONF"

if [ -f "$DESTINO_CONF/sentinela.conf" ]; then
    # Nunca sobrescreve uma configuracao existente: os limites e os tokens
    # do usuario estao ali dentro.
    install -m 0644 "$ORIGEM/sentinela.conf.example" "$DESTINO_CONF/sentinela.conf.example"
    info "$DESTINO_CONF/sentinela.conf ja existia e foi mantido"
else
    # 0600: o arquivo guarda o token do Telegram e a URL do webhook.
    install -m 0600 "$ORIGEM/sentinela.conf.example" "$DESTINO_CONF/sentinela.conf"
    info "$DESTINO_CONF/sentinela.conf"
fi

if [ "$COM_SYSTEMD" -eq 1 ]; then
    command -v systemctl >/dev/null 2>&1 || erro "systemctl nao encontrado"

    install -m 0644 "$ORIGEM/systemd/sentinela.service" /etc/systemd/system/sentinela.service
    install -m 0644 "$ORIGEM/systemd/sentinela.timer" /etc/systemd/system/sentinela.timer
    systemctl daemon-reload
    systemctl enable --now sentinela.timer

    info "agendado a cada 5 minutos (systemctl status sentinela.timer)"
fi

printf '\nPronto.\n\n'
printf 'Proximos passos:\n'
printf '  1. edite %s/sentinela.conf\n' "$DESTINO_CONF"
printf '  2. rode  sentinela status   para ver os valores atuais\n'
printf '  3. rode  sentinela testar   para conferir os alertas\n'

if [ "$MODO_USUARIO" -eq 1 ] && [[ ":$PATH:" != *":$DESTINO_BIN:"* ]]; then
    printf '\nAviso: %s nao esta no PATH. Acrescente ao seu ~/.bashrc:\n' "$DESTINO_BIN"
    printf '  export PATH="$PATH:%s"\n' "$DESTINO_BIN"
fi
