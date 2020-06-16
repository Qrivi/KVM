#!/bin/bash

# Constants
DIR="$(cd "$(dirname "$0")" && pwd)"
CATALOG='https://swscan.apple.com/content/catalogs/others/index-10.15-10.14-10.13-10.12-10.11-10.10-10.9-mountainlion-lion-snowleopard-leopard.merged-1.sucatalog'

inform() {
  echo "\n\033[1;36m$@\033[0m"
}
warning() {
  echo "\033[1;31m$@\033[0m"
}

findLinks() {
  links=($(awk '/'$@'</{print $1}' $DIR/macOS.sucatalog))
  let i=0
  for link in "${links[@]}"; do
    links[$i]="${link:8:${#link}-17}"
    let i++
  done

  let min=0
  let max=$((${#links[@]} - 1))

  while [[ min -lt max ]]; do
    x="${links[$min]}"
    links[$min]="${links[$max]}"
    links[$max]="$x"
    let min++
    let max--
  done

  echo ${links[@]}
}

getVersions() {
  plists=($(findLinks InstallInfo.plist))
  let i=0
  for plist in "${plists[@]}"; do
    version=$(curl -s -f $plist | tail -5)
    versions[$i]="$(echo $version | awk -v FS="(string>|</string)" '{print $2}')"
    let i++
  done
  echo ${versions[@]}
}

prettifyVersion() {
  version=$(echo $@)
  case $version in
  10.15.*)
    echo macOS "${version:0:7}" Catalina \("${version: -10}"\)
    ;;
  10.14.*)
    echo macOS "${version:0:7}" Mojave \("${version: -10}"\)
    ;;
  10.13.*)
    echo macOS "${version:0:7}" High Sierra \("${version: -10}"\)
    ;;
  *)
    echo macOS "${version:0:7}" \("${version: -10}"\)
    ;;
  esac
}

inform "Fetching the macOS software catalog..."
rm -rf $DIR/macOS.sucatalog
wget -O $DIR/macOS.sucatalog $CATALOG

inform "Looking for macOS BaseSystem..."
availableImages=($(findLinks BaseSystem.dmg))
for image in "${availableImages[@]}"; do
  echo $image
done

inform "Discovering available macOS versions..."
availableVersions=($(getVersions))
i=0
for version in "${availableVersions[@]}"; do
  let i++
  echo $i\) $(prettifyVersion $version)
done

let download=-1
while [[ $download == -1 ]]; do
  read -p "Which version do you want to download? [1-$i] : " input
  if [[ $((input)) != $input || $input == 0 || "$input" -gt "$i" ]]; then
    warning "$input is not a valid selection."
  else
    let download=$input-1
  fi
done

inform "Downloading macOS BaseSystem..."
rm -rf $DIR/BaseSystem.dmg $DIR/BaseSystem.img
wget -P $DIR ${availableImages[$download]}

if type qemu-img >/dev/null 2>&1; then
  inform "Converting Apple disk image to regular disk image..."
  qemu-img convert $DIR/BaseSystem.dmg -O raw $DIR/BaseSystem.img
else
  warning "qemu package is not installed!"
  echo You will need to convert BaseSystem.dmg to BaseSystem.img before you can use it.
fi

inform "Done!"
