#!/system/bin/sh

local_file_path="$0"
local_file_parent=$(dirname "${local_file_path}")
local_file_parent=$(cd "${local_file_parent}"||exit; pwd)
# shellcheck source=android/scripts/common.sh
. "${local_file_parent}/common.sh"

local_tmp="/data/local/tmp/"
dir_boottime_data="${local_tmp}/boottime"
F_RAW_DATA_CSV="${dir_boottime_data}/boot_time_raw_data.csv"
F_STATISTIC_DATA_CSV="${dir_boottime_data}/boot_time_statistic_data.csv"


# dmeg line example
# [    7.410422] init: Starting service 'logd'...
getTime(){
    key=$1
    if [ -z "${key}" ]; then
        return
    fi

    key_line=$(grep "${key}" "${LOG_DMESG}")
    if [ -n "${key_line}" ]; then
        timestamp=$(echo "${key_line}"|awk '{print $2}' | awk -F "]" '{print $1}')
        echo "${timestamp}"
    fi
}

getBootTimeInfoFromDmesg(){
    COLLECT_NO=$1

    LOG_LOGCAT_ALL="${dir_boottime_data}/logcat_all_${COLLECT_NO}.log"
    LOG_DMESG="${dir_boottime_data}/dmesg_${COLLECT_NO}.log"

    # dmesg starts before all timers are initialized, so kernel reports time as 0.0.
    # we can't work around this without external time metering.
    # here we presume kernel message starts from 0
    CONSOLE_SECONDS_START=0
    CONSOLE_SECONDS_END=$(getTime "Freeing unused kernel memory")
    if [ ! -z "${CONSOLE_SECONDS_END}" ] && [ ! -z "${CONSOLE_SECONDS_START}" ]; then
        CONSOLE_SECONDS=$(echo "$CONSOLE_SECONDS_END $CONSOLE_SECONDS_START - p" | dc)
        output_test_result "KERNEL_BOOT_TIME" "pass" "${CONSOLE_SECONDS}" "s"
    else
        output_test_result "KERNEL_BOOT_TIME" "fail" "-1" "s"
    fi

    POINT_FS_MOUNT_START=$(getTime "Freeing unused kernel memory:"|tail -n1)
    POINT_FS_MOUNT_END=$(getTime "init: Starting service 'logd'...")
    if [ ! -z "${POINT_FS_MOUNT_END}" ] && [ ! -z "${POINT_FS_MOUNT_START}" ]; then
        FS_MOUNT_TIME=$(echo "${POINT_FS_MOUNT_END} ${POINT_FS_MOUNT_START} - p" | dc)
        output_test_result "FS_MOUNT_TIME" "pass" "${FS_MOUNT_TIME}" "s"
    else
        output_test_result "FS_MOUNT_TIME" "fail" "-1" "s"
    fi

    POINT_FS_DURATION_START=$(getTime "init: /dev/hw_random not found"|tail -n1)
    POINT_FS_DURATION_END=$(getTime "init: Starting service 'logd'...")
    if [ ! -z "${POINT_FS_DURATION_END}" ] && [ ! -z "${POINT_FS_DURATION_START}" ]; then
        FS_MOUNT_DURATION=$(echo "${POINT_FS_DURATION_END} ${POINT_FS_DURATION_START} - p" | dc)
        output_test_result "FS_MOUNT_DURATION" "pass" "${FS_MOUNT_DURATION}" "s"
    else
        output_test_result "FS_MOUNT_DURATION" "fail" "-1" "s"
    fi

    POINT_SERVICE_BOOTANIM_START=$(getTime "init: Starting service 'bootanim'..."|tail -n1)
    POINT_SERVICE_BOOTANIM_END=$(getTime "init: Service 'bootanim'.* exited with status"|tail -n1)
    if [ ! -z "${POINT_SERVICE_BOOTANIM_END}" ] && [ ! -z "${POINT_SERVICE_BOOTANIM_START}" ]; then
        BOOTANIM_TIME=$(echo "${POINT_SERVICE_BOOTANIM_END} ${POINT_SERVICE_BOOTANIM_START} - p" | dc)
        output_test_result "BOOTANIM_TIME" "pass" "${BOOTANIM_TIME}" "s"
    else
        output_test_result "BOOTANIM_TIME" "fail" "-1" "s"
    fi

    ## When there are 2 lines of "Boot is finished",
    ## it mostly means that the surfaceflinger service restarted by some reason
    ## but here when there are multiple lines of "Boot is finished",
    ## use the last one line, and report the case later after checked all the logs
    TIME_INFO=$(grep "Boot is finished" "${LOG_LOGCAT_ALL}"|tail -n1)
    if [ -z "${TIME_INFO}" ]; then
        output_test_result "ANDROID_BOOT_TIME" "fail" "-1" "s"
    else
        while echo "${TIME_INFO}"|grep -q "("; do
            TIME_INFO=$(echo "${TIME_INFO}"|cut -d\( -f2-)
        done
        TIME_VALUE=$(echo "${TIME_INFO}"|cut -d\  -f1)
        ANDROID_BOOT_TIME=$(echo "${TIME_VALUE}" | awk '{printf "%.3f",$1/1000;}')
        output_test_result "ANDROID_BOOT_TIME" "pass" "${ANDROID_BOOT_TIME}" "s"
    fi

    SERVICE_START_TIME_INFO=$(grep "healthd:" "${LOG_DMESG}"|head -n 1)
    SERVICE_START_TIME_END=$(echo "$SERVICE_START_TIME_INFO"|cut -d] -f 1|cut -d[ -f2| tr -d " ")
    if [ ! -z "${SERVICE_START_TIME_END}" ] && [ ! -z "${CONSOLE_SECONDS_START}" ]; then
        SERVICE_START_TIME=$(echo "$SERVICE_START_TIME_END $CONSOLE_SECONDS_START - p" | dc)
        output_test_result "ANDROID_SERVICE_START_TIME" "pass" "${SERVICE_START_TIME}" "s"
    else
        output_test_result "ANDROID_SERVICE_START_TIME" "fail" "-1" "s"
    fi

    if [ ! -z "${CONSOLE_SECONDS}" ] && [ ! -z "${TIME_VALUE}" ]; then
        TOTAL_SECONDS=$(echo "$CONSOLE_SECONDS $TIME_VALUE" | awk '{printf "%.3f",$1 + $2/1000;}')
        output_test_result "TOTAL_BOOT_TIME" "pass" "${TOTAL_SECONDS}" "s"
    else
        output_test_result "TOTAL_BOOT_TIME" "fail" "-1" "s"
    fi
}

OPERATION=$1
if [ "X${OPERATION}" = "XCOLLECT" ]; then
    G_VERBOSE_OUTPUT=FALSE
    G_RECORD_LOCAL_CSV=FALSE
    COLLECT_NO=$2
    mkdir -p ${dir_boottime_data}

    # shellcheck disable=SC2035
    logcat -d -v time *:V > "${dir_boottime_data}/logcat_all_${COLLECT_NO}.log"
    output_test_result "BOOTTIME_LOGCAT_ALL_COLLECT" "pass"
    logcat -d -b events -v time > "${dir_boottime_data}/logcat_events_${COLLECT_NO}.log"
    output_test_result "BOOTTIME_LOGCAT_EVENTS_COLLECT" "pass"
    dmesg > "${dir_boottime_data}/dmesg_${COLLECT_NO}.log"
    output_test_result "BOOTTIME_DMESG_COLLECT" "pass"
elif [ "X${OPERATION}" = "XANALYZE" ]; then
    count=$2
    ## Check if there is any case that the surfaceflinger service
    ## was started several times
    i=1
    service_started_once=true
    while ${service_started_once}; do
        if [ $i -gt "$count" ]; then
            break
        fi
        ## check the existence of "Boot is finished"
        LOG_LOGCAT_ALL="${dir_boottime_data}/logcat_all_${i}.log"
        android_boottime_lines=$(grep -c "Boot is finished" "${LOG_LOGCAT_ALL}")
        if [ "${android_boottime_lines}" -ne 1 ]; then
            echo "There are ${android_boottime_lines} existences of 'Boot is finished' in file: ${LOG_LOGCAT_ALL}"
            echo "Please check the status first"
            service_started_once=false
        fi

        LOG_DMESG="${dir_boottime_data}/dmesg_${i}.log"
        ## check  the service of bootanim
        bootanim_lines=$(grep -c "'bootanim'" "${LOG_DMESG}")
        if [ "${bootanim_lines}" -ne 2 ]; then
            echo "bootanim service seems to be started more than once in file: ${LOG_DMESG}"
            echo "Please check the status first"
            service_started_once=false
        fi
        i=$((i+1))
    done

    if ${service_started_once}; then
        i=1
        G_RESULT_NOT_RECORD=TRUE
        G_RECORD_LOCAL_CSV=TRUE
        export G_RECORD_LOCAL_CSV G_RESULT_NOT_RECORD
        while true; do
            if [ $i -gt "$count" ]; then
                break
            fi
            getBootTimeInfoFromDmesg ${i}
            i=$((i+1))
        done
        G_RESULT_NOT_RECORD=FALSE
        export G_RESULT_NOT_RECORD
        if [ "X${G_RECORD_LOCAL_CSV}" = "XTRUE" ]; then
            statistic ${F_RAW_DATA_CSV} 2 |tee ${F_STATISTIC_DATA_CSV}
            sed -i 's/=/,/' "${F_STATISTIC_DATA_CSV}"

            G_RECORD_LOCAL_CSV=FALSE
            export G_RECORD_LOCAL_CSV
            while read -r line; do
                if ! echo "$line"|grep -q ,; then
                    continue
                fi
                key=$(echo "$line"|cut -d, -f1)
                measurement=$(echo "$line"|cut -d, -f2)
                units=$(echo "$line"|cut -d, -f3)
                output_test_result "${key}" "pass" "${measurement}" "${units}"
            done < "${F_STATISTIC_DATA_CSV}"
        fi

        output_test_result "SERVICE_STARTED_ONCE" "pass"
    else
        output_test_result "SERVICE_STARTED_ONCE" "fail"
    fi
    # set again for following output_test_result
    G_RECORD_LOCAL_CSV=FALSE
    cd ${local_tmp}|| exit 1
    tar -czvf boottime.tgz boottime
    if [ -n "$(which lava-test-run-attach)" ]; then
        lava-test-run-attach boottime.tgz application/x-gzip
    fi
    output_test_result "BOOTTIME_ANALYZE" "pass"
else
    G_VERBOSE_OUTPUT=FALSE
    G_RECORD_LOCAL_CSV=FALSE
    export G_VERBOSE_OUTPUT G_RECORD_LOCAL_CSV
    echo "Not recognised operation"
    output_test_result "BOOTTIME" "fail"
fi
