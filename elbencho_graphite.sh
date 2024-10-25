#!/bin/bash

# Default values for server, port, tag, and console output
SERVER="localhost"
PORT=2003
TAG="default"
ECHO_TO_CONSOLE=0  # Default is to not echo to console

# Function to display help information
print_help() {
    echo "Usage: $(basename $0) [options]"
    echo
    echo "Options:"
    echo "  -s, --server    Set the Graphite server address (default: localhost)"
    echo "  -p, --port      Set the Graphite port (default: 2003)"
    echo "  -t, --tag       Set the tag to be used in the metric name (default: default)"
    echo "  -e, --echo      Echo the data to console (default: disabled)"
    echo "  -h, --help      Show this help message"
    echo
    echo "Description:"
    echo "This script processes CSV data from Elbencho piped into it, and sends data to a Graphite server."
}

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -s|--server) SERVER="$2"; shift ;;
        -p|--port) PORT="$2"; shift ;;
        -t|--tag) TAG="$2"; shift ;;
        -e|--echo) ECHO_TO_CONSOLE=1 ;;  # Enable echo to console
        -h|--help) print_help; exit 0 ;;  # Show help message and exit
        *) echo "Unknown parameter passed: $1"; print_help; exit 1 ;;
    esac
    shift
done

check_nc_version() {
    # Get the version information from nc
    NC_VERSION_OUTPUT=$(nc -h 2>&1)

    # Check if the output contains "OpenBSD"
    if echo "$NC_VERSION_OUTPUT" | grep -q "OpenBSD"; then
        echo "Netcat is OpenBSD version. Appending nc command with '-q 0' for compatibility."
        NC=bsd
    else
        NC=notbsd
    fi
}

porcess_input() {
    HEADER=""
    HEADER_FIELDS=()
    while IFS=',' read -r line; do
        # Skip lines without commas, as they're unlikely to be the CSV header
        if [[ ! "$line" =~ , ]]; then
            continue
        fi

        if [[ -z "$HEADER" ]]; then
            HEADER="$line"
            IFS=',' read -r -a HEADER_FIELDS <<< "$HEADER"  # Store headers
            echo "Parsed Headers: ${HEADER_FIELDS[*]}"  # Debug line
            continue
        fi

        # Parse the CSV line
        IFS=',' read -r -a fields <<< "$line"

        # Determine the MixType and set a tag
        MIXTYPE_TAG=""
        for ((i=0; i<${#fields[@]}; i++)); do
            # echo "Processing field: ${HEADER_FIELDS[$i]}=${fields[$i]}"
            if [[ "${HEADER_FIELDS[$i],,}" == "mixtype" ]]; then
                if [[ "${fields[$i],,}" == "read" ]]; then  # Case-insensitive match
                    MIXTYPE_TAG="read"
                    fields[$i]=1
                elif [[ "${fields[$i],,}" == "write" ]]; then  # Case-insensitive match
                    MIXTYPE_TAG="write"
                    fields[$i]=2
                fi
            elif [[ "${HEADER_FIELDS[$i],,}" == "phase" ]]; then
                # Extract numeric value from Phase field or set MIXTYPE_TAG based on phase
                PHASE_CONTENT="${fields[$i]}"
                
                PHASE_NUMERIC=$(echo "$PHASE_CONTENT" | sed 's/[^0-9]*//g')  # Extract numeric part
                
                if [[ "${PHASE_CONTENT,,}" == *"write"* ]]; then
                    MIXTYPE_TAG="write"
                    PHASE_NUMERIC=2  # Example value, modify as needed
                elif [[ "$PHASE_NUMERIC" =~ ^[0-9]+$ ]]; then
                    PHASE_NUMERIC="$PHASE_NUMERIC"
                else
                    PHASE_NUMERIC=0  # Default value if phase is not numeric
                fi
                fields[$i]=$PHASE_NUMERIC

                # Update MixType if Phase contains WRITE
                if [[ "${PHASE_CONTENT,,}" == *"write"* ]]; then
                    MIXTYPE_TAG="write"
                    # Find the index of the MixType field and update it
                    for ((j=0; j<${#HEADER_FIELDS[@]}; j++)); do
                        if [[ "${HEADER_FIELDS[$j],,}" == "mixtype" ]]; then
                            fields[$j]=2
                            break
                        fi
                    done
                fi
            fi
        done

        # echo "Phase content: $PHASE_CONTENT"
        # echo "Phase numeric: $PHASE_NUMERIC"
        # echo "MixType tag: $MIXTYPE_TAG"
        # Get current timestamp
        TIMESTAMP=$(date +%s)

        # Echo the headers to stdout first if the flag is set and it's the first line of data
        if [[ $ECHO_TO_CONSOLE -eq 1 && -z "$FIRST_DATA_LINE" ]]; then
            echo "Timestamp, Metric, Value"
            FIRST_DATA_LINE=1  # Prevent headers from being printed multiple times
        fi

        # Echo the data to stdout if the flag is set
        if [[ $ECHO_TO_CONSOLE -eq 1 ]]; then
            echo "$line"
        fi

        # Prepare to send and optionally echo data
        i=0
        echo "$HEADER" | tr ',' '\n' | while read -r field; do
            # Clean up field name and replace '/' with 'per'
            METRIC=$(echo "$field" | tr ' ' '_' | sed 's/\//_per_/g')
            
            if [[ -n "$TAG" ]]; then
                METRIC="elbencho.$TAG.$MIXTYPE_TAG.$METRIC"
            else
                METRIC="elbencho.notag.$MIXTYPE_TAG.$METRIC"
            fi
            
            # Get the corresponding value from the fields array
            VALUE=${fields[$i]}
            
            # Format the data
            DATA="$METRIC $VALUE $TIMESTAMP"

            # Echo the metric, value, and timestamp to stdout if the flag is set
            if [[ $ECHO_TO_CONSOLE -eq 1 ]]; then
                echo "$TIMESTAMP, $METRIC, $VALUE"
            fi


            # Send the data to Graphite
            if [[ "$NC" == "bsd" ]]; then
                echo -e "$DATA" | nc -q 0 $SERVER $PORT
            else
                echo -e "$DATA" | nc $SERVER $PORT
            fi
            
            ((i++))
        done
    done
}

check_nc_version
porcess_input