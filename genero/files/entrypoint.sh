#!/usr/bin/env bash
#
# Licensed Material - Property Of Four Js Development Tools Europe Limited
#
# Copyright Four Js Development Tools Europe Limited 2013 - 2022.
# All rights reserved.
#
#==============================================================================
# DESCRIPTION
# This script is ran as an entrypoint script (Runs on container startup)
#
# This script runs as the main process in the container (PID 1). This means that
# it can handle all the signals sent to the container.
# When a pod status switches to 'terminating' state, Kubernetes will send a SIGTERM
# signal to the containers in the pod. This signal lets the containers know that
# they are going to be shut down soon.
#
# This script listens for this event and starts a graceful termination process
# which keeps the pod running as long as there are fglrun processes running
# and kills all idle fglrun processes.
# The pod, however, can be forcibly terminated when the terminationGracePeriod
# is reached, even if fglrun process are still running.
# The terminationGracePeriod is specified in the deployment configs of the pod.
#
# The entrypoint script will also exit if any of the vital processes that must be
# running on the container stops.
#==============================================================================

set -x

## Init Variables.
CATCH_SIGTERM=false
TERMINATION_CHECK_INTERVAL=5
PROCESSES_LIST="fastcgi sshd"

#------------------------------------------------------------------------------
# FUNCTIONS
#------------------------------------------------------------------------------

## getops Functions

usage() {
    echo "Usage: $(basename "$0") [-h] [-t GAS_TIMEOUT]"
    echo "Try '$(basename "$0") -h' for more information."
}

help_fct() {
    echo "Usage: $(basename "$0") [-h] [-t GAS_TIMEOUT]"
    echo " -h		display this help message and exit"
    echo " -t GAS_TIMEOUT       enable GAS Auto Logout feature and set the TIMEOUT to GAS_TIMEOUT"
    echo " -s SIGTERM_INTERVAL  ensure the container is not killed until there is no fglrun process left, check every SIGTERM_INTERVAL seconds"
    echo " -p PROCESSES_LIST  list of processes that must keep running on the container or else the entrypoint script exits shutting down the container"
    echo " -c TERMINATION_CHECK_INTERVAL  check every TERMINATION_CHECK_INTERVAL seconds that the vital processes are running or graceful termination process has started, due to receival of SIGTERM signal, but not yet completed"
}

while getopts ":ht:s:c:p:" opt; do
    case $opt in
    h)
        help_fct
        exit 0
        ;;
    t)
        GAS_TIMEOUT=$OPTARG
        sed -i "s/<TIMEOUT>0</<TIMEOUT>$GAS_TIMEOUT</" "$GASDIR/etc/as.xcf"
        ;;
    s)
        CATCH_SIGTERM=true
        SIGTERM_INTERVAL=$OPTARG
        ;;
    c)
        TERMINATION_CHECK_INTERVAL=$OPTARG
        ;;
    p)
        PROCESSES_LIST="$OPTARG"
        ;;
    :)
        echo "$(basename "$0"): -$OPTARG requires an argument." >&2
        usage >&2
        exit 1
        ;;
    ?)
        echo "$(basename "$0"): Invalid option: -$OPTARG" >&2
        usage >&2
        exit 1
        ;;
    esac
done

## Core Functions

function touch_shutdown_file (){
    # This function creates the flag file indicating that the entrypoint script should be exited
    # It takes in a message which indicates the shutdown reason

    # log the message #
    echo $1

    # Create a file that serves as a flag: Once it's created the entrypoint exists #
    touch "/tmp/shutdown.flg"
}

function check_processes() {
    # Check if any of the processes listed in the PROCESSES_LIST has stopped
    for process in $PROCESSES_LIST; do
        if ! pgrep -a $process > /dev/null; then
            # touch shutdown flag file: Once it's created the entrypoint exists
            touch_shutdown_file "$process is not running..."
            break # There's no need to check the rest of the processes
        fi
    done
}

function start_apache() {
    # This function starts apache

    echo "Start apache"
    apachectl start
}

function start_ssh() {
    # This function starts sshd

    echo "Start SSH"
    service ssh start > /dev/null
}

function start_fastcgi() {
    # This function starts fastcgi in the background

    # Start fasctgi
    COMMANDLINE="$GASDIR/bin/fastcgidispatch -s"
    #COMMANDLINE=$COMMANDLINE" -E res.log.output.type=CONSOLE"
    COMMANDLINE=$COMMANDLINE" -E res.log.format=\"category component date time relative-time process-id thread-id location contexts event-type event-params\""
    if [ -n "$FGLGASCONFIGURATION" ] && [ -f "$FGLGASCONFIGURATION" ]; then
        COMMANDLINE=$COMMANDLINE" -f $FGLGASCONFIGURATION"
    fi
    echo "Start dispatcher: $COMMANDLINE"
    su "$USER" -c "$COMMANDLINE" &
}

function start() {
   # Main entrypoint function that starts Apache and GAS Service.

    rm -f /tmp/shutdown.flg

    # Remote cloud based FLM is bugged as of 3.20.09 so this should work around it
    . "$FGLDIR/envcomp"
    fglWrt -a info

    # Start apache
    start_apache

    # Start fasctgi
    start_fastcgi

    # Start ssh
    start_ssh  

    # sleep for 5 seconds giving enough time for the processes to start
    sleep 5
}

function check_fglrun_processes() {
    # This function waits until all fglrun processes are killed to exit.

    keep_alive=true # This is a flag indicating that the pod shouldn't be terminated.
    while $keep_alive; do

        # Check if any fglrun processes are running #
        if ! pgrep -a fglrun > /dev/null; then
            # If there are no fglrun processes running, sleep for 5 secs.
            sleep 5
            # The sleep is added here to prevent the following case from happening:
            # If a user had a live session and refreshed the page at the same time we are checking for running fglrun processes,
            # then as refreshing the page causes the fglrun process to die and restart on the same pod while using a sticky session,
            # with the right timing, we could end up exiting that loop while there is effectively a new fglrun process that just started.
            # This would cause a bad user experience as a newly started program would crash right after starting.
            # Obviously, this specific case can happen even after waiting 5 more seconds but this should minimise potential occurences.
            if ! pgrep -a fglrun > /dev/null; then
            keep_alive=false
                # At this point, if there's stil no fglrun processing running, then we presume that it is safe to terminate the pod.
                # NOTE: This doesn't prevent the pod from terminating while someone keeps spamming the refresh button.
            fi
        fi

        if $keep_alive; then
            echo "fglrun process(es) still running, sleep for $SIGTERM_INTERVAL secs"
            sleep "$SIGTERM_INTERVAL"
        fi
    done
}

function start_graceful_termination_process() {
    # This function starts a graceful termination process for the containers of the
    # pod iff no more fglrun processes are running in the containers.
    # When no more fglrun processes are running, a flag file is created to point out
    # to the main process that the termination process completed and the entrypoint
    # script can be exited.

    echo "Captured SIGTERM Signal"

    if $CATCH_SIGTERM; then
        ###
        # Sleep while there's at least one fglrun process still running
        ###
        echo "Checking for running fglrun processess..."
        check_fglrun_processes

        ###
        # Start the termination process
        ###
        echo "No running fglrun process"
    fi

    # Create a file that serves as a flag: Once it's created the entrypoint exists #
    touch_shutdown_file "Graceful termination processes is complete..."
}

#------------------------------------------------------------------------------
# MAIN
#------------------------------------------------------------------------------

###
# Generate fgllicense. Error out if fgllicense could not be generated.
###
#./generate-fgllicense.sh || exit 1

###
# Trap the signal SIGTERM
###
trap start_graceful_termination_process SIGTERM
    # The trap command listens to incoming signals and executes the function 'start_graceful_termination_process'
    # when the SIGTERM signal is received

###
# Start Apache/GAS
###
start

###
# Run a loop which checks for a flag file indicating that the entrypoint script can be exited.
# This can happen for 2 reasons:
#   - The SIGTERM signal has been received and the graceful termination process has ended.
#   - One of the processes that must be running on the container has stopped.
###
while [ ! -f "/tmp/shutdown.flg" ]; do
    # Check if any of the processes from the <PROCESSES_LIST> has stopped
    check_processes
        # This function touches the shutdown file if any of the processes has stopped
    sleep "$TERMINATION_CHECK_INTERVAL"
done

echo "Shutting down..."
