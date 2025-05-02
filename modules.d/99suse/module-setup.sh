#!/bin/bash
# -*- mode: shell-script; indent-tabs-mode: nil; sh-basic-offset: 4; -*-
# ex: ts=8 sw=4 sts=4 et filetype=sh
# module-setup.sh for openSUSE / SLE initrd parameters conversion

install() {
    inst_hook cmdline 99 "$moddir/parse-suse-initrd.sh"

    inst_rules \
    60-io-scheduler.rules
}
