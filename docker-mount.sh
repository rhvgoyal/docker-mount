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

activate_thin_device() {
  local pool_name=$1 device_name=$2  device_id=$3  device_size=$4

  if is_device_active $device_name;then
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

get_graph_driver() {
  local id=$1
  local graphdriver

  if ! graphdriver=$(docker inspect --format='{{.GraphDriver.Name}}' $id);then
	  return 1
  fi
  echo $graphdriver
}

get_pool_name() {
  local pool_name

  if ! pool_name=$(docker info | grep "Pool Name:" | cut -d " " -f4); then
    return 1
  fi
  echo $pool_name
}

get_thin_device_id() {
  local id=$1
  local device_id

  if ! device_id=$(docker inspect --format='{{index (index .GraphDriver.Data 0) 1}}' $id); then
    return 1
  fi
  echo $device_id
}

get_thin_device_size() {
  local id=$1
  local device_size

  if ! device_size=$(docker inspect --format='{{index (index .GraphDriver.Data 1) 1}}' $id);then
    return 1
  fi
  echo $device_size
}

create_container() {
  local image=$1
  local container_id

  if ! container_id=$(docker create $image true);then
	  echo "Creating container from image $image failed."
	  return 1
  fi

  echo $container_id
}

remove_container() {
  local container=$1

  if ! docker rm $1;then
	  return 1
  fi
}

get_graph_driver () {
  local id=$1
  local graphdriver

  if ! graphdriver=$(docker inspect --format='{{.GraphDriver.Name}}' $id);then
    return 1
  fi

  echo $graphdriver
}

get_image_id () {
  local image_id

  if ! image_id=$(docker inspect --format='{{.Id}}' $1); then
   return 1
  fi
  echo $image_id
}

mount_image() {
  local image=$1
  local dir=$2
  local graphdriver pool_name image_id device_id device_size device_size_sectors
  local device_name container_id

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

