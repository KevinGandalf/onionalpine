#!/bin/sh
# Assemble a hybrid BIOS+UEFI ISO. Run after filesystem.squashfs exists.
set -eu
SDK=/workspace/iso-build/sdk
ROOT=/workspace/iso-build/rootfs
OUT=/workspace/iso-build/out
ISO=$OUT/iso-root
SRC=/workspace/iso-build/src

rm -rf "$ISO"
mkdir -p "$ISO/boot/grub" "$ISO/boot/syslinux" "$ISO/efi/boot" "$ISO/live"

cp -a "$ROOT/boot/vmlinuz-lts" "$ISO/boot/vmlinuz-lts"
cp -a "$OUT/initramfs-lts" "$ISO/boot/initramfs-lts"
mv "$OUT/filesystem.squashfs" "$ISO/live/filesystem.squashfs"
cp "$SRC/Liesmich.txt" "$ISO/README.txt"

mkdir -p "$SDK/mnt/iso" "$SDK/mnt/out"
mountpoint -q "$SDK/mnt/out" || mount --bind "$OUT" "$SDK/mnt/out"
if mountpoint -q "$SDK/mnt/iso"; then
	umount "$SDK/mnt/iso"
fi
mount --bind "$ISO" "$SDK/mnt/iso"

cat > "$ISO/boot/grub/grub.cfg" << 'EOF'
set timeout=3
set default=0
menuentry "Alpine XFCE + Tor (Live)" {
    linux /boot/vmlinuz-lts quiet ipv6.disable=1
    initrd /boot/initramfs-lts
}
EOF

cat > "$ISO/boot/syslinux/syslinux.cfg" << 'EOF'
DEFAULT lts
TIMEOUT 30
PROMPT 0
LABEL lts
  KERNEL /boot/vmlinuz-lts
  INITRD /boot/initramfs-lts
  APPEND quiet ipv6.disable=1
EOF

for f in isolinux.bin ldlinux.c32 libutil.c32 libcom32.c32; do
	cp "$SDK/usr/share/syslinux/$f" "$ISO/boot/syslinux/$f"
done

# GRUB EFI image
EARLY=$OUT/grub-early.cfg
cat > "$EARLY" << 'EOF'
search --no-floppy --set=root --label ALPINE_XFCE_TOR
set prefix=($root)/boot/grub
EOF

MODDIR="$SDK/usr/lib/grub/x86_64-efi"
MODS="all_video disk part_gpt part_msdos linux normal configfile search search_label efi_gop fat iso9660 cat echo ls test true help gzio multiboot2 efi_uga"
chroot "$SDK" grub-mkimage \
	--config=/mnt/out/grub-early.cfg \
	--directory=/usr/lib/grub/x86_64-efi \
	--prefix=/boot/grub \
	--output=/mnt/out/bootx64.efi \
	--format=x86_64-efi \
	--compression=xz \
	$MODS
cp "$OUT/bootx64.efi" "$ISO/efi/boot/bootx64.efi"
ls -lh "$ISO/efi/boot/bootx64.efi"

# FAT image large enough for the EFI binary
SIZE=$(stat -c%s "$ISO/efi/boot/bootx64.efi")
# 4 MiB FAT12/16 is plenty and still El Torito friendly
dd if=/dev/zero of="$ISO/boot/grub/efi.img" bs=1M count=4 status=none
# mformat geometry for 4MiB: 4*1024*1024/512 = 8192 sectors
chroot "$SDK" mformat -i /mnt/iso/boot/grub/efi.img -h 64 -t 32 -s 4 -c 1 -v EFI ::
chroot "$SDK" mmd -i /mnt/iso/boot/grub/efi.img ::/EFI ::/EFI/BOOT
chroot "$SDK" mcopy -i /mnt/iso/boot/grub/efi.img /mnt/iso/efi/boot/bootx64.efi ::/EFI/BOOT/BOOTX64.EFI

FINAL=$OUT/alpine-xfce-tor-3.24.2-x86_64.iso
chroot "$SDK" xorrisofs \
	-output /mnt/out/alpine-xfce-tor-3.24.2-x86_64.iso \
	-full-iso9660-filenames \
	-joliet \
	-rational-rock \
	-sysid LINUX \
	-volid ALPINE_XFCE_TOR \
	-isohybrid-mbr /usr/share/syslinux/isohdpfx.bin \
	-eltorito-boot boot/syslinux/isolinux.bin \
	-eltorito-catalog boot/syslinux/boot.cat \
	-no-emul-boot -boot-load-size 4 -boot-info-table \
	-eltorito-alt-boot \
	-e boot/grub/efi.img \
	-no-emul-boot \
	-isohybrid-gpt-basdat \
	/mnt/iso

echo ISO_DONE
ls -lh "$FINAL"
