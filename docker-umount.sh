#!/bin/bash

# Copyright (C) 2015 Red Hat, Inc.
#
# An script to unmount and remove thin device mounted by docker-mount.sh

# This source code is licensed under the GNU General Public License,
# Version 2.  See the file LICENSE for more details.
#
# Author: Vivek Goyal <vgoyal@redhat.com>

remove_thin_device() {
	dmsetup remove $1 || return 1
}

remove_container() {
  docker rm $1 > /dev/null || return 1
}

unmount_image() {
  local dir=$1
  local device container_id

  if ! device=$(findmnt -n -o SOURCE --target $dir);then
    echo "Failed to determine source of mount target"
    exit 1
  fi

  if ! umount $dir;then
    echo "Failed to unmount $dir"
    exit 1
  fi

  if ! remove_thin_device $device;then
    echo "Failed to remove thin device $device"
    exit 1
  fi

  container_id=${device#/dev/mapper/thin-}
  if ! remove_container ${container_id}; then
	  echo "Failed to remove container $container_id"
  fi
}

usage() {
	echo "Usage: $0: <directory>"
}

# Main script
if [ $# -lt 1 ];then
  usage
  exit 1
fi

MNTDIR=$1

if [ ! -d "$MNTDIR" ];then
	echo "Directory $MNTDIR does not exist"
	exit 1
fi

unmount_image "$MNTDIR"
