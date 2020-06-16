#!/bin/bash

DIR="$(cd "$(dirname "$0")" && pwd)"

inform(){
  echo "\n\033[1;36m$@\033[0m"
}

inform "Downloading VirtIO drivers for Windows..."
rm -rf $DIR/Windows/drivers/*
wget -P $DIR/Windows/drivers https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso

inform "Done!"
