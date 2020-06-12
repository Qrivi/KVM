# KVM

> Kristof's Vigorous Machine

This guide's a work in progress... 👨‍🔧

* [Intro](#intro)
* [Hardware Configuration](#hardware-configuration)
  + [Important Notes](#important-notes)
* [Host OS: Manjaro Linux](#host-os--manjaro-linux)
  + [Installation](#installation)
  + [Configure the Open Virtual Machine Firmware (OVMF) for PCI passthrough](#configure-the-open-virtual-machine-firmware--ovmf--for-pci-passthrough)
  + [Setting up a network bridge](#setting-up-a-network-bridge)
* [Guest OS: macOS Catalina](#guest-os--macos-catalina)
* [Guest OS: Windows 10](#host-os--windows-10)
* [Resources](#resources)

## Intro

Recently I switched from a Windows and macOS (Hackintosh) dual boot on my main system to a Linux install so I could use its type-1 (bare-metal) hypervisor to run the two aforementioned OS as kernel-based virtual machines (KVMs). The main benefit of this setup is the ability to pause one OS and switch to the other, rather than having to reboot, while the drop in overall performance is negligible thanks to hardware passthrough. Having the OS and boot files on a virtual disk that I can take snapshots of (e.g. prior to a system update) is really nice too!

I set up this repo to remind my future self of the steps I took to get everything working and have versioning of important configuration files. Special thanks to all my past selves to keep this up-to-date.

## Hardware Configuration

My current build ~~to flex~~ as a reference, as some of the configuration is specific to my build.

| Hardware    | Brand                                                                                                                            | Purchase date                                 |
|-------------|----------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------|
| Motherboard | Gigabyte GA-Z270-HD3P Intel Z270 LGA 1151 (ATX, Socket H4)                                                                       | Oct 2017                                      |
| CPU         | Intel Core i7 7700 Kaby Lake (8MB, 3.60/4.20 GHz)                                                                                | Oct 2017                                      |
| RAM         | 4x Crucial 8GB DDR4-2400                                                                                                         | Oct 2017                                      |
| GPU         | 1x Asus Expedition AMD Radeon RX 570 OC 4GB GDDR5<br>1x Asus ROG Strix Nvidia GeForce RTX 2070 SUPER OC 8GB GDDR6                | Oct 2018<br>June 2020                         |
| NIC         | Apple Broadcom BCM94360CD (802.11 a/b/g/n/ac, Bluetooth 4.0)                                                                     | Oct 2017                                      |
| PSU         | NZXT C750 80+ Gold 750W                                                                                                          | June 2020                                     |
| Storage     | 1x WD Blue 1TB (SATA SSD)<br>1x WD Blue 1TB (SATA HDD)<br>1x Crucial MX300 275GB (SATA SSD)<br>1x Kingston A400 240GB (SATA SSD) | June 2020<br>Oct 2017<br>Oct 2017<br>Jan 2019 |
| Peripherals | 1x Logitech B910 HD USB Webcam & Microphone<br>1x cheap USB mouse<br>1x cheap USB keyboard                                       | Oct 2017<br>Oct 2017<br>Oct 2017              |

### Important Notes

- You will need a CPU that supports virtualization and have VT-d and VT-x (Intel) or AMD-V (AMD) enabled in the BIOS.
- If you plan on passing through your only GPU, you will need a CPU with integrated graphics enabled in the BIOS.

## Host OS: Manjaro Linux

Went with Manjaro so I could have a lightweight Arch based Linux distro as the host OS without having too much trouble setting everything up — Manjaro's installation process is very intuitive and straightforward. However, any recent Linux distro should work though some commands might be different if it is not Arch based. A Red Hat distro like CentOS or Fedora is worth considering as KVM is a Red Hat technology.

I've also chosen to use the Xfce desktop environment as it is modular and modern _enough_ while remaining relatively lightweight. Any DE is fine, and you can choose to not install one and use the CLI ~~if you hate yourself~~.

### Installation

Create a USB installation media and install Manjaro. 👍

### Configure the Open Virtual Machine Firmware (OVMF) for PCI passthrough

First, edit the GRUB boot loader configuration to enable the I/O memory management unit (IOMMU). You will need `sudo` to edit this file.
```shell
sudo nano /etc/default/grub
```
Depending on the CPU architecture, add the `intel_iommu` or `amd_iommu` flag to `GRUB_CMDLINE_LINUX_DEFAULT` and set it to `on`. Also add the general `iommu` flag and set this one to `pt` — this will prevent Linux from touching devices which cannot be passed through. Leave the existing flags be.
```text
GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt apparmo r=1 security=apparmor udev.log_priority=3"
```
To persist these changes, rebuild the boot loader and reboot the system.
```shell
sudo grub-mkconfig -o /boot/grub/grub.cfg
reboot
```
Once rebooted, verify that IOMMU has been correctly enabled and IOMMU groups were created. If the `dmesg` output contains `DMAR: IOMMU enabled` and lists PCI slots being added to IOMMU groups, we are golden.
```shell
sudo dmesg | grep -i -e DMAR -e IOMMU
```
Next up, we will modify `mkinitcpio` to load the VFIO stub drivers early in order to prevent Manjaro itself from interacting with certain PCI devices (so we can pass them through to a guest VM) we will define later on.
```shell
sudo nano /etc/mkinitcpio.conf
```
Edit the `MODULES` to load `vfio_pci`, `vfio`, `vfio_iommu_type1`, and `vfio_virqfd` **in that order** and add `modconf` to the `HOOKS`. Make sure the VFIO modules are loaded **before** any other modules that interact with PCI hardware you want to passthrough to a guest OS (e.g. the `radeon` or `amdgpu` module). In most scenarios, simply add the VFIO modules to the beginning of the `MODULES` list.
```text
...
MODULES=(vfio_pci vfio vfio_iommu_type1 vfio_virqfd)
...
HOOKS="base udev autodetect modconf block keyboard keymap filesystems"
...
```
To persist these changes, regenerate the `initramfs` while passing it the kernel you are using as a preset. You can look this up or simply have it autocompleted by hitting tab. And reboot.
```shell
sudo mkinitcpio -p linux56
reboot
```
Once rebooted, it's install software time!
```shell
sudo pacman -Sy qemu libvirt ovmf virt-manager ebtables iptables dnsmasq

sudo systemctl enable libvirtd.service
sudo systemctl start libvirtd.service

sudo systemctl enable virtlogd.socket
sudo systemctl start virtlogd.socket

sudo virsh net-start default
sudo virsh net-autostart default
```

### Setting up a network bridge

Creating a network bridge in Linux that can be passed as a network interface controller (NIC) to a guest VM allows that VM to be in the same network as the host with minimum configuration required. This means that the guest OS will get its IP address from the home router/DHCP server and will be able to interact with other devices that are in the same network, such as network printers or network speakers.

While not strictly necessary, the first thing one can do is disable [Predictable Network Interface Names](https://www.freedesktop.org/wiki/Software/systemd/PredictableNetworkInterfaceNames/) that ship with `systemd`. This will make it so the ethernet interface will be `eth0` again, which is fine on consumer grade motherboards that do not have multiple ethernet interfaces.
```shell
sudo ln -s /dev/null /etc/systemd/network/99-default.link
sudo systemctl restart NetworkManager.service # Not sure if this is enough -- if not: just reboot
```
`ip a` should now list your ethernet adapter as `eth0`. E.g.:
```text
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP group default qlen 1000
    link/ether 52:54:00:8c:62:44 brd ff:ff:ff:ff:ff:ff
    inet 192.168.0.2/24 brd 192.168.121.255 scope global dynamic eth0
       valid_lft 2900sec preferred_lft 2900sec
    inet6 fe80::5054:ff:fe8c:6244/64 scope link
       valid_lft forever preferred_lft forever
```
I used `netctl` instead of `NetworkManager`, which came with Manjaro, to set up the bridge. However, I believe it should/might be perfectly possible to do so with `NetworkManager` too — I just haven't looked into this. To avoid conflicts, stop `NetworkManager` first, then install `netctl`.
```shell
sudo systemctl stop NetworkManager.service
sudo pacman -Sy netctl
```
To define a new network bridge, create its configuration file in `/etc/netctl` and give it a sensible name, such as `bridge` or `kvm-bridge`. You will need `sudo` to create and edit this file.
```shell
sudo nano /etc/netctl/bridge
```
Below is a basic bridge configuration that should suffice for most use-cases. More exotic bridge configurations are beyond the scope of this guide. Make sure `BindsToInterface` is set to your ethernet interface (which is `eth0` if Predictable Network Interface Names is disabled) and `Interface` "makes sense" (by convention it should start with `br`).
```text
Description="Bridge Connection for KVM"
Interface=br0
Connection=bridge
BindsToInterfaces=(eth0)
IP=dhcp
```
Once defined, we can enable and start the bridge. The last argument passed to the `netctl` commands is the file name of the bridge configuration we created in the previous step.
```shell
sudo netctl enable bridge
sudo netctl start bridge
```
To allow QEMU to use this bridge, append `allow br0`, where `br0` is your bridge's name, to QEMU's bridge configuration file. If this configuration file does not exist yet, create it.
```shell
sudo nano /etc/qemu/bridge.conf
```
In order to have both host and guest(s) be able to connect over ethernet, the ethernet adapter needs to be replaced with the bridge, then bind the ethernet adapter to the bridge. This can be done with `bridge-utils`.
```shell
sudo pacman -Sy bridge-utils
```
Fist we'll enable IPv4 forwarding and make it permanent.
```
sudo -s
sysctl net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-sysctl.conf
```
Then we'll load the `tun` module and configure it to be loaded at boot time.
```shell
sudo -s
modprobe tun
echo "tun" > /etc/modules-load.d/tun.conf
```
To have the bridge behave properly when QEMU starts a guest VM, we need to create a `qemu-ifup` and `qemu-ifdown` script in `/etc`. These files do not have an extension and you will need `sudo` to create them. Their respective contents should be as follows:
```shell
#!/bin/sh
echo "Executing /etc/qemu-ifup"
echo "Bringing up $1 for bridged mode..."
sudo /usr/bin/ip link set $1 up promisc on
echo "Adding $1 to br0..."
sudo /usr/bin/brctl addif br0 $1
sleep 2
```
```shell
#!/bin/sh
echo "Executing /etc/qemu-ifdown"
sudo /usr/bin/ip link set $1 down
sudo /usr/bin/brctl delif br0 $1
sudo /usr/bin/ip link delete dev $1
```
For these scripts to work, we need to fix their owner, group and permissions.
```shell
sudo chown root:kvm /etc/qemu-ifup
sudo chmod 750 /etc/qemu-ifup
sudo chown root:kvm /etc/qemu-ifdown
sudo chmod 750 /etc/qemu-ifdown
```
And we have to update the sudoers file so they can be run without prompting for the root password.
```shell
sudo EDITOR=nano visudo
```
Append the following to the sudoers file:
```
Cmnd_Alias  QEMU=/usr/bin/ip,/usr/bin/modprobe,/usr/bin/brctl
%kvm        ALL=NOPASSWD: QEMU
```
To avoid performance hickups or security conflicts, it is recommended to disable the firewall on the bridge in its configuration file. If this configuration file does not exist yet, create it.
```shell
sudo nano /etc/sysctl.d/10-disable-firewall-on-bridge.conf
```
Append the following to the configuration file:
```text
net.bridge.bridge-nf-call-ip6tables = 0
net.bridge.bridge-nf-call-iptables = 0
net.bridge.bridge-nf-call-arptables = 0
```
For the firewall configuration to be picked up correctly, the `br_netfilter` module needs to be loaded. First we'll enable the filter, then we'll make it permanent.
```shell
sudo -s
modprobe br_netfilter
cat /etc/modules-load.d/br_netfilter.conf
# Only if cat does not output "br_netfilter", add it. Must not be defined twice.
echo "br_netfilter" >> /etc/modules-load.d/br_netfilter.conf
```
In order to immediatly apply the updated configuration, we can reload the configuration file.
```shell
sudo sysctl -p /etc/sysctl.d/10-disable-firewall-on-bridge.conf
```
Great! The bridge is now set up and will put guests on the same network as the host, given the bridge is passed through as the guest's NIC. Both the host and the guest should be able to connect to the network (and the internet) simultaneously and `ip a` should now reflect the changes made to `eth0` and `br0`.
```text
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host
       valid_lft forever preferred_lft forever
2: eth0: <BROADCAST,MULTICAST,PROMISC,UP,LOWER_UP> mtu 1500 qdisc fq_codel master br0 state UP group default qlen 1000
    link/ether 1c:1b:0d:ed:39:57 brd ff:ff:ff:ff:ff:ff
3: br0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
    link/ether 1c:1b:0d:ed:39:57 brd ff:ff:ff:ff:ff:ff
    inet 192.168.0.2/24 brd 192.168.0.255 scope global noprefixroute br0
       valid_lft forever preferred_lft forever
    inet6 fe80::1e1b:dff:feed:3957/64 scope link
       valid_lft forever preferred_lft forever
```

## Guest OS: macOS Catalina

To be added...

## Guest OS: Windows 10

To be added...

## Resources

- **[PCI passthrough via OVMF - ArchWiki](https://wiki.archlinux.org/index.php/PCI_passthrough_via_OVMF)**
<br>Very useful and detailed guide on how to set up OVMF, enable IOMMU and set up PCI passthrough.

- **[Why is my network interface named enp0s25 instead of eth0?](https://askubuntu.com/a/704364)**
<br>ELI5 answer explaining `systemd`'s Predictable Network Interface naming.

- **[QEMU-KVM Bridged Networking - TurluCode](https://turlucode.com/qemu-kvm-bridged-networking)**
<br>Guide on how to define a bridged network that can be passed to a KVM.
