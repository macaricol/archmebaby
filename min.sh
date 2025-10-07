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
mount -o subvol=@ "$root_partition" /mnt
mkdir -p /mnt/home
mount -o subvol=@home "$root_partition" /mnt/home

echo "Mounting EFI partition..."
mount --mkdir "$efi_partition" /mnt/boot

echo "Enabling swap..."
swapon "$swap_partition"

# 4. Install Base System

echo "Installing base system packages..."
pacstrap -K /mnt base linux linux-firmware grub efibootmgr nano networkmanager sudo

# 5. Configure Filesystem Table (fstab)

echo "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

echo "Displaying fstab for verification..."
cat /mnt/etc/fstab
read -p "Please verify the fstab output. Press Enter to continue..."

# 6. Chroot into the New System

echo "Entering chroot environment..."

# Create a temporary script for chroot commands to handle interactive prompts
cat > /mnt/tmp/chroot-script.sh << 'CHROOT_EOF'
#!/bin/bash
set -e

# Function to prompt for input (redefined for chroot)
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

# Function to prompt for password (redefined for chroot)
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

echo "Setting time zone to Europe/Lisbon..."
ln -sf /usr/share/zoneinfo/Europe/Lisbon /etc/localtime
hwclock --systohc

echo "Configuring locale..."
echo "Please uncomment desired locales (e.g., pt_PT.UTF-8, en_US.UTF-8) in /etc/locale.gen."
read -p "Press Enter to open nano..."
nano /etc/locale.gen
locale-gen

echo "Creating /etc/locale.conf..."
echo "LANG=pt_PT.UTF-8" > /etc/locale.conf
echo "LC_MESSAGES=en_US.UTF-8" >> /etc/locale.conf

echo "Setting console keyboard layout..."
echo "KEYMAP=pt-latin9" > /etc/vconsole.conf

echo "Setting hostname..."
prompt_input "Enter the hostname (e.g., omega)" hostname
echo "$hostname" > /etc/hostname

echo "Setting root password..."
prompt_password "Enter root password" root_password
echo "root:$root_password" | chpasswd

echo "Creating user..."
prompt_input "Enter the username (e.g., ishmael)" username
prompt_password "Enter password for $username" user_password
useradd -m -G wheel -s /bin/bash "$username"
echo "$username:$user_password" | chpasswd

echo "Configuring sudo privileges for wheel group..."
echo "Please uncomment the line '%wheel ALL=(ALL:ALL) ALL' in the sudoers file."
read -p "Press Enter to open visudo..."
EDITOR=nano visudo

echo "Enabling NetworkManager..."
systemctl enable NetworkManager

echo "Installing GRUB for UEFI..."
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
CHROOT_EOF

# Make the chroot script executable
chmod +x /mnt/tmp/chroot-script.sh

# Run the chroot script interactively
arch-chroot /mnt /bin/bash /tmp/chroot-script.sh

# Clean up the temporary script
rm /mnt/tmp/chroot-script.sh

# 9. Exit and Unmount

echo "Unmounting filesystems..."
umount -R /mnt

echo "Rebooting system..."
read -p "Please remove the installation media after shutdown. Press Enter to reboot..."
reboot
