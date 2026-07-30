#!/bin/bash

current_path="$(pwd)"
max_partition=2
img_action="${1}"

error_msg() {
    echo -e " [💔] ${1}"
    exit 1
}

process_msg() {
    echo -e " [🌿] ${1}"
}

mount_try() {
    # Check mount parameters
    m_type="${1}"
    m_dev="${2}"
    m_target="${3}"
    process_msg "m_type:${m_type}, m_dev=${m_dev}, m_target=${m_target}"
    [[ -n "${m_type}" && -n "${m_dev}" && -n "${m_target}" ]] || {
        error_msg "Missing mount parameters: [ ${m_type}, ${m_dev}, ${m_target} ]"
    }

    t="1"
    max_try="10"
    while [[ "${t}" -le "${max_try}" ]]; do
        # Mount according to the partition format
        if [[ "${m_type}" == "btrfs" ]]; then
            mount -t ${m_type} -o discard,compress=zstd:1 ${m_dev} ${m_target} 2>/dev/null
        else
            mount -t ${m_type} -o discard ${m_dev} ${m_target} 2>/dev/null
        fi

        # Retry on mount failure
        if [[ "${?}" -eq 0 ]]; then
            break
        else
            sync && sleep 3
            umount -f ${m_target} 2>/dev/null
            ((t++))
        fi
    done
    [[ "${t}" -gt "${max_try}" ]] && error_msg "Failed to mount after [ ${t} ] attempts."
}

mount_image() {
    local fnnas_image_file="${1}"
    local mount_part mount_type
    [[ -f "${fnnas_image_file}" ]] || error_msg "Invalid image file: ${fnnas_image_file}."

    process_msg "Extracting FnNAS files."
    cd "${current_path}"
    local loop_old="$(losetup -P -f --show "${fnnas_image_file}")"
    [[ -n "${loop_old}" ]] || error_msg "losetup ${fnnas_image_file} failed."

    for mount_part in $(seq ${max_partition}); do
    case ${mount_part} in
        1) mount_type=ext4 ;;
        2) mount_type=btrfs ;;
        *) mount_type=ext4 ;;
    esac
        # Mount rootfs partition
        mount_dev="${loop_old}p${mount_part}"
        [ -b "${mount_dev}" ] || error_msg "Invalid partition: ${mount_dev}"
    local tmp_path=${current_path}/output_$(basename ${loop_old})_p${mount_part}
        rm -rf "${tmp_path}"; mkdir -p "${tmp_path}"
        mount_try "${mount_type}" "${mount_dev}" "${tmp_path}"
    done
}

umount_image() {
    for mnt in ${current_path}/output_*; do
        [ -d ${mnt} ] || continue
        process_msg "Umount: [${mnt}]"
        umount -f ${mnt}
        loop=${mnt##*output_}
        loop=${loop%%_*}
        [ -b /dev/${loop} ] || continue
        process_msg "Detach: [${loop}]"
        losetup -d /dev/${loop}
        [ "$(ls -A ${mnt})" ] || rm -rf ${mnt}
    done
}

if [ -f "${img_action}" ]; then
    mount_image "${img_action}"
elif [ "${img_action}" == "umount" ]; then
    umount_image
fi
