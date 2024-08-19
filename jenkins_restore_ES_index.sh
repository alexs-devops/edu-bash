#!/bin/bash
#set -x
##########################################################################################
###
### Script backup/restore ES index. Accepts parameters:
###  $1 -> Environment (e.g DEV1|DEV2|DEV3|DEV4|STG, etc)
###  $2 -> Backup name
###  $3 -> Restore common indices (YES|NO)
###  $4 -> Timestamp of the backup indices from snapshot. Ex: 202311011544 (NOT_NEEDED)
###  $5 -> Timestamp of the current/existing indices. Ex: 202311162258 (NOT_NEEDED)
###
##########################################################################################

### Define variables
BCKUP_NAME="$2"
RESTORE_COMMON="$3"
ENV_TYPE=$(echo ${BCKUP_NAME} | awk -F '_' '{ print $1 }')
STORE_ID=$(echo ${BCKUP_NAME} | awk -F '_' '{ print $2 }')

Datetime=`date '+%Y%m%d_%H%M%S'`
GC_SDK_DIR="/usr/opt/app/gcloud/google-cloud-sdk"

hostname

###################################################
### Message handler GUI. Accepts parameters:
###  $1 -> environmet (e.g Error; Warning; etc)
###################################################
gc_env (){

ENV=$1
case ${ENV} in

   #####################################################################
   # GENERAL SECTION: ALL environments should be added here
   #####################################################################
   DEV1|DEV2|DEV3|DEV9|DEV10|STG)
      env_num=`echo "${ENV}" | grep -Eo '[0-9]+$'`
      env_sym=`echo ${ENV,,} | grep -Eoh '[[:alpha:]]*'`
      env_purp="auth"
      env_def="${ENV,,}"
   ;;&

   #####################################################################
   # ES POD SECTION: App pod name
   #####################################################################
   DEV1|DEV2|DEV3|DEV9|DEV10|STG)
      GC_WRKLOAD="hcl-commerce-elasticsearch"
      ES_POD="hcl-commerce-elasticsearch-0"
   ;;&

   #####################################################################
   # GCP SECTION: Credentials, App pod name
   #####################################################################
   DEV1|DEV2|DEV3|DEV9)
      GC_PROJ=""
      GC_CL=""
      GC_SA="@.iam.gserviceaccount.com"
      GC_SA_KEY="${GC_SDK_DIR}/.json"
      GC_NAMESPC="${env_def}"
   ;;

   DEV10)
      GC_PROJ=""
      GC_CL=""
      GC_SA="@.iam.gserviceaccount.com"
      GC_SA_KEY="${GC_SDK_DIR}/.json"
      GC_NAMESPC="${env_def}"
   ;;

   STG)
      GC_PROJ=""
      GC_CL=""
      GC_SA="@.iam.gserviceaccount.com"
      GC_SA_KEY="${GC_SDK_DIR}/.json"
      GC_NAMESPC="${env_sym}"
   ;;

   *)
     echo "[ERROR]: Env name incorrect!"; exit 1;
   ;;
esac
}

###################################################
### Message handler GUI. Accepts parameters:
###  $1 -> error severity (e.g Error; Warning; etc)
###  $2 -> message
###  $3 -> exit status (optional)
###  $4 -> if not null, frame will not be printed
###################################################
print_message (){
   if [ ! -z "$3" ]; then exit_stat="(Exit status: $3)"; fi

   message="[$1]: $2 ${exit_stat}"; exit_stat="";

   if [ -z "$4" ]; then
      echo "************************************************************************************"
      echo "${message}";
      echo "************************************************************************************"
   else
      echo "${message}";
   fi
}

###################################################
### Executes gcloud auth and gcloud get-credentials
###################################################
gc_auth (){
    if ${GC_SDK_DIR}/bin/gcloud auth list --filter=status:ACTIVE | grep ${GC_SA} ;
    then
       print_message "INFO" "gc_auth: ${GC_SA} account is active." "" "no_frame"
    else
       ${GC_SDK_DIR}/bin/gcloud auth activate-service-account ${GC_SA} --key-file=${GC_SA_KEY}
       ${GC_SDK_DIR}/bin/gcloud container clusters get-credentials ${GC_CL} --region us-east4 --project ${GC_PROJ}
    fi
}

#########################################################
### Check exit status
### $1 -> exit status code
### $2 -> Message on error
#########################################################
chk_exit_status (){

   cat ${LOG_OUT}; echo " ";
   if [ "${rc}" = "0" ];
   then
      print_message "ERROR" "$2" "$1";
   exit 1;

fi

}

##############################
### MAIN
##############################

print_message "INFO" "Date: ${Datetime}."

gc_env $1

# Correct $PATH
if ! echo $PATH | grep ${GC_SDK_DIR};
then
   export PATH="${PATH}:${GC_SDK_DIR}/bin"; echo ${PATH}
fi

gc_auth
${GC_SDK_DIR}/bin/gcloud container clusters get-credentials ${GC_CL} --region us-east4 --project ${GC_PROJ}

LOG_OUT=/tmp/es_restore.log

## Check if backup exists
print_message "INFO" "Check if snapshot exists:"
kubectl exec -it ${ES_POD} -n ${GC_NAMESPC} -- curl -sk 'localhost:9200/_snapshot/backup/*' > ${LOG_OUT} 2>&1
if ! grep ${BCKUP_NAME} ${LOG_OUT};
then
   print_message "ERROR" "Backup name ${BCKUP_NAME} not found!";
   exit 1;
fi

## Check ES state is not red
print_message "INFO" "Check ES status:"
kubectl exec -it ${ES_POD} -n ${GC_NAMESPC} -- curl -sk 'localhost:9200/_cluster/health?pretty' | jq --exit-status '.status == "red"' > ${LOG_OUT} 2>&1
chk_exit_status "$?" "kubectl: ES status is red! Exiting..."

## Restore Snapshot/indices
# restore the common indices
if [[ "${RESTORE_COMMON}" = "${YES}" ]];
then
   gc_auth
   print_message "INFO" "Restore the common indices:"
   kubectl exec -it ${ES_POD} -n ${GC_NAMESPC} -- curl -X POST "http://localhost:9200/_snapshot/backup/${BCKUP_NAME}/_restore" \
   --header 'Content-Type: application/json' \
   --data "{ \"indices\": \"${ENV_TYPE}*\", \"ignore_unavailable\": true, \"include_global_state\": false, \"rename_pattern\": \"${ENV_TYPE}(.+)\", \"rename_replacement\": \"restored_index_${ENV_TYPE}\$1\", \"include_aliases\": false }" > ${LOG_OUT} 2>&1
   chk_exit_status "$?" "kubectl: restore from snapshot failed! Exiting..."

   # list of common ondices based on ${ENV_TYPE}
   if [[ "${ENV_TYPE}" = "auth" ]];
   then
      common_indices_list=(price workspace inventory store)
   elif [[ "${ENV_TYPE}" = "live" ]];
      common_indices_list=(price inventory store)
   else
      print_message "INFO" "Environment type defined incorrect! ${ENV_TYPE}";
      exit 1
   fi

   # delete and re-index the common indice
   for indice in ${common_indices_list[@]};
   do
      common_indice=${ENV_TYPE}.${indice}
      print_message "INFO" "Delete the common indice ${common_indice}:"
      gc_auth
      kubectl exec -it ${ES_POD} -n ${GC_NAMESPC} -- curl -X DELETE "localhost:9200/${common_indice}?pretty"
      chk_exit_status "$?" "kubectl: delete ${common_indice} failed! Exiting..."

      print_message "INFO" "Reindex the restored ${common_indice} index to rename it:"
      kubectl exec -it ${ES_POD} -n ${GC_NAMESPC} -- curl -X POST "localhost:9200/_reindex?pretty" -H 'Content-Type: application/json' -d '{ "source": { "index": "restored_index_${common_indice}" }, "dest": { "index": "${common_indice}" } }'
      chk_exit_status "$?" "kubectl: re-index ${common_indice} failed! Exiting..."
   done

fi

# restore store indices like .auth.${STORE_ID}.<indice>
print_message "INFO" "Restore store indices like .auth.${STORE_ID}.<indice>:"
gc_auth
kubectl exec -it ${ES_POD} -n ${GC_NAMESPC} -- curl -X POST "http://localhost:9200/_snapshot/backup/${BCKUP_NAME}/_restore" \
--header 'Content-Type: application/json' \
--data "{ \"indices\": \".${ENV_TYPE}*\", \"ignore_unavailable\": true, \"include_global_state\": false, \"include_aliases\": false }" > ${LOG_OUT} 2>&1
#--data "{ \"indices\": \".${ENV_TYPE}*\", \"ignore_unavailable\": true, \"include_global_state\": false, \"rename_pattern\": \".${ENV_TYPE}(.+)\", \"rename_replacement\": \"restored_index_${ENV_TYPE}\$1\", \"include_aliases\": false }" > ${LOG_OUT} 2>&1
chk_exit_status "$?" "kubectl: restore from snapshot failed! Exiting..."

## Switch the aliases for store indices like .auth.${STORE_ID}.<indice>

# Get new timestamp from .snapshots[].indices[] for snapshots[].snapshot == ${BCKUP_NAME}
new_timestmp="$(kubectl exec -it ${ES_POD} -n ${GC_NAMESPC} -- curl -X GET 'http://localhost:9200/_snapshot/backup/*' | jq -r ".snapshots[] | select (.snapshot == \"${BCKUP_NAME}\").indices[]" | grep -m1 $(date +%Y) | awk -F '.' '{ print $5 }')"
if [[ ! ${new_timestmp} =~ ^[0-9]+$ ]]
then
   print_message "ERROR" "Unable to get restored indice timestamp from snapshot: ${new_timestmp}";
   exit 1;
fi

#new_timestmp="$4"
#old_timestmp="$5"

indices_list=(attribute catalog category description product url)
for indice in ${indices_list[@]};
do

   alias_name="${ENV_TYPE}.${STORE_ID}.${indice}"
   print_message "INFO" "Switch the aliase ${alias_name}:"

   # get old index
   gc_auth
   old_index_name=`kubectl exec -it ${ES_POD} -n ${GC_NAMESPC} -- curl -X GET "http://localhost:9200/${alias_name}/_alias" | awk -F '["]' '{print $2}'`
   #old_index_name="${ENV_TYPE}.${STORE_ID}.${indice}.${old_timestmp}"
   print_message "INFO" "Old indice name: ${old_index_name}" "" "no_frame"
   if [[ ! ${old_index_name} == *"${ENV_TYPE}.${STORE_ID}.${indice}"* ]]; then
      print_message "ERROR" "Unable to get current indice name! ${old_index_name} differs from ${ENV_TYPE}.${STORE_ID}.${indice}.<timestamp>.";
      exit 1
   fi

   # get new index
   new_index_name=".${ENV_TYPE}.${STORE_ID}.${indice}.${new_timestmp}"
   print_message "INFO" "New indice name: ${new_index_name}" "" "no_frame"

   # add new indices to alias
   gc_auth
   print_message "INFO" "Add new ${new_index_name} indice to alias:"
   kubectl exec -it ${ES_POD} -n ${GC_NAMESPC} -- curl -X POST 'http://localhost:9200/_aliases' \
   --header 'Content-Type: application/json' \
   --data "{ \"actions\": [ { \"add\": { \"index\": \"${new_index_name}\", \"alias\": \"${alias_name}\" } } ] }"  > ${LOG_OUT} 2>&1
   chk_exit_status "$?" "kubectl: add new indice ${new_index_name} to alias ${alias_name} failed! Exiting...";

   # remove old indice from alias
   gc_auth
   print_message "INFO" "Remove old ${old_index_name} indice from alias:"
   kubectl exec -it ${ES_POD} -n ${GC_NAMESPC} -- curl -X POST 'http://localhost:9200/_aliases' \
   --header 'Content-Type: application/json' \
   --data "{ \"actions\": [ { \"remove\": { \"index\": \"${old_index_name}\", \"alias\": \"${alias_name}\" } } ] }"  > ${LOG_OUT} 2>&1
   chk_exit_status "$?" "kubectl: remove old indice ${old_index_name} from alias ${alias_name} failed! Exiting...";

done

Datetime=`date '+%Y%m%d_%H%M%S'`
print_message "INFO" "Completed. Date: ${Datetime}."
