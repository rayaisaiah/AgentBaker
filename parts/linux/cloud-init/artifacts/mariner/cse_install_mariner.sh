#!/bin/bash

echo "Sourcing cse_install_distro.sh for Mariner"

removeContainerd() {
    retrycmd_if_failure 10 5 60 dnf remove -y moby-containerd
}

installDeps() {
    dnf_makecache || exit $ERR_APT_UPDATE_TIMEOUT
    dnf_update || exit $ERR_APT_DIST_UPGRADE_TIMEOUT
    for dnf_package in blobfuse ca-certificates check-restart cifs-utils cloud-init-azure-kvp-22.4-3.cm2 conntrack-tools cracklib dnf-automatic ebtables ethtool fuse git inotify-tools iotop iproute ipset iptables jq kernel-devel-5.15.116.1-2.cm2 logrotate lsof nmap-ncat nfs-utils pam pigz psmisc rsyslog socat sysstat traceroute util-linux xz zip; do
      if ! dnf_install 30 1 600 $dnf_package; then
        exit $ERR_APT_INSTALL_TIMEOUT
      fi
    done

    # install additional apparmor deps for 2.0;
    if [[ $OS_VERSION == "2.0" ]]; then
      for dnf_package in apparmor-parser libapparmor blobfuse2 nftables; do
        if ! dnf_install 30 1 600 $dnf_package; then
          exit $ERR_APT_INSTALL_TIMEOUT
        fi
      done
    fi
}

installKataDeps() {
    if [[ $OS_VERSION != "1.0" ]]; then
      for dnf_package in kernel-mshv cloud-hypervisor kata-containers moby-containerd-cc hvloader mshv-bootloader-lx mshv; do
        if ! dnf_install 30 1 600 $dnf_package; then
          exit $ERR_APT_INSTALL_TIMEOUT
        fi
      done

#TODO: are we not feeding those in via the prior UVM build pipeline? Probably that was already different in another branch. Needs to be adapted so that things can be taken from a prior pipeline but not a blob storage
      echo "install UVM build pipeline artifacts from storage account"
      wget "https://mitchzhu.blob.core.windows.net/public/igvm-76080001.bin" -O igvm.bin
      wget "https://mitchzhu.blob.core.windows.net/public/igvm-debug-76080001.bin" -O igvm-debug.bin
      wget "https://mitchzhu.blob.core.windows.net/public/igvm-measurement-76080001" -O igvm-measurement
      wget "https://mitchzhu.blob.core.windows.net/public/igvm-debug-measurement-76080001" -O igvm-debug-measurement
      wget "https://mitchzhu.blob.core.windows.net/public/reference-info-base64-76080001" -O reference-info-base64
      wget "https://mitchzhu.blob.core.windows.net/public/kata-containers-initrd-76080001.img" -O kata-containers-initrd.img
      mkdir -p /opt/confidential-containers/share/kata-containers/
      mv igvm.bin /opt/confidential-containers/share/kata-containers/igvm.bin
      mv igvm-debug.bin /opt/confidential-containers/share/kata-containers/igvm-debug.bin
      mv igvm-measurement /opt/confidential-containers/share/kata-containers/igvm-measurement
      mv igvm-debug-measurement /opt/confidential-containers/share/kata-containers/igvm-debug-measurement
      mv reference-info-base64 /opt/confidential-containers/share/kata-containers/reference-info-base64
      mv kata-containers-initrd.img /opt/confidential-containers/share/kata-containers/kata-containers-initrd.img

#TODO let us change things right now: No more storage accounts for packages. If we can't build in the release pipeline natively in AB for now, we have to live with it: depends on package availability.
#since we can run this in our pre-release pipeline we will have the packages available. So, let us:
#add cloud-hypervisor-cvm package above, remove below
#add kata-containers-cc package above, remove below
#add kernel-uvm and kernel-uvm-cvm packages above - try to remove the devel packages below, we should only need it to build the tarfs module. If we still build this tarfs module for vanilla Kata during the first boot (I think so, we may leave it for now, but let's definitely try to not list kernel-uvm-cvm-devel
      echo "install cloud-hypervisor-igvm from storage account"
      wget "https://mitchzhu.blob.core.windows.net/public/cloud-hypervisor-igvm-76080001" -O cloud-hypervisor-igvm
      mkdir -p /opt/confidential-containers/bin/
      mv cloud-hypervisor-igvm /opt/confidential-containers/bin/cloud-hypervisor-igvm
      chmod 755 /opt/confidential-containers/bin/cloud-hypervisor-igvm

      echo "TEMP: install kata-cc packages from storage account"
      wget "https://mitchzhu.blob.core.windows.net/public/kernel-uvm-5.15.110.mshv2-2.cm2.x86_64.rpm" -O kernel-uvm.x86_64.rpm
      wget "https://mitchzhu.blob.core.windows.net/public/kernel-uvm-devel-5.15.110.mshv2-2.cm2.x86_64.rpm" -O kernel-uvm-devel.x86_64.rpm
      wget "https://mitchzhu.blob.core.windows.net/public/kata-containers-cc-0.4.2-1.cm2.x86_64.rpm" -O kata-containers-cc.x86_64.rpm
      rpm -ihv kernel-uvm.x86_64.rpm
      rpm -ihv kernel-uvm-devel.x86_64.rpm
      rpm -ihv kata-containers-cc.x86_64.rpm
      
      echo "append kata-cc config to use IGVM"
#TODO see comment on line 74
      sed -i 's/cloud-hypervisor-snp/cloud-hypervisor-igvm/g' /opt/confidential-containers/share/defaults/kata-containers/configuration-clh-snp.toml
      sed -i 's/valid_hypervisor_paths/#valid_hypervisor_paths/g' /opt/confidential-containers/share/defaults/kata-containers/configuration-clh-snp.toml
#TODO see comment on line 74
      sed -i '/#valid_hypervisor_paths =/a valid_hypervisor_paths = ["/opt/confidential-containers/bin/cloud-hypervisor-igvm"]' /opt/confidential-containers/share/defaults/kata-containers/configuration-clh-snp.toml
#TODO to remove or to change - we will have to point our CC config to the right CH-CHM binary. either we solve this via the initial config, or via SPEC, or here
      sed -i 's/cloud-hypervisor/cloud-hypervisor-igvm/g' /opt/confidential-containers/share/defaults/kata-containers/configuration-clh.toml
#TODO I believe to remove - we won't use IGVM for a non-snp config      
      sed -i '/image =/a igvm = "/opt/confidential-containers/share/kata-containers/kata-containers-igvm.img"' /opt/confidential-containers/share/defaults/kata-containers/configuration-clh.toml
      # Comment out image and kernel configs
#TODO: kernel should not be commented, while image is already commented. so, we are good to remove both lines. configuration-clh likelycomes as: kernel, initrd, uncommented while #image commented.
      sed -i 's/kernel = /#kernel = /g' /opt/confidential-containers/share/defaults/kata-containers/configuration-clh.toml
      sed -i 's/image = /#image = /g' /opt/confidential-containers/share/defaults/kata-containers/configuration-clh.toml
    fi
}

downloadGPUDrivers() {
    # Mariner CUDA rpm name comes in the following format:
    #
    # cuda-%{nvidia gpu driver version}_%{kernel source version}.%{kernel release version}.{mariner rpm postfix}
    #
    # Before installing cuda, check the active kernel version (uname -r) and use that to determine which cuda to install
    KERNEL_VERSION=$(uname -r | sed 's/-/./g')
    CUDA_VERSION="*_${KERNEL_VERSION}*"

    if ! dnf_install 30 1 600 cuda-${CUDA_VERSION}; then
      exit $ERR_APT_INSTALL_TIMEOUT
    fi
}

installNvidiaFabricManager() {
    # Check the NVIDIA driver version installed and install nvidia-fabric-manager
    NVIDIA_DRIVER_VERSION=$(cut -d - -f 2 <<< "$(rpm -qa cuda)")
    for nvidia_package in nvidia-fabric-manager-${NVIDIA_DRIVER_VERSION} nvidia-fabric-manager-devel-${NVIDIA_DRIVER_VERSION}; do
      if ! dnf_install 30 1 600 $nvidia_package; then
        exit $ERR_APT_INSTALL_TIMEOUT
      fi
    done
}

installNvidiaContainerRuntime() {
    MARINER_NVIDIA_CONTAINER_RUNTIME_VERSION="3.11.0"
    MARINER_NVIDIA_CONTAINER_TOOLKIT_VERSION="1.11.0"
    
    for nvidia_package in nvidia-container-runtime-${MARINER_NVIDIA_CONTAINER_RUNTIME_VERSION} nvidia-container-toolkit-${MARINER_NVIDIA_CONTAINER_TOOLKIT_VERSION} nvidia-container-toolkit-base-${MARINER_NVIDIA_CONTAINER_TOOLKIT_VERSION} libnvidia-container-tools-${MARINER_NVIDIA_CONTAINER_TOOLKIT_VERSION} libnvidia-container1-${MARINER_NVIDIA_CONTAINER_TOOLKIT_VERSION}; do
      if ! dnf_install 30 1 600 $nvidia_package; then
        exit $ERR_APT_INSTALL_TIMEOUT
      fi
    done
}

enableNvidiaPersistenceMode() {
    PERSISTENCED_SERVICE_FILE_PATH="/etc/systemd/system/nvidia-persistenced.service"
    touch ${PERSISTENCED_SERVICE_FILE_PATH}
    cat << EOF > ${PERSISTENCED_SERVICE_FILE_PATH} 
[Unit]
Description=NVIDIA Persistence Daemon
Wants=syslog.target

[Service]
Type=forking
ExecStart=/usr/bin/nvidia-persistenced --verbose
ExecStopPost=/bin/rm -rf /var/run/nvidia-persistenced
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl enable nvidia-persistenced.service || exit 1
    systemctl restart nvidia-persistenced.service || exit 1
}

# CSE+VHD can dictate the containerd version, users don't care as long as it works
installStandaloneContainerd() {
    CONTAINERD_VERSION=$1
    #overwrite the passed containerd_version since mariner uses only 1 version now which is different than ubuntu's
    CONTAINERD_VERSION="1.3.4"
    # azure-built runtimes have a "+azure" suffix in their version strings (i.e 1.4.1+azure). remove that here.
    CURRENT_VERSION=$(containerd -version | cut -d " " -f 3 | sed 's|v||' | cut -d "+" -f 1)
    # v1.4.1 is our lowest supported version of containerd
    
    if semverCompare ${CURRENT_VERSION:-"0.0.0"} ${CONTAINERD_VERSION}; then
        echo "currently installed containerd version ${CURRENT_VERSION} is greater than (or equal to) target base version ${CONTAINERD_VERSION}. skipping installStandaloneContainerd."
    else
        echo "installing containerd version ${CONTAINERD_VERSION}"
        removeContainerd
        # TODO: tie runc to r92 once that's possible on Mariner's pkg repo and if we're still using v1.linux shim
        if ! dnf_install 30 1 600 moby-containerd; then
          exit $ERR_CONTAINERD_INSTALL_TIMEOUT
        fi
    fi

    # Workaround to restore the CSE configuration after containerd has been installed from the package server.
    if [[ -f /etc/containerd/config.toml.rpmsave ]]; then
        mv /etc/containerd/config.toml.rpmsave /etc/containerd/config.toml
    fi

}

cleanUpGPUDrivers() {
    rm -Rf $GPU_DEST /opt/gpu
}

downloadContainerdFromVersion() {
    echo "downloadContainerdFromVersion not implemented for mariner"
}

downloadContainerdFromURL() {
    echo "downloadContainerdFromURL not implemented for mariner"
}

#EOF
