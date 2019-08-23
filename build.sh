#!/bin/bash
# File Name	: build.sh
# Purpose	: Build the Neoway android projects
# Usage		: ./build.sh <PROJECTS> [<userdebug/user>] [BUILD_TARGET]
# Author	: Neoway
# Date		: 2017.11.28

function usage()
{
	projects=$(ls device/nwy/ | tr ' ' '\n' | sed '/^$/d' | awk '{print "\t",NR".",$0}')
	
cat<<EOF

===========================================================

NAME
	build.sh - Build the Neoway Android projects

SYNOPSIS
	./build.sh <PROJECTS> [<userdebug/user>] [BUILD_TARGET]

PROJECTS
$projects

BUILD_TARGET
	kernel, aboot, etc.

EXAMPLES
	./build.sh N1
	./build.sh N1 user
	./build.sh N1 aboot
===========================================================

EOF
}

function custom_file_copy()
{
	project_dir=$1
	checkout=$2

	if [[ ! -e NWY_CUSTOM/$project_dir/ ]]
	then
		return 1
	fi

	if [[ $checkout -eq 0 ]]
	then
		printf "\n==============================================\n"
		printf "Copy $project_dir custom files\n"
		printf "==============================================\n"
		
		index1=0
		index2=0
		
		for file in $(find NWY_CUSTOM/$project_dir/ -type f | sed -e "s#NWY_CUSTOM/$project_dir/##g")
		do
			if [[ -e $file ]]
			then
				checkout_file[$index1]=$file
				index1=$((index1+1))
			else
				delete_file[$index2]=$file
				index2=$((index2+1))
			fi
			
			printf "copy $file ...\n"
		done
		cp -rf NWY_CUSTOM/$project_dir/* .
	else
		printf "\n==============================================\n"
		printf "Checkout $project_dir custom files\n"
		printf "==============================================\n"
		
		for file in ${checkout_file[@]}
		do
			git checkout $file
			printf "git checkout $file\n"
		done
		
		for file in ${delete_file[@]}
		do
			rm $file
			printf "rm $file\n"
		done
	fi
}

function is_nwy_project()
{
	projects=$(ls device/nwy/ | tr ' ' '\n' | sed '/^$/d' | awk '{print "\t",NR".",$0}')

	if [[ -z $(grep $build_pro <<< "$projects") ]]
	then
		printf "Not NWY projects !\n"
		exit 1
	fi
}

function signal_handler()
{
	custom_file_copy ${build_pro} 1
	exit 1
}

function cp_and_co_check()
{
	check=$1
	
	if [[ "$check" == "cp" ]]
	then
		for pj in $(ls device/nwy/)
		do
			if [[ -e ${pj}.ini ]] || [[ -e ${pj}.sh ]]
			then
				printf "Please checkout $pj custom files first!\n"
				exit 1
			fi
		done
		
		for file in $(find NWY_CUSTOM/${build_pro}/ -type f | sed -e "s#NWY_CUSTOM/${build_pro}/##g")
		do
			if [[ -e $file ]]
			then
				printf "git checkout $file\n" >> ${build_pro}.ini
				printf "printf \"git checkout $file\n\"\n" >> ${build_pro}.ini
			else
				printf "rm $file\n" >> ${build_pro}.ini
				printf "printf \"rm $file\n\"\n" >> ${build_pro}.ini
			fi
		done
		custom_file_copy ${build_pro} 0
		exit 1
	fi
	
	if [[ "$check" == "co" ]]
	then
		if [[ -e ${build_pro}.ini ]]
		then
			printf "\n==============================================\n"
			printf "Checkout ${build_pro} custom files\n"
			printf "==============================================\n"
			
			mv ${build_pro}.ini ${build_pro}.sh
			sed -i 's/\r$//' ${build_pro}.sh
			chmod a+x ${build_pro}.sh
			./${build_pro}.sh
			rm ${build_pro}.sh
		else
			printf "No ${build_pro}.ini Found!\n"
		fi
		exit 1
	fi
}

function need_cp_co()
{
	for pj in $(ls device/nwy/)
	do
		if [[ -e ${pj}.ini ]]
		then
			is_need_cp_co=0
			return 0
		fi
	done
	return 1
}

if [[ $# -lt 1 ]]
then
	usage && exit 1
fi

build_pro=$1
is_nwy_project
shift

cp_and_co_check $1

build_ver=userdebug
input_ver=$1

if [[ "$input_ver" == "user" ]]
then
	build_ver=user
	shift
fi

if [[ "$input_ver" == "userdebug" ]] || [[ "$input_ver" == "eng" ]]
then
	shift
fi

build_target=$1

if [[ -e ${build_pro}-${build_ver}_build.log ]]
then
	mv ${build_pro}-${build_ver}_build.log ${build_pro}-${build_ver}_build.log.old
fi

if [[ -e ${build_pro}-otapackage_build.log ]]
then
	mv ${build_pro}-otapackage_build.log ${build_pro}-otapackage_build.log.old
fi

is_need_cp_co=1
need_cp_co
if [[ ${is_need_cp_co} -eq 1 ]]
then
	custom_file_copy ${build_pro} 0
	trap 'signal_handler' SIGINT
fi


if [[ -e NWY_BUILD/platform_config.pl ]]
then
	perl NWY_BUILD/platform_config.pl ${build_pro}
fi

source build/envsetup.sh >/dev/null

lunch ${build_pro}-${build_ver}

if [[ "$build_target" == "kernelconfig" ]]
then
	make -j8 $@
elif [[ "$build_target" == "sdupdate" ]]
then
	make -j8 2>&1 | tee ${build_pro}-${build_ver}_build.log
	radio_path=device/nwy/${build_pro}/radio
	if [[ ! -e ${radio_path}/NON-HLOS.bin ]] || [[ ! -e ${radio_path}/sbl1.mbn ]] || [[ ! -e ${radio_path}/rpm.mbn ]] || [[ ! -e ${radio_path}/tz.mbn ]] || [[ ! -e ${radio_path}/hyp.mbn ]]
	then
		printf "Radio files are incomplete!\n"
	else
		if [[ -e out/target/product/${build_pro}/emmc_appsboot.mbn ]]
		then
			cp out/target/product/${build_pro}/emmc_appsboot.mbn ${radio_path}/
			make -j8 otapackage 2>&1 | tee ${build_pro}-otapackage_build.log
		fi
	fi
else
	make -j8 $@ 2>&1 | tee ${build_pro}-${build_ver}_build.log
fi

ret=$?

if [[ ${is_need_cp_co} -eq 1 ]]
then
	custom_file_copy ${build_pro} 1
fi

if [[ $ret -ne 0 ]]
then
	printf "\n==============================================\n"
	printf "    Build error, See ${build_pro}-${build_ver}_build.log !\n"
	printf "==============================================\n\n"
else
	printf "\n==============================================\n"
	printf "              Build finished !\n"
	printf "==============================================\n\n"
fi

