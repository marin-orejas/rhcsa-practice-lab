#!/bin/bash
# Reinstall exam nodes from their kickstarts: new golden image, new empty data disks, then reset.sh.
# Runs on the NUC as a member of the libvirt group (no sudo). Takes about 10 minutes.
# Usage: rebuild-nodes.sh [node...]   (default: node1 node2)
set -euo pipefail
cd "$(dirname "$0")"

pool=default
iso=/var/lib/libvirt/images/rhel-10.2-x86_64-dvd.iso
nodes=("$@")
[ "${#nodes[@]}" -gt 0 ] || nodes=(node1 node2)

# The root password stays out of git: the kickstarts carry @ROOT_PASSWORD@, and the first line
# of root-password (next to this script, mode 600) fills it in a temporary copy
password=$(head -n 1 root-password 2>/dev/null || true)
if ! [[ $password =~ ^[A-Za-z0-9]+$ ]]; then
    echo "root-password: missing, or not one word of letters and digits, nothing changed" >&2
    exit 1
fi
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

for n in "${nodes[@]}"; do
    # A NIC given by MAC makes Anaconda rename it to ksdev0
    if ! grep -q -- '--device=enp1s0' "$n.ks"; then
        echo "$n.ks: the NIC is not given by name, nothing changed" >&2
        exit 1
    fi
    if ! grep -q '^rootpw --plaintext @ROOT_PASSWORD@$' "$n.ks"; then
        echo "$n.ks: no rootpw line with @ROOT_PASSWORD@, nothing changed" >&2
        exit 1
    fi
    sed "/^rootpw /s/@ROOT_PASSWORD@/$password/" "$n.ks" >"$tmp/$n.ks"
done

for n in "${nodes[@]}"; do
    if virsh dominfo "$n" >/dev/null 2>&1; then
        [ "$(virsh domstate "$n")" = "shut off" ] || virsh destroy "$n" >/dev/null
        virsh undefine "$n" >/dev/null
    fi
    for vol in "$n.qcow2" "$n-vdb.qcow2" "$n-vdc.qcow2" "$n-golden.qcow2"; do
        virsh vol-delete "$vol" --pool "$pool" >/dev/null 2>&1 || true
    done
    virsh vol-create-as "$pool" "$n-golden.qcow2" 20G --format qcow2 >/dev/null
    virsh vol-create-as "$pool" "$n-vdb.qcow2" 5G --format qcow2 >/dev/null
    virsh vol-create-as "$pool" "$n-vdc.qcow2" 5G --format qcow2 >/dev/null
    virt-install --name "$n" --memory 2048 --vcpus 2 --osinfo rhel10.2 --boot uefi=off \
        --disk vol="$pool/$n-golden.qcow2" \
        --disk vol="$pool/$n-vdb.qcow2" \
        --disk vol="$pool/$n-vdc.qcow2" \
        --network network=exam,mac=52:54:00:fa:00:1"${n#node}" \
        --graphics vnc --video virtio \
        --location "$iso" \
        --initrd-inject "$tmp/$n.ks" \
        --extra-args "inst.ks=file:/$n.ks" \
        --noautoconsole >/dev/null
    echo "$n: install started"
done

for n in "${nodes[@]}"; do
    until [ "$(virsh domstate "$n")" = "shut off" ]; do sleep 15; done
    echo "$n: install finished"
done

# The VM runs on an overlay; the installed disk stays as the golden image
for n in "${nodes[@]}"; do
    virsh vol-create-as "$pool" "$n.qcow2" 20G --format qcow2 \
        --backing-vol "$n-golden.qcow2" --backing-vol-format qcow2 >/dev/null
    virt-xml "$n" --edit target=vda --disk path="/var/lib/libvirt/images/$n.qcow2" >/dev/null
done

./reset.sh "${nodes[@]}"
