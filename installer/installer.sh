#!/bin/bash -i
#
# This is the installer of AVerMedia retail drivers.
#
# NOTE: Be very careful about aliases on cp, rm, and etc..
#       They can block this script and be very hard to debug!
#

# get absolute path of this script
BASE=`(cd \`dirname $0\`; pwd)`
DRIVERNAME=`grep DRIVERNAME $BASE/installer.config | awk 'BEGIN{FS="="}{print $2}'`
PRODUCTNAME=`grep PRODUCTNAME $BASE/installer.config | awk 'BEGIN{FS="="}{print $2}'`
KONAME=`grep KONAME $BASE/installer.config | grep -v USBKONAME | awk 'BEGIN{FS="="}{print $2}'`
USBKONAME=`grep USBKONAME $BASE/installer.config | awk 'BEGIN{FS="="}{print $2}'`
DRIVERVERSION=`grep DRIVERVERSION $BASE/installer.config | awk 'BEGIN{FS="="}{print $2}'`
INSTALLERARCH=`grep INSTALLERARCH $BASE/installer.config | awk 'BEGIN{FS="="}{print $2}'`

SOURCE=$BASE/src/$KONAME.ko
USBSOURCE=$BASE/src/$USBKONAME.ko
TARGET=/lib/modules/`uname -r`/kernel/drivers/media/dvb/dvb-usb/$KONAME.ko
USBTARGET=/lib/modules/`uname -r`/kernel/drivers/media/dvb/dvb-usb/$USBKONAME.ko
BACKTITLE="AVerMedia $DRIVERNAME Linux Driver Installer"
LOGF=/tmp/$PRODUCTNAME-install.log

# try our best to determine terminal window width
# first use stty
if [[ "$COLUMNS" == "" ]]; then
	COLUMNS=`stty -a | grep columns | awk 'BEGIN{FS=";"}{print $3}' | awk '{print $2}'`
fi
# if stty failes, use width of 80 columns.
if [[ "$COLUMNS" == "" ]]; then
	COLUMNS=80
fi

# try our best to determine terminal window height
# use stty again
if [[ "$LINES" == "" ]]; then
	LINES=`stty -a | grep rows | awk 'BEGIN{FS=";"}{print $2}' | awk '{print $2}'`
fi
# if stty failes, use height of 25 lines
if [[ "$LINES" == "" ]]; then
	LINES=24
fi

let WIDTH=${COLUMNS}-4
let FSHEIGHT=${LINES}-13

init_log()
{
	# gather system infomation
	local gccver=`gcc --version | head -n 1 2>/dev/null`
	local kerninfo=`uname -a 2>/dev/null`
	local distroinfo=""
	local make=`which make 2>/dev/null`
	local dialog=`which dialog 2>/dev/null`
	local dialogver=`dialog --version 2>/dev/null`
	local instversion=`cat $BASE/.version` #s004

	if [ -e /etc/redhat-release ]; then
		distroinfo=`cat /etc/redhat-release 2>/dev/null`
	elif [ -e /etc/mandriva-release ]; then
		distroinfo=`cat /etc/mandriva-release 2>/dev/null`
	elif [ -e /etc/SuSE-release ]; then
		distroinfo=`cat /etc/SuSE-release 2>/dev/null`
	elif grep DISTRIB_DESCRIPTION /etc/lsb-release >/dev/null 2>&1; then
		distroinfo=`grep DISTRIB_DESCRIPTION /etc/lsb-release \
				| awk 'BEGIN{FS="="}{print $2}'`
	else
		distroinfo=`cat /etc/issue | head -n 1 2>/dev/null`
	fi

	
	rm -f $LOGF
	log "Installer started"
	log "Installer version: $instversion" #s004
	log "System Info:"
	log "Kernel: $kerninfo"
	log "GCC: $gccver"
	log "Make: $make"
	log "Distribution: $distroinfo"
	log "EUID: $EUID"
	log "Dialog: $dialog"
	log "Dialog version: $dialogver"
	log "Screen size: Columns=$COLUMNS, Lines=$LINES"
	log "Basedir: $BASE"

    # s014, log ALSA info
    if [ -e /proc/asound/version ]; then
        log_from_file /proc/asound/version
    fi
    if [ -e /proc/asound/cards ]; then
        log_from_file /proc/asound/cards
    fi
    if [ -e /proc/asound/devices ]; then
        log_from_file /proc/asound/devices
    fi
    if [ -e /proc/asound/pcm ]; then
        log_from_file /proc/asound/pcm
    fi
}

log()
{
	local msg="$1"
	echo -e "$1" >> $LOGF
}

# append content of file to installer log
log_from_file()
{
	local file="$1"
	echo -e "===== $1 BEGIN HERE =====" >> $LOGF
    #s016+s
    if [ ! -e $file ]; then
    echo "$file does not exist!" >>$LOGF 2>/dev/null
    else
    cat $file >>$LOGF 2>/dev/null
    fi
    #s016+e
	echo -e "===== $1 END HERE =======" >> $LOGF
}

# append kernel configuration and current messages in "dmesg" to installer log
log_from_kernel()
{
	echo -e "===== kernel message BEGIN HERE =====" >> $LOGF
	dmesg >>$LOGF 2>/dev/null
	echo -e "===== kernel message END HERE =======" >> $LOGF

	echo -e "===== kernel config BEGIN HERE =====" >> $LOGF
	if [ -e /lib/modules/`uname -r`/build/.config ]; then
		cat /lib/modules/`uname -r`/build/.config >>$LOGF 2>/dev/null
	else
		echo "kernel config not available" >>$LOGF
	fi
	echo -e "===== kernel config END HERE =====" >> $LOGF
}

# delay/sleep for number of micro seconds
mysleep()
{
	local microsec="$1"
	if which usleep >/dev/null 2>&1 ; then
		usleep $microsec
	else
		sleep 1
	fi
}

# FUNCTION: generate postfix string for use in kernel-dependent object path
# IN: Arg1: path to kernel source
#     Arg2: path to kernel objects outputs (as in make O=/.../objdir)
# OUT: KVSTR KVVER
generate_kdep_string()
{
	local ksrc="$1"
	local kobj="$2"

	# extract kernel versions from makefile in $ksrc
	local kversion=`grep -e '^VERSION' $ksrc/Makefile 2>/dev/null | awk '{print $3}'`
	local kpatchlevel=`grep -e '^PATCHLEVEL' $ksrc/Makefile 2>/dev/null | awk '{print $3}'`
	local ksublevel=`grep -e '^SUBLEVEL' $ksrc/Makefile 2>/dev/null | awk '{print $3}'`

	KVVER="${kversion}.${kpatchlevel}.${ksublevel}"

    #s016+s
    # retry extraction from makefile in $kobj
	if [[ "$kversion" != "2" || "$kpatchlevel" != "6" ]]; then
	    kversion=`grep -e '^VERSION' $kobj/Makefile 2>/dev/null | awk '{print $3}'`
	    kpatchlevel=`grep -e '^PATCHLEVEL' $kobj/Makefile 2>/dev/null | awk '{print $3}'`
	    ksublevel=`grep -e '^SUBLEVEL' $kobj/Makefile 2>/dev/null | awk '{print $3}'`

	    KVVER="${kversion}.${kpatchlevel}.${ksublevel}"
    fi
    #s016+e

	if [[ "$kversion" != "2" || "$kpatchlevel" != "6" ]]; then
		dialog --backtitle "$BACKTITLE" \
		--title "Kernel version error" \
		--msgbox "Installer cannot determine kernel version or the running kernel is not 2.6.x kernel. \n\
Installer will abort now.
" \
		10 $WIDTH
		log "generate_kdep_string: wrong kernel version ${kversion}.${kpatchlevel}.${ksublevel}. Abort."
        log_from_file $ksrc/Makefile #s016
        log_from_file $kobj/Makefile #s016
		exit
	fi

	local regstr=""
	local memstr=""

	# on x86_64 kernels, register parameter and high memory is no longer supported and we do not
	# need it in the version string.
	if grep -e '^CONFIG_X86_64=y' $kobj/.config >/dev/null 2>&1; then
		KVSTR="x64"
	else
	# on x86 kernels, register parameter and high memory support are deciding factors
	# in the version string.

		# kernel 2.6.20 and later all use register parameter
		if [[ "$ksublevel" -ge "20" ]]; then
			regstr="REG"
		elif grep -e '^CONFIG_REGPARM=y' $kobj/.config >/dev/null 2>&1; then
			regstr="REG"
		else
			regstr=""
		fi

		if grep -e '^CONFIG_HIGHMEM4G=y' $kobj/.config >/dev/null 2>&1; then
			memstr="4G"
		elif grep -e '^CONFIG_HIGHMEM64G=y' $kobj/.config >/dev/null 2>&1; then
			memstr="64G"
		#s005, if high memory support is disabled, use 4G prebuilt objects
		elif grep -e '^CONFIG_NOHIGHMEM=y' $kobj/.config >/dev/null 2>&1; then
			memstr="4G"
		else
			log "generate_kdep_string: unknown highmem setting"
		fi

		KVSTR="${memstr}${regstr}"
	fi

	log "generate_kdep_string: KVSTR=$KVSTR"
	log "generate_kdep_string: KVVER=$KVVER"
	export KVSTR KVVER
}

select_kernel_best_match()
{
	local kver=`echo $KVVER | awk 'BEGIN{FS="."}{print $3}'`
	rm -f .kerns 
	# construct a list of kernel subversion
	#s001 for d in `find $BASE/src/kdep -type d -name '2.6.*' 2>/dev/null`; do
	for d in `find $BASE/kdep -type d -name '2.6.*' 2>/dev/null`; do
		echo `basename $d | awk 'BEGIN{FS="."}{print $3}'` >>.kerns 2>/dev/null
	done

	local largest=`sort -g .kerns | tail -n 1 2>/dev/null`
	local smallest=`sort -g .kerns | head -n 1 2>/dev/null`

	# find a best matching version to the running kernel
	if [ $kver -lt $smallest ]; then
		kver=$smallest
	elif [ $kver -gt $largest ]; then
		kver=$largest
	else 
		kver=$largest
		for k in `sort -g .kerns`; do
			if [ $kver -le $k ]; then
				kver=$k
				break
			fi
		done
	fi
	export KVVER="2.6.$kver"
}

# Select the most appropriate pre-built objects to use on target system
# and copy them into src directory to proceed to build ko.
select_module()
{
	local kernelsrc=/lib/modules/`uname -r`/source
	local kernelobj=/lib/modules/`uname -r`/build

	# workaround for distributions lacking /lib/modules/kern/source
	# such as Ubuntu 7.10
	if [ ! -e $kernelsrc ]; then
		ln -f $kernelobj $kernelsrc
	fi

	# retrieve KVSTR and KVVER
	generate_kdep_string $kernelsrc $kernelobj

	# copy prebuild files
	# s003, only copy if this directory exists
	if [ -e $BASE/prebuild/OBJ-$KVSTR ]; then
		\cp -rf $BASE/prebuild/OBJ-$KVSTR/* src/ >/dev/null 2>.err
        	if [[ "$?" != "0" ]]; then
                	dialog --backtitle "$BACKTITLE" --title \
			"ERROR: Failed to copy files" --textbox .err  20 $WIDTH
        	        clear
                	exit
	        fi									fi

	# if we do not have binary for this kernel, try the best match
	if [ ! -e $BASE/kdep/$KVVER ]; then
		# return best match kernel in KVVER
		select_kernel_best_match
	fi

	# copy kernel dependent prebuild files
	# s003, only copy if this directory exists
	if [ -e $BASE/kdep/$KVVER/OBJ-$KVSTR ]; then
		\cp -rf $BASE/kdep/$KVVER/OBJ-$KVSTR/* src/ >/dev/null 2>.err
        	if [[ "$?" != "0" ]]; then
                	dialog --backtitle "$BACKTITLE" --title \
			"ERROR: Failed to copy files" --textbox .err  20 $WIDTH
        	        clear
                	exit
	        fi
	fi
}

# old version of select_module, obsolete.
select_module_old()
{
	local options=""
	local target
	local KERNELVER=`uname -r`
	
	log "Selecting module"

	# find matching .ko by version magic
	for ko in `find $BASE/ -name $KONAME.ko`; do
		KOVER=`modinfo $ko | grep -e '^vermagic:' | awk '{print $2}'`
		if [[ $KERNELVER == $KOVER ]]; then
			target=`dirname $ko`
			break;
		fi
	done

	# target found, copy files
	if [[ $target != "" ]]; then
		log "Module for $KERNELVER selected"

	        # copy distribution files based on the answer
	        \cp -ar $target/* $BASE/src/. >/dev/null 2>.err
	        if [[ "$?" != "0" ]]; then
	                dialog --backtitle "$BACKTITLE" --title \
			"ERROR: Failed to prepare build" --textbox .err  20 $WIDTH
	                clear
	                exit
	        fi									
	else 
		log "No PreBuild .ko for $KERNELVER"
	fi

        # copy all prebuilt objects, we may need them later
        \cp -ar OBJ-* $BASE/src/. >/dev/null 2>.err

	log "prebuild $SUF1$SUF2 selected."
}

# this routine builds ko and presents a progress bar.
build_driver()
{
	# let user select which distribution to install
	# and prepare building environment.
	select_module

	# check if the running kernel matchs the precompiled .ko
	# if they match, present the user the option to skip the compilation and
	# install it directly.
	if [[ -e $SOURCE ]]; then
		local kernel=`uname -r`
		local kover=`modinfo $SOURCE | grep -e '^vermagic:' | awk '{print $2}'`

		if [[ "$kernel" == "$kover" ]]; then

			log "Pre-built driver found"
			dialog --backtitle "$BACKTITLE" \
			--title "Driver found" \
			--yesno "Installer found that your current kernel is \"$kernel\"\nand it matches one of the precompiled drivers.\n\nDo you want to install the precompiled driver directly?" \
			10 $WIDTH

			# skip the building process
			if [[ "$?" == "0" ]]; then
				log "User chose to install prebuilt driver"
				return
			fi

		fi
	fi

	log "Building driver on-site"
	# build driver in the background
	pushd . >/dev/null 2>&1
	cd $BASE/src
	\rm -f .built
	((make clean ; make ) >/dev/null 2>.err ; touch .built) >/dev/null 2>&1 &

	# display fake progress bar
	( for((i=0;i<5;++i)); do 
		mysleep 1000000
		if [ -e .built ] ; then # break early if build completed
			break;
		fi
		let j=i*18;
		let j=j+18;
		echo $j;
	  done
	) | dialog --backtitle "$BACKTITLE" --title "Preparing installation" \
	--gauge "\nPreparing driver install, please wait a moment..." 7 $WIDTH 0

	# complete progress bar when compilation is done
	while [ ! -e .built ]; do
		mysleep 500000
	done

	if [[ ! -e "$SOURCE" || ! -e "$USBSOURCE" ]] ; then

		ls -al $SOURCE >>.err 2>&1
		ls -al $USBSOURCE >>.err 2>&1

		log "Building driver failed, error log follows"
		log_from_file .err
	    log_from_kernel #s017

		# if build failed, prompt user with possible causes and
		# offer to see the error log.
		dialog --backtitle "$BACKTITLE" --title "ERROR: driver preparation failed" \
		--yesno "Installer failed to prepare driver installation \
\nThis may be due to:\n\
\n1. The kernel source of the running kernel is not installed.\
\n   The package of kernel source is named like \"kernel-source\"\
\n   or \"kernel-devel\". Please consult your system manual.\n\
\n2. You have selected a wrong distribution. Try another one.\n\
\n3. Your kernel is not supported by our driver. If this is the case,\
\n   \"Expert\" mode installation might be an option.\n\n\
\n   The installer have an error log which might help you \
\n   identify the issue. Do you want to see it?\n" \
		40 $WIDTH

		if [[ "$?" == "0" ]]; then
			dialog --backtitle "$BACKTITLE" --title "Error log" \
			--textbox .err  20 $WIDTH
		fi
	else
		echo "100" | dialog --backtitle "$BACKTITLE" --title "Preparing installation" \
		--gauge "\nDriver preparation completed." 7 $WIDTH 
		mysleep 500000
	fi

	popd >/dev/null 2>&1
}

#s006+s
rename_old_driver()
{
#s008	local targets=`find /lib/modules/\`uname -r\`/kernel -name ${KONAME}.ko`
	local targets
	if [ "$USBKONAME" == "" ]; then
		targets=`find /lib/modules/\`uname -r\`/kernel -name ${KONAME}.ko`
	else
		# s012, also search for averusb.ko because in newer installers this 
		#       ko can have an additional suffix coming from the driver name.
		targets=`find /lib/modules/\`uname -r\`/kernel -name ${KONAME}.ko \
			-or -name ${USBKONAME}.ko -or -name averusb.ko`
	fi

	# rename all old drivers we can find.
	# we can fall for this if user has relocated previously installed driver, and
	# installer do not rename this relocated driver.
	for ko in $targets ; do

		oldver=`modinfo $ko | grep 'description' | awk 'BEGIN{FS=" "}{print $NF}'`

		dialog --backtitle "$BACKTITLE" \
		--title "Removing old driver $oldver" \
		--infobox "Rename kernel modules" 7 $WIDTH

		# rename installed driver
		log "Rename ${ko} to ${ko}.${oldver}"
		\mv -f $ko ${ko}.${oldver} >.err 2>&1
		if [[ "$?" != "0" ]]; then
			log "Rename failed, error log follows"
			log_from_file .err
			dialog --backtitle "$BACKTITLE" \
			--title "ERROR: Installer cannot rename old driver" \
			--textbox .err 20 $WIDTH 
			clear
			exit
		fi

	done

}
#s006+e

#s006, renamed to rename_old_driver_old and went obsolete.
rename_old_driver_old()
{
	OLDVER=`modinfo $TARGET | grep 'description' | awk 'BEGIN{FS=" "}{print $NF}'`

	dialog --backtitle "$BACKTITLE" \
	--title "Removing driver" \
	--infobox "Rename kernel modules" 7 $WIDTH

	# rename installed driver
	log "Rename $TARGET to ${TARGET}.${OLDVER}"
	\mv -f $TARGET ${TARGET}.${OLDVER} >.err 2>&1
	if [[ "$?" != "0" ]]; then
		log "Rename failed, error log follows"
		log_from_file .err
		dialog --backtitle "$BACKTITLE" \
		--title "ERROR: Installer cannot rename installed driver" \
		--textbox .err 20 $WIDTH 
		clear
		exit
	fi
}


# This routine installs the driver built in the previous steps and presents 
# UI to user.
install_built_driver()
{
	log "Installing built driver to $TARGET"

	dialog --backtitle "$BACKTITLE" \
	--title "Installing driver" \
	--infobox "Copying kernel modules ..." 7 $WIDTH

	install -d `dirname $TARGET` >/dev/null 2>.err && \
	install -o root -m 644 "$SOURCE" "$TARGET" >/dev/null 2>.err && \
	install -o root -m 644 "$USBSOURCE" "$USBTARGET" >/dev/null 2>.err && \
	mysleep 500000 

	if [[ "$?" != "0" ]]; then
		log "Driver install failed, error log follows"
		log_from_file .err
		dialog --backtitle "$BACKTITLE" \
		--title "ERROR: Driver installation failed" \
		--textbox .err 20 $WIDTH
		clear
		exit
	fi

	dialog --backtitle "$BACKTITLE" \
	--title "Installing driver" \
	--infobox "Rebuilding kernel module dependencies" 7 $WIDTH
	
	log "Rebuild module dependencies"
	depmod >/dev/null 2>.err && \
	mysleep 500000

	if [[ "$?" != "0" ]]; then
		log "Module dependency rebuild failed, error log follows"
		log_from_file .err
		dialog --backtitle "$BACKTITLE" \
		--title "ERROR: Failed rebuilding module dependencies." \
		--textbox .err 20 $WIDTH
		clear
		exit
	fi
}

# check if currently installed driver is already of the same version as the installer.
# if so, ask user if he wants to continue upgrading.
check_driver_version()
{
	log "Check installed driver version"
	if [ ! -e $BASE/.version ]; then
		return
	fi

	OLDVER=`modinfo $TARGET | grep 'description' | awk 'BEGIN{FS=" "}{print $NF}' | sed 's/v//g'`
	NEWVER=`cat $BASE/.version`

	log "Old version: $OLDVER, new version: $NEWVER"

	if [[ "$OLDVER" == "$NEWVER" ]]; then
		dialog --backtitle "$BACKTITLE" \
		--title "WARNING: Upgrading the same version of driver." \
		--yesno "Installer discovered that the currently installed driver \
is already the newest version: \"$NEWVER\".\n\nDo you still want to upgrade?" 10 $WIDTH

		if [[ "$?" != "0" ]]; then
			log "User abort installation"
			clear
			exit
		fi
	fi

}

# upgrading driver.
# 1. check if version of already the same
# 2. build driver
# 3. rename old driver
# 4. install new driver
upgrade_driver()
{
	check_driver_version

	log "Try to upgrade driver"
	while /bin/true; do
	
		\rm -f $SOURCE
		build_driver

		# if driver building failed, offer another chance
#s009		if [[ ! -e "$SOURCE" || ! -e "USBSOURCE" ]]; then
		if [[ ! -e "$SOURCE" || ! -e "$USBSOURCE" ]]; then #s009
			dialog --backtitle "$BACKTITLE" --title "Try again?" \
			--yesno "Driver building has failed, do you wish to try again?" 7 $WIDTH

			if [[ "$?" == "0" ]]; then
				log "retry after driver building failed"
				continue;
			else
				clear
				exit
			fi
		fi
	
		rename_old_driver
		mysleep 500000

		install_built_driver

		# notify the user if driver cannot be unloaded
		log "Try to unload driver"
		rmmod $KONAME >/dev/null 2>&1
		rmmod $USBKONAME >/dev/null 2>&1
		lsmod | grep $KONAME >/dev/null 2>&1
		if [[ "$?" == "0" ]]; then
			log "Cannot unload driver"
			dialog --backtitle "$BACKTITLE" \
			--title "" \
			--msgbox "Please note that AVerMedia $DRIVERNAME driver is currently loaded.\
\nIf you wish to use the newly installed driver, please do one of the following: \n\
\n 1. Reboot your system.\
\n 2. Manually unload and reload $DRIVERNAME driver by using 'rmmod' and 'modprobe' command" 20 $WIDTH 

			break # break out of while loop
		else
			log "Try reload driver"
			modprobe $KONAME >/dev/null 2>.err
			if [[ "$?" == "0" ]]; then
				log "Reload driver succeeded"
				break
			fi

			# driver failed to load, inform user and offer another chance
			log "Reload driver failed, error log follows"
			log_from_file .err
			log_from_kernel
			dialog --backtitle "$BACKTITLE" \
			--title "ERROR: Failed loading driver" \
			--textbox .err 20 $WIDTH

			dialog --backtitle "$BACKTITLE" \
			--title "Try again?" \
			--yesno "Do you wish try again?" 7 $WIDTH
			if [[ "$?" == "0" ]]; then
				log "retry after driver reload failed"
				continue;
			else
				clear
				exit
			fi
		fi

	done # end of while loop

	log "Upgrade completed"
	log_from_kernel
	dialog --backtitle "$BACKTITLE" \
	--title "Driver upgrade completed" \
	--msgbox "$DRIVERNAME Linux Driver is successfully upgraded." 7 $WIDTH

	if [ -e $BASE/tools ]; then
		install_tools
	fi
}

# remove currently installed driver
# 1. rename installed driver 
# 2. unload driver if it is loaded
# this will guarantee installation of new driver goes smoothly later.
remove_driver()
{
	rename_old_driver
	mysleep 500000
	
	# rebuild module dependency
	dialog --backtitle "$BACKTITLE" \
	--title "Removing driver" \
	--infobox "Rebuilding kernel module dependencies" 7 $WIDTH
	depmod >/dev/null 2>&1
	mysleep 500000

	# notify the user if driver is already loaded.
	rmmod $KONAME >/dev/null 2>&1
	lsmod | grep $KONAME >/dev/null 2>&1
	if [[ "$?" == "0" ]]; then
		log "cannot unload driver"
		dialog --backtitle "$BACKTITLE" \
		--title "" \
		--msgbox "Please note that $DRIVERNAME driver is currently loaded.\
\nIf you wish to truely disable the driver, do one of the following: \n\
\n 1. Reboot your system.\
\n 2. Manually unload $DRIVERNAME driver by using 'rmmod' command" 20 $WIDTH 

	fi

	dialog --backtitle "$BACKTITLE" \
	--title "Driver is removed" \
	--msgbox "$DRIVERNAME driver is successfully removed." 7 $WIDTH

	log "Driver removed"
}

ask_upgrade_or_remove()
{
	OLDVER=`modinfo $TARGET | grep 'description' | awk 'BEGIN{FS=" "}{print $NF}'`

	log "Ask user to choose upgrade or remove"
	dialog --backtitle "$BACKTITLE" --title "Upgrade or remove?" --menu \
	"$DRIVERNAME driver $OLDVER is already installed for the running kernel. \
\nDo you wish to upgrade or remove the installed driver?\n" 15 $WIDTH 3 \
	"Upgrade" "Upgrade to newest driver. Old driver will be renamed." \
	"Remove" "Disable and rename installed driver." \
	"Install Tools" "Only install the tools." 2>.ans

	if [[ "$?" != "0" ]]; then
		clear
		exit
	fi

	ans=`cat .ans`
	if [[ "$ans" == "Upgrade" ]] ; then
		log "User choose to upgrade driver"
		upgrade_driver
	elif [[ "$ans" == "Remove" ]] ; then
		log "User choose to remove driver"
		remove_driver
	elif [[ "$ans" == "Install Tools" ]] ; then
		log "User choose to install tools"
		install_tools
	fi
} 

# install driver, without considering the existence of old driver.
install_driver()
{
#	dialog --backtitle "$BACKTITLE" --yes-label "OK" --no-label "Cancel" \
#	--yesno "Installer will now proceed to building and installing $DRIVERNAME driver." 7 $WIDTH

#	if [[ "$?" != "0" ]]; then
#		clear
#		exit
#	fi
	
	log "Install New Driver"
	while /bin/true; do
	
		\rm -f $SOURCE
		build_driver

		# if driver building failed, offer another chance
		if [ ! -e $SOURCE ]; then
			log "Driver Building failed"
			dialog --backtitle "$BACKTITLE" \
			--title "Try again?" \
			--yesno "Driver building has failed, do you wish to try again?" 7 $WIDTH

			if [[ "$?" == "0" ]]; then
				# try another distribution
				log "retry after driver building failed"
				continue;
			else
				log "User abort after driver building failed"
				clear
				return
			fi
		fi
		
		install_built_driver

		modprobe $KONAME >/dev/null 2>.err
		# break if succeeded
		if [[ "$?" == "0" ]]; then
			log "Module loaded successfully"
			break
		fi
		log "Module load failed"
		log_from_kernel

		# driver failed to load, inform user and offer another chance
		dialog --backtitle "$BACKTITLE" \
		--title "ERROR: Failed loading driver" \
		--textbox .err 20 $WIDTH

		dialog --backtitle "$BACKTITLE" \
		--title "Try again?" \
		--yesno "Driver loading failed. Do you wish to try again?" 7 $WIDTH
		if [[ "$?" == "0" ]]; then
			# try another distribution
			log "retry after driver loading failed"
			continue;
		else
			# abort
			log "Loading driver failed, User abort"
			clear
			return
		fi

	done # end of while loop

	dialog --backtitle "$BACKTITLE" \
	--title "Driver Installation Completed" \
	--msgbox "$DRIVERNAME Linux Driver is successfully installed. \
\n\n$DRIVERNAME driver should be loaded automatically everytime the device\
\nis plugged in. If $DRIVERNAME device is already plugged in, please remove it\
 and re-plug it." 20 $WIDTH

 	log "Driver install completed"
	log_from_kernel

}

# this routine does expert installation, which is almost the same as installing driver, except
# that driver is not built by invoking the makefile.
# this leaves room for experts and kernel hackers to fix our driver if it is broken in future
# releases of kernels or vendor-modified kernels.
expert_installation()
{
	while /bin/true; do
	
		dialog --backtitle "$BACKTITLE" \
		--title "Select a directory for expert installation" \
		--fselect / $FSHEIGHT $WIDTH 2>.dir

		if [[ "$?" != "0" ]]; then
			clear
			exit
		fi

		local dir=`cat .dir 2>/dev/null`

		if [[ "$dir" == "" ]]; then
			continue;
		fi

		# clean it up
		rm -rf $dir/$PRODUCTNAME-expert-install
		mkdir -p $dir/$PRODUCTNAME-expert-install

		break;
	done # end of while loop

	log "$dir selected for expert installation"

	select_module
	
	\cp -ar $BASE/src/* $dir/$PRODUCTNAME-expert-install/. >/dev/null 2>.err &&
	\cp $BASE/README $dir/$PRODUCTNAME-expert-install/${PRODUCTNAME}_LinuxDrv_ReleaseNotes_${DRIVERVERSION}-Beta.txt \
>/dev/null 2>.err

	if [[ "$?" != "0" ]]; then

		log "Fail to extract expert files, error log follows"
		log_from_file .err
	
		dialog --backtitle "$BACKTITLE" \
		--title "ERROR: Cannot extract files for expert install" \
		--textbox .err 20 $WIDTH

		return
	fi

	log "Expert install succeeded"
	log_from_kernel
	dialog --backtitle "$BACKTITLE" \
	--title "Expert installation completed" \
	--msgbox "Driver package is extracted to \"$dir/$PRODUCTNAME-expert-install\". \n\
\nTo build $DRIVERNAME driver, type \"make\" under that directory.\
\nIf build succeeded, the driver is located at \"$dir/$PRODUCTNAME-expert-install/$KONAME.ko\" and \n\
\"$dir/$PRODUCTNAME-expert-install/$USBKONAME.ko\"." \
	11 $WIDTH
}


# install some TV tools, which are very simple tools used to verify our driver is working.
# this is because not all TV players are 100% complatible with our driver and we must have
# a way for edvanced users to confirm issues if they arises.
install_tools()
{
	# if there is no tool, do not proceed to install
	if [ ! -e $BASE/tools ]; then
		dialog --backtitle "$BACKTITLE" \
		--title "Tools installation not available" \
		--msgbox "This product has no additional software tools to install." \
		10 $WIDTH
		log "Tools install un-necessary"
		return
	else
		dialog --backtitle "$BACKTITLE" \
		--title "Tools Installation" \
		--msgbox "This product has some additional software tools to install. \n\
Please note that these tools are provided in source code format and only \n\
serves as examples to developing TV applications for use on AVerMedia TV tuners. \n\
They are not intended to be used directly by average users. \n\n\
Please select a directory to install.\n" \
		7 $WIDTH

		# user abort using ctrl+c
		if [[ "$?" != "0" ]]; then
			clear
			exit
		fi
	fi

	while /bin/true; do
		dialog --backtitle "$BACKTITLE" \
		--title "Select a directory for tools installation" \
		--fselect / $FSHEIGHT $WIDTH 2>.dir

		# user abort using ctrl+c
		if [[ "$?" != "0" ]]; then
			clear
			exit
		fi

		local dir=`cat .dir 2>/dev/null`
		if [[ "$dir" == "" ]]; then
			continue;
		fi

		break;
	done # end of while loop

	mkdir -p $dir/${PRODUCTNAME}-tools/ >/dev/null 2>.err && \ #s011  #s010
	cp -ar $BASE/tools/* $dir/${PRODUCTNAME}-tools/. >/dev/null 2>>.err #s010

	if [[ "$?" != "0" ]]; then
		log "Fail to extract tools file, error log follows"
		log_from_file .err

		dialog --backtitle "$BACKTITLE" \
		--title "ERROR: Cannot extract files for tools installation" \
		--textbox .err 20 $WIDTH

		return
	fi

	log "Tools install succeeded"
	dialog --backtitle "$BACKTITLE" \
	--title "Tools installation completed" \
	--msgbox "TOOLS is extracted to \"$dir/$PRODUCTNAME-tools\". \n\
\nTo build TOOLS, type \"make\" under that directory."\
	10 $WIDTH

	if [ -x $dir/$PRODUCTNAME-tools/audio-test.sh ]; then

		log "Ask to run audio test"
		dialog --backtitle "$BACKTITLE" \
		--title "Audio test" \
		--yesno "Installer can help you test TV audio to make sure it works.\n\
Do you want to run this audio test tool?\n\n\
If you choose not to, this tool is still available at:\n\
$dir/$PRODUCTNAME-tools/audio-test.sh\n"\
		11 $WIDTH

		if [[ "$?" == "0" ]]; then
			/bin/bash -i $dir/$PRODUCTNAME-tools/audio-test.sh
		fi	

	fi
}

welcome()
{
	local kernel=`uname -r`
	local products=`cat $BASE/.supported-products`
	
	if [ $(uname -a | grep -c "x86_64") -eq 1 ]; then
		export CURRARCH="x64"
		arch="64bit Linux"
	else
		export CURRARCH="x86"
        	arch="32bit Linux"
	fi

	log "Show Welcome Screen"

	dialog --backtitle "$BACKTITLE" \
	--title "Welcome to AVerMedia $DRIVERNAME Linux driver installer." \
	--msgbox "This installer will install/upgrade $DRIVERNAME driver\nfor the running kernel.\n\n\
$products \n\
\nYou are using: $arch \
\n \
\nYour running kernel: $kernel \
" 20 $WIDTH

	if [[ "$?" != "0" ]]; then
		clear
		exit
	fi

	# check if root
	log "check if root: EUID=$EUID"
	if [[ "$EUID" != "0" ]]; then

		dialog --backtitle "$BACKTITLE" \
		--title "ERROR: " \
		--msgbox \
		"You must be root to run installer. \
\nPlease login as root or use 'su' or 'sudo' to abtain root privilege. \
\nInstaller will now abort." 10 $WIDTH
		clear
		exit
	fi

	# check kernel source
	local kernelsrc=/lib/modules/`uname -r`/source
	local kernelobj=/lib/modules/`uname -r`/build
	log "check kernel source : $kernelsrc"
	log "check kernel build : $kernelobj"
	if [[ ! -e $kernelobj ]]; then
		dialog --backtitle "$BACKTITLE" \
		--title "ERROR: " \
		--msgbox "Kernel headers is not installed on this computer.\
\nThe folder \"$kernelobj\" does not exist.\
\nPlease install a package named \"kernel-devel\" or \"linux-devel\". \
" 10 $WIDTH
        clear #s013
        exit  #s013
	fi

	# check if architecture fits
	log "check architecture, current is $CURRARCH, installer is $INSTALLERARCH"
	if [[ "$INSTALLERARCH" != "$CURRARCH" ]]; then
		local correctarch
		if [[ "$CURRARCH" == "x86" ]]; then
			correctarch="32bit Linux"
		else
			correctarch="64bit Linux"
		fi
		local installerarch
		if [[ "$INSTALLERARCH" == "x86" ]]; then
			installerarch="32bit Linux"
		else
			installerarch="64bit Linux"
		fi
		dialog --backtitle "$BACKTITLE" \
		--title "ERROR: " \
		--msgbox "This installer is for $installerarch only. \
\nPlease use the correct installer for $correctarch.\n \
" 10 $WIDTH
		clear
		exit
	fi

	# show EULA
	# adjust window size for optimal look
	log "show EULA"
	local beginy1=2
	let halfwidth=${WIDTH}/2
	let beginx=${COLUMNS}/2
	let beginx=${beginx}-$halfwidth
	let height=${LINES}-9
	let width=${WIDTH}
	let beginy2=$beginy1+$height+1
	
	dialog --no-shadow  --backtitle "$BACKTITLE" \
	--title "End User License Agreement" \
	--exit-label "OK" --begin $beginy1 $beginx \
	--textbox $BASE/EULA $height $width \
	--and-widget  \
	--defaultno --begin $beginy2 $beginx \
	--yesno "Do you agree to the license agreement?" 5 $width

	if [[ "$?" != "0" ]]; then
		clear
		exit
	fi
}

check_modules()
{
        local  af_dvb=/lib/modules/`uname -r`/kernel/drivers/media/AF901X/dvb-core.ko
	local  af_dvb_tmp=/lib/modules/`uname -r`/kernel/drivers/media/AF901X/dvb-core.ko.tmp

	rmmod $KONAME >/dev/null 2>&1
	rmmod dvb-core videodev >/dev/null 2>&1

        if [ -e $af_dvb ]; then
		\mv -f $af_dvb $af_dvb_tmp >/dev/null 2>&1
		return
        fi
}

# =======================================================
# Script Starts here

# for depmod and administrator stuff
export PATH="$PATH:/sbin:/usr/sbin"

# init log file
init_log

if ! which dialog >/dev/null 2>&1; then
	echo "\"dialog\" is not installed on this system. Press [enter] to abort."
	log "\"dialog\" is not installed on this system. Press [enter] to abort."
	read ans
	exit
fi

welcome

log "Select Install Method"
dialog --backtitle "$BACKTITLE" --menu \
"Please select an installation method" 10 $WIDTH 2 \
"Normal" "Automatic installation. Recommended for most users" \
"Expert" "Extract drivers to selected location. For kernel hackers only" 2>.ans

# user abort using ctrl+c
if [[ "$?" != "0" ]]; then
	clear
	exit
fi

ans=`cat .ans`
if [[ "$ans" == "Expert" ]] ; then

	log "Expert Install Selected"
	expert_installation

	install_tools

else #if [[ "$ans" == "Normal" ]] ; then

	check_modules

	log "Normal Install Selected"
	if [[ -e "$TARGET" ]]; then
		ask_upgrade_or_remove
	else
		install_driver
		if [ -e $BASE/tools ]; then
		install_tools
		fi
	fi
fi

log "Installer finished"
clear
exit

