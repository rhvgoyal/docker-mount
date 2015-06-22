#!/bin/bash

# Copyright (C) 2015 Red Hat, Inc.
#
# An script to mount an image at specified mount point.
#
# This source code is licensed under the GNU General Public License,
# Version 2.  See the file LICENSE for more details.
#
# Author: Vivek Goyal <vgoyal@redhat.com>

GRAPHDRIVER=

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
  graphdriver=$(docker info 2>/dev/null | grep "Storage Driver" | cut -d":" -f2 | sed 's/^ *//') || return 1

  [ ! -n "$graphdriver" ] && return 1

  echo $graphdriver
}

check_graph_driver() {
  local graphdriver

  if ! graphdriver=`get_graph_driver`; then
	  echo "Failed to determine graphdriver. Exiting."
	  exit 1
  fi

  if [ "$graphdriver" != "devicemapper" ] && [ "$graphdriver" != "overlay" ];then
    echo "Graph driver $graphdriver is not supported. Exiting"
    exit 1
  fi

  GRAPHDRIVER=${graphdriver}
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
  device_size=$(docker inspect --format='{{.GraphDriver.Data.DeviceSize}}' $1) || return 1
  echo $device_size
}

create_container() {
  local image=$1
  local image_id container_id

  if ! image_id=$(get_image_id $image); then
    echo "Failed to determine image id. Exiting."
    exit 1
  fi

  if ! container_id=$(docker create $1 true);then
    echo "Failed to create container from image $1. Exiting."
    exit 1
  fi

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
  local container_id

  # Create a test container from image
  if ! container_id=$(create_container ${image});then
    echo "Create container from image $image failed."
    exit 1
  fi

  if [ "$GRAPHDRIVER" == "devicemapper" ];then
    if ! mount_container_devicemapper ${container_id} $2; then
      echo "Mounting container $container_id failed."
      remove_container $container_id
      exit 1
    fi
  elif [ "$GRAPHDRIVER" == "overlay" ];then
    if ! mount_container_overlay ${container_id} $2;then
      echo "Mounting container $container_id failed."
      remove_container $container_id
      exit 1
    fi
  else
    echo "Unsupported graph driver ${GRAPHDRIVER}. Exiting"
    exit 1
  fi
}

get_lower_dir () {
  local lower_dir
  lower_dir=$(docker inspect --format='{{.GraphDriver.Data.lowerDir}}' $1) || return 1
  echo $lower_dir
}

get_upper_dir () {
  local upper_dir
  upper_dir=$(docker inspect --format='{{.GraphDriver.Data.upperDir}}' $1) || return 1
  echo $upper_dir
}

get_work_dir () {
  local work_dir
  work_dir=$(docker inspect --format='{{.GraphDriver.Data.workDir}}' $1) || return 1
  echo $work_dir
}

mount_container_overlay() {
  local container_id=$1
  local dir=$2
  local mnt_opts="ro" fstype lower_dir

  if ! lower_dir=$(get_lower_dir ${container_id});then
	  echo "Failed to query lower dir for container $container_id"
	  return 1
  fi

  if ! upper_dir=$(get_upper_dir ${container_id});then
	  echo "Failed to query upper dir for container $container_id"
	  return 1
  fi

  if ! work_dir=$(get_work_dir ${container_id});then
	  echo "Failed to query work dir for container $container_id"
	  return 1
  fi

  mnt_opts="${mnt_opts},lowerdir=${lower_dir},upperdir=${upper_dir},workdir=${work_dir}"
  if ! mount -t overlay -o ${mnt_opts} overlay $dir;then
    echo "Failed to mount overlay fs."
    return 1
  fi
}

mount_container_devicemapper() {
  local container_id=$1
  local dir=$2
  local graphdriver pool_name image_id device_id device_size device_size_sectors
  local device_name
  local mnt_opts="ro" fstype

  if ! pool_name=$(get_pool_name); then
    echo "Failed to determine thin pool name."
    return 1
  fi

  if [ ! -e "/dev/mapper/$pool_name" ];then
    echo "Thin pool $pool_name does not seem to exist."
    return 1
  fi

  if ! device_id=$(get_thin_device_id ${container_id}); then
    echo "Failed to determine thin device id."
    return 1
  fi

  if ! device_size=$(get_thin_device_size ${container_id});then
    echo "Failed to determine thin device size."
    return 1
  fi

  device_size_sectors=$(($device_size/512))
  device_name="thin-${container_id}"

  if ! activate_thin_device "$pool_name" "$device_name" "$device_id" "$device_size_sectors";then
	  echo "Failed to activate thin device. Exiting"
	  return 1
  fi

  if ! fstype=$(get_fs_type "/dev/mapper/$device_name");then
	  echo "Failed to get fs type for device $device_name."
	  remove_thin_device $device_name
	  return 1
  fi

  if [ "$fstype" == "xfs" ];then
	  mnt_opts="$mnt_opts,nouuid"
  fi

  if ! mount -o ${mnt_opts} /dev/mapper/$device_name $dir;then
    echo "Failed to mount thin device."
    remove_thin_device $device_name
    return 1
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

check_graph_driver
mount_image "$IMAGE" "$MNTDIR"
