#!/bin/bash
# Reset exam nodes to the state right after their install:
# a new overlay on the golden image and two new empty data disks.
# Runs on the NUC as a member of the libvirt group (no sudo).
# Usage: reset.sh [node...]   (default: node1 node2)
set -euo pipefail

pool=default
dir=/var/lib/libvirt/images
declare -A ip=([node1]=172.25.250.11 [node2]=172.25.250.12)

nodes=("$@")
[ "${#nodes[@]}" -gt 0 ] || nodes=(node1 node2)

for n in "${nodes[@]}"; do
    if [ -z "${ip[$n]:-}" ]; then
        echo "$n: unknown node" >&2
        exit 2
    fi
    # The VM must run on its overlay. If it pointed at the golden image, a reset would not undo anything.
    if ! virsh domblklist "$n" --inactive | grep -qE "^ *vda +$dir/$n\.qcow2 *$"; then
        echo "$n: vda is not $dir/$n.qcow2, nothing changed" >&2
        exit 1
    fi

    [ "$(virsh domstate "$n")" = "shut off" ] || virsh destroy "$n" >/dev/null

    for vol in "$n.qcow2" "$n-vdb.qcow2" "$n-vdc.qcow2"; do
        virsh vol-delete "$vol" --pool "$pool" >/dev/null 2>&1 || true
    done
    virsh vol-create-as "$pool" "$n.qcow2" 20G --format qcow2 \
        --backing-vol "$n-golden.qcow2" --backing-vol-format qcow2 >/dev/null
    virsh vol-create-as "$pool" "$n-vdb.qcow2" 5G --format qcow2 >/dev/null
    virsh vol-create-as "$pool" "$n-vdc.qcow2" 5G --format qcow2 >/dev/null

    virsh start "$n" >/dev/null
    echo "$n: reset, booting"
done

# Wait until SSH answers, at most 2 minutes per node
for n in "${nodes[@]}"; do
    if timeout 120 bash -c "until (exec 3<>/dev/tcp/${ip[$n]}/22) 2>/dev/null; do sleep 2; done"; then
        echo "$n: up (${ip[$n]})"
    else
        echo "$n: no SSH after 2 minutes, check the console" >&2
    fi
done
