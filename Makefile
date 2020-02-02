# Disable builtin rules and variables since they aren't used
# This makes the output of "make -d" much easier to follow and speeds up evaluation
MAKEFLAGS+= --no-builtin-rules
MAKEFLAGS+= --no-builtin-variables

# Normal (libvirt and VirtualBox) images
IMAGES+= windows-2012-r2
IMAGES+= windows-2016
IMAGES+= windows-2019
IMAGES+= windows-2019-uefi
IMAGES+= windows-10
IMAGES+= windows-10-1903

# Images supporting vSphere
VSPHERE_IMAGES+= windows-2016
VSPHERE_IMAGES+= windows-2019
VSPHERE_IMAGES+= windows-10

# Generate build-* targets
VIRTUALBOX_BUILDS= $(addsuffix -virtualbox,$(addprefix build-,$(IMAGES)))
LIBVIRT_BUILDS= $(addsuffix -libvirt,$(addprefix build-,$(IMAGES)))
VSPHERE_BUILDS= $(addsuffix -vsphere,$(addprefix build-,$(VSPHERE_IMAGES)))

.PHONY: help $(VIRTUALBOX_BUILDS) $(LIBVIRT_BUILDS) $(VSPHERE_BUILDS)

help:
	@echo Type one of the following commands to build a specific windows box.
	@echo
	@echo VirtualBox Targets:
	@$(addprefix echo make ,$(addsuffix ;,$(VIRTUALBOX_BUILDS)))
	@echo
	@echo libvirt Targets:
	@$(addprefix echo make ,$(addsuffix ;,$(LIBVIRT_BUILDS)))
	@echo
	@echo vSphere Targets:
	@$(addprefix echo make ,$(addsuffix ;,$(VSPHERE_BUILDS)))

# Target specific pattern rules for build-* targets
$(VIRTUALBOX_BUILDS): build-%-virtualbox: %-amd64-virtualbox.box
$(LIBVIRT_BUILDS): build-%-libvirt: %-amd64-libvirt.box
$(VSPHERE_BUILDS): build-%-vsphere: %-amd64-vsphere.box

%-amd64-virtualbox.box: %.json %/autounattend.xml Vagrantfile.template *.ps1 drivers
	rm -f $@
	CHECKPOINT_DISABLE=1 PACKER_LOG=1 PACKER_LOG_PATH=$*-amd64-virtualbox-packer.log \
		packer build -only=$*-amd64-virtualbox -on-error=abort $*.json
	./get-windows-updates-from-packer-log.sh \
		$*-amd64-virtualbox-packer.log \
		>$*-amd64-virtualbox-windows-updates.log
	@echo BOX successfully built!
	@echo to add to local vagrant install do:
	@echo vagrant box add -f $*-amd64 $@

%-amd64-libvirt.box: %.json %/autounattend.xml Vagrantfile.template *.ps1 drivers
	rm -f $@
	CHECKPOINT_DISABLE=1 PACKER_LOG=1 PACKER_LOG_PATH=$*-amd64-libvirt-packer.log \
		packer build -only=$*-amd64-libvirt -on-error=abort $*.json
	./get-windows-updates-from-packer-log.sh \
		$*-amd64-libvirt-packer.log \
		>$*-amd64-libvirt-windows-updates.log
	@echo BOX successfully built!
	@echo to add to local vagrant install do:
	@echo vagrant box add -f $*-amd64 $@

%-uefi-amd64-virtualbox.box: %-uefi.json %-uefi/autounattend.xml Vagrantfile-uefi.template *.ps1 drivers %-uefi-amd64-virtualbox.iso
	rm -f $@
	CHECKPOINT_DISABLE=1 PACKER_LOG=1 PACKER_LOG_PATH=$*-uefi-amd64-virtualbox-packer.log \
		packer build -only=$*-uefi-amd64-virtualbox -on-error=abort $*-uefi.json
	./get-windows-updates-from-packer-log.sh \
		$*-uefi-amd64-virtualbox-packer.log \
		>$*-uefi-amd64-virtualbox-windows-updates.log
	@echo BOX successfully built!
	@echo to add to local vagrant install do:
	@echo vagrant box add -f $*-uefi-amd64 $@

%-uefi-amd64-libvirt.box: %-uefi.json %-uefi/autounattend.xml Vagrantfile-uefi.template *.ps1 drivers
	rm -f $@
	CHECKPOINT_DISABLE=1 PACKER_LOG=1 PACKER_LOG_PATH=$*-uefi-amd64-libvirt-packer.log \
		packer build -only=$*-uefi-amd64-libvirt -on-error=abort $*-uefi.json
	./get-windows-updates-from-packer-log.sh \
		$*-uefi-amd64-libvirt-packer.log \
		>$*-uefi-amd64-libvirt-windows-updates.log
	@echo BOX successfully built!
	@echo to add to local vagrant install do:
	@echo vagrant box add -f $*-uefi-amd64 $@

windows-2019-uefi-amd64-virtualbox.iso: windows-2019-uefi/autounattend.xml winrm.ps1
	xorrisofs -J -R -input-charset ascii -o $@ $^

%-amd64-vsphere.box: %-vsphere.json %/autounattend.xml dummy-windows-vsphere.box *.ps1
	rm -f $@
	CHECKPOINT_DISABLE=1 PACKER_LOG=1 PACKER_LOG_PATH=$*-amd64-vsphere-packer.log \
		packer build -only=$*-amd64-vsphere -on-error=abort $*-vsphere.json
	./get-windows-updates-from-packer-log.sh \
		$*-amd64-vsphere-packer.log \
		>$*-amd64-vsphere-windows-updates.log
	@echo 'Removing all cd-roms (except the first)...'
	govc device.ls "-vm.ipath=$$VSPHERE_TEMPLATE_IPATH" \
		| grep ^cdrom- \
		| tail -n+2 \
		| awk '{print $$1}' \
		| xargs -L1 govc device.remove "-vm.ipath=$$VSPHERE_TEMPLATE_IPATH"
	@echo 'Converting to template...'
	govc vm.markastemplate "$$VSPHERE_TEMPLATE_IPATH"
	@echo BOX successfully built!
	@echo to add to local vagrant install do:
	@echo vagrant box add -f dummy-windows dummy-windows-vsphere.box

# Windows 10 1903 depends on the same autounattend as Windows 10
# This allows the use of pattern rules by satisfying the prerequisite
.PHONY: windows-10-1903/autounattend.xml

dummy-windows-vsphere.box: Vagrantfile.template
	echo '{"provider":"vsphere"}' >metadata.json
	cp Vagrantfile.template Vagrantfile
	tar cvf $@ metadata.json Vagrantfile
	rm metadata.json Vagrantfile

drivers:
	rm -rf drivers.tmp
	mkdir -p drivers.tmp
	@# see https://docs.fedoraproject.org/en-US/quick-docs/creating-windows-virtual-machines-using-virtio-drivers/index.html
	@# see https://github.com/virtio-win/virtio-win-guest-tools-installer
	@# see https://github.com/crobinso/virtio-win-pkg-scripts
	wget -P drivers.tmp https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.173-6/virtio-win-0.1.173.iso
	7z x -odrivers.tmp drivers.tmp/virtio-win-*.iso
	mv drivers.tmp drivers
