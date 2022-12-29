# The "Swagricator" swag fabrication machine

## Introduction
The _swagricator_ fake hacker swag fabrication machine is an abstract virtual platform designed for producing content about exploiting Linux powered ARM devices. It attempts to provide a basic platform resembling a generic (SOHO) CPE, printer, access point, vending machine, drone, etc.
The _swagricator_ provides a basic booting Linux kernel with networking and BusyBox running in QEMU. After the system is powered up it will load available "modules" from a mounted SD card image which could resemble software running on the device.

This repository contains instructions and scripts used to build the basic _swagricator_ image and produce a module. Alongside these instructions a binary release is provided, content and module authors are encouraged to link their content and modules to a binary release to make sure memory layouts and ABI are consistent between virtual system, module and content so people can replicatie the demonstrated findings without trouble.

## Disclaimer
This project does not aim to be educational itself about the many intricacies of developing embedded platforms and assumes subject knowledge on the components involved. It is definitely not a guide on how to build software for use outside of experimentation and education. All scripts and code presented should not be taken as production quality but rather as a "quick and dirty" approach to building a basic platform for QEMU.

## Toolchain and build platform
At this time these instructions assume a recent version of Fedora Linux as the build platform along with the cross-build toolchain provided by this distribution (`dnf install arm-linux-gnueabihf-gcc arm-linux-gnueabihf-binutils`).

On the host system an empty directory is set aside for this project, this will be the root from which all instructions start. In preparation directory `build` is designated for downloading and building the source code for the required packages. A directory, `rootfs`, will be used to build the initrd used as the root filesystem which will be stored in directory `boot` along with the kernel image. 

```sh
mkdir build boot
```

## Kernel

With the QEMU virtual machine as machine type we don't need to make any adjustments to the kernel configuration to get a working kernel image. This means just downloading the source code and using _defconfig_ is sufficient to get up and running.

```sh
cd build
wget https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.0.2.tar.xz
tar xf linux-6.0.2.tar.xz
cd linux-6.0.2
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- defconfig
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- -j8
cp arch/arm/boot/zImage ../../boot/
cd ../../
```

## RootFS
With the kernel ready to go it is time to put together the initrd which is used as the root filesystem. The rootfs will contain a few items of basic plumbing such as a minimal init system, libc, standard tools provided by BusyBox and GDB for convenience later on.

### BusyBox
Busybox will create a convenient basic filesystem for us with the `make install` command, which will be moved to the root directory after it is generated.

```sh
cd build
wget https://busybox.net/downloads/busybox-1.35.0.tar.bz2
tar xf busybox-1.35.0.tar.bz2
cd busybox-1.35.0/
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- defconfig
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- install
mv _install ../../rootfs
cd ../../
mkdir ./rootfs/lib
```

### GDB
GDB requires gmplib which must be downloaded and compiled as a first step

```sh
cd build
wget https://gmplib.org/download/gmp/gmp-6.2.1.tar.lz
tar xf gmp-6.2.1.tar.lz
cd gmp-6.2.1/
./configure --host=arm-linux-gnueabihf
make
cp .libs/libgmp.so.10 ../../rootfs/lib
cd ../../
```

Next download and compile GDB itself

```sh
cd build
wget https://ftp.gnu.org/gnu/gdb/gdb-12.1.tar.xz
tar xf gdb-12.1.tar.xz
cd gdb-12.1/
./configure --host=arm-linux-gnueabihf CFLAGS="-I`pwd`/../gmp-6.2.1 -L`pwd`/../gmp-6.2.1/.libs/" CXXFLAGS="-I`pwd`/../gmp-6.2.1 -L`pwd`/../gmp-6.2.1/.libs"
make
cp gdb/gdb ../../rootfs/bin
cp gdbserver/gdbserver ../../rootfs/bin
cd ../../
```

### libc

Since everything was built using the Fedora toolchain we can use the available libc binaries for arm-linux installed on the host system.

```sh
cp /usr/arm-linux-gnueabihf/sys-root/lib/ld-linux-armhf.so.* ./rootfs/lib
cp /usr/arm-linux-gnueabihf/sys-root/lib/libcrypt.so.* ./rootfs/lib
cp /usr/arm-linux-gnueabihf/sys-root/lib/libc.so.* ./rootfs/lib
cp /usr/arm-linux-gnueabihf/sys-root/lib/libdl.so.* ./rootfs/lib
cp /usr/arm-linux-gnueabihf/sys-root/lib/libgcc_s.* ./rootfs/lib
cp /usr/arm-linux-gnueabihf/sys-root/lib/libm.so.* ./rootfs/lib
cp /usr/arm-linux-gnueabihf/sys-root/lib/libpthread.so.* ./rootfs/lib
cp /usr/arm-linux-gnueabihf/sys-root/lib/libresolv.so.* ./rootfs/lib
cp /usr/arm-linux-gnueabihf/sys-root/lib/librt.so.* ./rootfs/lib
cp /usr/arm-linux-gnueabihf/sys-root/lib/libstdc++.so* ./rootfs/lib
```

### Populating rootfs

Add standard directories

```sh
cd rootfs
mkdir proc sys dev dev/pts etc etc/init.d tmp var
```

Add a user root, with password `root`.

```sh
echo "root:SRG0WR2YM6e.s:0:0:root:/root:/bin/sh" > etc/passwd
echo "root:x:0:" > etc/group
```

Set hostname to `swagricator`

```sh
echo "swagricator" > etc/hostname
```

Create fstab

```sh
cat <<EOF > etc/fstab
tmpfs /tmp tmpfs defaults,size=64M,noatime,nodev,nosuid,mode=1777 0 0
proc /proc proc defaults 0 0
sys /sys sysfs defaults 0 0
devpts /dev/pts devpts defaults 0 0
EOF
```

Write logging to ramdisk

```sh
ln -s /tmp var/log
```

Create rcS, this will start other bootscripts

```sh
cat <<EOF > etc/init.d/rcS
#!/bin/sh
hostname -F /etc/hostname
mount -a
/sbin/mdev -s

for i in /etc/init.d/S??* ;do
    # Ignore dangling symlinks (if any).
    [ ! -f "\$i" ] && continue

    \$i start
done
EOF
chmod +x etc/init.d/rcS
```

Set up virtual networking, swagricator will get address 10.13.37.10/24

```sh
cat <<EOF > etc/init.d/S10network
#!/bin/sh
case "\$1" in
  start)
    echo "Starting network..."
    ip addr add 10.13.37.10/24 dev eth0
    ip link set eth0 up
    ip route add default via 10.13.37.2 dev eth0
    echo "nameserver 10.13.37.3" > etc/resolv.conf
    ;;
  stop)
    echo -n "Stopping network..."
    ip link set eth0 down
    ip addr del 10.13.37.10/24 dev eth0
    ip route del default via 10.13.37.2 dev eth0
    echo "" > /etc/resolv.conf
    ;;
  restart|reload)
    "$0" stop
    "$0" start
    ;;
  *)
    echo \$"Usage: \$0 {start|stop|restart}"
    exit 1
esac
exit \$?
EOF
chmod +x etc/init.d/S10network
```

Set up a telnet daemon

```sh
cat <<EOF > etc/init.d/S20telnetd
#!/bin/sh
case "\$1" in
  start)
    echo "Starting telnetd..."
    telnetd
    ;;
  stop)
    echo -n "Stopping telnetd..."
    killall telnetd
    ;;
  restart|reload)
    "$0" stop
    "$0" start
    ;;
  *)
    echo \$"Usage: \$0 {start|stop|restart}"
    exit 1
esac
exit \$?
EOF
chmod +x etc/init.d/S20telnetd
```

Add the bootscript to load a module mounted on an SD image if present

```sh
cat <<EOF > etc/init.d/S99module
#!/bin/sh
case "\$1" in
  start)
    echo "Loading module..."
    if [ -b "/dev/vda" ]; then
      echo "Found device node"
    else
      echo "No /dev/vda node found!"
      exit 1
    fi
    echo "Mounting module"
    mkdir -p /mnt/module
    mount /dev/vda /mnt/module
    if [ -f "/mnt/module/start.sh" ]; then
      echo "running start script for module"
      sh /mnt/module/start.sh
    else
      echo "No startup script for module found"
    fi
    ;;
  stop)
    echo "Umounting module..."
    if [ -f "/mnt/module/stop.sh" ]; then
      echo "Running stop script for module"
      sh /mnt/module/stop.sh
    else
      echo "No stop script for module found!"
    fi
    umount /mnt/module
    ;;
  restart|reload)
    "-/bin/sh" stop
    "-/bin/sh" start
    ;;
  *)
    echo $"Usage: $0 {start|stop|restart}"
    exit 1
esac
exit $?
EOF
chmod +x etc/init.d/S99module
```

Since finding bugs will probably crash lots of processes a simple monitoring script is order to restart any terminated processes

```sh
cat <<EOF > sbin/monitor.sh 
#!/bin/sh
echo "Monitoring module with pid \${1}"
while true
do
  if [ -d "/proc/\${1}" ]; then
    touch /tmp/monitor.\${1}
  else
    echo "Process \${1} ended"
    if [ -f "/mnt/module/start.sh" ]; then
      echo "Trying to restart"
      /bin/sh /mnt/module/start.sh &
    fi
    exit
  fi
  sleep 10
done
EOF
chmod +x sbin/monitor.sh
```

And return to base

```
cd ../
```

### Building initrd
With all components in place in the rootfs directory these can be combined to a working rootfs using `fakeroot`

```sh
cd rootfs
fakeroot -- bash -c "chown -R root:root ./ && find . | cpio -o --format=newc > ../boot/rootfs.img"
cd ../
```

## Booting
With `boot` now containing `rootfs.img` and `zImage` the system should now be bootable with the command listed below. Note that SLIRP (user mode networking) is used so no further configuration for networking is required on the host.

```
qemu-system-arm -m 256 -M virt-6.2 -kernel boot/zImage -initrd boot/rootfs.img -nographic -append "console=ttyAMA0 root=/dev/ram rdinit=/sbin/init" -netdev user,id=net0,net=10.13.37.0/24,dhcpstart=10.13.37.10,hostfwd=tcp::30023-:23 -device virtio-net-device,netdev=net0
```

After bootup the `Please press Enter to activate this console.` prompt should be shown. It is now possible to connect to the telnetd using `telnet localhost 30023` on the host system and proceed with logging in as user `root` with password `root`.
To quit QEMU enter <kbd>CTRL</kbd> + <kbd>a</kbd> <kbd>x</kbd>.

For convenience a startup script `run.sh` is provided that takes parameters `-m` to specify the module to load and `-p` to forward an additional port to localhost:31337 on the host system.

## Modules
The module loader script checks for the `/dev/vda` device node, this device node will appear if a disk image is specified in the `-drive` parameter to `qemu-system-arm`. It will then mount this image to `/mnt/module` and start a script `start.sh` that should take care of setting up the environment required for the module. If the module is a daemon it should start the daemon and ideally also turn on process monitoring. Call `/sbin/monitor.sh ${PID}` where ${PID} it the PID to monitor, after this PID is gone it calls `/mnt/module/start.sh` to restart the module. It is possible to unload a module gracefully by providing a `stop.sh` script.
