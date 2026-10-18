#!/bin/bash
# Exercise only disposable native Debian containers; never install on the host.
set -euo pipefail
test -f /.dockerenv
test "${SONIC_DEB_TEST_CONTAINER:-}" = 1
package_directory=$(realpath "$1")
export DEBIAN_FRONTEND=noninteractive
# Debian's normal policy prevents a hardware service from starting during this
# package-state test. Maintainer scripts still run and register the service.
printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d
chmod 755 /usr/sbin/policy-rc.d
apt-get update
apt-get -y --no-install-recommends install "$package_directory"/*.deb
packages=(libsaimetadata libsairedis libsaivs syncd-vs)
for package in "${packages[@]}"; do
    test "$(dpkg-query -W -f='${Status}' "$package")" = 'install ok installed'
    test "$(dpkg-query -W -f='${Version}' "$package")" = 1.0.0
done
dpkg-query -S /usr/bin/syncd /etc/init.d/syncd
for executable in syncd syncd_start.sh syncd_init_common.sh saidump.sh gbsyncdmgrd; do
    test "$(stat -c %a "/usr/bin/$executable")" = 755
done
for package in "${packages[@]}"; do
    test "$(stat -c %a "/usr/share/doc/$package/changelog.gz")" = 644
done
for file in /usr/bin/syncd /usr/lib/*/libsairedis.so.0 /usr/lib/*/libsaimetadata.so.0 /usr/lib/*/libsaivs.so.0; do
    test -e "$file"
    if ldd "$file" | grep 'not found'; then
        echo "Missing installed runtime dependency for $file" >&2
        exit 1
    fi
done
apt-get check
test -z "$(dpkg --audit)"
# Preserve an administrator's change to the declared init-script conffile.
printf '\n# retained across package reinstall\n' >> /etc/init.d/syncd
apt-get -y --reinstall --no-install-recommends install "$package_directory"/*.deb
grep -F '# retained across package reinstall' /etc/init.d/syncd
apt-get -y remove "${packages[@]}"
test ! -e /usr/bin/syncd
test -f /etc/init.d/syncd
apt-get -y --no-install-recommends install "$package_directory"/*.deb
apt-get -y purge "${packages[@]}"
test ! -e /usr/bin/syncd
test ! -e /etc/init.d/syncd
if ldconfig -p | grep -E 'libsairedis.so|libsaimetadata.so|libsaivs.so'; then
    echo 'Sairedis library remained in the loader cache after purge' >&2
    exit 1
fi
apt-get check
test -z "$(dpkg --audit)"
printf '%s\n' '{"configuration":"passed","debian_permissions":"passed","installed_elf_dependencies":"passed","reinstall":"passed","conffile_preservation":"passed","remove":"passed","purge":"passed"}' > "$package_directory/installation.json"
