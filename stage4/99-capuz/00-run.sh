#!/bin/bash -e
# CaPuZ: eigen slotstap bovenop het M5Stack CardputerZero-image.
# Bevat GEEN geheimen: wachtwoord en wifi stel je bij de eerste start in met
# de M5Stack-installatiewizard, of vooraf met capuz-instellingen.txt op de
# opstartpartitie (zie 3d). Tailscale koppelt via dat bestand of later met
# `sudo tailscale up`.

# 1. Volume echt toepassen (software-volume voor de ES8389).
install -d "${ROOTFS_DIR}/etc/wireplumber/wireplumber.conf.d"
install -m 644 files/60-capuz-soft-volume.conf \
    "${ROOTFS_DIR}/etc/wireplumber/wireplumber.conf.d/60-capuz-soft-volume.conf"

# 2. SSH alleen met sleutel; openbare sleutel van de beheer-pc voor gebruiker
#    pi. De M5Stack-wizard hernoemt pi naar de gekozen naam en verhuist de
#    thuismap, dus de sleutel verhuist mee.
install -d "${ROOTFS_DIR}/etc/ssh/sshd_config.d"
install -m 644 files/10-geen-wachtwoord.conf \
    "${ROOTFS_DIR}/etc/ssh/sshd_config.d/10-geen-wachtwoord.conf"
install -d -m 700 -o 1000 -g 1000 "${ROOTFS_DIR}/home/pi/.ssh"
install -m 600 -o 1000 -g 1000 files/authorized_keys \
    "${ROOTFS_DIR}/home/pi/.ssh/authorized_keys"

# 3. Eenmalige opruiming na de eerste start (bureaublad uit, wizards weg,
#    cloud-init uit).
install -d "${ROOTFS_DIR}/usr/lib/capuz"
install -m 755 files/capuz-firstboot-cleanup \
    "${ROOTFS_DIR}/usr/lib/capuz/capuz-firstboot-cleanup"
install -m 644 files/capuz-firstboot-cleanup.service \
    "${ROOTFS_DIR}/usr/lib/systemd/system/capuz-firstboot-cleanup.service"
install -d "${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants"
ln -sf /usr/lib/systemd/system/capuz-firstboot-cleanup.service \
    "${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/capuz-firstboot-cleanup.service"

# 3b. Raspberry Pi-hernoemdialoog (userconfig) nooit starten: die draait
#     anders onzichtbaar op tty8 en vangt toetsaanslagen op (zie het bestand).
install -d "${ROOTFS_DIR}/etc/systemd/system/userconfig.service.d"
install -m 644 files/10-capuz-userconfig-nooit.conf \
    "${ROOTFS_DIR}/etc/systemd/system/userconfig.service.d/10-capuz-userconfig-nooit.conf"

# 3c. Zodra de M5Stack-wizard klaar is meteen opruimen (scheelt een herstart).
install -d "${ROOTFS_DIR}/etc/systemd/system/LaunchWizard.service.d"
install -m 644 files/10-capuz-opruimen-na-wizard.conf \
    "${ROOTFS_DIR}/etc/systemd/system/LaunchWizard.service.d/10-capuz-opruimen-na-wizard.conf"

# 3d. Instellen zonder wizard: capuz-instellingen.txt op de opstartpartitie
#     (voorbeeld staat ernaast). Wordt vóór de wizard ingelezen en gewist.
install -m 755 files/capuz-voorinstellen \
    "${ROOTFS_DIR}/usr/lib/capuz/capuz-voorinstellen"
install -m 644 files/capuz-voorinstellen.service \
    "${ROOTFS_DIR}/usr/lib/systemd/system/capuz-voorinstellen.service"
install -d "${ROOTFS_DIR}/etc/systemd/system/sysinit.target.wants"
ln -sf /usr/lib/systemd/system/capuz-voorinstellen.service \
    "${ROOTFS_DIR}/etc/systemd/system/sysinit.target.wants/capuz-voorinstellen.service"
install -m 755 files/capuz-tailscale-koppelen \
    "${ROOTFS_DIR}/usr/lib/capuz/capuz-tailscale-koppelen"
install -m 644 files/capuz-tailscale-koppelen.service \
    "${ROOTFS_DIR}/usr/lib/systemd/system/capuz-tailscale-koppelen.service"
ln -sf /usr/lib/systemd/system/capuz-tailscale-koppelen.service \
    "${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/capuz-tailscale-koppelen.service"
install -m 644 files/capuz-instellingen-voorbeeld.txt \
    "${ROOTFS_DIR}/boot/firmware/capuz-instellingen-voorbeeld.txt"

# 4. Tailscale installeren (nog niet gekoppeld).
on_chroot << 'CHROOT'
set -e
install -d -m 0755 /usr/share/keyrings
curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.noarmor.gpg \
    -o /usr/share/keyrings/tailscale-archive-keyring.gpg
curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.tailscale-keyring.list \
    -o /etc/apt/sources.list.d/tailscale.list
apt-get update
apt-get install -y --no-install-recommends tailscale
systemctl enable tailscaled.service
CHROOT

# 5. Controle: de kernel moet vast blijven staan (zelfgebouwde drivers).
on_chroot << 'CHROOT'
if ! apt-mark showhold | grep -q '^linux-image-rpi-v8$'; then
    echo "FOUT: kernel staat niet op hold" >&2
    exit 1
fi
CHROOT
