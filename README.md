# gentoo-quick-installer

## About

This is a quick installer script that can be used to bootstrap amd64 Gentoo Linux quickly.

Script has been tested on VirtualBox. Other platforms could require additional manual tunining.

Anyway, it is simple, minimalistic, easy to read and easy to tune for your needs

Read more: http://www.artembutusov.com/gentoo-linux-quick-installer-script/

## Contribution

For almost any change please consider doing a few tests below.

Images should be bootable and should allow to login using root password-auth or password-less auth via SSH.

```shell
# livecd kernel with root password
USE_LIVECD_KERNEL=1 ROOT_PASSWORD=Gentoo123 ./gentoo-quick-installer.sh

# Compiled kernel with ssh public key
USE_LIVECD_KERNEL=0 SSH_PUBLIC_KEY=$(cat id_rsa.pub) ./gentoo-quick-installer.sh
```

## Copyright

gentoo-vbox-builder is licensed under the MIT.

A copy of this license is included in the file LICENSE.txt
