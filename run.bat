@ECHO OFF
SET module=%1
SET port=%2
IF "%~1" == "" GOTO run
ECHO Loading module %module%
SET module_param=-device virtio-blk-device,drive=hd -drive if=none,id=hd,format=raw,file=%module%
IF "%~2" == "" GOTO run
ECHO Forwarding port %port%
SET port_parm=hostfwd=tcp::31337-:%port%

:run
SET PATH=%PATH%;"C:\Program Files\qemu\"
qemu-system-arm.exe ^
    -M virt-6.2 ^
    -m 256 ^
    -kernel ./boot/zImage ^
    -initrd ./boot/rootfs.img ^
    -append "console=ttyAMA0 root=/dev/ram rdinit=/sbin/init" ^
    -nographic ^
    -netdev user,id=net0,net=10.13.37.0/24,dhcpstart=10.13.37.10,hostfwd=tcp::30023-:23,%port_param% -device virtio-net-device,netdev=net0 ^
    %module_param%