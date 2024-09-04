#!/bin/bash

# Default values for server, port, tag, and console output
SERVER="localhost"
PORT=2003
TAG="default"
ECHO_TO_CONSOLE=0  # Default is to not echo to console

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -s|--server) SERVER="$2"; shift ;;
        -p|--port) PORT="$2"; shift ;;
        -t|--tag) TAG="$2"; shift ;;
        -e|--echo) ECHO_TO_CONSOLE=1 ;;  # Enable echo to console
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# Process the piped input
HEADER=""
HEADER_FIELDS=()
while IFS=',' read -r line; do
    if [[ -z "$HEADER" ]]; then
        HEADER="$line"
        IFS=',' read -r -a HEADER_FIELDS <<< "$HEADER"  # Store headers
        continue
    fi

    # Parse the CSV line
    IFS=',' read -r -a fields <<< "$line"

    # Determine the MixType and set a tag
    MIXTYPE_TAG=""
    for ((i=0; i<${#fields[@]}; i++)); do
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
            
            if [[ "$PHASE_CONTENT" == *"write"* ]]; then
                MIXTYPE_TAG="write"
                PHASE_NUMERIC=2  # Example value, modify as needed
            elif [[ "$PHASE_NUMERIC" =~ ^[0-9]+$ ]]; then
                PHASE_NUMERIC="$PHASE_NUMERIC"
            else
                PHASE_NUMERIC=0  # Default value if phase is not numeric
            fi
            fields[$i]=$PHASE_NUMERIC

            # Update MixType if Phase contains WRITE
            if [[ "$PHASE_CONTENT" == *"write"* ]]; then
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
        printf "%s\n" "$DATA" | nc $SERVER $PORT
        
        ((i++))
    done
done