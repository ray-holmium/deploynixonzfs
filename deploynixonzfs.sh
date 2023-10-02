#!/bin/bash

set +u
# set -x

## Select disk ##

echo "Please select a disk to install NixOS on."

echo "WARNING: The disk will be wiped and any existing data will be lost if not backed up: "

# Get a list of all disk ids
mapfile -t disk_ids < <(ls /dev/disk/by-id/ | grep -E '^(ata|nvme|scsi|usb|wwn)-')

# Resolve each id to its device node name and map them to an associative array
declare -A disk_map
for id in "${disk_ids[@]}"; do
    disk=$(readlink -f "/dev/disk/by-id/$id")
    disk_map["$disk"]=$id
done

# Get a list of all device node names
disks=("${!disk_map[@]}")
select disk in "${disks[@]}"; do
    if [ -n "$disk" ]; then
        DISK="$disk"
        DISK_ID="/dev/disk/by-id/${disk_map[$disk]}"
        echo "Selected DISK: $DISK"
        echo "Selected DISK_ID: $DISK_ID"
        echo "Making initial preparations..."
        break
    else
        echo "Invalid selection"
    fi
done

## Error handler ##

# need to call second script to handle errors and cleanup
# because /mnt cannot unmount until this script closes

cleanup() {
    rm -rf ~/.config/nix || true
    swapoff /dev/mapper/swap_encrypted || true
    cryptsetup close swap_encrypted || true
    umount /mnt/vault || true
    umount /mnt/home || true
    umount /mnt/keys || true
    umount /mnt/nix || true
    umount /mnt/boot || true
    umount /mnt/bios || true
    umount /mnt/efi || true
    umount -f /mnt || true
    zpool export bpool || true
    zpool export rpool || true
}

wipe_disk() {
    # blkdiscard -f "${DISK}" || true
    wipefs --all --force "${DISK}"
    dd if=/dev/zero of="${DISK}" bs=1M count=10
}

handle_error() {
    local exit_code=$?
    while true; do
        read -rp "Would you like to wipe the disk now? [y/n]:" wipe_choice
        case "$wipe_choice" in
        [Yy]*)
            echo "WARNING: All data on disk $DISK will be destroyed."
            read -rp "Are you sure you want to proceed? [y/n]:" confirm_wipe
            case "$confirm_wipe" in
            [Yy]*)
                echo "Wiping disk... "
                cleanup
                wipe_disk
                break
                ;;
            [Nn]*)
                echo "Disk not wiped. WARNING: It's unsafe to leave the disk in a partial state. "
                continue
                ;;
            *) echo "Please answer yes or no." ;;
            esac
            ;;
        [Nn]*)
            echo "WARNING: It's unsafe to leave the disk in a partial state."
            read -rp "Are you sure you want to proceed without wiping the disk? [y/n]" confirm_skip
            case "$confirm_skip" in
            [Yy]*)
                echo "Skipping disk wipe..."
                echo "Unmounting partitions..."
                cleanup
                break
                ;;
            [Nn]*)
                echo "Returning to original disk wipe prompt..."
                continue
                ;;
            *)
                echo "Please answer yes or no."
                ;;
            esac
            ;;
        *)
            echo "Please answer yes or no."
            ;;
        esac
    done
    exit "$exit_code"
}

trap 'handle_error $LINENO' ERR

handle_sigint() {
    echo "Script interrupted by user. NixOS not installed. WARNING: Disk is in a partial state and needs to be wiped before further use. "

    while true; do
        read -rp "Would you like to wipe the disk now? [y/n]:" wipe_choice
        case "$wipe_choice" in
        [Yy]*)
            echo "WARNING: All data on disk $DISK will be destroyed."
            read -rp "Are you sure you want to proceed? [y/n]:" confirm_wipe
            case "$confirm_wipe" in
            [Yy]*)
                echo "Wiping disk..."
                cleanup
                wipe_disk
                break
                ;;
            [Nn]*)
                echo "Disk not wiped. WARNING: it is not safe to leave the disk in a partial state."
                continue
                ;;
            *) echo "Please answer yes or no." ;;
            esac
            ;;
        [Nn]*)
            echo "WARNING: it is not safe to leave the disk in a partial state."
            read -rp "Are you sure you want to proceed without wiping the disk? [y/n]" confirm_skip
            case "$confirm_skip" in
            [Yy]*)
                echo "Skipping disk wipe..."
                echo "Unmounting partitions..."
                cleanup
                break
                ;;
            [Nn]*)
                echo "Returning to original disk wipe prompt..."
                continue
                ;;
            *)
                echo "Please answer yes or no."
                ;;
            esac
            ;;
        *)
            echo "Please answer yes or no."
            ;;
        esac
    done

    exit 130
}

trap handle_sigint SIGINT

set -e
set -o pipefail

## Internet check ##

echo "This installer requires an internet connection. Checking connectivity now..."

ping -c 1 1.1.1.1 >/dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "Internet connectivity is available."
else
    echo "No Internet connectivity. Exiting."
    exit 1
fi

## Prepare USB ##

echo "Preparing NixOS default USB for custom install..."

mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" >>~/.config/nix/nix.conf

declare -A cmds_packages
cmds_packages=(
    ["git"]="git"
    ["gh"]="github-cli"
    ["jq"]="jq"
    ["partprobe"]="parted"
    ["lsblk"]="lsblk"
    ["free"]="free"
)

for cmd in "${!cmds_packages[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        nix-env -f '<nixpkgs>' -iA "${cmds_packages[$cmd]}"
    fi
done

## Disk/partitions ##

SYSTEM_MEMORY="$(free --mega | awk '/^Mem:/ {print $2}')"
echo "Detected system memory: $SYSTEM_MEMORY MiB"

EFI_SIZE="1024"
BIOS_SIZE="512"
BOOT_SIZE="1024"
SWAP_SIZE=$((SYSTEM_MEMORY + 2048))
EFI_START="1MiB"
EFI_END="${EFI_SIZE}MiB"
BIOS_START="${EFI_END}"
BIOS_END="$((BIOS_SIZE + EFI_SIZE))MiB"
BOOT_START="${BIOS_END}"
BOOT_END="$((BOOT_SIZE + BIOS_SIZE + EFI_SIZE))MiB"
SWAP_START="${BOOT_END}"
SWAP_END="$((SWAP_SIZE + BOOT_SIZE + BIOS_SIZE + EFI_SIZE))MiB"
RPOOL_START="${SWAP_END}"
RPOOL_END="204800 MiB"

echo "Partitioning disk ..."

check_alignment() {
    local disk="$1"
    local part_num="$2"
    if ! parted "$disk" align-check optimal "$part_num"; then
        echo "Partition $part_num on $disk is not optimally aligned."
        exit 1
    fi
}

partition_disk() {
    local disk="${1}"

    cleanup
    wipe_disk

    parted --script --align=optimal "${disk}" -- \
        mklabel gpt \
        mkpart EFI fat32 ${EFI_START} ${EFI_END} \
        mkpart BIOS ${BIOS_START} ${BIOS_END} \
        mkpart boot ${BOOT_START} ${BOOT_END} \
        mkpart swap linux-swap ${SWAP_START} ${SWAP_END} \
        mkpart rpool ${RPOOL_START} ${RPOOL_END} \
        set 1 esp on \
        set 2 bios_grub on \
        set 2 legacy_boot on 

    for i in {1..5}; do
        check_alignment "${disk}" "$i"
    done

    partprobe "${disk}"
    udevadm settle
}

partition_disk "${DISK}"

## ZFS ##

echo "Creating zpools ..."

zpool create -f -o compatibility=grub2 \
    -o ashift=12 \
    -o autotrim=on \
    -O acltype=posixacl \
    -O canmount=off \
    -O devices=off \
    -O normalization=formD \
    -O relatime=on \
    -O xattr=sa \
    -O mountpoint=none \
    -R "/mnt" \
    bpool \
    "${DISK_ID}"-part3

zpool create -f -o ashift=12 \
    -o autotrim=on \
    -R "/mnt" \
    -O acltype=posixacl \
    -O canmount=off \
    -O dnodesize=auto \
    -O normalization=formD \
    -O relatime=on \
    -O xattr=sa \
    -O mountpoint=none \
    rpool \
    "${DISK_ID}"-part5

echo "Creating encrypted root dataset. Please enter a system encryption passphrase: "


while true; do
    zfs create -o encryption=on \
        -o keyformat=passphrase \
        -o keylocation=prompt \
        -o mountpoint=none \
        -o canmount=off \
        rpool/nixos || true

    if [ $? -eq 0 ]; then
        echo "ZFS dataset created successfully."
        break
    else
        echo "Provided passwords do not match. Please try again."
    fi
done

echo "Preparing additional datasets..."

snapshot_dataset() {
    local dataset="$1"
    local snapshot_name="$2"
    zfs snapshot "${dataset}@${snapshot_name}"
}

zfs create -o mountpoint=legacy rpool/nixos/root
snapshot_dataset "rpool/nixos/root" "pre_install"
mount -t zfs rpool/nixos/root /mnt

mkdir /mnt/nix
zfs create -o mountpoint=legacy rpool/nixos/nix
snapshot_dataset "rpool/nixos/nix" "pre_install"
mount -t zfs rpool/nixos/nix /mnt/nix

mkdir /mnt/keys
zfs create -o mountpoint=legacy rpool/nixos/keys
snapshot_dataset "rpool/nixos/keys" "pre_install"
mount -t zfs rpool/nixos/keys /mnt/keys

mkdir /mnt/home
zfs create -o mountpoint=legacy rpool/nixos/home
snapshot_dataset "rpool/nixos/home" "pre_install"
mount -t zfs rpool/nixos/home /mnt/home

mkdir /mnt/boot
zfs create -o mountpoint=legacy bpool/boot
snapshot_dataset "bpool/boot" "pre_install"
mount -t zfs bpool/boot /mnt/boot

mkdir /mnt/efi
mkfs.vfat -n EFI "${DISK}"p1
mount -t vfat -o iocharset=iso8859-1 "${DISK}"p1 /mnt/efi

mkdir /mnt/bios
mkfs.fat -F 32 "${DISK}"p2
mount "${DISK}"p2 /mnt/bios

generate_passphrase() {
    head -c 1000 /dev/urandom | tr -dc 'a-zA-Z0-9!@#$%^&*()_+=-' | head -c 64
}

mkdir /keys || true

create_encrypted_dataset() {
    local dataset=$1
    local dataset_name
    dataset_name="$(basename "$dataset")"
    local passphrase
    passphrase=$(generate_passphrase)
    local keyfile="/keys/${dataset_name}.key"
    echo "${passphrase}" >"${keyfile}"
    chmod 0400 "${keyfile}"
    zfs create -o encryption=on -o keyformat=passphrase -o keylocation=file://"${keyfile}" -o mountpoint=legacy "${dataset}"

    passphrase_info+="${dataset}: ${passphrase}\n"
}

# currently the vault dataset does not unlock properly on boot after install
# this is possibly because the keyfile is not being copied to the initramfs
# or is otherwise not available at boot time. This needs to be investigated.

mkdir /mnt/vault
create_encrypted_dataset "rpool/vault"
snapshot_dataset "rpool/vault" "pre_install"
mount -t zfs rpool/vault /mnt/vault

rsync -av --info=all2 /keys/* /mnt/keys

echo "Enabling encrypted swap..."

cryptsetup open --type plain --key-file /dev/random "${DISK_ID}"-part4 swap_encrypted
mkswap /dev/mapper/swap_encrypted
swapon /dev/mapper/swap_encrypted

#### Install NixOS ####
# script could be split here

## git/Hub authentication ##

gh_auth() {
    while true; do
        if gh auth status 2>/dev/null; then
            echo "You're already authenticated with GitHub. Onward and upward! "
            break
        fi

        echo "Please enter your GitHub credentials."

        if gh auth login; then
            echo "Successfully authenticated with GitHub."
            break
        else
            read -rp "GitHub authentication failed. Would you like to try again? [y/n] " retry_choice
            if [[ ! "$retry_choice" =~ ^[Yy] ]]; then
                echo "Exiting GitHub authentication."
                return 1
            fi
        fi
    done
}

git_random_branch() {
    random_string="$(date +%s%N | sha256sum | head -c 8)"
    branch_name="br-$random_string"
}

read -rp "This installer requires git credentials to function. Would you like to enter yours now? [y/n] " credential_choice
if [[ "$credential_choice" =~ ^[Yy] ]]; then
    #the line below is bugged. I thought it froze but then it poppoed to life when I pressed enter.
    if git credential reject || [[ ! $(git config --get user.email) ]]; then
        read -rp "Enter your email: " git_email
        read -rp "Enter your name: " git_name
        git config --global user.email "$git_email"
        git config --global user.name "$git_name"

        read -rp "Would you like to cache these credentials (1 hour)? [Y/n] " cache_choice
        if [[ "$cache_choice" =~ [Yy] ]]; then
            git config --global credential.helper 'cache --timeout=3600'
        fi
    else
        echo "Git credentials are already cached. Onward and upward!"
    fi
else
    echo "This installer requires git credentials to function."
    exit 1
fi

read -rp "Would you like to log in to GitHub? (optional) [y/n] " gh_choice
if [[ "$gh_choice" =~ ^[Yy] ]]; then
    gh_auth
else
    echo "Skipping GitHub authentication... Onward and upward!"
fi

echo "Cloning into custom NixOS repository, copying new system config to disk... "

mkdir -p /mnt/etc

git clone --branch deploy \
    https://github.com/ray-holmium/deploynixonzfs /mnt/etc/nixos

cd /mnt/etc/nixos

if [[ "$gh_choice" =~ ^[Yy] ]]; then
    read -rp "Would you like create & sync this project with a new GitHub repo? [y/n] " gh_newrepo
    if [[ "$gh_newrepo" =~ ^[Yy] ]]; then
        git remote remove origin
        read -rp "Please enter a name for your new repo: " gh_repo_name
        gh_repo_url="$(gh repo create $gh_repo_name --private --confirm)"
        git remote add origin "$gh_repo_url"
        git branch -m main
        git add .
        git commit -asm "initial commit"
        git push -U main
        echo "New repository created. Onward and upward!"
    else
        echo "Using existing repository... "
        git_random_branch
        git checkout -b "$branch_name"
        git add .
        git commit -asm "initial commit" || true
    fi
else
    echo "Using local-only git repository..."
    git remote remove origin
    git branch -m main
fi

## System setup ##

#set hostname
read -rp "Please enter a hostname for this system: " HOSTNAME

#set username
read -rp "Please enter a username: " USERNAME

#apply chosen hostname
cp -r /mnt/etc/nixos/hosts/exampleHost /mnt/etc/nixos/hosts/"${HOSTNAME}"
sed -i "s|"exampleHost"|"${HOSTNAME}"|g" /mnt/etc/nixos/hosts/"${HOSTNAME}"/default.nix
sed -i "s|"exampleHost"|"${HOSTNAME}"|g" /mnt/etc/nixos/flake.nix

#apply chosen username
cp /mnt/etc/nixos/system-modules/users/exampleUser.nix /mnt/etc/nixos/system-modules/users/"${USERNAME}".nix
sed -i "s|"exampleUser"|"${USERNAME}"|g" /mnt/etc/nixos/flake.nix
sed -i "s|"exampleUser"|"${USERNAME}"|g" /mnt/etc/nixos/hosts/"${HOSTNAME}"/default.nix
sed -i "s|"exampleUser"|"${USERNAME}"|g" /mnt/etc/nixos/system-modules/users/default.nix
sed -i "s|"exampleUser"|"${USERNAME}"|g" /mnt/etc/nixos/system-modules/users/"${USERNAME}".nix
sed -i "s|"exampleUser@exampleHost"|"${USERNAME}@${HOSTNAME}"|g" /mnt/etc/nixos/flake.nix

#set user password

echo "Please enter a password for the user account."
userPwd=$(mkpasswd -m SHA-512)
sed -i \
    "s|userHash_placeholder|${userPwd}|" \
    /mnt/etc/nixos/system-modules/users/"${USERNAME}".nix

## Set local hardware requirements ##

echo "Importing local hardware requirements into new NixOS configuration ..."

#set boot devices
diskName="\"${DISK_ID##*/}-part1\""
sed -i "s|\"bootDevices_placeholder\"|${diskName}|g" /mnt/etc/nixos/hosts/"${HOSTNAME}"/default.nix

#set hostid
sed -i "s|\"abcd1234\"|\"$(head -c4 /dev/urandom | od -A none -t x4 | sed 's| ||g' || true)\"|g" /mnt/etc/nixos/hosts/"${HOSTNAME}"/default.nix

sed -i "s|\"x86_64-linux\"|\"$(uname -m || true)-linux\"|g" /mnt/etc/nixos/flake.nix

cp "$(command -v nixos-generate-config || true)" ./nixos-generate-config
chmod a+rw ./nixos-generate-config

echo 'print STDOUT "$initrdAvailableKernelModules"' >>./nixos-generate-config

kernelModules="$(./nixos-generate-config --show-hardware-config --no-filesystems | tail -n1 || true)"
sed -i "s|\"kernelModules_placeholder\"|${kernelModules}|g" /mnt/etc/nixos/hosts/"${HOSTNAME}"/default.nix

sed -i '$a fileSystems."/mnt" = {\n  device = "rpool";\n  fsType = "zfs";\n};' /etc/nixos/configuration.nix

echo "Updating NixOS flake.lock file to apply configuration changes to track latest system version ..."

## Commit and push hardware changes ##

if [[ "$gh_choice" =~ ^[Yy] ]]; then
    if [[ "$gh_newrepo" =~ ^[Yy] ]]; then
        git add .
        git commit -asm "set local hardware"
        git push -u origin main
    else
        echo "Using existing repository..."
        git add .
        git commit -asm "set local hardware"
        git push -u origin "$branch_name"
    fi
else
    echo "Using local-only git repository..."
    git add .
    git commit -asm "set local hardware"
fi

nix flake update --extra-experimental-features nix-command --extra-experimental-features flakes --commit-lock-file \
    "git+file:///mnt/etc/nixos"

## Final installation of configured system ##

echo "Finalizing installation and applying configuration..."

nixos-install \
    --root /mnt \
    --no-root-passwd \
    --flake "git+file:///mnt/etc/nixos#${HOSTNAME}"

echo "Success! Installation complete"

## Epilogue ##

# WARNING: this function does not correctly unmount /mnt
# or export zpools. This is because the script is still running.

read -rp "Would you like to reboot now? (y/n) " response
echo

if [[ $response =~ ^[Yy]$ ]]; then
    cleanup
    reboot
fi
