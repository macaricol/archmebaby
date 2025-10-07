#!/bin/bash

# Interactive Arch Linux Installation Script
# This script automates the Arch Linux installation process, prompting the user for necessary inputs such as disk, partitions, hostname, root password, username, and user password.
# Run as root in the Arch Linux live ISO environment.

# Exit on any error
set -e

# Function to check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "This script must be run as root. Please use sudo or switch to root."
        exit 1
    fi
}

# Function to prompt for user input with validation
prompt_input() {
    local prompt="$1"
    local var_name="$2"
    local input
    read -p "$prompt: " input
    if [ -z "$input" ]; then
        echo "Input cannot be empty. Please try again."
        prompt_input "$prompt" "$var_name"
    else
        eval "$var_name='$input'"
    fi
}

# Function to prompt for password securely
prompt_password() {
    local prompt="$1"
    local var_name="$2"
    local pass1 pass2
    read -s -p "$prompt: " pass1
    echo
    read -s -p "Confirm $prompt: " pass2
    echo
    if [ "$pass1" != "$pass2" ]; then
        echo "Passwords do not match. Please try again."
        prompt_password "$prompt" "$var_name"
    elif [ -z "$pass1" ]; then
        echo "Password cannot be empty. Please try again."
        prompt_password "$prompt" "$var_name"
    else
        eval "$var_name='$pass1'"
    fi
}

# Function to validate partition device
validate_partition() {
    local partition="$1"
    local description="$2"
    if [ ! -b "$partition" ]; then
        echo "Invalid $description: $partition does not exist. Please check using 'fdisk -l' or 'lsblk'."
        exit 1
    fi
}

# Check if running as root
check_root

echo "Starting Arch Linux installation..."

# 1. Pre-Installation Setup

echo "Setting keyboard layout to Portuguese (pt-latin9)..."
loadkeys pt-latin9

echo "Verifying internet connection..."
if ping -c 5 archlinux.org > /dev/null 2>&1; then
    echo "Internet connection is active."
else
    echo "No internet connection. Please configure your network and try again."
    exit 1
fi

echo "Checking for UEFI mode..."
if [ -d /sys/firmware/efi ]; then
    fw_size=$(cat /sys/firmware/efi/fw_platform_size 2>/dev/null || echo "unknown")
    echo "UEFI mode detected (platform size: $fw_size bits)."
else
    echo "BIOS mode detected. This script assumes UEFI. Exiting."
    exit 1
fi

echo "Synchronizing system clock..."
timedatectl

# 2. Disk Partitioning

echo "Listing available disks..."
fdisk -l

prompt_input "Enter the disk to partition (e.g., /dev/sda)" disk
validate_partition "$disk" "disk"

echo "Launching cfdisk to create partitions (EFI: 512M, Swap: 4G, Root: remaining)..."
echo "Please create at least three partitions:"
echo "- EFI partition (~512M)"
echo "- Swap partition (~4G recommended)"
echo "- Root partition (remaining space)"
read -p "Press Enter to launch cfdisk..."
cfdisk "$disk"

echo "Listing partitions after cfdisk..."
lsblk "$disk"

prompt_input "Enter the EFI partition (e.g., /dev/sda1)" efi_partition
validate_partition "$efi_partition" "EFI partition"

prompt_input "Enter the swap partition (e.g., /dev/sda2)" swap_partition
validate_partition "$swap_partition" "swap partition"

prompt_input "Enter the root partition (e.g., /dev/sda3)" root_partition
validate_partition "$root_partition" "root partition"

echo "Formatting partitions..."
mkfs.fat -F 32 "$efi_partition"
mkswap "$swap_partition"
mkfs.btrfs "$root_partition"

# 3. Mount Filesystems

echo "Mounting root partition..."
mount "$root_partition" /mnt

echo "Creating Btrfs subvolumes (@ and @home)..."
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home

echo "Remounting subvolumes..."
umount /mnt
mount -o subvol=@ "$root_partition" /
