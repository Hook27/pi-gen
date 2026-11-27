#!/bin/bash
# Offline test van stage4/99-capuz/files/capuz-voorinstellen met nepbestanden.
# Draait in een tijdelijke testmap met CAPUZ_DROOG=1: er wordt niets aan het
# echte systeem veranderd. Gebruik: bash capuz-tests/test-voorinstellen.sh
set -u
HIER=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="$HIER/stage4/99-capuz/files/capuz-voorinstellen"
# Nep-Tailscale-sleutel in stukjes, zodat GitHub hem niet als echte sleutel ziet.
NEP_TS="tsk""ey-nep-voorbeeld-0000"
GEHEIMEN=("Geheim=wachtwoord 123" "WifiSleutel!42" "$NEP_TS")
GOED=0; FOUT=0

nieuw_systeem() {   # maakt een nep-root + nep-opstartpartitie in $T
    T=$(mktemp -d); mkdir -p "$T/root/etc" "$T/boot" \
        "$T/root/usr/share/zoneinfo/Europe" "$T/root/var/lib/LaunchWizard"
    printf '127.0.0.1\tlocalhost\n127.0.1.1\tCaPuZ\n' > "$T/root/etc/hosts"
    echo CaPuZ > "$T/root/etc/hostname"
    echo "pi:100000:65536" > "$T/root/etc/subuid"
    : > "$T/root/usr/share/zoneinfo/Europe/Amsterdam"
    printf 'NL\tNetherlands\nBE\tBelgium\n' > "$T/root/usr/share/zoneinfo/iso3166.tab"
    : > "$T/root/var/lib/LaunchWizard/run-oobe"
    : > "$T/root/var/lib/LaunchWizard/run-keyboard-guide"
}
draai() {   # $1 = eerste gebruiker (UID 1000) in de test
    CAPUZ_DROOG=1 CAPUZ_ROOT="$T/root" CAPUZ_BOOT="$T/boot" \
        CAPUZ_TEST_EERSTE_GEBRUIKER="$1" sh "$SCRIPT" > "$T/uitvoer.txt" 2>&1
    echo $? > "$T/exit.txt"
}
check() {   # $1 = omschrijving, rest = test-commando
    local wat=$1; shift
    if "$@"; then GOED=$((GOED + 1)); echo "  ok    $wat"
    else FOUT=$((FOUT + 1)); echo "  FOUT  $wat"; fi
}
bevat()      { grep -qF -- "$2" "$1"; }
geen_geheim() {
    for g in "${GEHEIMEN[@]}"; do
        grep -rqF -- "$g" "$T/boot" "$T/uitvoer.txt" && return 1
    done; return 0
}
geen_instellingenbestand() { ! ls "$T/boot" | grep -qi '^capuz-instellingen\.txt'; }

GELDIG=$'\xEF\xBB\xBF# test\r\ngebruiker = jorg\r\nWACHTWOORD=Geheim=wachtwoord 123\r\nHOSTNAAM=CP0cstm\r\nWIFI_NAAM="Ziggo Thuis"\r\nWIFI_WACHTWOORD=WifiSleutel!42\r\nWIFI_LAND=nl\r\nTIJDZONE=Europe/Amsterdam\r\nTAILSCALE_SLEUTEL='"$NEP_TS"$'\r\nTOETSENBORD_UITLEG=nee\r\n'

echo "1. Geldig bestand (BOM, Windows-regeleinden, spaties, '=' in wachtwoord, .TXT.txt)"
nieuw_systeem; printf '%s' "$GELDIG" > "$T/boot/Capuz-Instellingen.TXT.txt"; draai pi
check "exit 0"                         bevat "$T/exit.txt" "0"
check "instellingenbestand gewist"     geen_instellingenbestand
check "hernoemen pi -> jorg"           bevat "$T/uitvoer.txt" "DROOG: usermod -l jorg pi"
check "thuismap verhuisd"              bevat "$T/uitvoer.txt" "DROOG: usermod -m -d /home/jorg jorg"
check "groep hernoemd"                 bevat "$T/uitvoer.txt" "DROOG: groupmod -n jorg pi"
check "wachtwoord gezet (verborgen)"   bevat "$T/uitvoer.txt" "chpasswd (jorg, wachtwoord verborgen)"
check "hostnaam-bestand"               bevat "$T/root/etc/hostname" "CP0cstm"
check "hosts 127.0.1.1"                bevat "$T/root/etc/hosts" $'127.0.1.1\tCP0cstm'
check "hosts localhost behouden"       bevat "$T/root/etc/hosts" $'127.0.0.1\tlocalhost'
check "tijdzone"                       bevat "$T/root/etc/timezone" "Europe/Amsterdam"
check "wifi-land NL (hoofdletters)"    bevat "$T/uitvoer.txt" "do_wifi_country NL"
check "wifi-profiel met spatie in naam" bevat "$T/uitvoer.txt" "ssid 'Ziggo Thuis'"
check "tailscale-sleutel bewaard"      bevat "$T/root/var/lib/capuz/tailscale-sleutel" "$NEP_TS"
check "toetsenbord-uitleg overgeslagen" bevat "$T/uitvoer.txt" "rm -f $T/root/var/lib/LaunchWizard/run-keyboard-guide"
check "resultaat: gebruiker OK"        bevat "$T/boot/capuz-instellingen-RESULTAAT.txt" "Gebruiker   : jorg  [OK]"
check "resultaat: wifi OK"             bevat "$T/boot/capuz-instellingen-RESULTAAT.txt" "Wifi        : Ziggo Thuis  [OK]"
check "resultaat: tailscale volgt"     bevat "$T/boot/capuz-instellingen-RESULTAAT.txt" "koppelen volgt"
check "geen geheim in uitvoer/resultaat" geen_geheim
rm -rf "$T"

fout_geval() {   # $1 = omschrijving, $2 = vervang-sed, $3 = verwachte foutregel
    echo "$1"
    nieuw_systeem
    printf "%s" "$GELDIG" | sed -b "$2" > "$T/boot/capuz-instellingen.txt"; draai pi
    check "fout gemeld"              bevat "$T/boot/capuz-instellingen-RESULTAAT.txt" "$3"
    check "niets veranderd (hostnaam)" bevat "$T/root/etc/hostname" "CaPuZ"
    check "niet hernoemd"            sh -c "! grep -q 'usermod' '$T/uitvoer.txt'"
    check "instellingenbestand gewist" geen_instellingenbestand
    check "geen geheim in uitvoer/resultaat" geen_geheim
    rm -rf "$T"
}
fout_geval "2. Hoofdletter in gebruikersnaam"  's/jorg/Jorg/'                    "- GEBRUIKER: verplicht"
fout_geval "3. Gebruikersnaam pi"              's/= jorg/= pi/'                  "GEBRUIKER: 'pi' mag niet"
fout_geval "4. Wifi-wachtwoord te kort"        's/WifiSleutel!42/kort/'          "- WIFI_WACHTWOORD: moet 8 tot 63"
fout_geval "5. Ongeldige Tailscale-sleutel"    "s/$NEP_TS/abc/" "- TAILSCALE_SLEUTEL: moet beginnen"
fout_geval "6. Onbekende tijdzone"             's#Europe/Amsterdam#Mars/Basis#'  "- TIJDZONE: 'Mars/Basis' bestaat niet"
fout_geval "7. Onbekend wifi-land"             's/WIFI_LAND=nl/WIFI_LAND=XX/'    "- WIFI_LAND: geen geldige"
fout_geval "8. Wifi-wachtwoord zonder wifi-naam" 's/WIFI_NAAM="Ziggo Thuis"/WIFI_NAAM=/' "- WIFI_NAAM: leeg"
fout_geval "9. Geen wachtwoord"                's/^WACHTWOORD=.*\r$/WACHTWOORD=\r/' "- WACHTWOORD: verplicht."

echo "10. Apparaat al ingesteld (eerste gebruiker heet al jorg)"
nieuw_systeem; printf '%s' "$GELDIG" > "$T/boot/capuz-instellingen.txt"; draai jorg
check "genegeerd gemeld"           bevat "$T/boot/capuz-instellingen-RESULTAAT.txt" "GENEGEERD"
check "instellingenbestand gewist" geen_instellingenbestand
check "niets veranderd"            bevat "$T/root/etc/hostname" "CaPuZ"
rm -rf "$T"

echo "11. Geen instellingenbestand"
nieuw_systeem; draai pi
check "exit 0"                     bevat "$T/exit.txt" "0"
check "geen resultaatbestand"      test ! -e "$T/boot/capuz-instellingen-RESULTAAT.txt"
check "niets veranderd"            bevat "$T/root/etc/hostname" "CaPuZ"
rm -rf "$T"

echo "12. Zonder wifi en zonder Tailscale"
nieuw_systeem
printf "%s" "$GELDIG" | sed -b -e 's/^WIFI_NAAM=.*\r$/WIFI_NAAM=\r/' -e 's/^WIFI_WACHTWOORD=.*\r$/WIFI_WACHTWOORD=\r/' \
    -e 's/^TAILSCALE_SLEUTEL=.*\r$/TAILSCALE_SLEUTEL=\r/' > "$T/boot/capuz-instellingen.txt"; draai pi
check "toegepast"                  bevat "$T/boot/capuz-instellingen-RESULTAAT.txt" "Gebruiker   : jorg  [OK]"
check "wifi niet ingesteld"        bevat "$T/boot/capuz-instellingen-RESULTAAT.txt" "Wifi        : niet ingesteld"
check "geen wifi-profiel"          sh -c "! grep -q nmcli '$T/uitvoer.txt'"
check "geen tailscale-sleutel"     test ! -e "$T/root/var/lib/capuz/tailscale-sleutel"
rm -rf "$T"

echo "13. Droge test zonder testmap wordt geweigerd"
out=$(CAPUZ_DROOG=1 sh "$SCRIPT" 2>&1); rc=$?
check "geweigerd (exit 2)"         test "$rc" -eq 2

echo
echo "Resultaat: $GOED geslaagd, $FOUT mislukt"
[ "$FOUT" -eq 0 ]
