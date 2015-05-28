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
  [ -n "$1" ] || return 1
  dmsetup info $1 > /dev/null 2>&1 || return 1
}

get_fs_type() {
  local fstype
  fstype=$(lsblk -o FSTYPE -n $1) || return 1
  echo $fstype
}


activate_thin_device() {
  local pool_name=$1 device_name=$2  device_id=$3  device_size=$4

  is_device_active $device_name && return 0
  dmsetup create $device_name --table "0 $device_size thin /dev/mapper/$pool_name ${device_id}" && return 0
  return 1
}

remove_thin_device() {
	dmsetup remove $1 || return 1
}

get_graph_driver() {
  local graphdriver
  graphdriver=$(docker inspect --format='{{.GraphDriver.Name}}' $1) || return 1
  echo $graphdriver
}

get_pool_name() {
  local pool_name
  pool_name=$(docker info | grep "Pool Name:" | cut -d " " -f4) || return 1
  echo $pool_name
}

get_thin_device_id() {
  local device_id
  device_id=$(docker inspect --format='{{.GraphDriver.Data.DeviceId}}' $1) || return 1
  echo $device_id
}

get_thin_device_size() {
  local device_size
  device_size=$(docker inspect --format='{{printf "%.0f" .GraphDriver.Data.DeviceSize}}' $1) || return 1
  echo $device_size
}

create_container() {
  local container_id
  container_id=$(docker create $1 true) || return 1
  echo $container_id
}

remove_container() {
  docker rm $1 || return 1
}

get_image_id () {
  local image_id
  image_id=$(docker inspect --format='{{.Id}}' $1) || return 1
  echo $image_id
}

mount_image() {
  local image=$1
  local dir=$2
  local graphdriver pool_name image_id device_id device_size device_size_sectors
  local device_name container_id
  local mnt_opts="ro" fstype

  if ! image_id=$(get_image_id $image); then
    echo "Failed to determine image id. Exiting."
    exit 1
  fi

  # Create a test container from image
  if ! container_id=$(create_container ${image});then
    echo "Create container from image $image failed."
    exit 1
  fi

  if ! graphdriver=$(get_graph_driver ${container_id});then
    echo "Failed to determine docker graph driver being used. Exiting."
    remove_container ${container_id}
    exit 1
  fi

  if [ "$graphdriver" != "devicemapper" ];then
    echo "Docker graph driver is not devicemapper. Exiting."
    remove_container ${container_id}
    exit 1
  fi

  if ! pool_name=$(get_pool_name); then
    echo "Failed to determine thin pool name. Exiting."
    remove_container ${container_id}
    exit 1
  fi

  if [ ! -e "/dev/mapper/$pool_name" ];then
    echo "Thin pool $pool_name does not seem to exist. Exiting."
    remove_container ${container_id}
    exit 1
  fi

  if ! device_id=$(get_thin_device_id ${container_id}); then
    echo "Failed to determine thin device id. Exiting."
    exit 1
  fi

  if ! device_size=$(get_thin_device_size ${container_id});then
    echo "Failed to determine thin device size. Exiting."
    exit 1
  fi

  device_size_sectors=$(($device_size/512))
  device_name="thin-${container_id}"

  if ! activate_thin_device "$pool_name" "$device_name" "$device_id" "$device_size_sectors";then
	  echo "Failed to activate thin device. Exiting"
	  exit 1
  fi

  if ! fstype=$(get_fs_type "/dev/mapper/$device_name");then
	  echo "Failed to get fs type for device $device_name. Exiting."
	  remove_thin_device $device_name
	  exit 1
  fi

  if [ "$fstype" == "xfs" ];then
	  mnt_opts="$mnt_opts,nouuid"
  fi

  if ! mount -o ${mnt_opts} /dev/mapper/$device_name $dir;then
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

