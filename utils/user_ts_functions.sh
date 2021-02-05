#!/usr/bin/env bash

#Use 'function ts_<FUNCTION> {}' for user functions.

function ts_active_project {
    if [[ -z $PROJECT_NAME ]]; then
        logerror "No project selected. Please run 'source source_me.sh <PROJECT>' again!"
        return 1
    elif [[ $1 != "quiet" ]]; then
        loginfo "You are currently working on project $PROJECT_NAME"
    fi
}

function ts_delete {
    ts_active_project quiet; PROJECTOK=$?; if [[ $PROJECTOK -ne 0 ]]; then return $PROJECTOK; fi

    read -p "Do you really want to delete project $PROJECT_NAME from this test suite? [Y/y]" -n 1 -r
    echo
    loginfo "Removing project $PROJECT_NAME ..."
    if [[ $REPLY =~ ^[Yy]$ ]]
    then
        cd $TESTSUITEDIR
        rm -rf $TESTSUITEDIR/projects/$PROJECT_NAME
        unset PROJECT_NAME
    fi
}

function ts_project_data {
    ts_active_project quiet; PROJECTOK=$?; if [[ $PROJECTOK -ne 0 ]]; then return $PROJECTOK; fi

    loginfo "Project: $PROJECT_NAME"
    loginfo "CMSSW build: $CMSSW_BUILD"
    loginfo "CMSSW packages: $CMSSW_PACKAGES"
    if [[ $CMSSW_REMOTE == "INVALID" ]]; then
        logerrormsg "Project remote: $CMSSW_REMOTE"
    else
        loginfo "Project remote: $CMSSW_REMOTE"
    fi
    if [[ $CMSSW_BRANCH == "INVALID" ]]; then
        logerrormsg "Project branch: $CMSSW_BRANCH"
    else
        loginfo "Project branch: $CMSSW_BRANCH"
    fi
}

function ts_set_remote {
    ts_active_project quiet; PROJECTOK=$?; if [[ $PROJECTOK -ne 0 ]]; then return $PROJECTOK; fi

    if [[ -z $1 ]]; then
        logwarn "Call me with name of remote owner!"
        return 1
    fi

    _ts_env_dev
    git remote | grep $1 > /dev/null
    if [[ $? -ne 0 ]]; then
        git remote add $1 git@github.com:${1}/cmssw.git
    fi
    loginfo "Fetching contents from remote. Credentials required!"
    git fetch $CMSSW_REMOTE
    if [[ $? -ne 0 ]]; then
        logerror "Remote fork $1 is not available! Use ts_set_remote to switch to a different remote."
        return 1
    fi
    export CMSSW_REMOTE=$1
    _ts_save_metadata
}

function ts_set_branch {
    ts_active_project quiet; PROJECTOK=$?; if [[ $PROJECTOK -ne 0 ]]; then return $PROJECTOK; fi

    if [[ -z $1	]]; then
        logwarn "Call me with branch name!"
        return 1
    fi

    _ts_env_dev
    git	branch | grep $1 > /dev/null
    if [[ $? -eq 0 ]]; then
        git checkout $1
    else
        git checkout --track $CMSSW_REMOTE/$1
        if [[ $? -ne 0 ]]; then
            logerror "Branch $1 not available on ${CMSSW_REMOTE}! Use ts_set_branch to switch to a different branch."
            return 1
        fi
    fi
    export CMSSW_BRANCH=$1
    _ts_save_metadata
}

function ts_add_package {
    ts_active_project quiet; PROJECTOK=$?; if [[ $PROJECTOK -ne 0 ]]; then return $PROJECTOK; fi

    cd $TESTSUITEDIR/projects/$PROJECT_NAME/dev/$CMSSW_BUILD/src
    git cms-addpkg $1
    RETURNCODE=$?
    if [[ $RETURNCODE -eq 0 ]]; then
        export CMSSW_PACKAGES="$CMSSW_PACKAGES $1"
        _ts_save_metadata
    else
        logerror "Package $1 could not be installed."
    fi
    cd -
    return $RETURNCODE
}

function ts_checkout_new_cmssw_build {
    ts_active_project quiet; PROJECTOK=$?; if [[ $PROJECTOK -ne 0 ]]; then return $PROJECTOK; fi

    #set up new cmssw build
    OLD_CMSSW_BUILD=$CMSSW_BUILD
    read -p "Please enter custom CMSSW build if required:" -r
    if [[ -z $REPLY ]]; then
        export CMSSW_BUILD=CMSSW_11_1_X_$(date -d "yesterday" +"%Y-%m-%d")-2300
    else
        export CMSSW_BUILD=$REPLY
    fi
    _ts_setup_cmssw
    if [[ $? -ne 0 ]]; then
        export CMSSW_BUILD=$OLD_CMSSW_BUILD
        unset OLD_CMSSW_BUILD
        return 1
    fi
    _ts_save_metadata

    #set up git and packages
    git cms-init
    for PACKAGE in $CMSSW_PACKAGES; do
        git cms-addpkg $PACKAGE
    done

    #copy local changes from old build
    cd $TESTSUITEDIR/projects/$PROJECT_NAME/dev/$OLD_CMSSW_BUILD/src
    cmsenv
    git diff > .ts_transfer_to_${CMSSW_BUILD}.diff
    cd $TESTSUITEDIR/projects/$PROJECT_NAME/dev/$CMSSW_BUILD/src
    cmsenv
    git apply $TESTSUITEDIR/projects/$PROJECT_NAME/dev/$OLD_CMSSW_BUILD/src/.ts_transfer_to_${CMSSW_BUILD}.diff
    unset OLD_CMSSW_BUILD
}

function ts_new_proxy {
    voms-proxy-init -rfc -voms cms
}

function ts_check_proxy {
    voms-proxy-info
    if [[ $? -eq 0 ]]; then
        TIMELEFT=$(voms-proxy-info | grep -E 'timeleft' | sed "s@timeleft  : @@")
        if [[ $TIMELEFT == "00:00:00" ]]; then
            ts_new_proxy
        fi
    else
        ts_new_proxy
    fi
}

function ts_test_code_checks {
    ts_active_project quiet; PROJECTOK=$?; if [[ $PROJECTOK -ne 0 ]]; then return $PROJECTOK; fi

    scram b -j 20
    if [[ $? -ne 0 ]]; then
        logerrormsg "Compilation failed!"
        return 1
    fi
    scram b code-format
    scram b code-checks
}

function ts_test_unit {
    ts_active_project quiet; PROJECTOK=$?; if [[ $PROJECTOK -ne 0 ]]; then return $PROJECTOK; fi

    LOGTAG=$1
    if [[ -z $LOGTAG ]]; then
        LOGTAG=$(date +%Y-%m-%d_%H-%M)
    fi

    scram b -j 20
    if [[ $? -ne 0 ]]; then
        logerrormsg "Compilation failed!"
        return 1
    fi
    export CMS_PATH=/cvmfs/cms-ib.cern.ch/week0
    logandrun 'scram b runtests' $TESTSUITEDIR/projects/$PROJECT_NAME/log/unit-tests_${LOGTAG}
    loginfo "Unit tests finished. Please check results in $TESTSUITEDIR/projects/$PROJECT_NAME/log/unit-tests_${LOGTAG}.log"
}

function ts_test_matrix {
    ts_active_project quiet; PROJECTOK=$?; if [[ $PROJECTOK -ne 0 ]]; then return $PROJECTOK; fi

    LOGTAG=$1
    if [[ -z $LOGTAG ]]; then
        LOGTAG=$(date +%Y-%m-%d_%H-%M)
    fi

    ts_check_proxy
    scram b -j 20
    if [[ $? -ne 0 ]]; then
        logerrormsg "Compilation failed!"
        return 1
    fi
    logandrun 'runTheMatrix.py -l limited -i all --ibeos' $TESTSUITEDIR/projects/$PROJECT_NAME/log/matrix-tests_${LOGTAG}
    loginfo "Matrix tests finished. Please check results in $TESTSUITEDIR/projects/$PROJECT_NAME/log/matrix-tests_${LOGTAG}.log"
}

function ts_test_standard_sequence {
    ts_active_project quiet; PROJECTOK=$?; if [[ $PROJECTOK -ne 0 ]]; then return $PROJECTOK; fi

    LOGTAG=$1
    if [[ -z $LOGTAG ]]; then
        LOGTAG=$(date +%Y-%m-%d_%H-%M)
    fi

    ts_check_proxy
    ts_test_code_checks
    ts_test_unit $LOGTAG
    ts_test_matrix $LOGTAG
    loginfo "Standard test sequence finished. Please check results in \n $TESTSUITEDIR/projects/$PROJECT_NAME/log/unit-tests_${LOGTAG}.log \n $TESTSUITEDIR/projects/$PROJECT_NAME/log/matrix-tests_${LOGTAG}.log"
}

function ts_rebase_to_master {
    ts_active_project quiet; PROJECTOK=$?; if [[ $PROJECTOK -ne 0 ]]; then return $PROJECTOK; fi

    _ts_env_dev
    loginfo "Fetching contents from official master. Credentials required!"
    git fetch official-cmssw
    git rebase official-cmssw/master
}

function ts_backport {
    ts_active_project quiet; PROJECTOK=$?; if [[ $PROJECTOK -ne 0 ]]; then return $PROJECTOK; fi

    _ts_env_dev

    loginfo "Checking sync status of current project. Credentials required!"
    git fetch $CMSSW_REMOTE
    git status | grep "Your branch is up to date with" > /dev/null
    if [[ $? -ne 0 ]]; then
        logwarn "Please synchronize your local repository with the remote first and try again! Aborting backport..."
        return 1
    fi
    #identify range of commits to backport and write it to logfile
    BASE_COMMIT=$(git rev-list --max-count 1 --min-parents=2 $CMSSW_BRANCH)
    LAST_COMMIT=$(git rev-list --max-count 1 $CMSSW_BRANCH)
    for ENTRY in $(git rev-list --max-count 100 $CMSSW_BRANCH); do
        if [[ $ENTRY == $BASE_COMMIT ]]; then
            break
        else
            echo $ENTRY
        fi
    done > $TESTSUITEDIR/projects/$PROJECT_NAME/log/original_commits_of_backport_temp.txt

    read -p "Please enter CMSSW build to backport to:" -r
    echo

    cd $TESTSUITEDIR
    if [ -d projects/${PROJECT_NAME}_backport_$REPLY ]; then
        logwarn "Backport project already exists! Aborting backport..."
        rm $TESTSUITEDIR/projects/$PROJECT_NAME/log/original_commits_of_backport_temp.txt
        return 1
    fi

    export CMSSW_BUILD=${REPLY}
    export BACKPORT_BASE=$PROJECT_NAME
    export PROJECT_NAME=${PROJECT_NAME}_backport_$CMSSW_BUILD

    loginfo "Creating backport project $PROJECT_NAME ..."
    mkdir projects/$PROJECT_NAME
    mkdir projects/$PROJECT_NAME/dev
    mkdir projects/$PROJECT_NAME/ref
    mkdir projects/$PROJECT_NAME/log
    mv $TESTSUITEDIR/projects/$BACKPORT_BASE/log/original_commits_of_backport_temp.txt $TESTSUITEDIR/projects/$PROJECT_NAME/log/original_commits_of_backport.txt
    _ts_setup_cmssw
    if [[ $? -ne 0 ]]; then
        logwarn "Aborting backport..."
        cd $TESTSUITEDIR
        rm -rf $TESTSUITEDIR/projects/$PROJECT_NAME
        export PROJECT_NAME=$BACKPORT_BASE
        source $TESTSUITEDIR/projects/$BACKPORT_BASE/project_metadata.sh
        return 1
    fi

    loginfo "Setting up local code packages..."
    git cms-init
    for PACKAGE in $CMSSW_PACKAGES; do
        git cms-addpkg $PACKAGE
    done
    export CMSSW_BRANCH=${CMSSW_BUILD}_backport_$CMSSW_BRANCH
    git checkout -b $CMSSW_BRANCH

    _ts_save_metadata

    git remote add $CMSSW_REMOTE git@github.com:${CMSSW_REMOTE}/cmssw.git
    loginfo "Fetching contents from remote. Credentials required!"
    git fetch $CMSSW_REMOTE
    loginfo "Start cherry-picking commits to be backported... List of commits is written to $TESTSUITEDIR/projects/$PROJECT_NAME/log/original_commits_of_backport.txt"
    git cherry-pick ${BASE_COMMIT}..${LAST_COMMIT}
}
