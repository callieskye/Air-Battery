IFS=$'\n'
if [ "x$1" = "xmac" ]; then
    # Tightened predicate with correct precedence and reduced scope
    # Added category == "CBPowerSource": on newer macOS versions some third-party BLE
    # peripherals (e.g. Keychron K6 HE, Mi Mouse 3) report battery via this category
    # instead of CBStackDeviceMonitor/Server.GATT, so those devices never showed up at
    # all previously. This is additive - if no lines match this category on a given
    # macOS version, it's a no-op.
    PRED='subsystem == "com.apple.bluetooth" AND (category == "CBStackDeviceMonitor" OR category == "Server.GATT" OR category == "CBPowerSource") AND (eventMessage CONTAINS "Battery" OR eventMessage CONTAINS "statedump: 0x001A" OR eventMessage CONTAINS "statedump: 0x001D")'
    STYLE="--style compact"
    LVL="--level info"

    # Prefer START_TS (absolute time) if provided; otherwise fall back to a short --last window ($2)
    if [ -n "$START_TS" ]; then
        data=$(/usr/bin/nice -n 19 /usr/bin/log show $STYLE $LVL --predicate "$PRED" --start "$START_TS")
    else
        WINDOW="${2:-10m}"
        data=$(/usr/bin/nice -n 19 /usr/bin/log show $STYLE $LVL --predicate "$PRED" --last "$WINDOW")
    fi

    #data=`log show --process bluetoothd --info --last $1|grep -E "com.apple.bluetooth:Server.GATT.*statedump|com.apple.bluetooth:CBStackDeviceMonitor.*Battery"`
    # Cache system_profiler's Bluetooth listing once, used below to fill in a missing MAC
    # address by matching on device name - some third-party BLE devices (Keychron K6 HE,
    # Mi Mouse 3, etc.) omit the "BDA ..." field in their log lines on newer macOS, which
    # meant `mac` came back empty and the device silently failed the "is this MAC actually
    # connected" filter in BTDBattery.swift, so it was dropped and never shown even though
    # its battery level WAS successfully read from the log.
    btProfilerData=`/usr/sbin/system_profiler SPBluetoothDataType 2>/dev/null`
    for i in `echo "$data"|grep "Battery"|grep -v "VID 0x004C"`
    do
        time=`echo $i|awk '{print $1"T"$2}'`
        # Fixes issue #137 (NuPhy keyboard, and likely other devices, not detected). This
        # used to require a ", PID" field to appear immediately after the name (", Nm
        # '...', PID") to match at all. Confirmed via a real `log show` capture that a
        # "Device found" line for a NuPhy Air75 V2-1 keyboard has no VID/PID logged at all -
        # its name is immediately followed by ", DsFl ..." instead - so the old pattern never
        # matched and `name` came back empty for this device (and presumably any other device
        # macOS doesn't log a VID/PID for). Matches just the quoted name itself now, regardless
        # of whatever field follows it.
        name=`echo $i|grep -o ", Nm '[^']*'"|sed "s/, Nm '//g;s/'\$//g"`
        type=`echo $i|grep -o ", DvT [A-z]*"|sed "s/, DvT //g"`
        # NOTE: was `grep -o "\d*"` - "\d" is a PCRE digit-class escape that BSD/macOS grep
        # (no -P support) does NOT understand; without -P it's treated as a literal "d",
        # so "\d*" matched zero-or-more literal d's, i.e. it matched an empty string on
        # every line instead of extracting the battery number. That silently produced an
        # empty $batt for every device parsed via this path, which then failed the
        # `[ "x$batt" != "x" ]` check below and got dropped entirely - this looks like the
        # actual root cause behind third-party BLE devices (Mi Mouse 3, Keychron boards)
        # never appearing in AirBattery at all. Fixed with a portable ERE digit class.
        batt=`echo $i|grep -o ", Battery M [+-]*[0-9]*%"|grep -oE "[0-9]+"`
        stat=`echo $i|grep -o ", Battery M [+-]*[0-9]*%"|grep -Eo "\+|\-"`
        mac=`echo $i|grep -o ", BDA [A-z0-9:]*"|sed "s/, BDA //g"`
        vid=`echo $i|grep -o ", VID 0x[A-z0-9]*"|sed "s/, VID //g"`
        pid=`echo $i|grep -o ", PID 0x[A-z0-9]*"|sed "s/, PID //g"`
        # Fallback: if the log line had no BDA field, try to recover the MAC by looking up
        # this device's name in system_profiler's paired-device listing instead.
        if [ "x$mac" = "x" ] && [ "x$name" != "x" ]; then
            mac=`echo "$btProfilerData"|grep -B20 "^ *$name:\$"|grep "Address:"|tail -1|sed 's/^ *Address: //g;s/://g' | sed -E 's/(..)/\1:/g;s/:$//'`
        fi
        if [ "x$batt" != "x" ]; then
            echo "{\"time\": \"$time\", \"vid\": \"$vid\", \"pid\": \"$pid\", \"type\": \"$type\", \"mac\": \"$mac\", \"name\": \"$name\", \"level\": $batt, \"status\": \"$stat\"}"
        fi
    done
    devData=`echo "$data"|grep -E "statedump: 0x001A Characteristic Value|statedump: 0x001D Characteristic Value"|grep -o "\[[A-z0-9 ]*\]"|sed 's/\[ //g;s/ \]//g'|awk '{if (NR%2==1) {line=$0} else {print line, $0}}'|awk 'length($0) == 23'`
    times=`echo "$data"|grep -E "statedump: 0x001D Characteristic Value"|awk '{print $1"T"$2}'`
    if [ `echo "$devData"|wc -l` = `echo "$times"|wc -l` ];then
        btData=`/usr/sbin/system_profiler SPBluetoothDataType`
        for i in `paste -d ' ' <(echo "$times") <(echo "$devData")`
        do
            if [ `echo $i|wc -w|tr -d " "` = "9" ];then
                time=`echo $i|awk '{print $1}'`
                batt=`echo $i|awk '{print "0x"$NF}'`
                vid=`echo $i|awk '{print "0x"$4$3}'`
                pid=`echo $i|awk '{print "0x"$6$5}'`
                name=`echo "$btData"|grep -B3 $pid|sed -n '1p'|sed 's/^ *//g;s/:$//g'`
                type=`echo "$btData"|grep -A5 $pid|grep "Minor Type: "|sed 's/^ *Minor Type: //g'`
                mac=`echo "$btData"|grep -B2 $pid|sed -n '1p'|sed 's/^ *Address: //g;s/:$//g'`
                echo "{\"time\": \"$time\", \"vid\": \"$vid\", \"pid\": \"$pid\", \"type\": \"$type\", \"mac\": \"$mac\", \"name\": \"$name\", \"level\": $(($batt)), \"status\": \"?\"}"
            fi
        done
    fi
else
    syslog=$1
    type=$2
    id=$3
    
    data=`$syslog $type -u $id --process SpringBoard -m '"Accessory Category" = Pencil;' -T SpringBoard`
    batt=`echo "$data"|grep "Current Capacity"|grep -o "[0-9]*"|sed -n '$p'`
    stat=`echo "$data"|grep "Is Charging"|grep -o "[0-9]*"|sed -n '$p'`
    model=`echo "$data"|grep "Product ID"|grep -o "[0-9]*"|sed -n '$p'`
    vendor=`echo "$data"|grep "Vendor ID"|grep -v Source|grep -o "[0-9]*"|sed -n '$p'`
    if [ x"$vendor" = "x76" ]; then vendor="Apple"; else vendor="Other"; fi
    
    #data=`$syslog $type -u $id -m 'name = Pencil' --process SpringBoard -T SpringBoard|tr ';' '\n'`
    #batt=`echo "$data"|grep "percentCharge ="|grep -o "[0-9]*"|sed -n '$p'`
    #stat=`echo "$data"|grep "charging ="|tr -d " "|sed 's/charging=//g'|sed -n '$p'`
    #model=`echo "$data"|grep "productIdentifier ="|grep -o "[0-9]*"|sed -n '$p'`
    #vendor=`echo "$data"|grep "vendor ="|tr -d " "|sed 's/vendor=//g'|sed -n '$p'`
    #if [ x"$stat" = "xYES" ]; then stat=1; else stat=0; fi
    echo "{\"level\": $batt, \"status\": $stat, \"model\": \"$model\", \"vendor\": \"$vendor\"}"
fi
