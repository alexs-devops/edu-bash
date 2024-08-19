#!/bin/bash
#set -x
##########################################################################################
###
### Script to clear Redis cache
###  $1 -> Environment (e.g DEV1|DEV2|DEV3|DEV4|STG, etc)
###  $2 -> Redis DB number (e.g 1|2)
###  $3 -> Redis key
##########################################################################################

### Define variables
REDIS_OPT=$2
Datetime=`date '+%Y%m%d_%H%M%S'`
WRK_DIR="/usr/opt/app/Ecom_V9/source/csrapp"
GC_SDK_DIR="/usr/opt/app/gcloud/google-cloud-sdk"
CICD_DIR="/opt/cicd"
REDIS_MASTER="hcl-commerce-redis-master-0"
REDIS_DB="$2"
REDIS_KEY="$3"

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
   DEV1|TST1|DEV2|TST2|DEV3|TST3|DEV4|TST4|DEV6|TST6|DEV7|TST7|DEV8|TST8|DEV9|TST9|DEV10|TST10|STG|PRD)
     env_num=`echo "${ENV}" | grep -Eo '[0-9]+$'`
     env_sym=`echo ${ENV,,} | grep -Eoh '[[:alpha:]]*'`
     GC_NAMESPC=`echo ${ENV,,}`
     GC_NAMESPC_REDIS="dev${env_num}"
   ;;&

   PRD|STG)
     GC_NAMESPC_REDIS="stg"
   ;;&

   #####################################################################
   # GCP SECTION: Credentials, App pod name
   #####################################################################
   DEV1|TST1|DEV2|TST2|DEV3|TST3|DEV9|TST9)
      GC_PROJ=""
      GC_CL=""
      GC_SA="@.iam.gserviceaccount.com"
      GC_SA_KEY="${GC_SDK_DIR}/.json"
   ;;

   DEV10|TST10)
      GC_PROJ=""
      GC_CL=""
      GC_SA="@.iam.gserviceaccount.com"
      GC_SA_KEY="${GC_SDK_DIR}/.json"
   ;;

   PRD|STG)
      GC_PROJ=""
      GC_CL=""
      GC_SA="@.iam.gserviceaccount.com"
      GC_SA_KEY="${GC_SDK_DIR}/.json"
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
    fi
    ${GC_SDK_DIR}/bin/gcloud container clusters get-credentials ${GC_CL} --region us-east4 --project ${GC_PROJ}
}

##############################
### MAIN
##############################

print_message "INFO" "Date: ${Datetime}."

gc_env $1

gc_auth

# Correct $PATH
if ! echo $PATH | grep ${GC_SDK_DIR};
then
   export PATH="${PATH}:${GC_SDK_DIR}/bin"; echo ${PATH}
fi


if [[ ! -z ${GC_NAMESPC_REDIS} ]];
then
   print_message "INFO" "Command execution: kubectl exec ${REDIS_MASTER} -n ${GC_NAMESPC_REDIS} -- redis-cli -n ${REDIS_DB} unlink ${REDIS_KEY}"
   ${GC_SDK_DIR}/bin/kubectl exec ${REDIS_MASTER} -n ${GC_NAMESPC_REDIS} -- redis-cli -n ${REDIS_DB} unlink ${REDIS_KEY}
   rc=$?;
   if [ "${rc}" != "0" ]; then
      print_message "ERROR" "Command 'kubectl exec' failed!"
   fi
else
   print_message "INFO" "No redis cache configured for ${ENV}.";
   exit 1
fi

Datetime=`date '+%Y%m%d_%H%M%S'`
print_message "INFO" "Completed. Date: ${Datetime}."

