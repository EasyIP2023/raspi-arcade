#!/bin/bash

cur_dir=$(pwd)
mount_dir="/tmp/retropie"
version="4.7.1"
img="retropie-buster-${version}-rpi2_3.img"
image_file="${cur_dir}/${img}"
loop_device=""
part_one=""
part_two=""

check_cmd() {
	[[ $1 -ne 0 ]] && {
		echo "[x] err: $2"
		exit 2
	}
}

check_root() {
	[[ $(id -u) -ne 0 ]] && {
	  echo "[x] Must be root to execute"
	  echo "[x] Try: sudo $0"
	  exit 2
	}
}

cleanup() {
	[[ -d ${mount_dir} ]] || exit 0

	sync -f ${mount_dir}

	# Using find user processes to kill anything
	# preventing a given mount point from unmounting
	fuser -mk ${mount_dir} >/dev/null
	umount -Rv ${mount_dir} >/dev/null
	losetup -d ${loop_device} >/dev/null
	rm -rf ${mount_dir} >/dev/null
}

download_img() {
	[[ -f ${image_file} ]] || {
		wget https://github.com/RetroPie/RetroPie-Setup/releases/download/${version}/${img}.gz
		check_cmd $? "wget failed"

		echo "Unziping ${image_file}.gz"
		gunzip ${image_file}.gz
		check_cmd $? "gunzip failed to decompress ${image_file}"
	}
}

mount_img() {
	mkdir -p ${mount_dir}/boot

	loop_device="$(losetup -f -P --show ${image_file})"
	check_cmd $? "no looback device created for ${image_file}"

	part_one="${loop_device}p1"
	part_two="${loop_device}p2"

	mount -t auto -o rw ${part_two} ${mount_dir}
	check_cmd $? "mounting of ${part_two} failed"

	mount -t auto -o rw ${part_one} ${mount_dir}/boot
	check_cmd $? "mounting of ${part_one} failed"
}

config_img() {
	# Switch from en_GB to en_US var
	# sed -i "s/en_GB.UTF-8/en_US.UTF-8/g" ${mount_dir}/etc/default/locale
	# I'm okay with doing this
	systemd-nspawn -D ${mount_dir} /bin/sh -c "dpkg-reconfigure locales"

	# https://www.systutorials.com/docs/linux/man/5-keyboard/
	# Change keyboard layout to US
	sed -i "s/XKBLAYOUT=\"gb\"/XKBLAYOUT=\"us\"/g" ${mount_dir}/etc/default/keyboard

	systemd-nspawn -D ${mount_dir} /bin/sh -c "locale-gen en_US.UTF-8" # Just encase
	systemd-nspawn -D ${mount_dir} /bin/sh -c "update-locale en_US.UTF-8"
	systemd-nspawn -D ${mount_dir} /bin/sh -c "ln -sf /usr/share/zoneinfo/US/Central /etc/localtime"
	systemd-nspawn -D ${mount_dir} /bin/sh -c "curl https://raw.githubusercontent.com/adafruit/Raspberry-Pi-Installer-Scripts/master/retrogame.sh > /home/pi/retrogame.sh"
	systemd-nspawn -D ${mount_dir} /bin/sh -c "chmod +x /home/pi/retrogame.sh"
	systemd-nspawn -D ${mount_dir} /bin/sh -c "/bin/bash -C /home/pi/retrogame.sh"
	systemd-nspawn -D ${mount_dir} /bin/sh -c "shred -n30 -uvz /home/pi/retrogame.sh"

	cp ${cur_dir}/retrogame.cfg ${mount_dir}/boot/
	sed -i -e "s/#hdmi_drive=2/hdmi_drive=2/g" \
				 -e "s/#disable_overscan=1/disable_overscan=1/g" \
				 -e "s/overscan_scale=1/#overscan_scale=1/g" \
	${mount_dir}/boot/config.txt
}

trap cleanup EXIT INT

check_root
download_img
mount_img
config_img

exit 0