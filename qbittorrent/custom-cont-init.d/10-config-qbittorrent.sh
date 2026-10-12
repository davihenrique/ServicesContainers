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

chown -R abc:abc /config/qBittorrent "$HOOK" /downloads/incomplete /downloads/complete
echo "[config-qbittorrent] configurações aplicadas"
