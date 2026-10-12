#!/bin/bash
# Executado pela imagem linuxserver a cada start do container, antes do qBittorrent subir.
# Aplica as configurações que antes eram feitas manualmente pelo WebUI.
set -euo pipefail

CONF=/config/qBittorrent/qBittorrent.conf
HOOK=/config/on-torrent-finished.sh

# Define KEY=VALUE dentro de [SECTION] no .ini, criando seção/chave se faltarem.
# Valores passados via ENVIRON porque o awk -v interpretaria as barras de "Session\...".
set_ini() {
    S="[$1]" K="$2" V="$3" awk '
        BEGIN { s = ENVIRON["S"]; k = ENVIRON["K"]; v = ENVIRON["V"] }
        $0 == s { print; insect = 1; next }
        /^\[/ { if (insect && !found) { print k "=" v; found = 1 } insect = 0 }
        insect && index($0, k "=") == 1 { if (!found) { print k "=" v; found = 1 } next }
        { print }
        END { if (!found) { if (!insect) print "\n" s; print k "=" v } }
    ' "$CONF" > "$CONF.tmp"
    mv "$CONF.tmp" "$CONF"
}

mkdir -p /config/qBittorrent /downloads/incomplete /downloads/complete
touch "$CONF"

# Hook chamado ao concluir cada torrent: só sinaliza o host, onde a unit
# mover-torrents.path do systemd dispara o mover-torrents.sh.
cat > "$HOOK" <<'HOOK'
#!/bin/sh
date > /config/torrent-finished
HOOK
chmod 755 "$HOOK"

set_ini BitTorrent 'Session\DefaultSavePath' /downloads/complete
set_ini BitTorrent 'Session\TempPath' /downloads/incomplete
set_ini BitTorrent 'Session\TempPathEnabled' true
set_ini AutoRun enabled true
set_ini AutoRun program "$HOOK"

# Usuário do WebUI vindo do secret QBT_WEBUI_USERNAME (via .env gerado pelo deploy).
# O qBittorrent exige ao menos 3 caracteres. Sem a variável, o usuário fica como está (padrão: admin).
if [[ -n "${QBT_WEBUI_USERNAME:-}" ]]; then
    if (( ${#QBT_WEBUI_USERNAME} < 3 )); then
        echo "[config-qbittorrent] QBT_WEBUI_USERNAME precisa de ao menos 3 caracteres, usuário mantido" >&2
    elif [[ "$(sed -n 's/^WebUI\\Username=//p' "$CONF" | head -n 1)" != "$QBT_WEBUI_USERNAME" ]]; then
        set_ini Preferences 'WebUI\Username' "$QBT_WEBUI_USERNAME"
        echo "[config-qbittorrent] usuário do WebUI definido a partir do secret"
    fi
fi

# Senha do WebUI vinda do secret QBT_WEBUI_PASSWORD (via .env gerado pelo deploy).
# O qBittorrent guarda só o hash: PBKDF2-SHA512, 100000 iterações, salt de 16 bytes.
# Se a senha atual já for a do secret, nada é alterado. Sem a variável, a senha fica como está.
if [[ -n "${QBT_WEBUI_PASSWORD:-}" ]]; then
    CURRENT=$(sed -n 's/^WebUI\\Password_PBKDF2=//p' "$CONF" | head -n 1)
    HASH=$(CURRENT="$CURRENT" python3 - <<'PY'
import base64, hashlib, os, re
pw = os.environ["QBT_WEBUI_PASSWORD"].encode()
m = re.fullmatch(r'"?@ByteArray\(([^:]+):([^)]+)\)"?', os.environ["CURRENT"])
if m:
    salt, key = base64.b64decode(m[1]), base64.b64decode(m[2])
    if hashlib.pbkdf2_hmac("sha512", pw, salt, 100000, len(key)) == key:
        raise SystemExit
salt = os.urandom(16)
key = hashlib.pbkdf2_hmac("sha512", pw, salt, 100000, 64)
print('"@ByteArray(%s:%s)"' % (base64.b64encode(salt).decode(), base64.b64encode(key).decode()))
PY
    )
    if [[ -n "$HASH" ]]; then
        set_ini Preferences 'WebUI\Password_PBKDF2' "$HASH"
        echo "[config-qbittorrent] senha do WebUI definida a partir do secret"
    fi
fi

chown -R abc:abc /config/qBittorrent "$HOOK" /downloads/incomplete /downloads/complete
echo "[config-qbittorrent] configurações aplicadas"
