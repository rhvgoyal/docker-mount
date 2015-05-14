# docker-mount
Tools to mount/unmount docker images

Preparation for Testing
=======================

- Rebuild docker with following PR.

  https://github.com/docker/docker/pull/13198

- Start docker with devicemapper graphdriver.

HOW TO TEST
===========

- Pull image
$ docker pull fedora

- Mount image
$ mkdir -p /tmp/image
$ docker-mount.sh fedora /tmp/image

- Unmount image
$ docker-umount.sh /tmp/image
