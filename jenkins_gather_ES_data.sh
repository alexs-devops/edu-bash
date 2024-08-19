#!/bin/bash
#set -x
##########################################################################################
###
### Script to must-gather ES data. Accepts parameters:
###  $1 -> Environment (e.g DEV1|DEV2|DEV3|DEV4|STG, etc)
###
##########################################################################################

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
   # NIFI URL SECTION: Specify nifi App URL
   #####################################################################

   DEV1)
      NIFI_HOSTNAME="${env_sym}-nifi.clothing.ca"
   ;;&

   DEV2|DEV3|DEV9|DEV10|STG)
      NIFI_HOSTNAME="${env_def}-nifi.clothing.ca"
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
       #${GC_SDK_DIR}/bin/gcloud container clusters get-credentials ${GC_CL} --region us-east4 --project ${GC_PROJ}
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

es_stats_dir="/tmp/es_stats"
if [[ ! -d ${es_stats_dir} ]];
then
   mkdir ${es_stats_dir}
else
   cd ${es_stats_dir}; rm -rf *.json
fi

print_message "INFO" "http://localhost:9200/_aliases:"
kubectl exec -it ${ES_POD} -n ${GC_NAMESPC} -- curl -sk 'http://localhost:9200/_aliases' > ${es_stats_dir}/aliases.json 2>&1
sleep 5s; cat ${es_stats_dir}/aliases.json
echo ""

print_message "INFO" "http://localhost:9200/_nodes/stats/:"
kubectl exec -it ${ES_POD} -n ${GC_NAMESPC} -- curl -sk 'http://localhost:9200/_nodes/stats/' > ${es_stats_dir}/nodeStats.json 2>&1
sleep 5s; cat ${es_stats_dir}/nodeStats.json
echo ""

print_message "INFO" "http://localhost:9200/_cluster/health?level=indices:"
kubectl exec -it ${ES_POD} -n ${GC_NAMESPC} -- curl -sk 'http://localhost:9200/_cluster/health?level=indices' > ${es_stats_dir}/clusterHealthIdices.json 2>&1
sleep 5s; cat ${es_stats_dir}/clusterHealthIdices.json
echo ""

print_message "INFO" "http://localhost:9200/_cluster/stats?pretty&human:"
kubectl exec -it ${ES_POD} -n ${GC_NAMESPC} -- curl -sk 'http://localhost:9200/_cluster/stats?pretty&human' > ${es_stats_dir}/clusterStats.json 2>&1
sleep 5s; cat ${es_stats_dir}/clusterStats.json
echo ""

print_message "INFO" "http://localhost:9200/_cluster/allocation/explain?pretty:"
kubectl exec -it ${ES_POD} -n ${GC_NAMESPC} -- curl -sk 'http://localhost:9200/_cluster/allocation/explain?pretty' > ${es_stats_dir}/clusterAllocation.json 2>&1
sleep 5s; cat ${es_stats_dir}/clusterAllocation.json
echo ""

print_message "INFO" "http://localhost:9200/_cluster/health/?level=shards:"
kubectl exec -it ${ES_POD} -n ${GC_NAMESPC} -- curl -sk 'http://localhost:9200/_cluster/health/?level=shards' > ${es_stats_dir}/clusterHealthShards.json 2>&1
sleep 5s; cat ${es_stats_dir}/clusterHealthShards.json
echo ""

print_message "INFO" "http://localhost:9200/_cluster/settings?include_defaults=true:"
kubectl exec -it ${ES_POD} -n ${GC_NAMESPC} -- curl -sk 'http://localhost:9200/_cluster/settings?include_defaults=true' > ${es_stats_dir}/clusterSettings.json 2>&1
sleep 5s; cat ${es_stats_dir}/clusterSettings.json
echo ""

print_message "INFO" "http://localhost:9200/_cat/thread_pool/get,refresh,write?h=host,name,active,queue,rejected,completed,largest,max,queue_size,size&v:"
kubectl exec -it ${ES_POD} -n ${GC_NAMESPC} -- curl -sk 'http://localhost:9200/_cat/thread_pool/get,refresh,write?h=host,name,active,queue,rejected,completed,largest,max,queue_size,size&v' > ${es_stats_dir}/catThreadPool.json 2>&1
sleep 5s; cat ${es_stats_dir}/catThreadPool.json
echo ""

print_message "INFO" "http://localhost:9200/_cat/nodes?h=ip,heapPercent,heapMax,heapCurrent,ramPercent,ramMax,ramCurrent,master,name,diskTotal,diskUsed,diskAvail,cpu,load_1m,load_5m,load_15m,refresh.total&v:"
kubectl exec -it ${ES_POD} -n ${GC_NAMESPC} -- curl -sk 'http://localhost:9200/_cat/nodes?h=ip,heapPercent,heapMax,heapCurrent,ramPercent,ramMax,ramCurrent,master,name,diskTotal,diskUsed,diskAvail,cpu,load_1m,load_5m,load_15m,refresh.total&v' > ${es_stats_dir}/catNodes.json 2>&1
sleep 5s; cat ${es_stats_dir}/catNodes.json
echo ""

print_message "INFO" "http://localhost:9200/_cat/allocation?v:"
kubectl exec -it ${ES_POD} -n ${GC_NAMESPC} -- curl -sk 'http://localhost:9200/_cat/allocation?v' > ${es_stats_dir}/catAllocation.json 2>&1
sleep 5s; cat ${es_stats_dir}/catAllocation.json
echo ""

print_message "INFO" "http://localhost:9200/_cat/segments?v:"
kubectl exec -it ${ES_POD} -n ${GC_NAMESPC} -- curl -sk 'http://localhost:9200/_cat/segments?v' > ${es_stats_dir}/catSegments.json 2>&1
sleep 5s; cat ${es_stats_dir}/catSegments.json
echo ""

print_message "INFO" "http://localhost:9200/_cat/indices?v&s=index:"
kubectl exec -it ${ES_POD} -n ${GC_NAMESPC} -- curl -sk 'http://localhost:9200/_cat/indices?v&s=index' > ${es_stats_dir}/catIndices.json 2>&1
sleep 5s; cat ${es_stats_dir}/catIndices.json
echo ""

print_message "INFO" "http://localhost:9200/_cat/shards?v:"
kubectl exec -it ${ES_POD} -n ${GC_NAMESPC} -- curl -sk 'http://localhost:9200/_cat/shards?v'  > ${es_stats_dir}/catShards.json 2>&1
sleep 5s; cat ${es_stats_dir}/catShards.json

print_message "INFO" "https://${NIFI_HOSTNAME}/nifi-api/system-diagnostics:"
curl -k https://${NIFI_HOSTNAME}/nifi-api/system-diagnostics > ${es_stats_dir}/nifiSystemDiagnostics.json 2>&1
sleep 5s; cat ${es_stats_dir}/nifiSystemDiagnostics.json
echo ""

print_message "INFO" "Gathered data located under ${es_stats_dir}."
ls -lhtr ${es_stats_dir}

Datetime=`date '+%Y%m%d_%H%M%S'`
print_message "INFO" "Completed. Date: ${Datetime}."
