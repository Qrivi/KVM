#!/bin/bash

DIR="$(cd "$(dirname "$0")" && pwd)"
SELECTION=$1

# URL to Apple's macOS software update catalog
CATALOG='https://swscan.apple.com/content/catalogs/others/index-10.15-10.14-10.13-10.12-10.11-10.10-10.9-mountainlion-lion-snowleopard-leopard.merged-1.sucatalog'

# Function to print bold text in teal
inform() {
  echo "\n\033[1;36m$@\033[0m"
}

# Function to print bold text in red
warning() {
  echo "\033[1;31m$@\033[0m"
}

# Returns all the links for a certain file name found in the catalog
findLinks() {
  links=($(awk '/'$@'</{print $1}' $DIR/macOS.sucatalog))
  i=0
  for link in "${links[@]}"; do
    links[$i]="${link:8:${#link}-17}"
    let i++
  done
  # Reversing the array so the newest links should be on top
  min=0
  max=$((${#links[@]} - 1))
  while [[ min -lt max ]]; do
    x="${links[$min]}"
    links[$min]="${links[$max]}"
    links[$max]="$x"
    let min++
    let max--
  done
  echo ${links[@]}
}

# Fetches an InstallInfo.plist and filters out the macOS version
getVersions() {
  plists=($(findLinks InstallInfo.plist))
  i=0
  for plist in "${plists[@]}"; do
    version=$(curl -s -f $plist | tail -5)
    versions[$i]="$(echo $version | awk -v FS="(string>|</string)" '{print $2}')"
    let i++
  done
  echo ${versions[@]}
}

# Returns a pretty name for a given macOS version
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

############
# Let's go #
############

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

download=-1
while [[ $download == -1 ]]; do
  if [[ $((SELECTION)) != $SELECTION || $SELECTION -eq 0 ]]; then # argument is NaN of 0 (none passed)
    read -p "Which version do you want to download? [1-$i] : " input
  else
    echo Choosing option $1 which was passed as an input argument.
    input=$SELECTION
    SELECTION=0
  fi

  if [[ $((input)) != $input || $input -eq 0 || "$input" -gt "$i" ]]; then # input is NaN, 0 or out of bounds
    warning "$input is not a valid selection."
  else
    let download=$input-1
  fi
done

inform "Downloading macOS BaseSystem..."
rm -rf $DIR/BaseSystem.dmg
wget -O $DIR/BaseSystem.dmg ${availableImages[$download]}

if type qemu-img >/dev/null 2>&1; then # qemu-img command is not found
  inform "Converting Apple disk image to regular disk image..."
  rm -rf $DIR/BaseSystem.img
  qemu-img convert $DIR/BaseSystem.dmg -O raw $DIR/BaseSystem.img
else
  warning "qemu package is not installed!"
  echo You will need to convert BaseSystem.dmg to BaseSystem.img before you can use it.
fi

inform "Done!"
