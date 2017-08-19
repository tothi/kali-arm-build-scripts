#!/bin/bash

# This is the Raspberry Pi3 Kali ARM build script - https://www.kali.org/downloads
# A trusted Kali Linux image created by Offensive Security - https://www.offensive-security.com
# With nexmon for native monitor mode: https://github.com/seemoo-lab/nexmon/
# Possibly needs: apt-get install gcc-multilib
# patched to build on other distros than Kali (e.g. tested on Gentoo)
# Maintained by @binkybear

if [[ $# -eq 0 ]] ; then
    echo "Please pass version number, e.g. $0 2.0"
    exit 0
fi

basedir=`pwd`/rpi3-nexmon-bh-$1
TOPDIR=`pwd`

# Package installations for various sections.
# This will build a minimal XFCE Kali system with the top 10 tools.
# This is the section to edit if you would like to add more packages.
# See https://www.kali.org/new/kali-linux-metapackages/ for meta packages you can
# use. You can also install packages, using just the package name, but keep in
# mind that not all packages work on ARM! If you specify one of those, the
# script will throw an error, but will still continue on, and create an unusable
# image, keep that in mind.

arm="abootimg cgpt fake-hwclock ntpdate u-boot-tools vboot-utils vboot-kernel-utils"
base="e2fsprogs initramfs-tools kali-defaults kali-menu parted sudo usbutils firmware-linux firmware-linux-nonfree firmware-libertas net-tools"
desktop="fonts-croscore fonts-crosextra-caladea fonts-crosextra-carlito gnome-theme-kali gtk3-engines-xfce kali-desktop-xfce kali-root-login lightdm network-manager network-manager-gnome xfce4 xserver-xorg-video-fbdev xserver-xorg-input-evdev xserver-xorg-input-synaptics"
tools="aircrack-ng ethtool hydra john libnfc-bin mfoc nmap passing-the-hash sqlmap usbutils winexe wireshark net-tools"
services="apache2 openssh-server"
extras="iceweasel xfce4-terminal wpasupplicant python-smbus i2c-tools python-requests python-configobj python-pip"
# kernel sauces take up space yo.
size=7000 # Size of image in megabytes

packages="${arm} ${base} ${desktop} ${tools} ${services} ${extras}"
architecture="armhf"
# If you have your own preferred mirrors, set them here.
# After generating the rootfs, we set the sources.list to the default settings.
mirror=http.kali.org

# Set this to use an http proxy, like apt-cacher-ng, and uncomment further down
# to unset it.
#export http_proxy="http://localhost:3142/"

mkdir -p ${basedir}
cd ${basedir}

# fetch the latest kali-rollig debootstrap script
# (in order to work with other distros than kali)
curl -s 'http://git.kali.org/gitweb/?p=packages/debootstrap.git;a=blob_plain;f=scripts/kali;hb=refs/heads/kali/master' > kali-debootstrap

# create the rootfs - not much to modify here, except maybe the hostname.
#debootstrap --foreign --arch $architecture kali-rolling kali-$architecture http://$mirror/kali

# use the downloaded kali-debootstrap script
debootstrap --foreign --arch $architecture kali-rolling kali-$architecture http://$mirror/kali ./kali-debootstrap
rm -f ./kali-debootstrap

# check for /usr/local/bin too, and register binfmt arm (if not registered)
cp /usr/bin/qemu-arm* kali-$architecture/usr/bin/ || \
    ( mkdir -p kali-$architecture/usr/local/bin ; \
      cp /usr/local/bin/qemu-arm-static kali-$architecture/usr/local/bin/ ; \
      [ -f /proc/sys/fs/binfmt_misc/arm ] ||\
	  echo ':arm:M::\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x28\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/local/bin/qemu-arm-static:' > /proc/sys/fs/binfmt_misc/register
    )

LANG=C chroot kali-$architecture /debootstrap/debootstrap --second-stage
cat << EOF > kali-$architecture/etc/apt/sources.list
deb http://$mirror/kali kali-rolling main contrib non-free
EOF

# Set hostname
echo "kali" > kali-$architecture/etc/hostname

# So X doesn't complain, we add kali to hosts
cat << EOF > kali-$architecture/etc/hosts
127.0.0.1       kali    localhost
::1             localhost ip6-localhost ip6-loopback
fe00::0         ip6-localnet
ff00::0         ip6-mcastprefix
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters
EOF

cat << EOF > kali-$architecture/etc/network/interfaces
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF

cat << EOF > kali-$architecture/etc/resolv.conf
nameserver 8.8.8.8
EOF

cat << EOF > kali-$architecture/lib/systemd/system/regenerate_ssh_host_keys.service
#
[Unit]
Description=Regenerate SSH host keys

[Service]
Type=oneshot
ExecStartPre=/bin/sh -c "if [ -e /dev/hwrng ]; then dd if=/dev/hwrng of=/dev/urandom count=1 bs=4096; fi"
ExecStart=/usr/bin/ssh-keygen -A
ExecStartPost=/bin/rm /lib/systemd/system/regenerate_ssh_host_keys.service ; /usr/sbin/update-rc.d regenerate_ssh_host_keys remove; /etc/init.d/ssh restart

[Install]
WantedBy=multi-user.target
EOF
chmod 755 kali-$architecture/lib/systemd/system/regenerate_ssh_host_keys.service

export MALLOC_CHECK_=0 # workaround for LP: #520465
export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive

mount -t proc proc kali-$architecture/proc
mount -o bind /dev/ kali-$architecture/dev/
mount -o bind /dev/pts kali-$architecture/dev/pts

cat << EOF > kali-$architecture/debconf.set
console-common console-data/keymap/policy select Select keymap from full list
console-common console-data/keymap/full select en-latin1-nodeadkeys
EOF

# Create monitor mode start/remove
cat << EOF > kali-$architecture/usr/bin/monstart
#!/bin/bash
echo "Nexutil setting monitoring mode"
/usr/bin/nexutil -m2
EOF
chmod +x kali-$architecture/usr/bin/monstart

cat << EOF > kali-$architecture/usr/bin/monstop
#!/bin/bash
/usr/bin/nexutil -m0
echo "Monitor mode stopped"
EOF
chmod +x kali-$architecture/usr/bin/monstop

cat << EOF > kali-$architecture/third-stage
#!/bin/bash
dpkg-divert --add --local --divert /usr/sbin/invoke-rc.d.chroot --rename /usr/sbin/invoke-rc.d
cp /bin/true /usr/sbin/invoke-rc.d
echo -e "#!/bin/sh\nexit 101" > /usr/sbin/policy-rc.d
chmod +x /usr/sbin/policy-rc.d

apt-get update
apt-get --yes --force-yes install locales-all

debconf-set-selections /debconf.set
rm -f /debconf.set
apt-get update
apt-get -y install git-core binutils ca-certificates initramfs-tools u-boot-tools
apt-get -y install locales console-common less nano git
echo "root:toor" | chpasswd
sed -i -e 's/KERNEL\!=\"eth\*|/KERNEL\!=\"/' /lib/udev/rules.d/75-persistent-net-generator.rules
rm -f /etc/udev/rules.d/70-persistent-net.rules
export DEBIAN_FRONTEND=noninteractive
apt-get --yes --force-yes install $packages
apt-get --yes --force-yes dist-upgrade
apt-get --yes --force-yes autoremove

# Because copying in authorized_keys is hard for people to do, let's make the
# image insecure and enable root login with a password.

# libinput seems to fail hard on RaspberryPi devices, so we make sure it's not
# installed here (and we have xserver-xorg-input-evdev and
# xserver-xorg-input-synaptics packages installed above!)
apt-get --yes --force-yes purge xserver-xorg-input-libinput

echo "Making the image insecure"
rm -f /etc/ssh/ssh_host_*_key*
sed -i -e 's/^#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

# Generate SSH host keys on first run
systemctl enable regenerate_ssh_host_keys

update-rc.d ssh enable

cp  /etc/bash.bashrc /root/.bashrc

# Fix startup time from 5 minutes to 15 secs on raise interface wlan0
sed -i 's/^TimeoutStartSec=5min/TimeoutStartSec=15/g' "/lib/systemd/system/networking.service"

rm -f /usr/sbin/policy-rc.d
rm -f /usr/sbin/invoke-rc.d
dpkg-divert --remove --rename /usr/sbin/invoke-rc.d

rm -f /third-stage
EOF

chmod +x kali-$architecture/third-stage
LANG=C chroot kali-$architecture /third-stage

cat << EOF > kali-$architecture/cleanup
#!/bin/bash
rm -rf /root/.bash_history
apt-get update
apt-get clean
rm -f /0
rm -f /hs_err*
rm -f cleanup
rm -f /usr/bin/qemu*
EOF

chmod +x kali-$architecture/cleanup
LANG=C chroot kali-$architecture /cleanup

umount kali-$architecture/proc/sys/fs/binfmt_misc
umount kali-$architecture/dev/pts
umount kali-$architecture/dev/
umount kali-$architecture/proc

# Create the disk and partition it
echo "Creating image file for Raspberry Pi3 Nexmon"
dd if=/dev/zero of=${basedir}/kali-$1-rpi3-nexmon.img bs=1M count=$size
parted kali-$1-rpi3-nexmon.img --script -- mklabel msdos
parted kali-$1-rpi3-nexmon.img --script -- mkpart primary fat32 0 64
parted kali-$1-rpi3-nexmon.img --script -- mkpart primary ext4 64 -1

# For chroot later
OUTPUTFILE="${basedir}/kali-$1-rpi3-nexmon.img"

loopdevice=`losetup -f --show $OUTPUTFILE`
device=`kpartx -va $loopdevice| sed -E 's/.*(loop[0-9])p.*/\1/g' | head -1`
sleep 5
device="/dev/mapper/${device}"
bootp=${device}p1
rootp=${device}p2

# Create file systems
echo "Mkfs"
mkfs.vfat $bootp
mkfs.ext4 $rootp

mkdir -p ${basedir}/bootp ${basedir}/root
mount $bootp ${basedir}/bootp
mount $rootp ${basedir}/root

echo "Rsyncing rootfs into image file"
rsync -HPavz -q ${basedir}/kali-$architecture/ ${basedir}/root/

# Enable login over serial
echo "T0:23:respawn:/sbin/agetty -L ttyAMA0 115200 vt100" >> ${basedir}/root/etc/inittab

cat << EOF > ${basedir}/root/etc/apt/sources.list
deb http://http.kali.org/kali kali-rolling main non-free contrib
deb-src http://http.kali.org/kali kali-rolling main non-free contrib
EOF

# Uncomment this if you use apt-cacher-ng otherwise git clones will fail.
#unset http_proxy

# Kernel section. If you want to use a custom kernel, or configuration, replace
# them in this section.

cd ${TOPDIR}
git clone --depth 1 https://github.com/seemoo-lab/nexmon.git ${basedir}/root/opt/nexmon
mkdir -p ${basedir}/root/opt/nexmon/firmware/
touch .scmversion

# RPI Firmware
git clone --depth 1 https://github.com/raspberrypi/firmware.git rpi-firmware
cp -rf rpi-firmware/boot/* ${basedir}/bootp/
rm -rf ${basedir}/root/lib/firmware  # Remove /lib/firmware to copy linux firmware
rm -rf rpi-firmware

# Linux Firmware
cd ${basedir}/root/lib
git clone --depth 1 https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git firmware
rm -rf ${basedir}/root/lib/firmware/.git

# Setup build
cd ${TOPDIR}
git clone --depth 1 https://github.com/nethunteros/re4son-raspberrypi-linux.git -b rpi-4.4.y-nexutil ${basedir}/root/usr/src/kernel
cd ${basedir}/root/usr/src/kernel

# fix (dont symlink if exists)
[ -d /usr/include/asm ] || ln -s /usr/include/asm-generic /usr/include/asm

# Set default defconfig
export ARCH=arm
export CROSS_COMPILE=arm-linux-gnueabihf-
make re4son_pi2_defconfig

# patch CROSS_COMPILE (e.g. for gentoo)
[ -x /usr/bin/armv7a-hardfloat-linux-gnueabi-gcc ] &&\
    export CROSS_COMPILE=armv7a-hardfloat-linux-gnueabi-

#make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- re4son_pi2_defconfig
make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} re4son_pi2_defconfig

# Build kernel
make -j $(grep -c processor /proc/cpuinfo)

# Make kernel modules
make modules_install INSTALL_MOD_PATH=${basedir}/root

# Copy kernel to boot
perl scripts/mkknlimg --dtok arch/arm/boot/zImage ${basedir}/bootp/kernel7.img
cp arch/arm/boot/dts/*.dtb ${basedir}/bootp/
cp arch/arm/boot/dts/overlays/*.dtb* ${basedir}/bootp/overlays/
cp arch/arm/boot/dts/overlays/README ${basedir}/bootp/overlays/

# Make firmware and headers
#make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- firmware_install INSTALL_MOD_PATH=${basedir}/root
make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} firmware_install INSTALL_MOD_PATH=${basedir}/root

# Fix up the symlink for building external modules
# kernver is used so we don't need to keep track of what the current compiled
# version is
kernver=$(ls ${basedir}/root/lib/modules/)
cd ${basedir}/root/lib/modules/$kernver
rm build
rm source
ln -s /usr/src/kernel build
ln -s /usr/src/kernel source

# Create cmdline.txt file
cat << EOF > ${basedir}/bootp/cmdline.txt
dwc_otg.fiq_fix_enable=2 console=ttyAMA0,115200 kgdboc=ttyAMA0,115200 console=tty1 root=/dev/mmcblk0p2 rootfstype=ext4 rootwait rootflags=noload net.ifnames=0
EOF

# systemd doesn't seem to be generating the fstab properly for some people, so
# let's create one.
cat << EOF > ${basedir}/root/etc/fstab
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
proc            /proc           proc    defaults          0       0
/dev/mmcblk0p1  /boot           vfat    defaults          0       2
/dev/mmcblk0p2  /               ext4    defaults,noatime  0       1
EOF

# Firmware needed for rpi3 wifi (copy nexmon firmware)
mkdir -p ${basedir}/root/lib/firmware/brcm/
cp ${basedir}/../misc/rpi3/brcmfmac43430-sdio-nexmon.bin ${basedir}/root/lib/firmware/brcm/brcmfmac43430-sdio.bin
cp ${basedir}/../misc/rpi3/brcmfmac43430-sdio.txt ${basedir}/root/lib/firmware/brcm/

# Copy nexutil
cp ${basedir}/../misc/rpi3/nexutil ${basedir}/root/usr/bin/nexutil
chmod +x ${basedir}/root/usr/bin/nexutil

cd ${basedir}

cp ${basedir}/../misc/zram ${basedir}/root/etc/init.d/zram
chmod +x ${basedir}/root/etc/init.d/zram

sed -i -e 's/^#PermitRootLogin.*/PermitRootLogin yes/' ${basedir}/root/etc/ssh/sshd_config

# Unmount partitions
umount $bootp
umount $rootp
kpartx -dv $loopdevice
losetup -d $loopdevice

rm -rf ${basedir}/bootp
rm -rf ${basedir}/root
rm -rf ${basedir}/boot
rm -rf ${basedir}/patches

# Clean up all the temporary build stuff and remove the directories.
# Comment this out to keep things around if you want to see what may have gone
# wrong.
echo "Cleaning up the temporary build files..."
rm -rf ${basedir}/kernel ${basedir}/bootp ${basedir}/root ${basedir}/kali-$architecture ${basedir}/boot ${basedir}/patches

# If you're building an image for yourself, comment all of this out, as you
# don't need the sha1sum or to compress the image, since you will be testing it
# soon.
echo "Generating sha256sum for kali-$1-rpi3-nexmon.img"
sha256sum kali-$1-rpi3-nexmon.img > ${basedir}/kali-$1-rpi3-nexmon.img.sha256sum

# Don't pixz on 32bit, there isn't enough memory to compress the images.
MACHINE_TYPE=`uname -m`
if [ ${MACHINE_TYPE} == 'x86_64' ]; then
	echo "Compressing kali-$1-rpi3-nexmon.img"
	pixz ${basedir}/kali-$1-rpi3-nexmon.img ${basedir}/kali-$1-rpi3-nexmon.img.xz
	rm ${basedir}/kali-$1-rpi3-nexmon.img
	echo "Generating sha265sum for kali-$1-rpi3-nexmon.img.xz"
	sha256sum kali-$1-rpi3-nexmon.img.xz > ${basedir}/kali-$1-rpi3-nexmon.img.xz.sha256sum
fi

