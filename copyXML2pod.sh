#!/bin/bash
#set -x
##########################################################################################
###
### Script to deploy site map xml files:
###  $1 -> Environment (e.g DEV1|DEV2|DEV3|DEV4|STG, etc)
###
##########################################################################################

### Define variables
Datetime=`date '+%Y%m%d_%H%M%S'`
WRK_DIR=$(pwd)
GC_SDK_DIR="/usr/opt/app/gcloud/google-cloud-sdk"
XML_LIST=(sitemap.xml sitemap_pdp.xml)

hostname

###################################################
### Message handler GUI. Accepts parameters:
###  $1 -> environmet (e.g Error; Warning; etc)
###################################################
gc_env (){

ENV=$1
case ${ENV} in

   #####################################################################
   # AUTH ENVIRONMENT SECTION: ALL DEV/STG environments should be added here
   #####################################################################
   DEV1|DEV2|DEV3|DEV4|DEV6|DEV7|DEV8|DEV9|DEV10|STG)
     env_num=`echo "${ENV}" | grep -Eo '[0-9]+$'`
     env_sym=`echo ${ENV,,} | grep -Eoh '[[:alpha:]]*'`
     GC_PREFIX="ecomenv"
     env_purp="auth"
     env_def="${ENV,,}"
     utilnspc=${env_def}
   ;;&

   STG)
     env_def="${env_sym}"
   ;;&

   #####################################################################
   # LIVE ENVIRONMENT SECTION: ALL TST/PRD environments should be added here
   #####################################################################
   TST1|TST2|TST3|TST4|TST6|TST7|TST8|TST9|TST10|PRD)
     env_num=`echo "${ENV}" | grep -Eo '[0-9]+$'`
     env_sym=`echo ${ENV,,} | grep -Eoh '[[:alpha:]]*'`
     GC_PREFIX="ecomenv"
     env_purp="live"
     env_def="${ENV,,}"
     utilnspc="dev${env_num}"
   ;;&

   PRD)
     env_def="${env_sym}"
     utilnspc="stg"
   ;;&

   #####################################################################
   # OLD ENVIRONMENT SECTION: Old environments with prefix 'ecom'
   # used for pod naming
   #####################################################################
   DEV3|TST3)
     GC_PREFIX="ecom"
   ;;&

   #####################################################################
   # GCP SECTION: Credentials, App pod name
   #####################################################################
   TST1|DEV1|DEV2|TST2|DEV4|TST4|DEV6|TST6|TST9|DEV9)

   ;;

   DEV3|TST3|DEV8|TST8|DEV10|TST10)

   ;;

   STG|PRD)

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
### Check bash exait status. Accepts param:
### $1 -> exit stat
### $2 -> command
###################################################
check_exit_stat (){

   exit_stat="$1"
   if [[ "${exit_stat}" != "0" ]];
   then
      print_message "ERROR" "$2: Command failed." "${rc}"; exit 1;
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
       #/usr/bin/gcloud container clusters get-credentials ${GC_CL} --region us-east4 --project ${GC_PROJ}
    fi
    ${GC_SDK_DIR}/bin/gcloud container clusters get-credentials ${GC_CL} --region us-east4 --project ${GC_PROJ}
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

## Get util pod name
utilpod=$(${GC_SDK_DIR}/bin/kubectl get pods -n ${utilnspc} | grep util | tail -n +1 | awk '{print $1}')

## Copy xml files form util pod
script_path="/scripts//uc4/sitemap"
for xml_file in ${XML_LIST[@]};
do
   print_message "INFO" "Copying ${xml_file} to ${WRK_DIR}"
   ${GC_SDK_DIR}/bin/kubectl cp ${utilpod}:${script_path}/${xml_file} ${WRK_DIR}/${xml_file} -n ${utilnspc};
   check_exit_stat $? "kubectl cp ${utilpod}:${script_path}/${xml_file} ${WRK_DIR}/${xml_file}"

   WEB_DIR="/usr/opt/app/IBM/WebSphere/CommerceServer80/instances/prod01/web/mw"
   for i in 01 02 03 04 05; 
   do
     print_message "INFO" "Copying ${xml_file} to <hotname>${i}:" "" "no_frame";
     scp ${WRK_DIR}/${xml_file} <hostname>${i}:${WEB_DIR};
     check_exit_stat $? "scp" 
   done

done

Datetime=`date '+%Y%m%d_%H%M%S'`
print_message "INFO" "Completed. Date: ${Datetime}."