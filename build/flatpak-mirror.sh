#!/bin/bash
# Build the exam lab Flatpak repo on infra, signed with a lab GPG key.
# Runs on infra as root, which has internet through its NAT NIC:
#   ssh infra bash -s < build/flatpak-mirror.sh
# Steps: install the apps from Flathub, copy their refs into a new repo with
# new commits signed by the lab key, write lab.flatpakrepo for the clients.
set -euo pipefail

apps=(org.gnome.Calculator org.gnome.TextEditor)
src=/var/lib/flatpak/repo
web=/var/www/html/flatpak
repo=$web/repo
url=http://infra.lab.example.com/flatpak/repo/
export GNUPGHOME=/root/flatpak-gpg

echo "== Flathub install: ${apps[*]}"
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install -y --noninteractive flathub "${apps[@]}" >/dev/null

echo "== Lab signing key"
if [ ! -d "$GNUPGHOME" ]; then
    mkdir -m 700 "$GNUPGHOME"
    gpg --batch --pinentry-mode loopback --passphrase '' \
        --quick-gen-key 'Exam lab Flatpak <flatpak@lab.example.com>' rsa3072 sign never
fi
key=$(gpg --list-secret-keys --with-colons | awk -F: '$1 == "fpr" {print $10; exit}')
echo "key $key"

echo "== Copy refs into $repo"
[ -d "$repo" ] || ostree init --repo="$repo" --mode=archive
# Apps and runtimes only. Locale refs are partial (one language) and openh264 downloads
# from the internet at install time, so the clients skip them.
refs=$(ostree refs --repo="$src" | sed -n 's/^flathub:\(\(app\|runtime\)\/.*\)$/\1/p' \
       | grep -v -e '\.Locale/' -e '\.Debug/' -e 'openh264')
for ref in $refs; do
    echo "$ref"
    flatpak build-commit-from --src-repo="$src" --src-ref="flathub:$ref" \
        --gpg-sign="$key" --gpg-homedir="$GNUPGHOME" --no-update-summary "$repo" "$ref"
done
flatpak build-update-repo --gpg-sign="$key" --gpg-homedir="$GNUPGHOME" "$repo"

echo "== Client files"
gpg --export "$key" > "$web/lab.gpg"
cat > "$web/lab.flatpakrepo" <<EOF
[Flatpak Repo]
Title=Exam lab
Url=$url
Comment=Flatpak apps for the exam lab
GPGKey=$(base64 -w0 "$web/lab.gpg")
EOF
restorecon -R "$web"

echo "== Self-test over HTTP with signature checks"
flatpak --user remote-delete --force labtest 2>/dev/null || true
flatpak --user remote-add --gpg-import="$web/lab.gpg" labtest http://172.25.250.10/flatpak/repo/
flatpak --user remote-ls labtest
flatpak --user remote-delete --force labtest
echo "== Done: $(ostree refs --repo="$repo" | wc -l) refs, $(du -sh "$repo" | cut -f1)"
