#!/bin/bash
#set -x
##########################################################################################
###
### Script to export data from Redis to CACHEIVL:
###  $1 -> Environment (e.g TST1|PRD, etc)
###
##########################################################################################

### Define variables
ORIG_ENV=$1
Datetime=`date '+%Y%m%d_%H%M%S'`
WRK_DIR="/usr/opt/app/Ecom_V9/source/ecomutil/scripts/redis"
REM_DIR="/scripts/redis/"
GC_SDK_DIR="/usr/opt/app/gcloud/google-cloud-sdk"
CICD_DIR="/opt/cicd"

hostname

###################################################
### Message handler GUI. Accepts parameters:
###  $1 -> environmet (e.g Error; Warning; etc)
###################################################
gc_env (){
ENV=$1

case ${ENV} in

   DEV1|DEV2|DEV3|DEV9|DEV10|STG)
      env_num=`echo "${ENV}" | grep -Eo '[0-9]+$'`
      GC_WRKLOAD="ecomenv${env_num}authts-utils"
      GC_NAMESPC="${ENV,,}"
      REDIS_POD="hcl-commerce-redis-master-0"
   ;;&

   DEV1|DEV2|DEV3|DEV9)
      GC_PROJ=""
      GC_CL=""
      GC_SA="@.iam.gserviceaccount.com"
      GC_SA_KEY="${GC_SDK_DIR}/.json"
      GC_IMAGE="us.gcr.io//commerce/ts-utils"
   ;;

   DEV10)
      GC_PROJ=""
      GC_CL=""
      GC_SA="@.iam.gserviceaccount.com"
      GC_SA_KEY="${GC_SDK_DIR}/.json"
      GC_IMAGE="us.gcr.io//commerce/ts-utils"
   ;;

   STG)
      GC_PROJ=""
      GC_CL=""
      GC_SA="@.iam.gserviceaccount.com"
      GC_SA_KEY="${GC_SDK_DIR}/.json"
      GC_IMAGE="us.gcr.io//commerce/ts-utils"
      GC_WRKLOAD="ecomprodauthts-utils"
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
       #${GC_SDK_DIR}/bin/gcloud container clusters get-credentials ${GC_CL} --region us-east4 --project ${GC_PROJ}
    fi
    ${GC_SDK_DIR}/bin/gcloud container clusters get-credentials ${GC_CL} --region us-east4 --project ${GC_PROJ}
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

## Define auth env
env_num=`echo "${ORIG_ENV}" | grep -Eo '[0-9]+$'`
case ${ORIG_ENV} in

   TST1|TST2|TST3|TST4|TST6|TST7|TST8|TST9|TST10)
      ENV="DEV${env_num}"
   ;;

   PRD)
      ENV="STG"
   ;;

esac

## Get credentials
# Correct $PATH
if ! echo $PATH | grep ${GC_SDK_DIR};
then
   export PATH="${PATH}:${GC_SDK_DIR}/bin"; echo ${PATH}
fi

gc_env ${ENV}

## Copy script to Redis
print_message "INFO" "Copy script to Redis:"
${GC_SDK_DIR}/bin/kubectl cp ${WRK_DIR}/redis_export_for_eviction.sh ${REDIS_POD}:/tmp/redis_export_for_eviction.sh -n ${GC_NAMESPC}
chk_exit_status "$?" "kubectl: Copying script failed! Exiting..."

## Execute cript on Redis
print_message "INFO" "Execute script on Redis:"
${GC_SDK_DIR}/bin/kubectl exec -it ${REDIS_POD} -n ${GC_NAMESPC} -- /bin/sh -c "cd /tmp/; chmod 755 ./redis_export_for_eviction.sh; ./redis_export_for_eviction.sh 127.0.0.1" 
chk_exit_status "$?" "kubectl: Executing script failed! Exiting..."

## Copy file from Redis to ts-utils
print_message "INFO" "Copy /tmp/redis_eviction.csv from Redis:"
${GC_SDK_DIR}/bin/kubectl cp ${REDIS_POD}:/tmp/redis_eviction.csv /tmp/redis_eviction.csv -n ${GC_NAMESPC}
chk_exit_status "$?" "kubectl: Copying csv failed! Exiting..."

# get pod name
utilpod=`${GC_SDK_DIR}/bin/kubectl get pods -n ${GC_NAMESPC} | grep ts-util | tail -1 | awk '{print $1}'`
chk_exit_status "$?" "kubectl: Getting pod failed! Exiting..."
print_message "INFO" "ts-utils pod: ${utilpod}";

# create dir
${GC_SDK_DIR}/bin/kubectl exec -it ${utilpod} -n ${GC_NAMESPC} -- /bin/bash -c "mkdir -p ${REM_DIR}" 
chk_exit_status "$?" "kubectl: Creating dir failed! Exiting..."

# copy csv file
print_message "INFO" "Copy /tmp/redis_eviction.csv to ts-utils:${REM_DIR}:"
${GC_SDK_DIR}/bin/kubectl cp /tmp/redis_eviction.csv ${utilpod}:${REM_DIR}/redis_eviction.csv -n ${GC_NAMESPC}
chk_exit_status "$?" "kubectl: Copying csv failed! Exiting..."

## Execute script on ts-util
print_message "INFO" "Executing script on ts-utils:"
${GC_SDK_DIR}/bin/kubectl cp ${WRK_DIR}/redis_cacheivl_insert.sh ${utilpod}:${REM_DIR}/redis_cacheivl_insert.sh -n ${GC_NAMESPC}
${GC_SDK_DIR}/bin/kubectl exec -it ${utilpod}  -n ${GC_NAMESPC} -- /bin/bash -c "cd ${REM_DIR}; chmod 755 redis_cacheivl_insert.sh; ./redis_cacheivl_insert.sh ${ORIG_ENV}"
chk_exit_status "$?" "kubectl: Executing script failed! Exiting..."


## Clean up
if [[ -f /tmp/redis_eviction.csv ]];
then
   rm -v /tmp/redis_eviction.csv;
fi

Datetime=`date '+%Y%m%d_%H%M%S'`
print_message "INFO" "Completed. Date: ${Datetime}."

