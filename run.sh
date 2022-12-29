module=""

while getopts m:p: flag
do
    case "${flag}" in
        m)
            module=${OPTARG}
            ;;
        p)
            port=${OPTARG}
            ;;

    esac
done

if [ -z "$module" ]
then
    echo "Starting without loading module"
else
    echo "Loading module ${module}"
    module_param="-device virtio-blk-device,drive=hd -drive if=none,id=hd,format=raw,file=${module}"
fi

if [ -z "$port" ]
then
    echo "Forwarding no additional ports"
else
    echo "Forwarding additional port ${port} to localhost:31337"
    port_param="hostfwd=tcp::31337-:${port}"
fi

qemu-system-arm \
    -M virt-6.2 \
    -m 256 \
    -kernel ./boot/zImage \
    -initrd ./boot/rootfs.img \
    -append "console=ttyAMA0 root=/dev/ram rdinit=/sbin/init" \
    -nographic \
    -netdev user,id=net0,net=10.13.37.0/24,dhcpstart=10.13.37.10,hostfwd=tcp::30023-:23,${port_param} -device virtio-net-device,netdev=net0 \
    ${module_param}