#!/usr/bin/env bash
export DEB_BUILD_OPTIONS="nocheck"
export FAILFAST="$2"
export SYSTEMD="$1"
if [ "$SYSTEMD" != "true" ]; then
	export DEB_BUILD_PROFILES="nosystemd"
fi

# Build order: xorgproto first (provides x11proto-dev), then xlibre-server (provides xserver-xlibre-dev), then drivers, then xlibre meta-package
TO_BUILD="xorgproto xlibre-server xserver-xlibre-input-elographics xserver-xlibre-input-libinput xserver-xlibre-input-vmmouse xserver-xlibre-input-wacom xserver-xlibre-video-ati xserver-xlibre-video-fbdev xserver-xlibre-video-nouveau xserver-xlibre-video-sisusb xserver-xlibre-video-vmware xserver-xlibre-input-evdev xserver-xlibre-input-synaptics xserver-xlibre-input-void xserver-xlibre-video-amdgpu xserver-xlibre-video-dummy xserver-xlibre-video-intel xserver-xlibre-video-qxl xserver-xlibre-video-vesa xserver-xlibre-video-voodoo xserver-xlibre-input-keyboard xserver-xlibre-input-mouse xlibre"
ORIGINAL_DIR="$(pwd)"

# Detect architecture
ARCH=$(dpkg --print-architecture)
echo -e "\e[0;32mBuilding for architecture\e[0m: $ARCH"

# x86-only packages that should be skipped on ARM
X86_ONLY_PACKAGES="xserver-xlibre-input-vmmouse xserver-xlibre-video-vmware xserver-xlibre-video-intel xserver-xlibre-video-voodoo"

for dir in $TO_BUILD; do
	# Skip x86-only packages on non-x86 architectures
	if [ "$ARCH" != "amd64" ] && [ "$ARCH" != "i386" ]; then
		skip=false
		for pkg in $X86_ONLY_PACKAGES; do
			if [ "$dir" = "$pkg" ]; then
				echo -e "\e[33mSkipping x86-only package on $ARCH\e[0m: $dir"
				skip=true
				break
			fi
		done
		if [ "$skip" = "true" ]; then
			continue
		fi
	fi

	if [ -d "$dir" ]; then
		echo -e "\e[0;32mBuilding in directory\e[0m: $dir"
		cd "$dir" || { echo "Failed to enter directory: $dir"; exit 1; }

		# Fetch pristine-tar and upstream branches needed for gbp
		git fetch origin pristine-tar:pristine-tar 2>/dev/null || true
		git fetch origin upstream/latest:upstream/latest 2>/dev/null || true

		# Install build dependencies
		mk-build-deps --install --remove --tool='apt-get -o Debug::pkgProblemResolver=yes --no-install-recommends -y' debian/control || true

		# don't sign packages, they will be signed in a repo.
		if ! gbp buildpackage --git-builder="debuild -i -I -us -uc" --git-debian-branch="xlibre/latest" --git-upstream-branch="upstream/latest" --git-pristine-tar; then
			echo -e "\e[31mFailed to build package\e[0m: $dir"
			if [ "$FAILFAST" = "true" ]; then
				exit 1
			fi
		fi

		cd "$ORIGINAL_DIR" || { echo "Failed to return to original directory"; exit 1; }

		# Install intermediate packages needed for subsequent builds
		if [ "$dir" = "xorgproto" ]; then
			echo -e "\e[0;32mInstalling x11proto-dev\e[0m"
			dpkg -i x11proto-dev_*.deb || apt-get install -f -y
		fi
		if [ "$dir" = "xlibre-server" ]; then
			echo -e "\e[0;32mInstalling xserver-xlibre-dev\e[0m"
			dpkg -i xserver-xlibre-dev_*.deb || apt-get install -f -y
		fi

	else
		echo "Directory not found: $dir"
	fi
done
mkdir -p $ORIGINAL_DIR/build
mv *.build *.buildinfo *.changes *.deb *.xz *.gz *.dsc *.udeb $ORIGINAL_DIR/build || { echo "Unable to move files to 'build' directory"; exit 1; }
