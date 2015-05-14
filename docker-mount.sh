#!/bin/bash

# Copyright (C) 2015 Red Hat, Inc.
#
# An script to mount an image at specified mount point.
#
# This source code is licensed under the GNU General Public License,
# Version 2.  See the file LICENSE for more details.
#
# Author: Vivek Goyal <vgoyal@redhat.com>

is_device_active() {
  local device=$1
  if ! dmsetup info $device;then
	  return 1
  fi
}

activate_thin_device() {
  local pool_name=$1
  local device_name=$2
  local device_id=$3
  local device_size=$4

  if is_device_active $device_name > /dev/null 2>&1;then
    return
  fi

  if ! dmsetup create $device_name --table "0 $device_size thin /dev/mapper/$pool_name ${device_id}";then
	  return 1
  fi
}

remove_thin_device() {
	local device_name=$1
	dmsetup remove $device_name
}

mount_image() {
  local image=$1
  local dir=$2
  local graphdriver pool_name image_id device_id device_size device_size_sectors
  local device_name

  if ! graphdriver=$(docker inspect --format='{{.GraphDriver.Name}}' $image);then
    echo "Failed to determine docker graph driver being used. Exiting."
    exit 1
  fi

  if [ "$graphdriver" != "devicemapper" ];then
	  echo "Docker graph driver is not devicemapper. Exiting."
	  exit 1
  fi

  if ! pool_name=$(docker info | grep "Pool Name:" | cut -d " " -f4); then
    echo "Failed to determine thin pool name. Exiting."
    exit 1
  fi

  if [ ! -e "/dev/mapper/$pool_name" ];then
    echo "Thin pool $pool_name does not seem to exist. Exiting."
    exit 1
  fi

  if ! image_id=$(docker inspect --format='{{.Id}}' $image); then
    echo "Failed to determine image id. Exiting."
    exit 1
  fi

  if ! device_id=$(docker inspect --format='{{index (index .GraphDriver.Data 0) 1}}' $image); then
    echo "Failed to determine thin device id. Exiting."
    exit 1
  fi

  if ! device_size=$(docker inspect --format='{{index (index .GraphDriver.Data 1) 1}}' $image);then
    echo "Failed to determine thin device size. Exiting."
    exit 1
  fi

  device_size_sectors=$(( $device_size/512))
  device_name="thin-${image_id}"

  if ! activate_thin_device "$pool_name" "$device_name" "$device_id" "$device_size_sectors";then
	  echo "Failed to activate thin device. Exiting"
	  exit 1
  fi

  if ! mount -o "ro" /dev/mapper/$device_name $dir;then
    echo "Failed to mount thin device."
    remove_thin_device $device_name
    exit 1
  fi
}

usage() {
	echo "Usage: $0: <docker-image> <directory>"
}

# Main script
if [ $# -lt 2 ];then
  usage
  exit 1
fi

IMAGE=$1
MNTDIR=$2

if [ ! -d "$MNTDIR" ];then
	echo "Directory $MNTDIR does not exist"
	exit 1
fi

mount_image "$IMAGE" "$MNTDIR"

