#!/bin/bash

# called by dracut
check() {
    resume_on_cmdline() {
        local _cmdline _arg _value

        read -ra _cmdline < /proc/cmdline
        for _arg in "${_cmdline[@]}"; do
            if [[ $_arg == resume=* ]] || [[ $_arg == "noresume" ]]; then
                _value="${_arg#resume=}"
            fi
        done

        [[ $_value ]] && printf "%s" "$_value"
    }

    swap_on_netdevice() {
        local _dev
        for _dev in "${swap_devs[@]}"; do
            block_is_netdevice "$(get_maj_min "$_dev")" && return 0
        done
        return 1
    }

    # Only support resume if there is any suitable swap and
    # it is not mounted on a net device
    [[ $hostonly ]] || [[ $mount_needs ]] && {
        # sanity check: do not add the resume module if there is a
        # resume argument pointing to a non existent disk or to a
        # volatile swap
        local _resume
        _resume=$(resume_on_cmdline)
        if [ -n "$_resume" ]; then
            [[ $_resume == "noresume" ]] && return 255
            _resume="$(label_uuid_to_dev "$_resume")"
            if [ ! -e "$_resume" ]; then
                derror "Current resume kernel argument points to an invalid disk"
                return 255
            fi
            if [[ $_resume == /dev/mapper/* ]]; then
                if [[ -f "$dracutsysrootdir"/etc/crypttab ]]; then
                    local _mapper _opts
                    read -r _mapper _ _ _opts < <(grep -m1 -w "^${_resume#/dev/mapper/}" "$dracutsysrootdir"/etc/crypttab)
                    if [[ -n $_mapper ]] && [[ $_opts == *swap* ]]; then
                        derror "Current resume kernel argument points to a volatile swap"
                        return 255
                    fi
                fi
            fi
        fi
        ((${#swap_devs[@]})) || return 255
        swap_on_netdevice && return 255
    }

    return 0
}

# called by dracut
depends() {
    if ! dracut_module_included "systemd"; then
        echo initqueue
    fi
    return 0
}

# called by dracut
cmdline() {
    local _resume

    for dev in "${!host_fs_types[@]}"; do
        [[ ${host_fs_types[$dev]} =~ ^(swap|swsuspend|swsupend)$ ]] || continue
        _resume=$(shorten_persistent_dev "$(get_persistent_dev "$dev")")
        [[ -n ${_resume} ]] && printf " resume=%s" "${_resume}"
    done
}

# called by dracut
install() {
    local _bin
    local _resumeconf

    if [[ $hostonly_cmdline == "yes" ]]; then
        _resumeconf=$(cmdline)
        [[ $_resumeconf ]] && printf "%s\n" "$_resumeconf" >> "${initdir}/etc/cmdline.d/20-resume.conf"
    fi

    # if systemd is included and has the hibernate-resume tool, use it and nothing else
    if dracut_module_included "systemd"; then
        inst_multiple -o \
            "$systemdutildir"/system-generators/systemd-hibernate-resume-generator \
            "$systemdsystemunitdir"/systemd-hibernate-resume.service \
            "$systemdutildir"/systemd-hibernate-resume
        return 0
    fi

    # Optional uswsusp support
    for _bin in /usr/sbin/resume /usr/lib/suspend/resume /usr/lib64/suspend/resume /usr/lib/uswsusp/resume /usr/lib64/uswsusp/resume; do
        [[ -x "${dracutsysrootdir-}${_bin}" ]] && {
            inst "${_bin}" /usr/sbin/resume
            [[ $hostonly ]] && [[ -f "${dracutsysrootdir-}/etc/suspend.conf" ]] && inst -H /etc/suspend.conf
            break
        }
    done

    inst_hook cmdline 10 "$moddir/parse-resume.sh"
    inst_script "$moddir/resume.sh" /lib/dracut/resume.sh
}
