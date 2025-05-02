#!/bin/bash

# Parse SUSE kernel module dependencies
#
# Kernel modules using "request_module" function may not show up in modprobe
# To worka round this, add depedencies in the following form:
# # SUSE_INITRD: module_name REQUIRES module1 module2 ...
# to /etc/modprobe.d/*.conf

# called by dracut
check() {
    # Skip the module if no SUSE INITRD is used
    local conf_files=$(get_modprobe_conf_files)
    [[ $conf_files ]] && grep -q "^# SUSE INITRD: " $conf_files
}

get_modprobe_conf_files() {
    ls /etc/modprobe.d/*.conf /run/modprobe.d/*.conf \
       /lib/modprobe.d/*.conf /usr/lib/modprobe.d/*.conf \
       2>/dev/null
    return 0
}

get_suse_initrd_lines() {
    local conf_files=$(get_modprobe_conf_files)
    [[ -z "$conf_files" ]] || grep -h "^# SUSE INITRD: " $conf_files
}

read_initrd_modules() {
    if [[ -f /etc/sysconfig/kernel ]]; then
        INITRD_MODULES=
        . /etc/sysconfig/kernel
        echo "$INITRD_MODULES"
    fi
}

filter_builtin() {
    while [[ $# -gt 0 ]]; do
        grep -q "/$1.ko" "/lib/modules/$kernel/modules.builtin" || echo "$1"
        shift
    done
}

# called by dracut
installkernel() {
    local line mod reqs all_mods="$(filter_builtin $(read_initrd_modules))"

    while read -r line; do
        mod="${line##*SUSE INITRD: }"
        mod="${mod%% REQUIRES*}"
        reqs="${line##*REQUIRES }"
        if [[ ! $hostonly ]] || grep -q "^$mod\$" "$DRACUT_KERNEL_MODALIASES"
        then
            all_mods="$all_mods $(filter_builtin $reqs)"
        fi
    done <<< "$(get_suse_initrd_lines)"

    # strip whitespace
    all_mods="$(echo $all_mods)"
    if [[ "$all_mods" ]]; then
        hostonly='' dracut_instmods $all_mods
    fi

    return 0
}
