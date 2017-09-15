#!/bin/bash -e

# A POSIX variable
OPTIND=1 # Reset in case getopts has been used previously in the shell.

while getopts "a:v:q:u:d:s:i:o:" opt; do
    case "$opt" in
    a)  ARCH=$OPTARG
        ;;
    v)  VERSION=$OPTARG
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
    o)  UNAME_ARCH=$OPTARG
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

dir="$VERSION"
COMPONENTS="main"
VARIANT="minbase"
args=( -d "$dir" debootstrap --no-check-gpg --variant="$VARIANT" --components="$COMPONENTS" --include="$INCLUDE" --arch="$ARCH" "$SUITE" http://archive.raspbian.org/raspbian)

mkdir -p mkimage $dir
curl https://raw.githubusercontent.com/docker/docker/master/contrib/mkimage.sh > mkimage.sh
curl https://raw.githubusercontent.com/docker/docker/master/contrib/mkimage/debootstrap > mkimage/debootstrap
chmod +x mkimage.sh mkimage/debootstrap

mkimage="$(readlink -f "${MKIMAGE:-"mkimage.sh"}")"
{
    echo "$(basename "$mkimage") ${args[*]/"$dir"/.}"
    echo
    echo 'https://github.com/docker/docker/blob/master/contrib/mkimage.sh'
} > "$dir/build-command.txt"

sudo DEBOOTSTRAP="qemu-debootstrap" nice ionice -c 3 "$mkimage" "${args[@]}" 2>&1 | tee "$dir/build.log"
cat "$dir/build.log"
sudo chown -R "$(id -u):$(id -g)" "$dir"

xz -d < $dir/rootfs.tar.xz | gzip -c > $dir/rootfs.tar.gz
sed -i /^ENV/d "${dir}/Dockerfile"
echo "ENV ARCH=${UNAME_ARCH} UBUNTU_SUITE=${SUITE} DOCKER_REPO=${DOCKER_REPO}" >> "${dir}/Dockerfile"
cat >> "${dir}/Dockerfile" <<EOF
RUN if [ ! -s /etc/apt/sources.list ]; then \
  echo "deb http://archive.raspbian.org/raspbian ${SUITE} main contrib" > /etc/apt/sources.list; \
fi
EOF

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
    docker build -t "${DOCKER_REPO}:${ARCH}-${SUITE}" "${dir}/full"
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
