#!/bin/bash
#####################################################################
#### Script to sync and restart App/Solr servers                 ####
#### Usage:                                                      ####
####  $1 -> env name                                             ####
####  $2 -> WAS type (solr; wc)                                  ####
####  $3 -> action (stop; start; sync; sync_stat)                ####
#####################################################################

### Debug
# set -x

###########################################################
### Define environment/store specific variables
### Accepts parameter(s):
###  $1 -> env name
###########################################################
define_env (){

   ## Set env specific var
   case $1 in
      prd1)
         APP_HOST=(hostname610 hostname612 hostname614 hostname616)
         WEB_HOST=(hostnameweb601 hostnameweb602 hostnameweb603 hostnameweb604 hostnameweb605)
         SOLR_HOST=(hostnamesrch601 hostnamesrch603 hostnamesrch608)
         WC_HOST="hostname601"
         APP_QNTTY=(2 2 2 2)
         SOLR_QNTTY=(1 1 1)
         APP_SERV=(app110 app210 app112 app212 app114 app214 app116 app216)
         SOLR_SERV=(srchapp1 srchapp3 srchapp8)
         INS=prod01
         ;;
      prd2)
         APP_HOST=(ws8sc601 hostname611 hostname613 hostname615 hostname617)
         WEB_HOST=(hostnameweb601 hostnameweb602 hostnameweb603 hostnameweb604 hostnameweb605)
         SOLR_HOST=(hostnamesrch602 hostnamesrch604)
         WC_HOST="hostname601"
         APP_QNTTY=(1 2 2 2 2)
         SOLR_QNTTY=(1 1)
         APP_SERV=(app1sc01 app111 app211 app113 app213 app115 app215 app117 app217)
         SOLR_SERV=(srchapp2 srchapp4)
         INS=prod01
         ;;
      stg)
         APP_HOST=(stgsrv601)
         WEB_HOST=(stgsrveb601)
         SOLR_HOST=(stgsrch601)
         WC_HOST="stg601"
         APP_QNTTY=(1)
         SOLR_QNTTY=(1)
         APP_SERV=(server1)
         SOLR_SERV=(srchapp1)
         INS=stg01
         ;;
      *)
         chk_status 1 "Incorrect env name!" Error
         ;;
   esac

   WAS="/usr/opt/app/IBM/WebSphere/AppServer"
   WASBIN="${WAS}/profiles/${INS}/bin"
   WASLOG="${WAS}/profiles/${INS}/logs"
   SOLRINS="${INS}_solr"
   SOLRBIN="${WAS}/profiles/${SOLRINS}/bin"
   SOLRLOG="${WAS}/profiles/${SOLRINS}/logs"
}

##################################################
### Message handler GUI
### Accepts parameters:
###  $1 -> exit status
###  $2 -> message
###  $3 -> error severity (e.g Error; Warning; etc)
###################################################
chk_status (){

   rc=$1;
   message="$3: $2 ($1)"
   err_templ=$3; err_templ="${err_templ^^}"

   if [ "${err_templ}" = "ERROR" ]; then message="${message^^}"; fi

   if [[ $rc != 2 ]];
   then
     echo "${message}";

     ## Interrupt sript execution
     case ${rc} in
        1)
           exit $1;
        ;;

        *)
           # do nothing
        ;;
     esac

   fi

}

##################################################
# Send alert mail
##################################################
send_alert_mail (){

   echo "Please check PROD Deployment log. Manual action required." | mutt -s "[WARN]: eComm PROD Deployment: Action required" "<email_list>"

}

##################################################
### Define bin; logs dir location and instanse name based on WAS type
### Accepts parameters:
###  $1 -> WAS type (solr; wc)
###################################################
was_define (){
   case $1 in
      solr)
         BIN=${SOLRBIN}
         LOGS=${SOLRLOG}
         PS="${INS}_search"
         HOST_LIST=( "${SOLR_HOST[@]}" )
         SERV_LIST=( "${SOLR_SERV[@]}" )
         QNTTY_LIST=( "${SOLR_QNTTY[@]}" )
         CACHE_PORTS=(10116)
         PROTOCOL="http"
      ;;

      wc)
         BIN=${WASBIN}
         LOGS=${WASLOG}
         PS="${INS}_node"
         HOST_LIST=( "${APP_HOST[@]}" )
         SERV_LIST=( "${APP_SERV[@]}" )
         QNTTY_LIST=( "${APP_QNTTY[@]}")
         CACHE_PORTS=(10117 10147)
         PROTOCOL="https"
      ;;

      *)
         chk_status 1 "was_restart: wrong WAS type specified!" Error
      ;;
   esac
}

##################################################
### Stop/Start WAS
### Accepts parameters:
###  $1 -> WAS type (solr; wc)
###  $2 -> action (stop; start; sync)
###  $3 -> wait timeout (null or value in ms)
###################################################
was_restart (){

   ## Variables
   NODE_TIMEOUT=150
   APP_TIMEOUT=$3
   TONULL="> /dev/null 2>&1 < /dev/null"

   if [[ -z "${APP_TIMEOUT}" ]];
   then
      chk_status 0 "was_restart: Timeout parameter not specified($3)! 900 ms will be used as default." Info
      APP_TIMEOUT=900
   fi

   was_define $1

   ## Define action
   case $2 in

      stop)

         # stop App basing on qauntity of JVMs on App server
         app_host_arr_size=${#HOST_LIST[@]}
         k=0
         echo " "
         echo "Host list: ${HOST_LIST[@]}"
         for (( i=0; i<${app_host_arr_size}; i++ ));
         do
            echo " "
            echo "========== Stopping Node on ${HOST_LIST[$i]}: ========="
            COMMAND=""

            for (( j=0; j<${QNTTY_LIST[$i]}; j++ ));
            do
               echo "----- Stopping App ${HOST_LIST[$i]}:${SERV_LIST[$k]} -----"

               # generate stop clones command
               if [ ${j} -ne 0 ];
               then
                  COMMAND="${COMMAND}; ${BIN}/./stopServer.sh ${SERV_LIST[$k]} ${TONULL}"
               else
                  COMMAND="${BIN}/./stopServer.sh ${SERV_LIST[$k]} ${TONULL}"
               fi

               k=$((k+1))
            done

         # stop Node/App servers (s) using one ssh connection to server
         COMMAND="ssh ${HOST_LIST[$i]} -f \"(${BIN}/./stopNode.sh ${TONULL} ; ${COMMAND}) ${TONULL} &\""
         echo "${COMMAND}"
         eval ${COMMAND} > /dev/null 2>&1 < /dev/null &

         done
      ;;


      start)

         chk_action_stat sync_stat

         # start Node command
         COMMAND=""
         app_host_arr_size=${#HOST_LIST[@]}
         echo "${HOST_LIST[@]}"
         for (( i=0; i<${app_host_arr_size}; i++ ));
         do
            echo " "
            echo "========== Starting Node on ${HOST_LIST[$i]}: ========="
            COMMAND="ssh ${HOST_LIST[$i]} -f \"(${BIN}/./startNode.sh ${TONULL}) &\""
            echo "${COMMAND}"
            eval ${COMMAND} > /dev/null 2>&1 < /dev/null &

         done

         echo " "
         echo "=== Waiting for nodeagent startup... ==="
         sleep ${NODE_TIMEOUT}

         COMMAND=""
         # start App server(s)
         k=0
         for (( i=0; i<${app_host_arr_size}; i++ ));
         do
            echo " "
            echo "========== Checking Node agent status on ${HOST_LIST[$i]}: ========="
            echo "ssh ${HOST_LIST[$i]} -f ps -ef | grep nodeagent | grep ${PS}"
            ssh ${HOST_LIST[$i]} -f "ps -ef | grep nodeagent | grep -v grep | grep ${PS} > /dev/null"

            # if Nodeagent started
            if [ $? -eq 0 ]
            then
               chk_status 0 "Node on ${HOST_LIST[$i]} is running. Continue..." Info

            for (( j=0; j<${QNTTY_LIST[$i]}; j++ ));
            do
               echo "----- Starting App ${HOST_LIST[$i]}:${SERV_LIST[$k]} -----"

               # generate start clones command
               if [ ${j} -ne 0 ];
               then
                  COMMAND="${COMMAND} && ${BIN}/./startServer.sh ${SERV_LIST[$k]} ${TONULL}"
               else
                  COMMAND="${BIN}/./startServer.sh ${SERV_LIST[$k]} ${TONULL}"
               fi

               k=$((k+1))
            done

            # start App servers(s) using one ssh connection to server
            COMMAND="ssh ${HOST_LIST[$i]} -f \"(${COMMAND}) &\""
            echo "${COMMAND}"
            eval ${COMMAND}

            # if Nodeagent NOT started
            else
               chk_status 0 "Node on ${HOST_LIST[$i]} is NOT running. Skipping..." Error
               send_alert_mail

               for (( j=0; j<${QNTTY_LIST[$i]}; j++ ));
               do
                  chk_status 0 "Please start App ${HOST_LIST[$i]}:${SERV_LIST[$k]} manually." Info

                  k=$((k+1))
               done
            fi

         done

         sleep ${APP_TIMEOUT}
         chk_action_stat app_stat

      ;;

      sync)

         # sync Node(s)
         app_host_arr_size=${#HOST_LIST[@]}
         echo "${HOST_LIST[@]}"
         for (( i=0; i<${app_host_arr_size}; i++ ));
         do
            echo " "
            echo "========== Checking Node agent status on ${HOST_LIST[$i]}: ========="
            echo "ssh ${HOST_LIST[$i]} -f ps -ef | grep ${PS}"
            ssh ${HOST_LIST[$i]} "ps -ef | grep ${PS} | grep -v grep > /dev/null"

            # if WAS/Nodeagent NOT started
            if [ $? -eq 1 ]
            then
               chk_status 0 "JVM process on ${HOST_LIST[$i]} is NOT running. Continue..." Info

               echo "========== Syncing Node on ${HOST_LIST[$i]}: ========="
               COMMAND="ssh ${HOST_LIST[$i]} -f \"(${BIN}/./syncNode.sh ${WC_HOST} 8879 ${TONULL}) & \""
               echo "${COMMAND}"
               eval ${COMMAND} > /dev/null 2>&1 < /dev/null &

            else
               ### NOTE: Should be removed to force fail on NodeSync check??
               ###       Add retry posibility??
               ###       Remove from array and proceed manually??
               chk_status 0 "Sync cannot be started on ${HOST_LIST[$i]}. JVM is running!!! Proceed manually. Continue..." Error
               send_alert_mail

            fi

         done

      ;;

      *)
         chk_status 1 "was_restart: wrong action specified!" Error
      ;;

   esac
   HOST_LIST=()
   SERV_LIST=()
   QNTTY_LIST=()
}

##################################################
### Check Sync/App state
### Accepts parameters:
###  $1 -> action (app_stat; sync_stat)
###################################################
chk_action_stat () {
   ## Define action
   case $1 in

      # check Sync Node status
      sync_stat)

         SERV_LIST_NEW=()
         QNTTY_LIST_NEW=()
         HOST_LIST_NEW=()
         # convert time stamp to log format e.g 9/26/19 4:59
         TIME_STAMP=`date +%-m/%-d/%y`
         # succesfull log message e.g "NodeSyncTask  A   ADMS0003I: The configuration synchronization completed successfully"
         MESSAGE="The\ configuration\ synchronization\ completed\ successfully"
         ERROR="\ E\ "
         SYNC_TIMEOUT=180

         app_host_arr_size=${#HOST_LIST[@]};
         serv_count=0

         for (( i=0; i<${app_host_arr_size}; i++ ));
         do

            (( serv_count+=${QNTTY_LIST[$i]} ))
            retry=0
            retry_max=2
            while [ "${retry}" -lt "${retry_max}" ];
            do

               retry=$(( retry+1 ))

               echo " "
               echo "========== Checking Sync Node process status on ${HOST_LIST[$i]}: ========="
               ssh ${HOST_LIST[$i]} "ps -ef | grep  syncNode.sh | grep -v grep > /dev/null"; PROCESS_RUN=1;
               ssh ${HOST_LIST[$i]} "grep ${TIME_STAMP} ${LOGS}/syncNode.log | grep ${MESSAGE} | grep -v grep > /dev/null"; SYNC_STATE=0;
               ssh ${HOST_LIST[$i]} "grep ${TIME_STAMP} ${LOGS}/syncNode.log | grep ${ERROR} | grep -v grep > /dev/null"; ERROR_EXIST=1;

               # if error do  NOT detected in syncNode.log
               # AND if ./syncNode.sh process do NOT detected
               # AND if success ${MESSAGE} detected in syncNode.log
               if [[ ${ERROR_EXIST} -eq 1 && ${PROCESS_RUN} -eq 1 && ${SYNC_STATE} -eq 0 ]];
               then
                  echo "Issue(s) detected: no (${ERROR_EXIST}) JVM detected: no (${PROCESS_RUN}) Success message detected: yes ($SYNC_STATE)"
                  chk_status 0 "Sync Node completed successfully." Info
                  retry=$(( retry_max+1 ))

                  QNTTY_LIST_NEW+=(${QNTTY_LIST[$i]})
                  HOST_LIST_NEW+=(${HOST_LIST[$i]})
                  for (( j=0; j<${QNTTY_LIST[$i]}; j++ ));
                  do
                     d=${QNTTY_LIST[$i]}
                     k=$(( serv_count-d+j ))
                     SERV_LIST_NEW+=(${SERV_LIST[$k]});
                  done

               else

                  # Process ./syncNode.sh running
                  if [[ ${PROCESS_RUN} -ne 1 ]];
                  then
                     chk_status 0 "chk_action_stat: sync_stat: ./syncNode.sh in progress on ${HOST_LIST[$i]}. " Info

                     if [[ "${retry}" -le "${retry_max}" ]];
                     then
                        chk_status 0 "  Waiting ${SYNC_TIMEOUT}..." Info
                        sleep ${SYNC_TIMEOUT};
                        chk_status 0 "Retrying..." Info
                     else
                        chk_status 0 "  Still in progress! Check manually. Skipping..." Error
                        send_alert_mail
                     fi

                  # ${MESSAGE} - success message not found
                  elif [[ ${SYNC_STATE} -ne 0 ]];
                  then
                     chk_status 0 "${HOST_LIST[$i]}: Success message do not found in syncNode.log. Skipping..." Error
                     send_alert_mail
                     retry=$(( retry_max+1 ))

                  # ${ERROR_EXIST} - error exists during Sync Node
                  elif [[ ${ERROR_EXIST} -ne 1 ]];
                  then
                     chk_status 0 "SyncNode ${HOST_LIST[$i]}: Errors detected in syncNode.log. Skipping..." Error
                     send_alert_mail
                     retry=$(( retry_max+1 ))
                  fi

               fi

            done
         done

      #   SERV_LIST=()
      #   QNTTY_LIST=()
      #   HOST_LIST=()

      #   SERV_LIST=${SERV_LIST_NEW[@]}
      #   QNTTY_LIST=${QNTTY_LIST_NEW[@]}
      #   HOST_LIST=${HOST_LIST_NEW[@]}

      ;;

      ## Check Dynacache App status
      app_stat)

      SERV_LIST_NEW=()
      QNTTY_LIST_NEW=()
      HOST_LIST_NEW=()
      k=0

      for (( i=0; i<${#HOST_LIST[@]}; i++ ))
      do
         for (( j=0; j<${QNTTY_LIST[$i]}; j++))
         do
            RESP_CODE=$(ssh ${WC_HOST} -f "curl --connect-timeout 5 -b cookie.txt -c cookie.txt -o /dev/null -Isw '%{http_code}' ${PROTOCOL}://${HOST_LIST[$i]}.sectmw.com:${CACHE_PORTS[$j]}/cachemonitor/")
            if [[ "${RESP_CODE}" -eq "200" ]];
            then
               SERV_LIST_NEW+=(${SERV_LIST[$k]});
               chk_status 0 "App Status ${HOST_LIST[$i]}:${SERV_LIST[$k]}: UP." Info
               if [[ "j" -eq "$(( ${QNTTY_LIST[$i]}-1 ))" ]];
               then
                  QNTTY_LIST_NEW+=(${QNTTY_LIST[$i]})
                  HOST_LIST_NEW+=(${HOST_LIST[$i]})
               fi
            else
               chk_status 0 "App Status ${HOST_LIST[$i]}:${SERV_LIST[$k]}: DOWN. Please check serverStart.log! Continue..." Error
               send_alert_mail
            fi
            k=$(($k + 1))
         done

      done

      ## Less then 70% of servers started
      if  [[ "${#SERV_LIST_NEW[@]}" -le "$(( ${#SERV_LIST[@]}*70/100 ))" ]];
      then
         chk_status 1 "chk_action_stat: app_stat: Less then 70% of App servers started! Quantity started: ${#SERV_LIST_NEW[@]}." Error
      fi
      #HOST_LIST=(${HOST_LIST_NEW[@]})
      #SERV_LIST=(${SERV_LIST_NEW[@]})
      #QNTTY_LIST=(${QNTTY_LIST_NEW[@]})
      ;;

      *)
         chk_status 1 "chk_stat: Wrong action specified!" Error
      ;;

   esac

}

##################################################
### Clear WAS profile root temp dir
### Accepts parameters:
###  $1 -> env name (prd; stg; tst; dev; etc)
###################################################
was_clear_temp_dir () {

   TEMP="${WAS}/profiles/${INS}/temp"

   for HOST in ${APP_HOST[@]}; do

   echo "========== Clear profile_root temp on ${HOST}: =================="

   case $1 in

      dev|dev2|dev3|dev4|dev5|tst|tst2|tst3|tst4|tst5|stg)
         ssh ${HOST} -tt "find ${TEMP}/WC_*_node/server*/WC_${INS}/Stores.war/*AuroraStorefrontAssetStore/ -type f -print -delete"
      ;;

      prd)
         ssh ${HOST} -tt "find ${TEMP}/WC_*_node/wc_*lone*/WC_${INS}/Stores.war/*AuroraStorefrontAssetStore/ -type f -print -delete"
      ;;

      *)
        chk_status 1 "was_partial_deploy: Env name to clear profiles/${INS}/temp dir incorrect! ($1)" Error
      :;

   esac
   done

}


##################################################
### Partial WC App deployment
### Accepts parameters:
###  $1 -> env name (prd; stg; tst; dev; etc)
###  $2 -> partial_app; partial_log; partial_dat
###################################################
was_partial_deploy () {

   CUR_DIR="$(pwd)"
   SRC_DIR="${WAS}/source"
   DMGR_BIN="${WAS}/profiles/Dmgr01/bin"
   WSADMIN="${DMGR_BIN}/wsadmin.sh"
   PY_DIR="${WAS}/scripts/jython"
   APP_EAR="WC_${INS}"

   case $2 in
      partial_app)
         PY_SCRIPT="partialApp.py"
         TARGET_FILE="partialApp.zip"
      ;;

      partial_log)
         PY_SCRIPT="partialLogic.py"
         TARGET_FILE="WebSphereCommerceServerExtensionsLogic.jar"
      ;;

      partial_dat)
         PY_SCRIPT="partialData.py"
         TARGET_FILE="WebSphereCommerceServerExtensionsData.jar"
      ;;

      *)
        chk_status 1 "was_partial_deploy: Wrong param passed($1)! Expected: partial_app; partial_log; partial_dat." Error
      ;;

   esac

   ## Update *.py scripts
   sed -i -E "s/WC_[a-z]+01/${APP_EAR}/" ${CUR_DIR}/${PY_SCRIPT}
   grep ${APP_EAR} ${CUR_DIR}/${PY_SCRIPT} > /dev/null; rc=$?;
   if [[ "${rc}" -ne "0" ]]; then
      chk_status 1 "was_partial_deploy: Application ${APP_EAR} not found @ ${CUR_DIR}/${PY_SCRIPT}!" Error
   fi

   ssh ${WC_HOST} -f " if [[ ! -d ${SRC_DIR} ]]; then mkdir ${SRC_DIR}; fi \
      if [[ ! -d ${PY_DIR} ]]; then mkdir ${PY_DIR}; fi \
      if [[ -f ${SRC_DIR}/${TARGET_FILE} ]]; then rm ${SRC_DIR}/${TARGET_FILE}; fi \
   /"

   ## Upload data and start partial deployment
   scp ${CUR_DIR}/${PY_SCRIPT} ${WC_HOST}:${PY_DIR}/
   scp ${CUR_DIR}/${TARGET_FILE} ${WC_HOST}:${SRC_DIR}/

   ssh ${WC_HOST} -f "${WSADMIN} ${PY_DIR}/${PY_SCRIPT} > /dev/null 2>&1 < /dev/null &"  > /dev/null 2>&1 < /dev/null &

   sleep 500

   for HOST in ${APP_HOST[@]}; do

   echo "Clear profile on ${HOST}:"

   case $1 in

      dev|dev2|dev3|dev4|dev5|tst|tst2|tst3|tst4|tst5|stg)
         ssh ${HOST} -tt "find ${TEMP}/WC_*_node/server*/WC_${INS}/Stores.war/* -type f -print -delete"
      ;;

      prd)
         ssh ${HOST} -tt "find ${TEMP}/WC_*_node/wc_*lone*/WC_${INS}/Stores.war/* -type f -print -delete"
      ;;

      *)
        chk_status 1 "was_partial_deploy: Env name to clear profiles/${INS}/temp dir incorrect! ($1)" Error
      :;

   esac
   done

}

##################################################
### Restore manifest.json
### Accepts params:
###  $1 -> action: restore; backup
###  $2 -> file new/old
###################################################
restore_manifest () {

   EAR_DIR="/usr/opt/app/IBM/WebSphere/AppServer/profiles/${INS}/installedApps/WC_${INS}_cell/WC_${INS}.ear"

   sufix="$2"
   for HOST in ${APP_HOST[@]}; do

      case $1 in
         backup)
            chk_status 0 "restore_manifest: Backup manifest.json: " Info
            ssh ${HOST} -tt "cp -av ${EAR_DIR}/Stores.war/MWAuroraStorefrontAssetStore/minify/manifest.json ${EAR_DIR}/../backup/manifest.json.MW.${sufix}; cp -av ${EAR_DIR}/Stores.war/JABAuroraStorefrontAssetStore/minify/manifest.json ${EAR_DIR}/../backup/manifest.json.JAB.${sufix}"
         ;;

         restore)
            chk_status 0 "restore_manifest: Retore  manifest.json: " Info
            ssh ${HOST} -tt "cp -av ${EAR_DIR}/../backup/manifest.json.MW.${sufix} ${EAR_DIR}/Stores.war/MWAuroraStorefrontAssetStore/minify/manifest.json; cp -av ${EAR_DIR}/../backup/manifest.json.JAB.${sufix} ${EAR_DIR}/Stores.war/JABAuroraStorefrontAssetStore/minify/manifest.json"
         ;;

         *)
           chk_status 0 "restore_manifest: action specified incorrect!" Info
         ;;

      esac

   done
}

#########################################
###              MAIN                 ###
#########################################
case $1 in

   prd_solr)
      define_env prd1
      was_restart solr stop
      sleep 5m

      was_restart solr sync
      sleep 7m

      was_restart solr start

      define_env prd2
      was_restart solr stop
      sleep 5m

      was_restart solr sync
      sleep 7m

      was_restart solr start

   ;;

   prd_test)
      define_env prd2
         BIN=${WASBIN}
         LOGS=${WASLOG}
         PS="${INS}_node"
         HOST_LIST=( "${APP_HOST[@]}" )
         SERV_LIST=( "${APP_SERV[@]}" )
         QNTTY_LIST=( "${APP_QNTTY[@]}")
         CACHE_PORTS=(10117 10147)
         PROTOCOL="https"
      #set -x
      chk_action_stat sync_stat

   ;;

   prd_wc)
      define_env prd1
      was_restart wc stop
      restore_manifest backup old
      sleep 5m

      was_restart wc sync
      sleep 35m

      echo "=== 30 mins have passed ===="
      restore_manifest backup new
      restore_manifest restore old
      was_restart wc start 25m

      define_env prd2
      was_restart wc stop
      sleep 5m

      was_restart wc sync
      sleep 35m

      echo "=== 30 mins have passed ===="

      was_restart wc start 25m

      define_env prd1
      restore_manifest restore new

   ;;

   prd_grp1_restore_manifest)
      define_env prd1
      restore_manifest restore new
   ;;

   prd_clear_temp)
      define_env prd1
      was_clear_temp_dir prd

      define_env prd2
      was_clear_temp_dir prd
   ;;

   *)
      define_env $1
      was_restart $2 $3
   ;;
esac
