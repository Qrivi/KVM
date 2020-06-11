# KVM

> Kristof's Vigorous Machine

## Intro

Recently I switched from a Windows and macOS (Hackintosh) dual boot on my main system to a Linux install so I could use its type-1 (bare-metal) hypervisor to run the two aforementioned OS as kernel-based virtual machines (KVMs). The main benefit of this setup is the ability to pause one OS and switch to the other, rather than having to reboot, while the drop in overall performance is negligible thanks to hardware passthrough. Having the OS and boot files on a virtual disk that I can take snapshots of (e.g. prior to a system update) sounds really nice too.

I set up this repo to remind my future self of the steps I took to get everything working and have versioning of important configuration files. Special thanks to all my past selves to keep this up-to-date.

## Hardware Configuration

My current build ~~to flex~~ as a reference, as some of the configuration is specific to my build.

| Hardware    | Brand                                                                                                             | Purchase date |
|-------------|-------------------------------------------------------------------------------------------------------------------|---------------|
| Motherboard | Gigabyte GA-Z270-HD3P Intel Z270 LGA 1151 (ATX, Socket H4)                                                        | Oct 2017      |
| CPU         | Intel Core i7 7700 Kaby Lake (8MB, 3.60/4.20 GHz)                                                                 | Oct 2017      |
| RAM         | 4x Crucial 8GB DDR4-2400                                                                                          | Oct 2017      |
| GPU         | 1x Asus Expedition AMD Radeon RX 570 OC 4GB GDDR5<br>1x Asus ROG Strix Nvidia GeForce RTX 2070 SUPER OC 8GB GDDR6 | Oct 2018<br>June 2020|
| NIC         | Apple Broadcom BCM94360CD (802.11 a/b/g/n/ac, Bluetooth 4.0)                                                      | Oct 2017      |
| PSU         | NZXT C750 80+ Gold 750W                                                                                           | June 2020     |
| Storage     | 1x 1TB WD SSD (SATA)<br>1x 1TB WD HDD (SATA)<br>1x 250GB Crucial SSD (SATA)<br>1x 250GB Kingston SSD (SATA)       | June 2020<br>Oct 2017<br>Oct 2017<br>Jan 2019 |
| Peripherals | 1x cheap USB webcam and microphone<br>1x cheap USB mouse<br>1x cheap USB keyboard                                 | Oct 2017<br>Oct 2017<br>Oct 2017 |

### Important Notes

- You will need a CPU that supports virtualization and have VT-d and VT-x (Intel) or AMD-Vi (AMD) enabled in the BIOS.
- If you plan on passing through your only GPU, you will need a CPU with integrated graphics enabled in the BIOS.

## Host OS: Manjaro Linux

Went with Manjaro so I could have a lightweight Arch based Linux distro as the host OS without having too much trouble setting everything up — Manjaro's installation process is very intuitive and straight-forward. However, any recent Linux distro should work though some commands might be different if it is not Arch based. A Red Hat distro like CentOS or Fedora is worth considering as KVM is a Red Hat technology.

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

### Set up a network bridge

WIP




## Resources

- **[PCI passthrough via OVMF - ArchWiki](https://wiki.archlinux.org/index.php/PCI_passthrough_via_OVMF)**
<br>Very useful and detailed guide on how to set up OVMF, enable IOMMU and set up PCI passthrough.
