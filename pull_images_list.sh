#!/bin/bash
# set -x
####################################################################################
#
# Script to update deployed images list:
# images.html
#
####################################################################################

### Define variables
Datetime=`date '+%Y%m%d_%H%M%S'`
WRK_DIR="/usr/opt/app/Ecom_V9/scripts"
GC_SDK_DIR="/usr/opt/app/gcloud/google-cloud-sdk"
CICD_DIR="/opt/cicd"
Env_List=(DEV1 TST1 DEV2 TST2 DEV3 TST3 DEV9 TST9 DEV10 TST10 STG PRD)

hostname

###################################################
### Message handler GUI. Accepts parameters:
###  $1 -> environmet (e.g Error; Warning; etc)
###  $2 -> app or ALL
###################################################
gc_env (){
ENV=$1
APP=$2

Deployments_List=()
case ${ENV} in
   DEV1|DEV2|DEV3|DEV9|DEV10|STG)
     env_num=`echo "${ENV}" | grep -Eo '[0-9]+$'`
     GC_PREFX="ecomenv"
     env_purp="auth"
     if [ "${APP}" == "ALL" ]
     then
        Deployments_List=(${env_purp}cache-app ${env_purp}crs-app ${env_purp}nextjs ${env_purp}nodejs ${env_purp}nodejs- ${env_purp}query-app ${env_purp}reactjs ${env_purp}store-web ${env_purp}ts-app ${env_purp}ts-utils ${env_purp}ts-web ${env_purp}xc-app ingest-app nifi-app query-app registry-app tooling-web)
     fi
   ;;&

   TST1|TST2|TST3|TST9|TST10|PRD)
     env_num=`echo "${ENV}" | grep -Eo '[0-9]+$'`
     GC_PREFX="ecomenv"
     env_purp="live"
     if [ "${APP}" == "ALL" ]
     then
        Deployments_List=(${env_purp}cache-app ${env_purp}crs-app ${env_purp}csrapp ${env_purp}nextjs ${env_purp}nodejs ${env_purp}nodejs- ${env_purp}query-app ${env_purp}reactjs ${env_purp}store-web ${env_purp}ts-app ${env_purp}ts-web ${env_purp}xc-app tooling-web)
     fi
   ;;&

   TST1|DEV1|TST2|DEV2|DEV3|TST3|TST9|DEV9)
      GC_PROJ=""
      GC_CL=""
      GC_SA="@.iam.gserviceaccount.com"
      GC_SA_KEY="${GC_SDK_DIR}/.json"
      GC_IMAGE_PATH="us.gcr.io//commerce"
      GC_WRKLOAD_PRFX="${GC_PREFX}${env_num}"
      GC_NAMESPC="${ENV,,}"
   ;;

   TST10|DEV10)
      GC_PROJ=""
      GC_CL=""
      GC_SA="@.iam.gserviceaccount.com"
      GC_SA_KEY="${GC_SDK_DIR}/.json"
      GC_IMAGE_PATH="us.gcr.io//commerce"
      GC_WRKLOAD_PRFX="${GC_PREFX}${env_num}"
      GC_NAMESPC="${ENV,,}"
   ;;

   STG|PRD)
      GC_PREFX="ecomprod"
      GC_PROJ=""
      GC_CL=""
      GC_SA="@.iam.gserviceaccount.com"
      GC_SA_KEY="${GC_SDK_DIR}/.json"
      GC_IMAGE_PATH="us.gcr.io//commerce"
      GC_WRKLOAD_PRFX="${GC_PREFX}"
      GC_NAMESPC="${ENV,,}"
   ;;

   *)
      echo "[ERROR]: Env name incorrect (${ENV})!"; exit 1;
   ;;
esac

#add specific app to proceed
if [ "${APP}" != "ALL" ]
then
   Deployments_List+=(${APP})
fi

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

#########################################################
### Sent alert mail
#########################################################
mail_send (){
   mail_to="as511@.com"
   mail_subj="[ERROR]: images.html: ${ENV}: ${APP}: record count too low"
   mail_body="[Datetime]: ${0}: Records count has been decreased, during the images.html modification. File restored from backup. Check images.html deployment logs."

   echo "${mail_body}" | mutt -s "${mail_subj}" -- ${mail_to}; rc="$?";
   if [ "${rc}" != "0" ]; then
      print_message "WARN" "mail_send: Sent mail failed!" "${rc}"
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

###################################################
### Executes kubectl get deployments
###################################################
gc_get_deployment (){
   print_message "INFO" "gc_get_deployment: get deployments list:"
   deployments_list_file="${WRK_DIR}/deployments_list.txt"
   #${GC_SDK_DIR}/bin/kubectl get deployment -n ${GC_NAMESPC} -o jsonpath='{range .items[*]}{@.metadata.name}{" "}{@.spec.template.spec.containers[*].image}{"\n"}{end}' | column -t | grep ${GC_PREFX} > ${deployments_list_file}

   # Correct $PATH
   if ! echo $PATH | grep ${GC_SDK_DIR};
   then
     export PATH="${PATH}:${GC_SDK_DIR}/bin"; echo ${PATH}
   fi

   ${GC_SDK_DIR}/bin/kubectl get deployment -n ${GC_NAMESPC} -o jsonpath='{range .items[*]}{@.metadata.name}{" "}{@.spec.template.spec.containers[*].image}{"\n"}{end}' | column -t | grep ${GC_PREFX} > ${deployments_list_file}.tmp

   # PRD: 'ts-utils' located at 'cicd' namespace
   if [[ "${ENV}" == "PRD" ]];
   then
      ${GC_SDK_DIR}/bin/kubectl get deployment -n cicd -o jsonpath='{range .items[*]}{@.metadata.name}{" "}{@.spec.template.spec.containers[*].image}{"\n"}{end}' | column -t | grep "util" >> ${deployments_list_file}.tmp
   fi

   cat ${deployments_list_file}.tmp

   ## Remove deployment that not in ${Deployments_List[@]}
   for deployment in ${Deployments_List[@]};
   do
      grep "${GC_WRKLOAD_PRFX}${deployment}  " ${deployments_list_file}.tmp >> ${deployments_list_file}
   done

   print_message "INFO" "gc_get_deployment: deployments list to be added to images.html:"
   cat ${deployments_list_file}; 
   rm ${deployments_list_file}.tmp
}

###################################################
### Modify html file for one env
###################################################
html_modify (){
   HTML_FILE="${WRK_DIR}/images.html"
   deployments_list_file="${WRK_DIR}/deployments_list.txt"

   ## backup ${HTML_FILE}
   if [ ! -d ${WRK_DIR}/backup ];
   then
      mkdir ${WRK_DIR}/backup
   elif [ ! -f ${WRK_DIR}/backup/$(basename ${HTML_FILE}).`date +%F` ]
   then
      cp -av ${HTML_FILE} ${WRK_DIR}/backup/$(basename ${HTML_FILE}).`date +%F`
   else
      print_message "INFO" "html_modify: backup already exists." "" "no_frame"
   fi

   ## find line numbers in ${HTML_FILE}
   for deployment in ${Deployments_List[@]}; 
   do
      #row_number=xmllint --html --format --xpath '//table[@data-name="${ENV}"]' ${HTML_FILE} | grep -n ${deployment} | cut -d : -f 1`

      if [[ $(grep "${GC_WRKLOAD_PRFX}${deployment}" ${deployments_list_file} | awk '{print $2}') ]];
      then
         deploy_image="$(grep "${GC_WRKLOAD_PRFX}${deployment}" ${deployments_list_file} | awk '{print $2}')"
         print_message "INFO" "html_modify: Deployment name: ${deploy_image}."
      else
         deploy_image="disabled"
         print_message "WARN" "html_modify: ${GC_WRKLOAD_PRFX}${deployment} not enabled."
      fi

      # modify html table
      #echo -e "cd //table[@data-name="DEV3"]/tr/td[@data-name="${deployment}"]\nset ${deploy_image}\nsave"|xmllint --html --shell ${HTML_FILE} 2>/dev/null
xmllint --html --shell ${HTML_FILE} 2>/dev/null <<EOF
cd //table[@data-name="${ENV}"]/tr/td[@data-name="${deployment}"]
set ${deploy_image}
save
EOF

      # check records count
      records_count=$(cat ${HTML_FILE} | wc -l)
      if [[ ${records_count} -le 10 ]];
      then
         print_message "ERROR" "html_modify: Record count too low (${records_count})."
         #restore from backup	  
         cp -av ${WRK_DIR}/backup/$(basename ${HTML_FILE}).`date +%F` ${HTML_FILE}
         mail_send
         exit 0
      fi
   done

   ## xmllint inserts <p>${set value}</p> tags; remove <p>; </p> tags
   sed -e 's#</p>##g' -e 's#<p>##g' ${HTML_FILE} > ${HTML_FILE}.temp
   sed '/^$/d' ${HTML_FILE}.temp > ${HTML_FILE}
   rm ${HTML_FILE}.temp

}

##############################
### MAIN
##############################

print_message "INFO" "Date: ${Datetime}."
case $1 in
   refresh_all)
      for environment in ${Env_List[@]}; 
      do
         gc_env ${environment} ALL
         print_message "INFO" "${ENV}: Updating image list..."
         gc_auth

         # Correct $PATH
         if ! echo $PATH | grep ${GC_SDK_DIR};
         then
            export PATH="${PATH}:${GC_SDK_DIR}/bin"; echo ${PATH}
         fi

         gc_get_deployment
         html_modify

         ## Clean up
         if [ -f ${deployments_list_file} ];
         then
            rm ${deployments_list_file} 
         fi

      done
   ;;

   *)
      gc_env $2 $3 
      gc_auth

      # Correct $PATH
         if ! echo $PATH | grep ${GC_SDK_DIR};
         then
            export PATH="${PATH}:${GC_SDK_DIR}/bin"; echo ${PATH}
         fi

      gc_get_deployment
      html_modify

      ## Clean up
      if [ -f ${deployments_list_file} ];
      then
         rm ${deployments_list_file} 
      fi

   ;;
esac
