#!/bin/bash -e

# A POSIX variable
OPTIND=1 # Reset in case getopts has been used previously in the shell.

while getopts "a:v:q:u:d:s:i:o:t:" opt; do
    case "$opt" in
    a)  ARCH=$OPTARG
        ;;
    v)  TIEPIE_ARCH=$OPTARG
        ;;
    q)  QEMU_ARCH=$OPTARG
        ;;
    u)  QEMU_VER=$OPTARG
        ;;
    d)  DOCKER_REPO=$OPTARG
        ;;
    s)  SUITE=$OPTARG
        ;;
    i)  INCLUDE=$OPTARG
        ;;
    t)  DATE=$OPTARG
        ;;
    esac
done

shift $((OPTIND-1))

[ "$1" = "--" ] && shift

INCLUDE_FILES=(packages/all.txt packages/${SUITE}-all.txt packages/all-${ARCH}.txt packages/${SUITE}-${ARCH}.txt)
for include_file in ${INCLUDE_FILES[@]}; do
    if [ -s ${include_file} ]; then
        INCLUDE+=,$(sed ':a;N;$!ba;s/\n/,/g' ${include_file})
    fi
done

dir="$SUITE"
COMPONENTS="main"
VARIANT="minbase"
args=( -d "$dir" debootstrap --no-check-gpg --variant="$VARIANT" --components="$COMPONENTS" --include="$INCLUDE" --arch="$ARCH" "$SUITE" http://raspbian.raspberrypi.org/raspbian)

mkdir -p mkimage $dir
curl https://raw.githubusercontent.com/docker/docker/master/contrib/mkimage.sh > mkimage.sh
curl https://raw.githubusercontent.com/docker/docker/master/contrib/mkimage/debootstrap > mkimage/debootstrap
chmod +x mkimage.sh mkimage/debootstrap
patch -f mkimage/debootstrap < patch/debootstrap.patch
if [ "$?" != 0 ]; then exit 1; fi

mkimage="$(readlink -f "${MKIMAGE:-"mkimage.sh"}")"
{
    echo "$(basename "$mkimage") ${args[*]/"$dir"/.}"
    echo
    echo 'https://github.com/docker/docker/blob/master/contrib/mkimage.sh'
} > "$dir/build-command.txt"

sudo DEBOOTSTRAP="qemu-debootstrap" nice ionice -c 3 "$mkimage" "${args[@]}" 2>&1 | tee "$dir/build.log"
sudo chown -R "$(id -u):$(id -g)" "$dir"

xz -d < $dir/rootfs.tar.xz | gzip -c > $dir/rootfs.tar.gz
sed -i /^ENV/d "${dir}/Dockerfile"
echo "ENV TIEPIE_OS=linux TIEPIE_DISTRIBUTION=raspbian TIEPIE_ARCH=${TIEPIE_ARCH} TIEPIE_CODENAME=${SUITE} DOCKER_REPO=${DOCKER_REPO}" >> "${dir}/Dockerfile"
if [[ "$SUITE" =~ ^wheezy|jessie|stretch$ ]]; then
cat >> "${dir}/Dockerfile" <<EOF
RUN echo "deb http://raspbian.raspberrypi.org/raspbian ${SUITE} main contrib non-free rpi" > /etc/apt/sources.list && \\
    echo "deb http://archive.raspberrypi.org/debian ${SUITE} main ui staging" >> /etc/apt/sources.list && \\
    wget http://archive.raspberrypi.org/debian/raspberrypi.gpg.key && \\
    apt-key add raspberrypi.gpg.key && \\
    rm raspberrypi.gpg.key
EOF
else
cat >> "${dir}/Dockerfile" <<EOF
RUN echo "deb http://raspbian.raspberrypi.org/raspbian ${SUITE} main contrib non-free rpi" > /etc/apt/sources.list
EOF
fi

if [ "$DOCKER_REPO" ]; then
    docker build -t "${DOCKER_REPO}:${ARCH}-${SUITE}-slim" "${dir}"
    mkdir -p "${dir}/full"
    (
    cd "${dir}/full"
    if [ ! -f x86_64_qemu-${QEMU_ARCH}-static.tar.gz ]; then
        wget -N https://github.com/multiarch/qemu-user-static/releases/download/${QEMU_VER}/x86_64_qemu-${QEMU_ARCH}-static.tar.gz
    fi
    tar xf x86_64_qemu-*.gz
    )
    cat > "${dir}/full/Dockerfile" <<EOF
FROM ${DOCKER_REPO}:${ARCH}-${SUITE}-slim
ADD qemu-*-static /usr/bin/
EOF
    docker build -t "${DOCKER_REPO}:${ARCH}-${SUITE}" -t "${DOCKER_REPO}:${ARCH}-${SUITE}-${DATE}" "${dir}/full"
fi

docker run -it --rm "${DOCKER_REPO}:${ARCH}-${SUITE}" bash -xc '
    uname -a
    echo
    cat /etc/apt/sources.list
    echo
    cat /etc/os-release 2>/dev/null
    echo
    cat /etc/lsb-release 2>/dev/null
    echo
    cat /etc/debian_version 2>/dev/null
    true
'
